from pydantic import BaseModel, Field
from typing import Optional


class TransactionCreate(BaseModel):
    type: str = Field(pattern="^(expense|income)$")
    category_id: int
    amount: int = Field(gt=0)
    description: str = Field(default="", max_length=255)
    note: str = Field(default="", max_length=500)
    date: str  # YYYY-MM-DD


class TransactionUpdate(BaseModel):
    amount: Optional[int] = Field(default=None, gt=0)
    description: Optional[str] = None
    note: Optional[str] = None
    category_id: Optional[int] = None
    date: Optional[str] = None


class CategoryBrief(BaseModel):
    id: int
    name: str
    icon: str


class UserBrief(BaseModel):
    id: int
    display_name: str


class TransactionOut(BaseModel):
    id: int
    amount: int
    type: str
    description: str
    note: str
    date: str
    category: CategoryBrief
    user: UserBrief
    created_at: str
    updated_at: str


class PaginationMeta(BaseModel):
    page: int
    per_page: int
    total: int
    total_pages: int


class PaginatedTransactions(BaseModel):
    data: list[TransactionOut]
    meta: PaginationMeta
