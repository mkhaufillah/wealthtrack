from pydantic import BaseModel, Field
from typing import Optional


class BudgetCreate(BaseModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")  # "2026-05"
    category_id: int
    amount: int
    cycle_on: Optional[int] = Field(None, ge=1, le=28, description="Override cycle day for this budget. If omitted, uses user's current cycle setting (new) or keeps original (update).")


class BudgetResponse(BaseModel):
    id: int
    month: str
    category_id: int
    category_name: str
    category_icon: str
    amount: int


class BudgetSummaryItem(BaseModel):
    id: int
    category_id: int
    category_name: str
    category_icon: str
    budget_amount: int
    actual_spent: int
    percentage: float
    remaining: int
