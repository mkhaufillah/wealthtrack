from typing import Optional

from fastapi import APIRouter, Depends, Query

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.services.summary_service import SummaryService

router = APIRouter(prefix="/summaries", tags=["summaries"])


@router.get("/daily")
async def daily_summary(
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Income/expense summary for a specific date range (single-user)."""
    service = SummaryService(db)
    return await service.get_daily_summary(
        user_id=current_user["id"],
        date_from=date_from,
        date_to=date_to,
    )


@router.get("/household")
async def household_summary(
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Household-wide summary across members of the current user's household."""
    service = SummaryService(db)
    return await service.get_household_summary(
        user_id=current_user["id"],
        date_from=date_from,
        date_to=date_to,
    )


@router.get("/monthly")
async def monthly_summary(
    month: Optional[str] = Query(None, pattern=r"^\d{4}-\d{2}$"),
    month_from: Optional[str] = Query(None, pattern=r"^\d{4}-\d{2}$"),
    month_to: Optional[str] = Query(None, pattern=r"^\d{4}-\d{2}$"),
    d_from_override: Optional[str] = Query(None, description="Explicit date_from (YYYY-MM-DD) for cycle support"),
    d_to_override: Optional[str] = Query(None, description="Explicit date_to (YYYY-MM-DD) for cycle support"),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Monthly summary for a given month (YYYY-MM). Default: current month.

    With month_from + month_to, returns an array of monthly summaries
    (multi-month range) for trend charts.

    With d_from_override + d_to_override, overrides the date range
    (used for billing cycle support from client).
    """
    service = SummaryService(db)
    return await service.get_monthly_summary(
        user_id=current_user["id"],
        month=month,
        month_from=month_from,
        month_to=month_to,
        d_from_override=d_from_override,
        d_to_override=d_to_override,
    )


@router.get("/current-month")
async def current_month_summary(
    use_cycle: bool = Query(False, description="Use user's billing cycle instead of calendar month"),
    ref_date: Optional[str] = Query(None, description="Reference date (YYYY-MM-DD). Defaults to server today."),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Shorthand — monthly summary for the current cycle or month."""
    service = SummaryService(db)
    return await service.get_current_month_summary(
        user_id=current_user["id"],
        use_cycle=use_cycle,
        ref_date=ref_date,
    )


@router.get("/cycle-info")
async def cycle_info(
    ref_date_str: Optional[str] = Query(None, alias="date", description="Reference date (YYYY-MM-DD). Defaults to today."),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Return the billing cycle date range for a given reference date."""
    service = SummaryService(db)
    return await service.get_cycle_info(
        user_id=current_user["id"],
        ref_date_str=ref_date_str,
    )


@router.get("/all-time-category-balance")
async def all_time_category_balance(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Returns all-time balance for Savings & Investment and Emergency Funds."""
    service = SummaryService(db)
    return await service.get_all_time_category_balance(
        user_id=current_user["id"],
    )


@router.get("/debt")
async def debt_summary(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Total remaining debt: KPR remaining principal + CC transactions + CC installment remaining."""
    service = SummaryService(db)
    return await service.get_debt_summary(
        user_id=current_user["id"],
    )


@router.get("/debt/household")
async def household_debt_summary(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Household-wide debt summary — aggregate across all household members."""
    service = SummaryService(db)
    return await service.get_household_debt_summary(
        user_id=current_user["id"],
    )
