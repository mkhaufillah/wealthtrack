from pydantic import BaseModel, Field
from typing import Optional


class TransactionCreate(BaseModel):
    type: str = Field(pattern="^(expense|income)$")
    category_id: int
    amount: int = Field(gt=0)
    description: str = Field(default="", max_length=255)
    note: str = Field(default="", max_length=500)
    date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")  # YYYY-MM-DD


class TransactionUpdate(BaseModel):
    type: Optional[str] = Field(default=None, pattern=r"^(expense|income)$")
    amount: Optional[int] = Field(default=None, gt=0)
    description: Optional[str] = None
    note: Optional[str] = None
    category_id: Optional[int] = None
    date: Optional[str] = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")


class CategoryBrief(BaseModel):
    id: int
    name: str
    name_en: str = ''
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


class TransferOwnerIn(BaseModel):
    user_id: int = Field(gt=0, description="New owner user ID, must be in same household")


class TransferItem(BaseModel):
    user_id: int = Field(gt=0, description="Recipient user ID, must be in same household")
    amount: int = Field(gt=0, description="Amount to transfer")


class TransferRequest(BaseModel):
    date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$", description="YYYY-MM-DD")
    transfers: list[TransferItem] = Field(min_length=1, max_length=10)


class TransferResult(BaseModel):
    sender_expense: TransactionOut
    recipient_income: TransactionOut


class TransferResponse(BaseModel):
    transactions: list[TransferResult]
