
from pydantic import BaseModel, Field


class RatePeriodIn(BaseModel):
    period_start: int = Field(ge=1)
    period_end: int = Field(ge=1)
    interest_rate: float = Field(ge=0, le=1)
    rate_type: str = "fixed"


class KPRCalculateRequest(BaseModel):
    property_price: int = Field(ge=0)
    down_payment: int = Field(ge=0, default=0)
    tenor_months: int = Field(ge=12, le=360)
    interest_type: str = "fixed"
    base_interest_rate: float = 0.075
    graduated_increment: float = 0.005
    graduated_every_months: int = 12
    rate_periods: list[RatePeriodIn] = []


class KPRCalculateOut(BaseModel):
    total_loan: int
    tenor_months: int
    monthly_payment: int
    total_payment: int
    total_interest: int
    total_months: int


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
    due_date: int | None = Field(None, ge=1, le=31)
    household_id: int | None = None


class KPRSimulationUpdate(BaseModel):
    name: str | None = None
    property_price: int | None = None
    down_payment: int | None = None
    tenor_months: int | None = None


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
    due_date: int | None = None
    current_month_number: int = 1
    current_month_payment: int = 0
    current_remaining_balance: int = 0
    household_id: int | None = None
    display_order: int = 0


class KPRSimulationDetailOut(KPRSimulationOut):
    schedule: list[KPRScheduleItemOut]
    summary: dict


class ExtraPaymentCreate(BaseModel):
    amount: int = Field(ge=1000)
    apply_month: int = Field(ge=1, le=600)
    reduction_type: str = Field("tenor", pattern=r"^(tenor|installment)$")


class ExtraPaymentPreviewRequest(BaseModel):
    amount: int = Field(ge=1000)
    apply_month: int = Field(ge=1, le=600)


class ExtraPaymentOptionOut(BaseModel):
    new_installment: int
    new_tenor: int
    total_interest_paid: int
    interest_saved: int
    end_date: str


class ExtraPaymentPreviewOut(BaseModel):
    option_installment: ExtraPaymentOptionOut
    option_tenor: ExtraPaymentOptionOut
    comparison: dict


class ExtraPaymentOut(BaseModel):
    id: int
    simulation_id: int
    amount: int = 0
    apply_month: int = 1
    reduction_type: str = "tenor"
    old_remaining_balance: int = 0
    new_remaining_balance: int = 0
    old_remaining_months: int = 0
    new_remaining_months: int = 0
    old_installment: int = 0
    new_installment: int = 0
    total_interest_saved: int = 0
    original_end_date: str = ""
    new_end_date: str = ""
    created_at: str = ""
