"""OCR Pydantic response schemas."""

from pydantic import BaseModel


class OcrResult(BaseModel):
    amount: int | None = None
    description: str | None = None
    date: str | None = None  # YYYY-MM-DD
    category_name: str | None = None
    type: str | None = None  # "expense" or "income"
    note: str | None = None
    raw_text: str = ""


class OcrAutoSaveResult(BaseModel):
    job_id: int
    transaction_id: int | None = None
    status: str = "processing"


class OcrPendingCount(BaseModel):
    count: int
    error: str | None = None
    has_failure: bool = False
    failed_job_id: int | None = None
