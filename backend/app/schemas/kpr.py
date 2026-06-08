from pydantic import BaseModel, Field
from typing import Optional


class RatePeriodIn(BaseModel):
    period_start: int = Field(ge=1)
    period_end: int = Field(ge=1)
    interest_rate: float = Field(ge=0, le=1)
    rate_type: str = "fixed"


class KPRSimulationCreate(BaseModel):
    name: str = "KPR Simulation"
    property_price: int = Field(ge=0)
    down_payment: int = Field(ge=0, default=0)
    tenor_months: int = Field(ge=12, le=360)
    interest_type: str = "fixed"
    base_interest_rate: float = 0.075
    graduated_increment: float = 0.005
    graduated_every_months: int = 12
    rate_periods: list[RatePeriodIn] = []
    start_month: int = Field(1, ge=1, le=12)
    start_year: int = Field(2026, ge=2000, le=2100)
    due_date: Optional[int] = Field(None, ge=1, le=31)


class KPRSimulationUpdate(BaseModel):
    name: Optional[str] = None
    property_price: Optional[int] = None
    down_payment: Optional[int] = None
    tenor_months: Optional[int] = None


class KPRScheduleItemOut(BaseModel):
    month_number: int
    payment: int
    principal: int
    interest: int
    remaining_balance: int
    rate_type: str
    interest_rate: float


class KPRSimulationOut(BaseModel):
    id: int
    user_id: int
    name: str
    property_price: int
    down_payment: int
    total_loan: int
    tenor_months: int
    interest_type: str
    created_at: str
    total_interest: int = 0
    monthly_payment: int = 0
    start_month: int = 1
    start_year: int = 2026
    due_date: Optional[int] = None
    current_month_number: int = 1
    current_month_payment: int = 0
    current_remaining_balance: int = 0


class KPRSimulationDetailOut(KPRSimulationOut):
    schedule: list[KPRScheduleItemOut]
    summary: dict
