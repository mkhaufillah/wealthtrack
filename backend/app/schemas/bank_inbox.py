from typing import Optional

from pydantic import BaseModel, Field


class BankInboxIn(BaseModel):
    package: str = Field(min_length=3, max_length=200)
    title: str = Field(default="", max_length=300)
    text: str = Field(default="", max_length=2000)
    posted_at: str = Field(default="", max_length=40)


class BankInboxConfirmIn(BaseModel):
    category_id: Optional[int] = Field(default=None, gt=0)


class BankInboxItem(BaseModel):
    id: int
    bank: Optional[str]
    package: str
    title: str
    text: str
    posted_at: str
    amount: Optional[int]
    type: Optional[str]
    merchant: str
    parsed: bool
    status: str
    transaction_id: Optional[int]
    created_at: str


class BankInboxList(BaseModel):
    items: list[BankInboxItem]
    pending_count: int
