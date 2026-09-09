from pydantic import BaseModel
from typing import Optional, Literal


class CategoryOut(BaseModel):
    id: int
    name: str
    type: str
    icon: str
    is_default: bool
    keywords: list[str] = []
    copy_key: str = ""


class CategoryCreate(BaseModel):
    name: str
    type: Literal["expense", "income"]
    icon: str = "strokeRoundedInvoice01"
    keywords: list[str] = []
    sort_order: int = 0


class CategoryUpdate(BaseModel):
    name: Optional[str] = None
    icon: Optional[str] = None
    keywords: Optional[list[str]] = None
    sort_order: Optional[int] = None
