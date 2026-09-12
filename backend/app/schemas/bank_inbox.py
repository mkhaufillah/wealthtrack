
from pydantic import BaseModel, Field


class BankInboxIn(BaseModel):
    package: str = Field(min_length=3, max_length=200)
    title: str = Field(default="", max_length=300)
    text: str = Field(default="", max_length=2000)
    posted_at: str = Field(default="", max_length=40)


class BankInboxConfirmIn(BaseModel):
    category_id: int | None = Field(default=None, gt=0)
    internal: bool = False
    pair_id: int | None = Field(default=None, gt=0)


class BankInboxItem(BaseModel):
    id: int
    bank: str | None
    package: str
    title: str
    text: str
    posted_at: str
    amount: int | None
    type: str | None
    merchant: str
    parsed: bool
    status: str
    transaction_id: int | None
    created_at: str
    suggested_category_id: int | None = None
    pair_id: int | None = None
    internal_suggested: bool = False


class BankInboxList(BaseModel):
    items: list[BankInboxItem]
    pending_count: int
