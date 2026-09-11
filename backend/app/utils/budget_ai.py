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

    Returns list of dicts with: category_id, category_name,
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

    from app.core.vault_ctx import current_dek, current_sealed
    from app.core.vault_row import unpack_money

    if current_sealed() and current_dek():
        dek = current_dek()
        cursor = await db.execute(
            f"""SELECT * FROM transactions t
                WHERE t.user_id = ? AND t.type = 'expense' AND ({or_conditions})""",
            (user_id, *params),
        )
        buckets: dict = {}
        for raw in await cursor.fetchall():
            d = unpack_money(dek, dict(raw))
            cid = d.get("category_id")
            if cid is None:
                continue
            b = buckets.setdefault(
                int(cid),
                {"category_id": int(cid), "amounts": [], "name": d.get("category_name") or ""},
            )
            b["amounts"].append(int(d.get("amount") or 0))
            if d.get("category_name"):
                b["name"] = d["category_name"]
        ids = list(buckets.keys())
        meta = {}
        if ids:
            ph = ",".join("?" * len(ids))
            cur = await db.execute(
                f"SELECT id, name, icon, copy_key FROM categories WHERE id IN ({ph})",
                tuple(ids),
            )
            meta = {r["id"]: dict(r) for r in await cur.fetchall()}
        out = []
        for cid, b in buckets.items():
            amts = b["amounts"]
            m = meta.get(cid) or {}
            out.append(
                {
                    "category_id": cid,
                    "category_name": b["name"] or m.get("name") or f"Cat#{cid}",
                    "category_icon": m.get("icon") or "strokeRoundedInvoice01",
                    "copy_key": m.get("copy_key") or "",
                    "avg_amount": int(sum(amts) / len(amts)) if amts else 0,
                    "max_amount": max(amts) if amts else 0,
                    "months_analyzed": min(3, max(1, len(amts))),
                }
            )
        out.sort(key=lambda x: -x["avg_amount"])
        return out

    cursor = await db.execute(
        f"""SELECT t.category_id,
                   c.name AS category_name,
                   c.icon AS category_icon,
                   c.copy_key AS copy_key,
                   COALESCE(AVG(t.amount_ord), 0)::bigint AS avg_amount,
                   COALESCE(MAX(t.amount_ord), 0)::bigint AS max_amount,
                   COUNT(DISTINCT LEFT(COALESCE(t.date, LEFT(t.created_at::text, 10)), 7))
                       AS months_with_data
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.user_id = ?
              AND t.type = 'expense'
              AND ({or_conditions})
            GROUP BY t.category_id, c.name, c.icon, c.copy_key
            ORDER BY avg_amount DESC""",
        (user_id, *params),
    )
    rows = await cursor.fetchall()
    return [
        {
            "category_id": r["category_id"],
            "category_name": r["category_name"] or f"Cat#{r['category_id']}",
            "category_icon": r["category_icon"] or "📦",
            "copy_key": r["copy_key"] or "",
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
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_ord ELSE 0 END), 0) AS actual
           FROM budgets b
           LEFT JOIN categories c ON b.category_id = c.id
           LEFT JOIN transactions t ON t.category_id = b.category_id
               AND t.user_id = b.user_id
               AND COALESCE(t.date, LEFT(t.created_at::text, 10)) BETWEEN ? AND ?
           WHERE b.month = ? AND b.user_id = ?
           GROUP BY b.category_id, b.category_name, b.budget_amount, c.icon""",
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
