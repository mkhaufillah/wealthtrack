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
    name_id: str = ""
    name_en: str = ""


class CategoryCreate(BaseModel):
    name: str
    type: Literal["expense", "income"]
    icon: str = "strokeRoundedInvoice01"
    keywords: list[str] = []
    sort_order: int = 0
    name_en: Optional[str] = None


class CategoryUpdate(BaseModel):
    name: Optional[str] = None
    icon: Optional[str] = None
    keywords: Optional[list[str]] = None
    sort_order: Optional[int] = None
    name_en: Optional[str] = None
