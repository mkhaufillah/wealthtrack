from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.services.export_service import ExportService

router = APIRouter(prefix="/exports", tags=["exports"])


@router.get("/yearly")
async def export_yearly(
    year: int = Query(..., ge=2020, le=2100),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Export all transactions for a given year as .xlsx.

    One sheet per month (12 sheets). Columns: Date | Type | Category | Amount | Description | Note | Owner.
    Each sheet ends with a summary row (total income, total expense, balance).
    """
    try:
        import openpyxl  # noqa: F401 — ensure it's available before delegating
    except ImportError:
        raise HTTPException(status_code=500, detail="openpyxl not installed")

    service = ExportService(db)
    buf, filename = await service.export_yearly(year=year, user_id=current_user["id"])

    return StreamingResponse(
        buf,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )

