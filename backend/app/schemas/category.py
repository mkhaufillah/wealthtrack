from pydantic import BaseModel


class CategoryOut(BaseModel):
    id: int
    name: str
    type: str
    icon: str
    is_default: bool
