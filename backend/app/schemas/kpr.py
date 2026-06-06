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


class KPRSimulationDetailOut(KPRSimulationOut):
    schedule: list[KPRScheduleItemOut]
    summary: dict
