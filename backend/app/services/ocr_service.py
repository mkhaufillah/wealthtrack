"""OCR service — business logic extracted from app.routers.ocr.

Encapsulates image validation, compression, Vision API integration (with retry),
background OCR job processing, and OCR job status queries.
No FastAPI dependency — instantiated with a CursorWrapper.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import re
from datetime import datetime
from io import BytesIO
from pathlib import Path

import httpx
from PIL import Image

from app.core.config import settings
from app.database import CursorWrapper, background_tasks

logger = logging.getLogger(__name__)

# ── System-wide semaphore: max 2 concurrent Vision API calls across all users ──
_ocr_semaphore = asyncio.Semaphore(2)

# ── Allowed image MIME types (raster only — SVG/vector not supported) ──
ALLOWED_MIME = {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"}

# ── Magic bytes for image format validation ──
IMAGE_MAGIC: dict[bytes, str] = {
    b"\xff\xd8\xff": "JPEG",
    b"\x89PNG\r\n\x1a\n": "PNG",
    b"RIFF": "WEBP",  # WebP starts with RIFF
}

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


# ── Domain Exceptions ─────────────────────────────────────────────────


class OcrError(Exception):
    """Base OCR service exception."""

    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(detail)


class OcrImageError(OcrError):
    """Invalid or corrupted image."""


class OcrApiKeyError(OcrError):
    """Missing or invalid API key."""

    def __init__(self, detail: str = "OCR not configured (missing API key)") -> None:
        super().__init__(detail)


class OcrVisionApiError(OcrError):
    """Vision API returned an error."""

    def __init__(self, detail: str, status_code: int = 502) -> None:
        self.status_code = status_code
        super().__init__(detail)


class OcrTimeoutError(OcrError):
    """Vision API timed out."""

    def __init__(self, detail: str = "Vision API timed out") -> None:
        super().__init__(detail)


class OcrBusyError(OcrError):
    """User already has a processing job."""


# ── Service ───────────────────────────────────────────────────────────


class OcrService:
    """Service layer for OCR operations.

    Instantiated with a ``CursorWrapper`` obtained from the FastAPI
    ``get_db`` dependency.  All business logic lives here, not in the
    router.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    # ── Public API ───────────────────────────────────────────────────

    async def process_ocr(
        self,
        file_bytes: bytes,
        content_type: str,
        user_id: int,
    ) -> dict:
        """Process a single OCR image synchronously.

        Validates, compresses, calls the Vision API, and returns a
        dict with keys: ``amount``, ``description``, ``date``,
        ``category_name``, ``type``, ``note``, ``raw_text``.

        Raises:
            OcrImageError: Invalid or unsupported image.
            OcrApiKeyError: API key is not configured.
            OcrVisionApiError: Vision API error (non‑retryable).
            OcrTimeoutError: Vision API timed out.
        """
        self._validate_image(content_type, file_bytes)

        api_key = settings.OPENCODE_GO_API_KEY
        if not api_key:
            raise OcrApiKeyError()

        data_url = self._compress_image(file_bytes)
        categories_str = await self._load_categories()
        prompt = SYSTEM_PROMPT.format(categories=categories_str)

        content = await self._call_vision_api(data_url, prompt, api_key)

        try:
            parsed = json.loads(content)
        except json.JSONDecodeError:
            return {"raw_text": content}

        return {
            "amount": int(parsed["amount"]) if parsed.get("amount") else None,
            "description": str(parsed.get("description", "")),
            "date": str(parsed.get("date", "")),
            "category_name": str(parsed.get("category_name", "")),
            "type": str(parsed.get("type", "")),
            "note": str(parsed.get("note", "")),
            "raw_text": content,
        }

    async def process_and_save(
        self,
        file_bytes: bytes,
        content_type: str,
        filename: str,
        user_id: int,
    ) -> dict:
        """Process OCR image and auto-save transaction in the background.

        Validates, saves the image to disk, creates an ``ocr_jobs``
        record, and spawns a background task that compresses, calls
        the Vision API (with retry), and persists the transaction.

        Returns a dict with keys: ``job_id``, ``status``.

        Raises:
            OcrImageError: Invalid or unsupported image.
            OcrApiKeyError: API key is not configured.
            OcrBusyError: User already has a processing job.
        """
        api_key = settings.OPENCODE_GO_API_KEY
        if not api_key:
            raise OcrApiKeyError()

        # Per-user queue: reject if user already has a processing job
        cursor = await self.db.execute(
            "SELECT COUNT(*) as count FROM ocr_jobs WHERE user_id = ? AND status = 'processing'",
            (user_id,),
        )
        row = await cursor.fetchone()
        if row["count"] > 0:
            raise OcrBusyError(
                "You already have an OCR job being processed. "
                "Please wait for it to complete."
            )

        self._validate_image(content_type, file_bytes)

        # Save image to disk
        ocr_dir = Path(settings.OCR_IMAGE_DIR)
        ocr_dir.mkdir(exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        ext = Path(filename or "receipt.jpg").suffix or ".jpg"
        img_filename = f"ocr_{user_id}_{ts}{ext}"
        img_path = str(ocr_dir / img_filename)
        with open(img_path, "wb") as f:
            f.write(file_bytes)

        # Create OCR job
        cursor = await self.db.execute(
            "INSERT INTO ocr_jobs (user_id, image_filename, status) VALUES (?, ?, 'processing')",
            (user_id, img_filename),
        )
        job_id = cursor.lastrowid

        # ── Background: process and save transaction ──
        async def _process() -> None:
            try:
                from app.database import get_db_bg

                bg_db = await get_db_bg()
                try:
                    raw_bytes = open(img_path, "rb").read()
                    data_url = self._compress_image(raw_bytes)
                    categories_str = await self._load_categories(bg_db)
                    prompt = SYSTEM_PROMPT.format(categories=categories_str)

                    content = await self._call_vision_api_with_retry(
                        data_url, prompt, api_key
                    )
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
                    txn_date = str(
                        parsed.get("date", datetime.now().strftime("%Y-%m-%d"))
                    )

                    if amount > 0 and category_id:
                        cursor = await bg_db.execute(
                            """INSERT INTO transactions
                               (user_id, type, category_id, category_name, amount, description, note, date)
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                            (
                                user_id,
                                txn_type,
                                category_id,
                                category_name,
                                amount,
                                description,
                                note,
                                txn_date,
                            ),
                        )
                        txn_id = cursor.lastrowid
                        await bg_db.execute(
                            "UPDATE ocr_jobs SET status = 'completed', transaction_id = ?, "
                            "completed_at = TO_CHAR(NOW(), 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') "
                            "WHERE id = ?",
                            (txn_id, job_id),
                        )
                    else:
                        await bg_db.execute(
                            "UPDATE ocr_jobs SET status = 'failed', "
                            "error = 'OCR failed. Please try again with a clearer photo.' "
                            "WHERE id = ?",
                            (job_id,),
                        )
                except json.JSONDecodeError:
                    await bg_db.execute(
                        "UPDATE ocr_jobs SET status = 'failed', "
                        "error = 'OCR failed. Please try again with a clearer photo.' "
                        "WHERE id = ?",
                        (job_id,),
                    )
                except Exception as e:
                    logger.warning("OCR background task error: %s", e)
                    await bg_db.execute(
                        "UPDATE ocr_jobs SET status = 'failed', "
                        "error = 'OCR failed. Please try again with a clearer photo.' "
                        "WHERE id = ?",
                        (job_id,),
                    )
                finally:
                    await bg_db.close()
            except Exception as bg_err:
                import logging as _logging

                _logging.getLogger("wealthtrack.ocr").exception(
                    "OCR background task crashed: %s", bg_err
                )

        task = asyncio.create_task(_process())
        background_tasks.add(task)
        task.add_done_callback(background_tasks.discard)

        return {"job_id": job_id, "status": "processing"}

    async def get_pending_count(self, user_id: int) -> dict:
        """Get pending OCR jobs count and recent failures.

        Returns a dict with keys: ``count``, ``error`` (optional),
        ``has_failure``, ``failed_job_id`` (optional).
        """
        cursor = await self.db.execute(
            "SELECT COUNT(*) as count FROM ocr_jobs WHERE user_id = ? AND status = 'processing'",
            (user_id,),
        )
        row = await cursor.fetchone()
        processing_count = row["count"]

        # Check for recent failures (last 60 seconds) to surface error to user
        cursor = await self.db.execute(
            "SELECT id, error FROM ocr_jobs "
            "WHERE user_id = ? AND status = 'failed' "
            "AND created_at::timestamp > NOW() - INTERVAL '60 seconds' "
            "ORDER BY created_at DESC LIMIT 1",
            (user_id,),
        )
        failed_row = await cursor.fetchone()

        result: dict = {
            "count": processing_count,
            "has_failure": False,
        }
        if failed_row and failed_row["error"]:
            result["error"] = failed_row["error"]
            result["has_failure"] = True
            result["failed_job_id"] = failed_row["id"]

        return result

    # ── Internal helpers ────────────────────────────────────────────

    def _validate_image(self, mime: str, raw_bytes: bytes) -> None:
        """Validate MIME type and image magic bytes. Raises OcrImageError."""
        if mime not in ALLOWED_MIME:
            raise OcrImageError(
                f"Unsupported image format: {mime}. "
                f"Allowed: {', '.join(sorted(ALLOWED_MIME))}"
            )

        if len(raw_bytes) < 12:
            raise OcrImageError("Invalid or corrupted image file")

        for magic, fmt in IMAGE_MAGIC.items():
            if raw_bytes[: len(magic)] == magic:
                return

        raise OcrImageError("Invalid image — unrecognised file signature")

    def _compress_image(self, image_bytes: bytes) -> str:
        """Resize (max 1200px longest side) and re-encode as JPEG, return data URL."""
        img = Image.open(BytesIO(image_bytes))
        w, h = img.size
        max_side = 1200
        if max(w, h) > max_side:
            ratio = max_side / max(w, h)
            new_w, new_h = int(w * ratio), int(h * ratio)
            img = img.resize((new_w, new_h), Image.LANCZOS)

        # Convert to RGB (JPEG doesn't support alpha)
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGB")

        compressed = BytesIO()
        img.save(compressed, format="JPEG", optimize=True, quality=85)
        b64 = base64.b64encode(compressed.getvalue()).decode()
        return f"data:image/jpeg;base64,{b64}"

    async def _load_categories(self, db: CursorWrapper | None = None) -> str:
        """Load all categories from DB and format them for the prompt.

        Accepts an optional *db* argument so background tasks can pass
        a separate connection (``get_db_bg``).
        """
        cursor = await (db or self.db).execute(
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

    async def _call_vision_api(
        self, data_url: str, prompt: str, api_key: str
    ) -> str:
        """Call the Vision API (single attempt, no retry)."""
        try:
            async with _ocr_semaphore:
                async with httpx.AsyncClient(timeout=60) as client:
                    resp = await client.post(
                        "https://opencode.ai/zen/go/v1/chat/completions",
                        headers={
                            "Authorization": f"Bearer {api_key}",
                            "Content-Type": "application/json",
                        },
                        json={
                            "model": "kimi-k2.5",
                            "messages": [
                                {"role": "system", "content": prompt},
                                {
                                    "role": "user",
                                    "content": [
                                        {
                                            "type": "image_url",
                                            "image_url": {"url": data_url},
                                        },
                                        {
                                            "type": "text",
                                            "text": "Extract transaction data from this image.",
                                        },
                                    ],
                                },
                            ],
                            "max_tokens": 4096,
                        },
                    )

            if resp.status_code == 429:
                raise OcrVisionApiError(
                    "Vision API rate limit exceeded. Please wait and try again.",
                    status_code=429,
                )
            elif resp.status_code == 401:
                raise OcrVisionApiError(
                    "OCR service unauthorized — check API key configuration"
                )
            elif resp.status_code == 503:
                raise OcrVisionApiError(
                    "OCR service temporarily unavailable. Please try again later."
                )
            elif resp.status_code != 200:
                raise OcrVisionApiError(f"Vision API error: HTTP {resp.status_code}")

            body = resp.json()
            content = body["choices"][0]["message"]["content"].strip()
            content = re.sub(r"^```(?:json)?\s*", "", content)
            content = re.sub(r"\s*```$", "", content)
            return content

        except httpx.TimeoutException:
            raise OcrTimeoutError()
        except httpx.RequestError as e:
            raise OcrVisionApiError(f"Vision API request failed: {e}")

    async def _call_vision_api_with_retry(
        self, data_url: str, prompt: str, api_key: str
    ) -> str:
        """Call the Vision API with retry (5 attempts, jittered exp. backoff for 429).

        Unlike ``_call_vision_api``, this does **not** translate httpx
        exceptions into ``OcrVisionApiError`` — those propagate to the
        caller's ``except Exception`` handler (the background task).
        """
        import random as _random

        vision_resp = None
        last_exc: Exception | None = None

        async with _ocr_semaphore:
            for attempt in range(5):
                try:
                    async with httpx.AsyncClient(timeout=60) as client:
                        vision_resp = await client.post(
                            "https://opencode.ai/zen/go/v1/chat/completions",
                            headers={
                                "Authorization": f"Bearer {api_key}",
                                "Content-Type": "application/json",
                            },
                            json={
                                "model": "kimi-k2.5",
                                "messages": [
                                    {"role": "system", "content": prompt},
                                    {
                                        "role": "user",
                                        "content": [
                                            {
                                                "type": "image_url",
                                                "image_url": {"url": data_url},
                                            },
                                            {
                                                "type": "text",
                                                "text": "Extract transaction data from this image.",
                                            },
                                        ],
                                    },
                                ],
                                "max_tokens": 4096,
                            },
                        )

                    if vision_resp.status_code == 429 and attempt < 4:
                        base_wait = 2**attempt  # 1, 2, 4, 8s
                        jitter = _random.uniform(0.5, 1.5)
                        await asyncio.sleep(base_wait * jitter)
                        continue
                    break

                except (httpx.TimeoutException, httpx.RequestError) as e:
                    last_exc = e
                    if attempt < 4:
                        await asyncio.sleep(2**attempt)
                        continue
                    raise OcrVisionApiError(f"Vision API request failed: {last_exc}")

        if vision_resp is None:
            raise OcrVisionApiError("Vision API request failed: no response")

        if vision_resp.status_code == 429:
            raise OcrVisionApiError(
                f"Vision API rate limit (attempt {attempt + 1}/5)"
            )
        elif vision_resp.status_code == 401:
            raise OcrVisionApiError("Vision API unauthorized — check API key")
        elif vision_resp.status_code != 200:
            raise OcrVisionApiError(
                f"Vision API error: HTTP {vision_resp.status_code} "
                f"(attempt {attempt + 1}/5)"
            )

        content = vision_resp.json()["choices"][0]["message"]["content"].strip()
        content = re.sub(r"^```(?:json)?\s*", "", content)
        content = re.sub(r"\s*```$", "", content)
        return content
