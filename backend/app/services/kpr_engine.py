"""KPR (Mortgage) Calculation Engine.

Supports:
- Fixed rate (suku bunga tetap)
- Floating rate (suku bunga mengambang)
- Graduated rate (suku bunga berjenjang)
- Mix (kombinasi fixed + floating + graduated)
"""

from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional


@dataclass
class MonthlySchedule:
    month_number: int
    payment: int
    principal: int
    interest: int
    remaining_balance: int
    rate_type: str
    interest_rate: float


@dataclass
class RatePeriod:
    period_start: int
    period_end: int
    interest_rate: float
    rate_type: str = "fixed"


def _decimal(value: float) -> Decimal:
    return Decimal(str(value))


def _annual_to_monthly(annual_rate: float) -> Decimal:
    """Convert annual interest rate to monthly."""
    return _decimal(annual_rate) / Decimal('12')


def _calculate_payment(
    principal: Decimal,
    monthly_rate: Decimal,
    remaining_months: int,
) -> Decimal:
    """Calculate monthly payment using standard amortization formula.
    
    M = P * (r * (1+r)^n) / ((1+r)^n - 1)
    """
    if monthly_rate == 0:
        return principal / Decimal(str(remaining_months))
    one_plus_r = Decimal('1') + monthly_rate
    numerator = principal * monthly_rate * (one_plus_r ** remaining_months)
    denominator = (one_plus_r ** remaining_months) - Decimal('1')
    return numerator / denominator


def calculate_kpr(
    total_loan: int,
    tenor_months: int,
    rate_periods: Optional[list[RatePeriod]] = None,
    interest_type: str = "fixed",
    base_interest_rate: float = 0.075,
    graduated_increment: float = 0.005,
    graduated_every_months: int = 12,
) -> list[MonthlySchedule]:
    """Calculate full KPR amortization schedule.

    Args:
        total_loan: Total loan amount in IDR (property price - down payment)
        tenor_months: Loan tenure in months
        rate_periods: For 'mix' type, explicit rate periods
        interest_type: 'fixed', 'floating', 'graduated', or 'mix'
        base_interest_rate: Base annual interest rate (e.g. 0.075 = 7.5%)
        graduated_increment: Annual rate increment for graduated type
        graduated_every_months: How often rate changes for graduated

    Returns:
        List of MonthlySchedule for each month
    """
    remaining = _decimal(total_loan)
    schedule: list[MonthlySchedule] = []

    for month in range(1, tenor_months + 1):
        # Determine current rate for this month
        current_rate: float = base_interest_rate
        current_rate_type: str = interest_type

        if interest_type == "mix" and rate_periods:
            for rp in rate_periods:
                if rp.period_start <= month <= rp.period_end:
                    current_rate = rp.interest_rate
                    current_rate_type = rp.rate_type
                    break
        elif interest_type == "graduated":
            periods_passed = (month - 1) // graduated_every_months
            current_rate = base_interest_rate + (graduated_increment * periods_passed)
            current_rate_type = "graduated"

        monthly_rate = _annual_to_monthly(current_rate)
        remaining_months = tenor_months - month + 1

        # Calculate payment
        payment = _calculate_payment(remaining, monthly_rate, remaining_months)

        # Round to integer (IDR)
        interest_amount = (remaining * monthly_rate).to_integral_value(rounding=ROUND_HALF_UP)
        principal_amount = (payment - interest_amount).to_integral_value(rounding=ROUND_HALF_UP)
        payment_amount = principal_amount + interest_amount

        schedule.append(MonthlySchedule(
            month_number=month,
            payment=int(payment_amount),
            principal=int(principal_amount),
            interest=int(interest_amount),
            remaining_balance=int(remaining - principal_amount),
            rate_type=current_rate_type,
            interest_rate=current_rate,
        ))

        remaining -= principal_amount

    return schedule


def simulate_summary(schedule: list[MonthlySchedule]) -> dict:
    """Calculate summary stats from a full schedule."""
    if not schedule:
        return {
            "total_payment": 0,
            "total_interest": 0,
            "monthly_payment": 0,
            "total_months": 0,
        }
    return {
        "total_payment": sum(s.payment for s in schedule),
        "total_interest": sum(s.interest for s in schedule),
        "monthly_payment": schedule[0].payment if schedule else 0,
        "total_months": len(schedule),
    }
