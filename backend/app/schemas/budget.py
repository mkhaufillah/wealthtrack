from pydantic import BaseModel
from typing import Optional


class BudgetCreate(BaseModel):
    month: str  # "2026-05"
    category_id: int
    amount: int


class BudgetResponse(BaseModel):
    id: int
    month: str
    category_id: int
    category_name: str
    category_icon: str
    amount: int


class BudgetSummaryItem(BaseModel):
    category_id: int
    category_name: str
    category_icon: str
    budget_amount: int
    actual_spent: int
    percentage: float
    remaining: int
