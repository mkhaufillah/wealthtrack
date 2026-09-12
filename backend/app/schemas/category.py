from typing import Literal

from pydantic import BaseModel


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
    name_en: str | None = None


class CategoryUpdate(BaseModel):
    name: str | None = None
    icon: str | None = None
    keywords: list[str] | None = None
    sort_order: int | None = None
    name_en: str | None = None
