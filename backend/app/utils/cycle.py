"""Billing cycle date range utilities.

Allows users to set a custom "cycle start day" (e.g., 25th) so their
financial period runs from day N of month M to day N-1 of month M+1,
instead of the fixed calendar month (1st–last day).
"""

from datetime import date, timedelta
from typing import Tuple


def get_cycle_range(today: date, cycle_start_day: int = 1) -> Tuple[date, date]:
    """Return (start_date, end_date) for the current billing cycle.

    If cycle_start_day == 1: standard calendar month (1st to last day).
    If cycle_start_day == 25: cycle runs from 25th of previous month
                               to 24th of the current month.

    cycle_start_day must be between 1 and 28.
    For months with fewer days than cycle_start_day, the last valid
    day of the month is used instead (e.g., start_day=31 on Feb -> Feb 28).
    """
    if cycle_start_day == 1:
        # Standard calendar month
        start = date(today.year, today.month, 1)
        if today.month == 12:
            end = date(today.year, 12, 31)
        else:
            end = date(today.year, today.month + 1, 1) - timedelta(days=1)
        return start, end

    # Determine cycle start date
    if today.day >= cycle_start_day:
        # Current cycle started this month
        start = _safe_date(today.year, today.month, cycle_start_day)
    else:
        # Current cycle started last month
        prev = _prev_month(today.year, today.month)
        start = _safe_date(prev[0], prev[1], cycle_start_day)

    # End = day before next cycle start
    next_start = _next_cycle_start(start, cycle_start_day)
    end = next_start - timedelta(days=1)

    return start, end


def format_cycle_label(cycle_start: date, cycle_end: date) -> str:
    """Return a human-readable label for a cycle, e.g. '25 Apr – 24 May'."""
    months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    start_str = f"{cycle_start.day} {months[cycle_start.month - 1]}"
    if cycle_start.month == cycle_end.month and cycle_start.year == cycle_end.year:
        return start_str
    end_str = f"{cycle_end.day} {months[cycle_end.month - 1]}"
    if cycle_end.year != cycle_start.year:
        end_str += f" {cycle_end.year}"
    return f"{start_str} – {end_str}"


# ─── Internal helpers ──────────────────────────────────────────


def _safe_date(year: int, month: int, day: int) -> date:
    """Create a date, clamping day to the last valid day of the month."""
    try:
        return date(year, month, day)
    except ValueError:
        # Day exceeds month length — use last day of month
        if month == 12:
            return date(year, 12, 31)
        return date(year, month + 1, 1) - timedelta(days=1)


def _prev_month(year: int, month: int) -> Tuple[int, int]:
    """Return (year, month) of the previous month."""
    if month == 1:
        return year - 1, 12
    return year, month - 1


def _next_cycle_start(current_start: date, cycle_start_day: int) -> date:
    """Return the start date of the next cycle."""
    if current_start.month == 12:
        return _safe_date(current_start.year + 1, 1, cycle_start_day)
    return _safe_date(current_start.year, current_start.month + 1, cycle_start_day)
