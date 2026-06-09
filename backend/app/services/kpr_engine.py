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
class ExtraPaymentResult:
    old_remaining_balance: int
    new_remaining_balance: int
    old_remaining_months: int
    new_remaining_months: int
    old_installment: int
    new_installment: int
    total_interest_paid: int
    total_interest_saved: int
    original_end_date: str
    new_end_date: str
    schedule: list[MonthlySchedule]


@dataclass
class ExtraPaymentComparison:
    option_installment: ExtraPaymentResult  # Opsi A — kurangi cicilan
    option_tenor: ExtraPaymentResult       # Opsi B — kurangi tenor


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


def _calc_end_date(start_month: int, start_year: int, months: int) -> str:
    """Calculate end date string (YYYY-MM) from start + months ahead."""
    total_months = start_month + months - 1
    y = start_year + (total_months - 1) // 12
    m = ((total_months - 1) % 12) + 1
    return f"{y}-{m:02d}"


def _get_current_installment_and_balance(
    schedule: list[MonthlySchedule],
    apply_month: int,
) -> tuple[int, int, int]:
    """Get the monthly payment amount, remaining balance, and remaining months
    at the given apply_month (before that month's payment is made).

    apply_month is 1-based. The balance at month N is the remaining_balance
    from month N-1 (or total_loan if N=1).
    """
    if apply_month <= 1:
        # Balance before first payment = total from month 1
        bal = schedule[0].remaining_balance + schedule[0].principal
        installment = schedule[0].payment
        remaining_months = len(schedule)
    else:
        prev = schedule[apply_month - 2]  # 0-indexed
        bal = prev.remaining_balance
        installment = schedule[apply_month - 1].payment
        remaining_months = len(schedule) - apply_month + 1

    return installment, bal, remaining_months


def _build_schedule_from(
    principal: Decimal,
    monthly_rate: Decimal,
    payment: Decimal,
    start_month: int,
    total_original_months: int,
    rate_type: str,
    interest_rate: float,
    fixed_tenor: int | None = None,
) -> list[MonthlySchedule]:
    """Build schedule starting from a given month.

    If fixed_tenor is set (Opsi A), use that many months with recalculated payment.
    If not (Opsi B), iterate with fixed payment until balance hits 0.
    """
    schedule: list[MonthlySchedule] = []
    remaining = principal
    month = start_month
    max_iter = (total_original_months - start_month + 1) * 2  # safety cap

    if fixed_tenor is not None:
        # Opsi A: fixed tenor, payment already calculated via _calculate_payment
        for i in range(fixed_tenor):
            interest_amount = (remaining * monthly_rate).to_integral_value(rounding=ROUND_HALF_UP)
            principal_amount = (payment - interest_amount).to_integral_value(rounding=ROUND_HALF_UP)

            if principal_amount <= 0:
                principal_amount = remaining
                payment = interest_amount + principal_amount

            schedule.append(MonthlySchedule(
                month_number=month,
                payment=int(payment),
                principal=int(principal_amount),
                interest=int(interest_amount),
                remaining_balance=int(remaining - principal_amount),
                rate_type=rate_type,
                interest_rate=interest_rate,
            ))
            remaining -= principal_amount
            month += 1
            if remaining <= 0:
                break
    else:
        # Opsi B: fixed payment, iterate until balance hits 0
        iterations = 0
        while remaining > 0 and iterations < max_iter:
            interest_amount = (remaining * monthly_rate).to_integral_value(rounding=ROUND_HALF_UP)
            principal_amount = (payment - interest_amount).to_integral_value(rounding=ROUND_HALF_UP)

            if principal_amount <= 0:
                # Payment too small, force payoff
                principal_amount = remaining
                payment = interest_amount + principal_amount

            new_balance = remaining - principal_amount
            schedule.append(MonthlySchedule(
                month_number=month,
                payment=int(payment),
                principal=int(principal_amount),
                interest=int(interest_amount),
                remaining_balance=int(new_balance),
                rate_type=rate_type,
                interest_rate=interest_rate,
            ))
            remaining -= principal_amount
            month += 1
            iterations += 1

    return schedule


def apply_extra_payment(
    schedule: list[MonthlySchedule],
    extra_amount: int,
    apply_month: int,
    penalty_rate: float = 0,
    reduction_type: str = "tenor",
    start_month: int = 1,
    start_year: int = 2026,
) -> ExtraPaymentResult:
    """Apply extra payment at a specific month.

    - reduction_type='tenor' (Opsi B): Keep same monthly payment, shorten tenor.
    - reduction_type='installment' (Opsi A): Keep same tenor, lower monthly payment.

    Returns the new schedule + savings info.
    """
    # Get current state at apply_month
    current_installment, remaining_balance, remaining_months = (
        _get_current_installment_and_balance(schedule, apply_month)
    )

    # Apply penalty
    extra_with_penalty = extra_amount
    penalty_amount = 0
    if penalty_rate > 0:
        penalty_amount = int(extra_amount * penalty_rate)
        extra_with_penalty = extra_amount - penalty_amount

    new_balance = remaining_balance - extra_with_penalty
    if new_balance < 0:
        new_balance = 0

    # Get the rate info at apply_month
    current_entry = schedule[apply_month - 1] if apply_month <= len(schedule) else schedule[-1]
    monthly_rate = _annual_to_monthly(current_entry.interest_rate)

    # Calculate original total interest (schedule before extra payment)
    # from apply_month onwards
    original_total_interest = sum(
        s.interest for s in schedule[apply_month - 1:]
    )

    if reduction_type == "installment":
        # Opsi A: Keep same tenor, recalculate installment
        new_tenor = remaining_months
        new_payment_dec = _calculate_payment(
            _decimal(new_balance), monthly_rate, new_tenor
        )

        new_schedule = _build_schedule_from(
            principal=_decimal(new_balance),
            monthly_rate=monthly_rate,
            payment=new_payment_dec,
            start_month=apply_month,
            total_original_months=len(schedule),
            rate_type=current_entry.rate_type,
            interest_rate=current_entry.interest_rate,
            fixed_tenor=new_tenor,
        )

        new_installment = new_schedule[0].payment if new_schedule else 0
        new_total_interest = sum(s.interest for s in new_schedule)
        new_months = len(new_schedule)

    else:
        # Opsi B: Keep same installment, shorten tenor
        new_payment_dec = _decimal(current_installment)

        new_schedule = _build_schedule_from(
            principal=_decimal(new_balance),
            monthly_rate=monthly_rate,
            payment=new_payment_dec,
            start_month=apply_month,
            total_original_months=len(schedule),
            rate_type=current_entry.rate_type,
            interest_rate=current_entry.interest_rate,
        )

        new_installment = new_schedule[0].payment if new_schedule else 0
        new_total_interest = sum(s.interest for s in new_schedule)
        new_months = len(new_schedule)

    total_interest_saved = original_total_interest - new_total_interest
    if total_interest_saved < 0:
        total_interest_saved = 0

    # Build the combined schedule (months before extra payment + after)
    combined_schedule = schedule[:apply_month - 1] + new_schedule

    original_end_date = _calc_end_date(start_month, start_year, len(schedule))
    new_end_date = _calc_end_date(start_month, start_year, len(combined_schedule))

    return ExtraPaymentResult(
        old_remaining_balance=remaining_balance,
        new_remaining_balance=new_balance,
        old_remaining_months=remaining_months,
        new_remaining_months=len(new_schedule),
        old_installment=current_installment,
        new_installment=new_installment,
        total_interest_paid=new_total_interest,
        total_interest_saved=total_interest_saved,
        original_end_date=original_end_date,
        new_end_date=new_end_date,
        schedule=combined_schedule,
    )


def preview_extra_payment(
    schedule: list[MonthlySchedule],
    extra_amount: int,
    apply_month: int,
    penalty_rate: float = 0,
    start_month: int = 1,
    start_year: int = 2026,
) -> ExtraPaymentComparison:
    """Preview both reduction options side-by-side. No side effects."""
    opt_installment = apply_extra_payment(
        schedule, extra_amount, apply_month, penalty_rate,
        reduction_type="installment", start_month=start_month, start_year=start_year,
    )
    opt_tenor = apply_extra_payment(
        schedule, extra_amount, apply_month, penalty_rate,
        reduction_type="tenor", start_month=start_month, start_year=start_year,
    )
    return ExtraPaymentComparison(
        option_installment=opt_installment,
        option_tenor=opt_tenor,
    )
