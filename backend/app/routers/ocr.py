import logging

# kept for test mock compatibility (test_ocr.py monkeypatches app.routers.ocr.httpx)
import httpx  # noqa: F401
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.core.rate_limiter import check_rate_limit
from app.core.security import get_current_user
from app.database import get_db
from app.schemas.ocr import OcrAutoSaveResult, OcrPendingCount, OcrResult
from app.services.ocr_service import (
    OcrApiKeyError,
    OcrBusyError,
    OcrError,
    OcrImageError,
    OcrService,
    OcrTimeoutError,
    OcrVisionApiError,
)

router = APIRouter(prefix="/ocr", tags=["ocr"])

logger = logging.getLogger(__name__)

# ── Rate limit: max 30 OCR calls per user (Redis sliding window, persisted) ──


async def _check_rate_limit(user_id: int):
    """Redis sliding window: max 30 OCR scans per user per day."""
    await check_rate_limit(
        key=f"ocr:user_{user_id}",
        max_requests=30,
        window_sec=86400,
        error_message="OCR kebanyakan: max 30 kali per hari",
    )


# ── Endpoints ─────────────────────────────────────────────────────────


@router.post("/process", response_model=OcrResult)
async def process_ocr(
    file: UploadFile = File(...),
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Process an image through vision AI to extract transaction data."""
    await _check_rate_limit(current_user["id"])

    if not file.content_type:
        raise HTTPException(status_code=400, detail="Tipe file tidak dikenali")

    image_bytes = await file.read()
    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Gambar terlalu besar (maks 10 MB)")

    service = OcrService(db)
    try:
        result = await service.process_ocr(
            file_bytes=image_bytes,
            content_type=file.content_type,
            user_id=current_user["id"],
        )
    except OcrTimeoutError as e:
        raise HTTPException(status_code=504, detail=e.detail)
    except OcrVisionApiError as e:
        raise HTTPException(
            status_code=getattr(e, "status_code", 502), detail=e.detail
        )
    except OcrApiKeyError as e:
        raise HTTPException(status_code=500, detail=e.detail)
    except OcrImageError as e:
        raise HTTPException(status_code=400, detail=e.detail)
    except OcrError as e:
        raise HTTPException(status_code=502, detail=e.detail)

    return OcrResult(**result)


@router.post("/process-and-save", response_model=OcrAutoSaveResult)
async def process_ocr_and_save(
    file: UploadFile = File(...),
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Process OCR image and auto-save transaction. Returns immediately."""
    await _check_rate_limit(current_user["id"])

    if not file.content_type:
        raise HTTPException(status_code=400, detail="Tipe file tidak dikenali")

    raw = await file.read()
    if len(raw) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Gambar terlalu besar (maks 10 MB)")

    service = OcrService(db)
    try:
        job_info = await service.process_and_save(
            file_bytes=raw,
            content_type=file.content_type,
            filename=file.filename or "receipt.jpg",
            user_id=current_user["id"],
        )
    except OcrBusyError as e:
        raise HTTPException(status_code=429, detail=e.detail)
    except OcrImageError as e:
        raise HTTPException(status_code=400, detail=e.detail)
    except OcrApiKeyError as e:
        raise HTTPException(status_code=500, detail=e.detail)
    except OcrError as e:
        raise HTTPException(status_code=502, detail=e.detail)

    return OcrAutoSaveResult(**job_info)


@router.get("/pending-count", response_model=OcrPendingCount)
async def ocr_pending_count(
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get count of pending OCR jobs and surface recent failures."""
    service = OcrService(db)
    info = await service.get_pending_count(current_user["id"])
    return OcrPendingCount(**info)
