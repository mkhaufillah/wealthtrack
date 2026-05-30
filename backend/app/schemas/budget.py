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
    category_name_en: str = ''
    category_icon: str
    amount: int


class BudgetSummaryItem(BaseModel):
    id: int
    category_id: int
    category_name: str
    category_name_en: str = ''
    category_icon: str
    budget_amount: int
    actual_spent: int
    percentage: float
    remaining: int
    cycle_on: int


class UnbudgetedExpense(BaseModel):
    category_id: int
    category_name: str
    category_name_en: str = ''
    category_icon: str
    total: int


class BudgetSummaryResponse(BaseModel):
    items: list[BudgetSummaryItem]
    uncategorized_expenses: list[UnbudgetedExpense] = []


class BudgetSuggestion(BaseModel):
    category_id: int
    category_name: str
    category_name_en: str = ''
    category_icon: str
    suggested_amount: int
    historical_avg: int
    historical_max: int
    months_analyzed: int
    has_budget: bool = False
    existing_amount: int = 0


class BudgetSuggestionResponse(BaseModel):
    items: list[BudgetSuggestion]
    total_suggested: int = 0
    total_income: int = 0
    warning: str = ''


class BudgetHealthItem(BaseModel):
    category_id: int
    category_name: str
    category_name_en: str = ''
    category_icon: str
    budget_amount: int
    actual_spent: int
    percentage: float
    remaining: int
    daily_rate: int
    projected_end: int
    projected_remaining: int
    health: str  # "healthy" | "warning" | "at_risk" | "exhausted"


class BudgetHealthResponse(BaseModel):
    days_elapsed: int
    total_days: int
    cycle_progress_pct: float
    categories: list[BudgetHealthItem]
