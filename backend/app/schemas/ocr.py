"""OCR Pydantic response schemas."""
from typing import Optional
from pydantic import BaseModel


class OcrResult(BaseModel):
    amount: Optional[int] = None
    description: Optional[str] = None
    date: Optional[str] = None  # YYYY-MM-DD
    category_name: Optional[str] = None
    type: Optional[str] = None  # "expense" or "income"
    note: Optional[str] = None
    raw_text: str = ""


class OcrAutoSaveResult(BaseModel):
    job_id: int
    transaction_id: Optional[int] = None
    status: str = "processing"


class OcrPendingCount(BaseModel):
    count: int
    error: Optional[str] = None
    has_failure: bool = False
    failed_job_id: Optional[int] = None
