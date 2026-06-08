from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.utils.cycle import get_cycle_range

router = APIRouter(prefix="/summaries", tags=["summaries"])


def _parse_date_iso(s: str) -> date:
    """Parse date from ISO string — handles both '2026-05-28' and '2026-05-28T00:00:00.000'."""
    try:
        return date.fromisoformat(s)
    except ValueError:
        return datetime.fromisoformat(s).date()


async def _get_cycle_start_day(db : CursorWrapper, user_id: int) -> int:
    cursor = await db.execute(
        "SELECT COALESCE(cycle_start_day, 1) as cycle_start_day FROM users WHERE id = ?",
        (user_id,),
    )
    row = await cursor.fetchone()
    return row["cycle_start_day"] if row else 1


@router.get("/daily")
async def daily_summary(
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db : CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    today = date.today().isoformat()
    d_from = date_from or today
    d_to = date_to or today

    cursor = await db.execute(
        """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
           FROM transactions t
           WHERE t.user_id = ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
           GROUP BY t.type""",
        (current_user["id"], d_from, d_to),
    )
    rows = await cursor.fetchall()
    income = 0
    expense = 0
    for r in rows:
        if r["type"] == "income":
            income = r["total"]
        else:
            expense = r["total"]

    cursor = await db.execute(
        """SELECT c.id, c.name, c.icon, c.name_en AS category_name_en, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t
           JOIN categories c ON t.category_id = c.id
           WHERE t.user_id = ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
             AND t.type = 'expense'
           GROUP BY c.id ORDER BY total DESC""",
        (current_user["id"], d_from, d_to),
    )
    by_cat = await cursor.fetchall()
    categories = []
    for r in by_cat:
        pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
        categories.append(
            {
                "category_id": r["id"],
                "category_name": r["name"],
                "category_name_en": r["category_name_en"] or "",
                "icon": r["icon"] or "",
                "total": int(r["total"]),
                "count": r["count"],
                "percentage": pct,
            }
        )

    # By user (current user breakdown)
    cursor = await db.execute(
        """SELECT t.user_id, u.display_name,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) as total_expense,
                  COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) as total_income
           FROM transactions t
           JOIN users u ON t.user_id = u.id
           WHERE t.user_id = ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
           GROUP BY t.user_id, u.display_name""",
        (current_user["id"], d_from, d_to),
    )
    by_user = await cursor.fetchall()
    users = [
        {
            "user_id": r["user_id"],
            "display_name": r["display_name"],
            "total_expense": int(r["total_expense"]),
            "total_income": int(r["total_income"]),
        }
        for r in by_user
    ]

    return {
        "date_from": d_from,
        "date_to": d_to,
        "total_income": int(income),
        "total_expense": int(expense),
        "balance": int(income - expense),
        "by_category": categories,
        "by_user": users,
    }


@router.get("/household")
async def household_summary(
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db : CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Household-wide summary across members of the current user's household."""
    today = date.today().isoformat()
    d_from = date_from or today
    d_to = date_to or today

    # Get the user's household ID
    cursor = await db.execute(
        "SELECT household_id FROM household_members WHERE user_id = ?",
        (current_user["id"],),
    )
    hm = await cursor.fetchone()
    if not hm:
        # User not in a household — return personal-only summary
        # (same shape but with only current user's data)
        cursor = await db.execute(
            """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
               FROM transactions t
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               GROUP BY t.type""",
            (current_user["id"], d_from, d_to),
        )
        rows = await cursor.fetchall()
        income = 0
        expense = 0
        for r in rows:
            if r["type"] == "income":
                income = r["total"]
            else:
                expense = r["total"]
        user_row = await (await db.execute(
            "SELECT display_name FROM users WHERE id = ?",
            (current_user["id"],),
        )).fetchone()
        display_name = user_row["display_name"] if user_row else ""
        return {
            "date_from": d_from,
            "date_to": d_to,
            "total_income": int(income),
            "total_expense": int(expense),
            "balance": int(income - expense),
            "by_category": [],
            "by_user": [
                {
                    "user_id": current_user["id"],
                    "display_name": display_name,
                    "total_expense": int(expense),
                    "total_income": int(income),
                }
            ],
        }

    household_id = hm["household_id"]

    cursor = await db.execute(
        """SELECT t.type, CAST(COALESCE(SUM(t.amount), 0) AS INTEGER) as total, COUNT(*) as count
           FROM transactions t
           JOIN household_members hm ON hm.user_id = t.user_id AND hm.household_id = ?
           WHERE COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
           GROUP BY t.type""",
        (household_id, d_from, d_to),
    )
    rows = await cursor.fetchall()
    income = 0
    expense = 0
    for r in rows:
        if r["type"] == "income":
            income = r["total"]
        else:
            expense = r["total"]

    cursor = await db.execute(
        """SELECT c.id, c.name, c.icon, c.name_en AS category_name_en, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t
           JOIN categories c ON t.category_id = c.id
           JOIN household_members hm ON hm.user_id = t.user_id AND hm.household_id = ?
           WHERE COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
             AND t.type = 'expense'
           GROUP BY c.id ORDER BY total DESC""",
        (household_id, d_from, d_to),
    )
    by_cat = await cursor.fetchall()
    categories = []
    for r in by_cat:
        pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
        categories.append(
            {
                "category_id": r["id"],
                "category_name": r["name"],
                "category_name_en": r["category_name_en"] or "",
                "icon": r["icon"] or "",
                "total": int(r["total"]),
                "count": r["count"],
                "percentage": pct,
            }
        )

    # By user — LEFT JOIN from household_members so users with 0 transactions still appear
    cursor = await db.execute(
        """SELECT hm.user_id, u.display_name,
                  CAST(COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS INTEGER) as total_expense,
                  CAST(COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) AS INTEGER) as total_income
           FROM household_members hm
           JOIN users u ON hm.user_id = u.id
           LEFT JOIN transactions t ON t.user_id = hm.user_id
               AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
               AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
           WHERE hm.household_id = ?
           GROUP BY hm.user_id, u.display_name ORDER BY total_expense DESC""",
        (d_from, d_to, household_id),
    )
    by_user = await cursor.fetchall()
    users = [
        {
            "user_id": r["user_id"],
            "display_name": r["display_name"],
            "total_expense": int(r["total_expense"]),
            "total_income": int(r["total_income"]),
        }
        for r in by_user
    ]

    return {
        "date_from": d_from,
        "date_to": d_to,
        "total_income": int(income),
        "total_expense": int(expense),
        "balance": int(income - expense),
        "by_category": categories,
        "by_user": users,
    }


@router.get("/monthly")
async def monthly_summary(
    month: Optional[str] = Query(None, pattern=r"^\d{4}-\d{2}$"),
    month_from: Optional[str] = Query(None, pattern=r"^\d{4}-\d{2}$"),
    month_to: Optional[str] = Query(None, pattern=r"^\d{4}-\d{2}$"),
    d_from_override: Optional[str] = Query(None, description="Explicit date_from (YYYY-MM-DD) for cycle support"),
    d_to_override: Optional[str] = Query(None, description="Explicit date_to (YYYY-MM-DD) for cycle support"),
    db : CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Monthly summary for a given month (YYYY-MM). Default: current month.

    With month_from + month_to, returns an array of monthly summaries
    (multi-month range) for trend charts.

    With d_from_override + d_to_override, overrides the date range
    (used for billing cycle support from client).
    """
    today = date.today()

    # Multi-month range mode
    m_from = month_from if isinstance(month_from, str) else None
    m_to = month_to if isinstance(month_to, str) else None
    if m_from or m_to:
        m_from = m_from or "2026-01"
        m_to = m_to or today.strftime("%Y-%m")
        return await _monthly_range(m_from, m_to, db, current_user)

    # Single month mode (backward compatible)
    m = month or today.strftime("%Y-%m")
    d_from_parsed = _parse_date_iso(d_from_override) if d_from_override is not None else None
    d_to_parsed = _parse_date_iso(d_to_override) if d_to_override is not None else None
    return await _single_month(m, today, db, current_user,
                                d_from_override=d_from_parsed, d_to_override=d_to_parsed)


async def _single_month(m: str, today: date, db : CursorWrapper, current_user: dict,
                         d_from_override: Optional[date] = None,
                         d_to_override: Optional[date] = None) -> dict:
    """Monthly summary for a single month (YYYY-MM).

    When d_from_override/d_to_override are provided, uses those dates
    instead of calendar month — supports billing cycle range.
    """
    if d_from_override and d_to_override:
        d_from = d_from_override.isoformat()
        d_to = d_to_override.isoformat()
    else:
        d_from = f"{m}-01"
        if m == today.strftime("%Y-%m"):
            d_to = today.isoformat()
        else:
            import calendar
            y, mo = map(int, m.split("-"))
            d_to = f"{m}-{calendar.monthrange(y, mo)[1]}"

    cursor = await db.execute(
        """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
           FROM transactions t
           WHERE t.user_id = ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
           GROUP BY t.type""",
        (current_user["id"], d_from, d_to),
    )
    rows = await cursor.fetchall()
    income = 0
    expense = 0
    for r in rows:
        if r["type"] == "income":
            income = r["total"]
        else:
            expense = r["total"]

    cursor = await db.execute(
        """SELECT c.id, c.name, c.icon, c.name_en AS category_name_en, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t JOIN categories c ON t.category_id = c.id
           WHERE t.user_id = ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
             AND t.type = 'expense'
           GROUP BY c.id ORDER BY total DESC""",
        (current_user["id"], d_from, d_to),
    )
    categories = []
    for r in await cursor.fetchall():
        pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
        categories.append({
            "category_id": r["id"], "category_name": r["name"],
            "category_name_en": r["category_name_en"] or "",
            "icon": r["icon"] or "", "total": int(r["total"]),
            "count": r["count"], "percentage": pct,
        })

    # Income category breakdown
    cursor = await db.execute(
        """SELECT c.id, c.name, c.icon, c.name_en AS category_name_en, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t JOIN categories c ON t.category_id = c.id
           WHERE t.user_id = ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
             AND t.type = 'income'
           GROUP BY c.id ORDER BY total DESC""",
        (current_user["id"], d_from, d_to),
    )
    income_categories = []
    for r in await cursor.fetchall():
        income_total_data = int(r["total"])
        pct = round((income_total_data / income * 100), 1) if income > 0 else 0
        income_categories.append({
            "category_id": r["id"], "category_name": r["name"],
            "category_name_en": r["category_name_en"] or "",
            "icon": r["icon"] or "", "total": income_total_data,
            "count": r["count"], "percentage": pct,
        })

    cursor = await db.execute(
        """SELECT COALESCE(t.date, LEFT(t.created_at::text, 10)) as date,
                  CAST(COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS INTEGER) as expense,
                  CAST(COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) AS INTEGER) as income
           FROM transactions t
           WHERE t.user_id = ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
           GROUP BY 1 ORDER BY 1""",
        (current_user["id"], d_from, d_to),
    )
    daily_snapshot = [dict(r) for r in await cursor.fetchall()]

    return {
        "month": m,
        "total_income": int(income),
        "total_expense": int(expense),
        "balance": int(income - expense),
        "categories": categories,
        "income_categories": income_categories,
        "daily_snapshot": daily_snapshot,
    }


async def _monthly_range(m_from: str, m_to: str, db : CursorWrapper, current_user: dict) -> list:
    """Multi-month summary range. Returns list of {month, income, expense, balance}."""
    import calendar

    # Generate all months between m_from and m_to
    y1, m1 = map(int, m_from.split("-"))
    y2, m2 = map(int, m_to.split("-"))
    months = []
    y, mo = y1, m1
    while (y < y2) or (y == y2 and mo <= m2):
        months.append(f"{y}-{mo:02d}")
        mo += 1
        if mo > 12:
            mo = 1
            y += 1

    results = []
    for m in months:
        d_from = f"{m}-01"
        _, days = calendar.monthrange(*map(int, m.split("-")))
        d_to = f"{m}-{days}"

        cursor = await db.execute(
            """SELECT t.type, COALESCE(SUM(t.amount), 0) as total
               FROM transactions t
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               GROUP BY t.type""",
            (current_user["id"], d_from, d_to),
        )
        rows = await cursor.fetchall()
        income = 0
        expense = 0
        for r in rows:
            if r["type"] == "income":
                income = r["total"]
            else:
                expense = r["total"]

        results.append({
            "month": m,
            "total_income": int(income),
            "total_expense": int(expense),
            "balance": int(income - expense),
        })

    return results


@router.get("/current-month")
async def current_month_summary(
    use_cycle: bool = Query(False, description="Use user's billing cycle instead of calendar month"),
    ref_date: Optional[str] = Query(None, description="Reference date (YYYY-MM-DD). Defaults to server today."),
    db : CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Shorthand — monthly summary for the current cycle or month."""
    today = _parse_date_iso(ref_date) if ref_date else date.today()
    if use_cycle:
        cycle_start = await _get_cycle_start_day(db, current_user["id"])
        d_from, d_to = get_cycle_range(today, cycle_start)
        result = await _single_month(
            f"{d_from.year}-{d_from.month:02d}", today, db, current_user,
            d_from_override=d_from, d_to_override=d_to,
        )
        result["date_from"] = d_from.isoformat()
        result["date_to"] = d_to.isoformat()
        return result
    return await monthly_summary(month=None, db=db, current_user=current_user, d_from_override=None, d_to_override=None)


@router.get("/cycle-info")
async def cycle_info(
    ref_date_str: Optional[str] = Query(None, alias="date", description="Reference date (YYYY-MM-DD). Defaults to today."),
    db : CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Return the billing cycle date range for a given reference date."""
    cycle_start_day = await _get_cycle_start_day(db, current_user["id"])
    ref_date = date.fromisoformat(ref_date_str) if ref_date_str else date.today()
    d_from, d_to = get_cycle_range(ref_date, cycle_start_day)
    return {
        "cycle_start_day": cycle_start_day,
        "date_from": d_from.isoformat(),
        "date_to": d_to.isoformat(),
    }


@router.get("/all-time-category-balance")
async def all_time_category_balance(
    db : CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Returns all-time balance for Savings & Investment and Emergency Funds.

    For each, it calculates: SUM(expense transactions) - SUM(income transactions)
    """
    user_id = current_user["id"]

    # Fetch category IDs for Savings & Investment (both name_en variants)
    cursor = await db.execute(
        "SELECT id FROM categories WHERE name_en IN ('Savings & Investment', 'Savings & Investment Disbursed')"
    )
    savings_ids = [r["id"] for r in await cursor.fetchall()]

    # Fetch category IDs for Emergency Funds
    cursor = await db.execute(
        "SELECT id FROM categories WHERE name_en = 'Emergency Funds'"
    )
    emergency_ids = [r["id"] for r in await cursor.fetchall()]

    async def _query_balance(cat_ids: list[int]) -> dict:
        if not cat_ids:
            return {"total_expense": 0, "total_income": 0, "balance": 0}
        placeholders = ",".join("?" for _ in cat_ids)
        cursor = await db.execute(
            f"""SELECT
                   COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) as total_expense,
                   COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) as total_income
               FROM transactions t
               WHERE t.user_id = ?
                 AND t.category_id IN ({placeholders})""",
            (user_id, *cat_ids),
        )
        row = await cursor.fetchone()
        exp = int(row["total_expense"])
        inc = int(row["total_income"])
        return {"total_expense": exp, "total_income": inc, "balance": exp - inc}

    return {
        "savings_investment": await _query_balance(savings_ids),
        "emergency_funds": await _query_balance(emergency_ids),
    }


@router.get("/debt")
async def debt_summary(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Total remaining debt: KPR remaining principal + CC transactions + CC installment remaining."""
    user_id = current_user["id"]

    # Total KPR remaining: remaining_balance BEFORE this month's payment
    # If current_month=1 (no payment made yet), use total_loan
    # If current_month>1, use remaining_balance at month (current_month - 1)
    cursor = await db.execute(
        """SELECT COALESCE(SUM(
            CASE WHEN cm.current_month <= 1 THEN ks.total_loan
            ELSE (
                SELECT kms.remaining_balance
                FROM kpr_monthly_schedules kms
                WHERE kms.simulation_id = ks.id
                AND kms.month_number = cm.current_month - 1
            ) END
        ), 0) AS total_kpr
        FROM kpr_simulations ks
        CROSS JOIN LATERAL (
            SELECT LEAST(
                (EXTRACT(YEAR FROM CURRENT_DATE) - ks.start_year) * 12
                + (EXTRACT(MONTH FROM CURRENT_DATE) - ks.start_month) + 1,
                ks.tenor_months
            ) AS current_month
        ) cm
        WHERE ks.user_id = ?""",
        (user_id,),
    )
    row = await cursor.fetchone()
    total_kpr = int(row["total_kpr"]) if row else 0

    # Count active KPR simulations
    cursor = await db.execute(
        "SELECT COUNT(*) AS cnt FROM kpr_simulations WHERE user_id = ?",
        (user_id,),
    )
    row = await cursor.fetchone()
    kpr_count = row["cnt"] if row else 0

    # Total CC: unpaid transactions (non-installment) + installment remaining amounts
    cursor = await db.execute(
        """SELECT
               COALESCE(SUM(cct.amount), 0) AS total_txns
           FROM credit_card_transactions cct
           JOIN credit_cards cc ON cc.id = cct.card_id
           WHERE cc.user_id = ? AND cct.is_installment = 0""",
        (user_id,),
    )
    row = await cursor.fetchone()
    total_cc_txns = int(row["total_txns"]) if row else 0

    cursor = await db.execute(
        """SELECT
               COUNT(*) AS total_active,
               COALESCE(SUM(cci.monthly_amount * cci.remaining_months), 0) AS total_installments
           FROM credit_card_installments cci
           JOIN credit_cards cc ON cc.id = cci.card_id
           WHERE cc.user_id = ? AND cci.remaining_months > 0""",
        (user_id,),
    )
    row = await cursor.fetchone()
    total_cc_installments = int(row["total_installments"]) if row else 0
    cc_count = row["total_active"] if row else 0

    total_cc = total_cc_txns + total_cc_installments

    return {
        "total_kpr": total_kpr,
        "kpr_count": kpr_count,
        "total_cc": total_cc,
        "cc_count": cc_count,
        "total_debt": total_kpr + total_cc,
    }
