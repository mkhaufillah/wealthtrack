from pydantic import BaseModel, Field
from typing import Optional


class CreditCardCreate(BaseModel):
    name: str = Field(min_length=1)
    card_number_last4: str = ""
    billing_date: int = Field(1, ge=1, le=31)
    due_date: int = Field(15, ge=1, le=31)
    credit_limit: int = 0
    household_id: Optional[int] = None


class CreditCardUpdate(BaseModel):
    name: Optional[str] = None
    billing_date: Optional[int] = None
    due_date: Optional[int] = None
    credit_limit: Optional[int] = None


class CreditCardOut(BaseModel):
    id: int
    user_id: int
    name: str
    card_number_last4: str
    billing_date: int
    due_date: int
    credit_limit: int
    created_at: str
    active_installments: int = 0
    household_id: Optional[int] = None
    display_order: int = 0


class CreditCardTransactionCreate(BaseModel):
    description: str = ""
    amount: int = Field(ge=0)
    category_id: Optional[int] = None
    transaction_date: str
    is_installment: bool = False
    installment_id: Optional[int] = None


class CreditCardTransactionOut(BaseModel):
    id: int
    card_id: int
    description: str
    amount: int
    category_id: Optional[int] = None
    transaction_date: str
    is_installment: bool
    installment_id: Optional[int] = None
    created_at: str


class CreditCardInstallmentCreate(BaseModel):
    description: str = ""
    total_amount: int = Field(ge=0)
    monthly_amount: int = Field(ge=0)
    total_months: int = Field(ge=1)
    remaining_months: int = Field(ge=1)
    start_month: str


class CreditCardInstallmentOut(BaseModel):
    id: int
    card_id: int
    description: str
    total_amount: int
    monthly_amount: int
    total_months: int
    remaining_months: int
    start_month: str
    created_at: str


class NextMonthProjection(BaseModel):
    total_installments: int = 0
    total_expected: int = 0
    per_card: list[dict] = []
