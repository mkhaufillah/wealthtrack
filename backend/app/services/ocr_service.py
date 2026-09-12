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

def _vision_model() -> str:
    return (
        "deepseek/deepseek-v4-flash-vision-exp"
        if settings.llm_via_openrouter
        else "deepseek-v4-flash-vision-exp"
    )


def sweep_ocr_images(max_age_hours: int = 24) -> int:
    """Delete leftover receipt images older than ``max_age_hours``.

    Each OCR job deletes its own image in a ``finally`` block, so anything still
    on disk is an orphan from a crash or a container restart. Without this the
    OCR dir grows forever (and it holds pictures of receipts — data we do not
    want to keep around). Returns the number of files removed.
    """
    import time
    from pathlib import Path as _Path

    directory = _Path(settings.OCR_IMAGE_DIR)
    if not directory.exists():
        return 0
    cutoff = time.time() - (max_age_hours * 3600)
    removed = 0
    for path in directory.glob("ocr_*"):
        try:
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
                removed += 1
        except OSError:
            continue
    if removed:
        logger.info("ocr image sweep removed %s stale file(s)", removed)
    return removed

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

    def __init__(self, detail: str = "OCR belum dikonfigurasi (API key kosong)") -> None:
        super().__init__(detail)


class OcrVisionApiError(OcrError):
    """Vision API returned an error."""

    def __init__(self, detail: str, status_code: int = 502) -> None:
        self.status_code = status_code
        super().__init__(detail)


class OcrTimeoutError(OcrError):
    """Vision API timed out."""

    def __init__(self, detail: str = "Layanan baca struk lambat, coba lagi ya") -> None:
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

        from app.core.llm import vision_plan

        if not any(a.key for a in vision_plan()):
            raise OcrApiKeyError()

        data_url = self._compress_image(file_bytes)
        categories_str = await self._load_categories()
        prompt = SYSTEM_PROMPT.format(categories=categories_str)

        content = await self._call_vision_api(data_url, prompt)

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
        # Validate image first so non-image requests fail fast (400)
        # regardless of API key availability
        self._validate_image(content_type, file_bytes)

        # Per-user queue: reject if user already has a processing job
        cursor = await self.db.execute(
            "SELECT COUNT(*) as count FROM ocr_jobs WHERE user_id = ? AND status = 'processing'",
            (user_id,),
        )
        row = await cursor.fetchone()
        if row["count"] > 0:
            raise OcrBusyError(
                "Struk sebelumnya masih diproses, tunggu ya."
            )

        from app.core.llm import vision_plan

        if not any(a.key for a in vision_plan()):
            raise OcrApiKeyError()

        # Save image to disk
        sweep_ocr_images()
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
            "INSERT INTO ocr_jobs (user_id, status) VALUES (?, 'processing')",
            (user_id,),
        )
        job_id = cursor.lastrowid
        from app.core.vault_ctx import current_dek, set_dek

        captured_dek = current_dek()

        # ── Background: process and save transaction ──
        async def _process() -> None:
            try:
                from app.database import get_db_bg

                set_dek(captured_dek)
                bg_db = await get_db_bg()
                try:
                    raw_bytes = open(img_path, "rb").read()
                    data_url = self._compress_image(raw_bytes)
                    categories_str = await self._load_categories(bg_db)
                    prompt = SYSTEM_PROMPT.format(categories=categories_str)

                    content = await self._call_vision_api_with_retry(
                        data_url, prompt
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
                        from app.core.vault_write import pack_txn

                        packed = pack_txn(
                            amount=amount,
                            description=description,
                            note=note,
                            category_id=category_id,
                            category_name=category_name,
                        )
                        cursor = await bg_db.execute(
                            """INSERT INTO transactions
                               (user_id, type, date,
                                vault_blob, amount_ord, category_trace)
                               VALUES (?, ?, ?, ?, ?, ?)""",
                            (
                                user_id,
                                txn_type,
                                txn_date,
                                packed["vault_blob"],
                                packed["amount_ord"],
                                packed.get("category_trace") or "",
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
                            "error = 'Gagal baca struk. Fotoin yang lebih jelas ya.' "
                            "WHERE id = ?",
                            (job_id,),
                        )
                except json.JSONDecodeError:
                    await bg_db.execute(
                        "UPDATE ocr_jobs SET status = 'failed', "
                        "error = 'Gagal baca struk. Fotoin yang lebih jelas ya.' "
                        "WHERE id = ?",
                        (job_id,),
                    )
                except Exception as e:
                    logger.warning("OCR background task error: %s", e)
                    await bg_db.execute(
                        "UPDATE ocr_jobs SET status = 'failed', "
                        "error = 'Gagal baca struk. Fotoin yang lebih jelas ya.' "
                        "WHERE id = ?",
                        (job_id,),
                    )
                finally:
                    try:
                        from pathlib import Path as _P

                        _P(img_path).unlink(missing_ok=True)
                    except Exception:
                        pass
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
                f"Format foto gak didukung: {mime}. "
                f"Yang bisa: {', '.join(sorted(ALLOWED_MIME))}"
            )

        if len(raw_bytes) < 12:
            raise OcrImageError("Foto rusak atau gak lengkap")

        for magic, fmt in IMAGE_MAGIC.items():
            if raw_bytes[: len(magic)] == magic:
                return

        raise OcrImageError("Foto tidak dikenali — formatnya aneh")

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
        self, data_url: str, prompt: str, api_key: str | None = None
    ) -> str:
        """Call the Vision API (one attempt per provider, no retry)."""
        from app.core.llm import vision_plan

        last_status = 0
        network_err: Exception | None = None
        timeout_hit = False
        for attempt in vision_plan():
            try:
                async with _ocr_semaphore:
                    async with httpx.AsyncClient(timeout=120) as client:
                        resp = await client.post(
                            attempt.url,
                            headers=attempt.headers,
                            json={
                                "model": attempt.model,
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
                                                "text": "Ambil data transaksi dari gambar ini.",
                                            },
                                        ],
                                    },
                                ],
                                "max_tokens": 4096,
                            },
                        )
            except httpx.TimeoutException as e:
                timeout_hit = True
                network_err = e
                continue  # try the next provider
            except httpx.RequestError as e:
                last_status = 0
                network_err = e
                logger.warning("OCR vision via %s unreachable: %s", attempt.provider, e)
                continue

            if resp.status_code == 200:
                body = resp.json()
                content = body["choices"][0]["message"]["content"].strip()
                content = re.sub(r"^```(?:json)?\s*", "", content)
                content = re.sub(r"\s*```$", "", content)
                return content

            last_status = resp.status_code
            logger.warning(
                "OCR vision via %s HTTP %s: %s",
                attempt.provider,
                resp.status_code,
                (getattr(resp, "text", "") or "")[:300],
            )
            continue  # try the next provider

        if last_status == 429:
            raise OcrVisionApiError(
                "Kebanyakan request. Tunggu sebentar, coba lagi.",
                status_code=429,
            )
        if last_status in (401, 403):
            raise OcrVisionApiError("OCR belum dikonfigurasi — cek API key")
        if last_status == 503:
            raise OcrVisionApiError("Layanan baca struk lagi sibuk. Coba sebentar lagi ya.")
        if last_status:
            raise OcrVisionApiError(f"Layanan baca struk error (HTTP {last_status})")
        if timeout_hit:
            raise OcrTimeoutError()
        if network_err is not None:
            raise OcrVisionApiError(f"Gagal hubungi layanan baca struk: {network_err}")
        raise OcrVisionApiError("Gagal hubungi layanan baca struk")

    async def _call_vision_api_with_retry(
        self, data_url: str, prompt: str, api_key: str | None = None
    ) -> str:
        """Call the Vision API across the provider plan (OpenCode → OpenRouter).

        Per provider: up to 5 attempts with jittered backoff for transient
        failures (timeout, 429, 5xx). Auth/quota answers (401/403/429) skip to
        the next provider instead of burning all retries on a dead one — this is
        what makes "OpenCode limit" stop meaning "OCR down".

        Unlike ``_call_vision_api``, httpx exceptions are not translated into
        ``OcrVisionApiError`` until every provider has been tried.
        """
        import random as _random

        from app.core.llm import vision_plan

        payload = {
            "messages": [
                {"role": "system", "content": prompt},
                {
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": data_url}},
                        {"type": "text", "text": "Ambil data transaksi dari gambar ini."},
                    ],
                },
            ],
            "max_tokens": 4096,
        }

        plan = vision_plan()
        if not plan:
            raise OcrApiKeyError()

        last_exc: Exception | None = None

        async with _ocr_semaphore:
            for attempt in plan:
                for round_no in range(5):
                    resp = None
                    try:
                        async with httpx.AsyncClient(timeout=120) as client:
                            resp = await client.post(
                                attempt.url,
                                headers=attempt.headers,
                                json={**payload, "model": attempt.model},
                            )
                    except (httpx.TimeoutException, httpx.RequestError) as exc:
                        last_exc = exc
                        await asyncio.sleep((2 ** round_no) + _random.uniform(0, 1))
                        continue

                    if resp.status_code == 200:
                        body = resp.json()
                        content = body["choices"][0]["message"]["content"].strip()
                        content = re.sub(r"^```(?:json)?\s*", "", content)
                        content = re.sub(r"\s*```$", "", content)
                        return content

                    logger.warning(
                        "OCR vision via %s HTTP %s: %s",
                        attempt.provider,
                        resp.status_code,
                        (resp.text or "")[:300],
                    )
                    if resp.status_code == 429:
                        last_exc = OcrVisionApiError(
                            "Kebanyakan request. Tunggu sebentar, coba lagi.",
                            status_code=429,
                        )
                        break  # quota → try the next provider now
                    if resp.status_code in (401, 403):
                        last_exc = OcrVisionApiError(
                            f"Vision API error: HTTP {resp.status_code}"
                        )
                        break  # bad key → try the next provider now
                    last_exc = OcrVisionApiError(
                        f"Vision API error: HTTP {resp.status_code}"
                    )
                    if resp.status_code >= 500:
                        await asyncio.sleep((2 ** round_no) + _random.uniform(1, 3))
                        continue
                    break

        if last_exc:
            raise last_exc
        raise OcrVisionApiError("Layanan baca struk mentok setelah dicoba ulang")
