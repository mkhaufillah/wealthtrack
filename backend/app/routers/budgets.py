from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.schemas.budget import (
    BudgetCreate,
    BudgetResponse,
    BudgetSummaryItem,
    BudgetSummaryResponse,
    UnbudgetedExpense,
    BudgetSuggestion,
    BudgetSuggestionResponse,
    BudgetHealthResponse,
)
from app.services.budget_service import (
    BudgetService,
    BudgetNotFoundError,
    CategoryNotFoundError,
)

router = APIRouter(prefix="/budgets", tags=["budgets"])


def _get_service(db: CursorWrapper) -> BudgetService:
    """Factory — keep router stateless."""
    return BudgetService(db)


@router.get("", response_model=list[BudgetResponse])
async def list_budgets(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    service = _get_service(db)
    rows = await service.list_budgets(current_user["id"], month)
    return [BudgetResponse(**r) for r in rows]


@router.post("", status_code=201, response_model=BudgetResponse)
async def create_or_update_budget(
    data: BudgetCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    service = _get_service(db)
    try:
        result = await service.create_or_update_budget(
            user_id=current_user["id"],
            month=data.month,
            category_id=data.category_id,
            amount=data.amount,
            cycle_on_override=data.cycle_on,
        )
    except CategoryNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    return BudgetResponse(**result)


@router.delete("/{budget_id}", status_code=204)
async def delete_budget(
    budget_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    service = _get_service(db)
    try:
        await service.delete_budget(current_user["id"], budget_id)
    except BudgetNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.get("/summary", response_model=BudgetSummaryResponse)
async def budget_summary(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    use_cycle: bool = Query(False, description="Use user's billing cycle for actuals date range"),
    d_from_override: Optional[str] = Query(None, description="Override date_from for non-budget expense query"),
    d_to_override: Optional[str] = Query(None, description="Override date_to for non-budget expense query"),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Budgets vs actual spending for a given month."""
    service = _get_service(db)
    data = await service.get_summary(
        user_id=current_user["id"],
        month=month,
        use_cycle=use_cycle,
        d_from_override=d_from_override,
        d_to_override=d_to_override,
    )
    return BudgetSummaryResponse(
        items=[BudgetSummaryItem(**it) for it in data["items"]],
        uncategorized_expenses=[UnbudgetedExpense(**ue) for ue in data["uncategorized_expenses"]],
    )


@router.get("/suggestions", response_model=BudgetSuggestionResponse)
async def budget_suggestions(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    num_cycles: int = Query(3, ge=1, le=12),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Analyse historical spending and suggest budget amounts per category."""
    service = _get_service(db)
    data = await service.get_suggestions(
        user_id=current_user["id"],
        month=month,
        num_cycles=num_cycles,
    )
    return BudgetSuggestionResponse(
        items=[BudgetSuggestion(**it) for it in data["items"]],
        total_suggested=data["total_suggested"],
        total_income=data["total_income"],
        warning=data["warning"],
    )


@router.get("/health", response_model=BudgetHealthResponse)
async def budget_health(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get budget health forecast — projected end-of-cycle spending vs budget."""
    service = _get_service(db)
    return await service.get_health(
        user_id=current_user["id"],
        month=month,
    )
