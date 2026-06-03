"""AI-powered budget utilities: historical analysis, suggestions, projections."""
from datetime import date, datetime, timezone
from app.utils.cycle import get_cycle_range_for_month


async def get_historical_spending(
    db,
    user_id: int,
    cycle_start_day: int = 1,
    num_cycles: int = 3,
) -> list[dict]:
    """Analyze avg/max spending per expense category over last N cycles.

    Returns list of dicts with: category_id, category_name, category_name_en,
    category_icon, avg_amount, max_amount, months_analyzed.
    Only categories with at least one transaction in the period are included.
    """
    today = date.today()
    cycles = []
    # Build a list of (month_param,) for the last N cycles
    for i in range(num_cycles):
        y = today.year
        m = today.month - i
        while m < 1:
            m += 12
            y -= 1
        month_str = f"{y:04d}-{m:02d}"
        d_from, d_to = get_cycle_range_for_month(month_str, cycle_start_day)
        cycles.append((d_from.isoformat(), d_to.isoformat()))

    # Build conditions for each cycle
    or_conditions = " OR ".join(
        "(COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ? AND "
        "COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?)"
        for _ in range(num_cycles)
    )
    params = []
    for d_from, d_to in cycles:
        params.extend([d_from, d_to])

    cursor = await db.execute(
        f"""SELECT t.category_id,
                   c.name AS category_name,
                   c.name_en AS category_name_en,
                   c.icon AS category_icon,
                   CAST(COALESCE(AVG(t.amount), 0) AS INTEGER) AS avg_amount,
                   CAST(COALESCE(MAX(t.amount), 0) AS INTEGER) AS max_amount,
                   COUNT(DISTINCT LEFT(COALESCE(t.date, LEFT(t.created_at::text, 10)), 7))
                       AS months_with_data
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.user_id = ?
              AND t.type = 'expense'
              AND ({or_conditions})
            GROUP BY t.category_id, c.name, c.name_en, c.icon
            ORDER BY avg_amount DESC""",
        (user_id, *params),
    )
    rows = await cursor.fetchall()
    return [
        {
            "category_id": r["category_id"],
            "category_name": r["category_name"] or f"Cat#{r['category_id']}",
            "category_name_en": r["category_name_en"] or "",
            "category_icon": r["category_icon"] or "📦",
            "avg_amount": r["avg_amount"],
            "max_amount": r["max_amount"],
            "months_analyzed": r["months_with_data"],
        }
        for r in rows
    ]


async def get_projection(
    db,
    user_id: int,
    cycle_start_day: int,
    d_from: str,
    d_to: str,
) -> dict:
    """Calculate mid-cycle budget projections.

    Returns dict with:
    - days_elapsed: number of days into the cycle
    - total_days: total days in cycle
    - cycle_progress_pct: percentage of cycle completed
    - categories: list per budget with projected_end_amount
    """
    d_from_date = date.fromisoformat(d_from)
    d_to_date = date.fromisoformat(d_to)
    total_days = (d_to_date - d_from_date).days or 1
    today = date.today()
    days_elapsed = max(1, (today - d_from_date).days)
    progress_pct = round(days_elapsed / total_days * 100, 1)

    # Get budgets with actual spending for this cycle
    cursor = await db.execute(
        """SELECT b.category_id, b.category_name, b.budget_amount,
                  c.icon AS category_icon,
                  c.name_en AS category_name_en,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS actual
           FROM budgets b
           LEFT JOIN categories c ON b.category_id = c.id
           LEFT JOIN transactions t ON t.category_id = b.category_id
               AND t.user_id = b.user_id
               AND COALESCE(t.date, LEFT(t.created_at::text, 10)) BETWEEN ? AND ?
           WHERE b.month = ? AND b.user_id = ?
           GROUP BY b.category_id, b.category_name, b.budget_amount, c.icon, c.name_en""",
        (d_from, d_to, d_from_date.strftime("%Y-%m"), user_id),
    )
    rows = await cursor.fetchall()

    categories = []
    for r in rows:
        actual = r["actual"]
        budget = r["budget_amount"]
        pct = round(actual / budget * 100, 1) if budget > 0 else 0.0
        remaining = budget - actual
        daily_rate = int(actual / days_elapsed) if days_elapsed > 0 else 0
        projected_end = int(daily_rate * total_days)
        projected_remaining = budget - projected_end

        if pct >= 100:
            health = "exhausted"
        elif projected_remaining < 0:
            health = "at_risk"
        elif pct >= 70:
            health = "warning"
        else:
            health = "healthy"

        categories.append({
            "category_id": r["category_id"],
            "category_name": r["category_name"],
            "category_name_en": r["category_name_en"] or "",
            "category_icon": r["category_icon"] or "📦",
            "budget_amount": budget,
            "actual_spent": actual,
            "percentage": pct,
            "remaining": remaining,
            "daily_rate": daily_rate,
            "projected_end": projected_end,
            "projected_remaining": projected_remaining,
            "health": health,
        })

    return {
        "days_elapsed": days_elapsed,
        "total_days": total_days,
        "cycle_progress_pct": progress_pct,
        "categories": categories,
    }
