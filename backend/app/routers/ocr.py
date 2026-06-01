from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import Optional
import httpx
import base64
import json
import re
import asyncio
import os
from io import BytesIO
from pathlib import Path
from datetime import datetime
from PIL import Image

# System-wide semaphore: max 2 concurrent Vision API calls across all users
_ocr_semaphore = asyncio.Semaphore(2)

from app.core.config import settings
from app.core.security import get_current_user
from app.database import get_db

router = APIRouter(prefix="/ocr", tags=["ocr"])

# ── Rate limit: max 10 OCR calls per user (stored in-memory per server)
#    Sufficient for personal use; a proper Redis-backed solution can replace later.
import time
_user_ocr_counts: dict[int, list[float]] = {}

# ── Allowed image MIME types (raster only — SVG/vector not supported)
ALLOWED_MIME = {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"}

# ── Magic bytes for image format validation
IMAGE_MAGIC: dict[bytes, str] = {
    b'\xff\xd8\xff': "JPEG",
    b'\x89PNG\r\n\x1a\n': "PNG",
    b'RIFF': "WEBP",  # WebP starts with RIFF
}


def _check_rate_limit(user_id: int):
    now = time.time()
    day_ago = now - 86400
    if user_id not in _user_ocr_counts:
        _user_ocr_counts[user_id] = []
    # Prune old entries
    _user_ocr_counts[user_id] = [t for t in _user_ocr_counts[user_id] if t > day_ago]
    if len(_user_ocr_counts[user_id]) >= 10:
        raise HTTPException(status_code=429, detail="OCR rate limit: max 10/day")
    _user_ocr_counts[user_id].append(now)


def _validate_image(mime: str, raw_bytes: bytes) -> None:
    """Validate MIME type and image magic bytes."""
    if mime not in ALLOWED_MIME:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported image format: {mime}. Allowed: {', '.join(sorted(ALLOWED_MIME))}",
        )

    if len(raw_bytes) < 12:
        raise HTTPException(status_code=400, detail="Invalid or corrupted image file")

    # Check magic bytes
    for magic, fmt in IMAGE_MAGIC.items():
        if raw_bytes[:len(magic)] == magic:
            return

    raise HTTPException(status_code=400, detail="Invalid image — unrecognised file signature")


async def _load_categories(db) -> str:
    """Load all categories from DB and format them for the prompt."""
    cursor = await db.execute(
        "SELECT name, type FROM categories ORDER BY type, sort_order"
    )
    rows = await cursor.fetchall()
    expense = []
    income = []
    for r in rows:
        if r["type"] == "expense":
            expense.append(r["name"])
        else:
            income.append(r["name"])
    return (
        "Kategori Expense: " + ", ".join(expense) + "\n"
        "Kategori Income: " + ", ".join(income)
    )


class OcrResult(BaseModel):
    amount: Optional[int] = None
    description: Optional[str] = None
    date: Optional[str] = None  # YYYY-MM-DD
    category_name: Optional[str] = None
    type: Optional[str] = None  # "expense" or "income"
    note: Optional[str] = None
    raw_text: str = ""


SYSTEM_PROMPT = """You are a receipt/transaction OCR assistant. Given an image of a receipt, bill, or transaction note, extract structured financial data.

Return ONLY valid JSON with these fields:
{{
  "amount": integer (total amount in Rupiah, no decimals),
  "description": "short description of what was purchased",
  "date": "YYYY-MM-DD" (transaction date, use today if not visible),
  "type": "expense" or "income",
  "category_name": "choose EXACTLY from the valid category list below — do NOT invent new categories",
  "note": "any extra details that don't fit in description (e.g. payment method, store name, quantity, notes on the receipt)"
}}

Valid categories (pick ONLY from this list — match by type):
{categories}

Rules:
1. type must match — expense categories CANNOT be used for income and vice versa
2. category_name must be EXACTLY one of the listed names (case-sensitive)
3. If you can't determine the type or category, set type to "expense" and category_name to the closest match
4. If the image is not a receipt/financial document, return {{"raw_text": "description of what the image contains"}}
Do NOT include markdown formatting. Return ONLY the JSON object."""


@router.post("/process", response_model=OcrResult)
async def process_ocr(
    file: UploadFile = File(...),
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Process an image through vision AI to extract transaction data."""
    _check_rate_limit(current_user["id"])

    if not file.content_type:
        raise HTTPException(status_code=400, detail="Could not detect file type")

    # Read image
    image_bytes = await file.read()
    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 10 MB)")

    # Validate image
    _validate_image(file.content_type, image_bytes)

    # Compress: resize if longest side > 1200px, re-encode as JPEG
    img = Image.open(BytesIO(image_bytes))
    w, h = img.size
    max_side = 1200
    if max(w, h) > max_side:
        ratio = max_side / max(w, h)
        new_w, new_h = int(w * ratio), int(h * ratio)
        img = img.resize((new_w, new_h), Image.LANCZOS)

    # Convert to RGB (JPEG doesn't support alpha) and compress
    if img.mode in ("RGBA", "P"):
        img = img.convert("RGB")
    compressed = BytesIO()
    img.save(compressed, format="JPEG", optimize=True, quality=85)
    compressed_bytes = compressed.getvalue()

    # Encode as base64 data URL — always JPEG after compression
    b64 = base64.b64encode(compressed_bytes).decode()
    data_url = f"data:image/jpeg;base64,{b64}"

    api_key = settings.OPENCODE_GO_API_KEY
    if not api_key:
        raise HTTPException(status_code=500, detail="OCR not configured (missing API key)")

    # Load valid categories for prompt
    categories_str = await _load_categories(db)
    prompt = SYSTEM_PROMPT.format(categories=categories_str)

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                "https://opencode.ai/zen/go/v1/chat/completions",
                headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
                json={
                    "model": "kimi-k2.5",
                    "messages": [
                        {"role": "system", "content": prompt},
                        {
                            "role": "user",
                            "content": [
                                {"type": "image_url", "image_url": {"url": data_url}},
                                {"type": "text", "text": "Extract transaction data from this image."},
                            ],
                        },
                    ],
                    "max_tokens": 4096,
                },
            )

        if resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Vision API error: {resp.status_code}")

        body = resp.json()
        content = body["choices"][0]["message"]["content"].strip()

        # Clean markdown code fences if present
        content = re.sub(r"^```(?:json)?\s*", "", content)
        content = re.sub(r"\s*```$", "", content)

        try:
            parsed = json.loads(content)
        except json.JSONDecodeError:
            return OcrResult(raw_text=content)

        return OcrResult(
            amount=int(parsed["amount"]) if parsed.get("amount") else None,
            description=str(parsed.get("description", "")),
            date=str(parsed.get("date", "")),
            category_name=str(parsed.get("category_name", "")),
            type=str(parsed.get("type", "")),
            note=str(parsed.get("note", "")),
            raw_text=content,
        )

    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Vision API timed out")
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Vision API request failed: {e}")


# ── Background OCR (auto-save) ──


class OcrAutoSaveResult(BaseModel):
    job_id: int
    transaction_id: Optional[int] = None
    status: str = "processing"


class OcrPendingCount(BaseModel):
    count: int
    error: Optional[str] = None
    has_failure: bool = False


@router.post("/process-and-save", response_model=OcrAutoSaveResult)
async def process_ocr_and_save(
    file: UploadFile = File(...),
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Process OCR image and auto-save transaction. Returns immediately."""
    _check_rate_limit(current_user["id"])

    # Per-user queue: reject if user already has a processing job
    cursor = await db.execute(
        "SELECT COUNT(*) as count FROM ocr_jobs WHERE user_id = ? AND status = 'processing'",
        (current_user["id"],),
    )
    row = await cursor.fetchone()
    if row["count"] > 0:
        raise HTTPException(status_code=429, detail="You already have an OCR job being processed. Please wait for it to complete.")

    if not file.content_type:
        raise HTTPException(status_code=400, detail="Could not detect file type")

    raw = await file.read()
    if len(raw) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 10 MB)")

    _validate_image(file.content_type, raw)

    # Save image to disk
    ocr_dir = Path(settings.DB_PATH).parent / "ocr_images"
    ocr_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    ext = Path(file.filename or "receipt.jpg").suffix or ".jpg"
    img_filename = f"ocr_{current_user['id']}_{ts}{ext}"
    img_path = str(ocr_dir / img_filename)
    with open(img_path, "wb") as f:
        f.write(raw)

    # Create OCR job
    cursor = await db.execute(
        "INSERT INTO ocr_jobs (user_id, image_filename, status) VALUES (?, ?, 'processing')",
        (current_user["id"], img_filename),
    )
    job_id = cursor.lastrowid
    await db.commit()

    # Background: process and save transaction
    ocr_dir_str = str(ocr_dir)

    async def _process():
        try:
            from app.database import get_db_bg

            bg_db = await get_db_bg()
            try:
                # ⚠️ SIMULATED ERROR: always fails for testing error banner
                err_msg = (
                    "Gagal memproses struk. Penyebab: gambar buram atau "
                    "tidak ada informasi transaksi yang jelas. "
                    "Coba foto ulang dengan pencahayaan cukup dan pastikan "
                    "nominal serta tanggal terlihat."
                )
                raise Exception(err_msg)

                # Read and compress
                raw_bytes = open(img_path, "rb").read()
                img = Image.open(BytesIO(raw_bytes))
                w, h = img.size
                max_side = 1200
                if max(w, h) > max_side:
                    ratio = max_side / max(w, h)
                    img = img.resize((int(w * ratio), int(h * ratio)), Image.LANCZOS)
                if img.mode in ("RGBA", "P"):
                    img = img.convert("RGB")
                compressed = BytesIO()
                img.save(compressed, format="JPEG", optimize=True, quality=85)
                b64 = base64.b64encode(compressed.getvalue()).decode()
                data_url = f"data:image/jpeg;base64,{b64}"

                categories_str = await _load_categories(bg_db)
                prompt = SYSTEM_PROMPT.format(categories=categories_str)

                # Vision API call with retry (5 attempts, jittered exponential backoff for 429)
                import random as _random
                vision_resp = None
                async with _ocr_semaphore:
                    for attempt in range(5):
                        async with httpx.AsyncClient(timeout=60) as client:
                            vision_resp = await client.post(
                                "https://opencode.ai/zen/go/v1/chat/completions",
                                headers={"Authorization": f"Bearer {settings.OPENCODE_GO_API_KEY}", "Content-Type": "application/json"},
                                json={
                                    "model": "kimi-k2.5",
                                    "messages": [
                                        {"role": "system", "content": prompt},
                                        {"role": "user", "content": [
                                            {"type": "image_url", "image_url": {"url": data_url}},
                                            {"type": "text", "text": "Extract transaction data from this image."},
                                        ]},
                                    ],
                                    "max_tokens": 4096,
                                },
                            )
                        if vision_resp.status_code == 429 and attempt < 4:
                            base_wait = 2 ** attempt  # 1, 2, 4, 8s
                            jitter = _random.uniform(0.5, 1.5)
                            await asyncio.sleep(base_wait * jitter)
                            continue
                        break

                if vision_resp.status_code != 200:
                    raise Exception(f"Vision API error: {vision_resp.status_code}")

                content = vision_resp.json()["choices"][0]["message"]["content"].strip()
                content = re.sub(r"^```(?:json)?\s*", "", content)
                content = re.sub(r"\s*```$", "", content)
                parsed = json.loads(content)

                category_name = parsed.get("category_name", "")
                txn_type = parsed.get("type", "expense")
                cursor = await bg_db.execute(
                    "SELECT id FROM categories WHERE name = ? AND type = ?",
                    (category_name, txn_type),
                )
                cat_row = await cursor.fetchone()
                category_id = cat_row["id"] if cat_row else None

                if not category_id:
                    cursor = await bg_db.execute(
                        "SELECT id FROM categories WHERE name = 'Lainnya' AND type = ?",
                        (txn_type,),
                    )
                    cat_row = await cursor.fetchone()
                    category_id = cat_row["id"] if cat_row else None

                amount = int(parsed.get("amount", 0))
                description = str(parsed.get("description", ""))
                note = str(parsed.get("note", ""))
                txn_date = str(parsed.get("date", datetime.now().strftime("%Y-%m-%d")))

                if amount > 0 and category_id:
                    cursor = await bg_db.execute(
                        """INSERT INTO transactions (user_id, type, category_id, category_name, amount, description, note, date)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                        (current_user["id"], txn_type, category_id, category_name, amount, description, note, txn_date),
                    )
                    txn_id = cursor.lastrowid
                    await bg_db.execute(
                        "UPDATE ocr_jobs SET status = 'completed', transaction_id = ?, completed_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?",
                        (txn_id, job_id),
                    )
                else:
                    await bg_db.execute(
                        "UPDATE ocr_jobs SET status = 'failed', error = 'Could not determine amount or category' WHERE id = ?",
                        (job_id,),
                    )

                await bg_db.commit()
            except json.JSONDecodeError:
                await bg_db.execute(
                    "UPDATE ocr_jobs SET status = 'failed', error = 'Invalid JSON from vision API' WHERE id = ?",
                    (job_id,),
                )
                await bg_db.commit()
            except Exception as e:
                err_msg = str(e)
                await bg_db.execute(
                    "UPDATE ocr_jobs SET status = 'failed', error = ? WHERE id = ?",
                    (err_msg, job_id),
                )
                await bg_db.commit()
            finally:
                await bg_db.close()
        except Exception as bg_err:
            import logging
            logging.getLogger("wealthtrack.ocr").exception("OCR background task crashed: %s", bg_err)

    asyncio.create_task(_process())

    return OcrAutoSaveResult(job_id=job_id, status="processing")


@router.get("/pending-count", response_model=OcrPendingCount)
async def ocr_pending_count(
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT COUNT(*) as count FROM ocr_jobs WHERE user_id = ? AND status = 'processing'",
        (current_user["id"],),
    )
    row = await cursor.fetchone()
    processing_count = row["count"]

    # Check for recent failures (last 60 seconds) to surface error to user
    cursor = await db.execute(
        "SELECT error FROM ocr_jobs WHERE user_id = ? AND status = 'failed' AND created_at > datetime('now', '-60 seconds') ORDER BY created_at DESC LIMIT 1",
        (current_user["id"],),
    )
    failed_row = await cursor.fetchone()

    if failed_row and failed_row["error"]:
        return OcrPendingCount(count=processing_count, error=failed_row["error"], has_failure=True)

    return OcrPendingCount(count=processing_count)
