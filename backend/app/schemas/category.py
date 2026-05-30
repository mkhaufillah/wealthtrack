from pydantic import BaseModel
from typing import Optional, Literal


class CategoryOut(BaseModel):
    id: int
    name: str
    name_en: str = ""
    type: str
    icon: str
    is_default: bool
    keywords: list[str] = []


class CategoryCreate(BaseModel):
    name: str
    name_en: str = ""
    type: Literal["expense", "income"]
    icon: str = ""
    keywords: list[str] = []
    sort_order: int = 0


class CategoryUpdate(BaseModel):
    name: Optional[str] = None
    name_en: Optional[str] = None
    icon: Optional[str] = None
    keywords: Optional[list[str]] = None
    sort_order: Optional[int] = None
