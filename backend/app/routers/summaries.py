from fastapi import APIRouter, Depends, Query
import aiosqlite
from datetime import date
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user

router = APIRouter(prefix="/summaries", tags=["summaries"])


@router.get("/daily")
async def daily_summary(
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    today = date.today().isoformat()
    d_from = date_from or today
    d_to = date_to or today

    cursor = await db.execute(
        """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
           FROM transactions t
           WHERE t.user_id = ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
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
        """SELECT c.id, c.name, c.icon, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t
           JOIN categories c ON t.category_id = c.id
           WHERE t.user_id = ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
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
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           GROUP BY t.user_id""",
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
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Household-wide summary across ALL users. Requires authentication."""
    today = date.today().isoformat()
    d_from = date_from or today
    d_to = date_to or today

    cursor = await db.execute(
        """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
           FROM transactions t
           WHERE COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           GROUP BY t.type""",
        (d_from, d_to),
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
        """SELECT c.id, c.name, c.icon, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t
           JOIN categories c ON t.category_id = c.id
           WHERE COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
             AND t.type = 'expense'
           GROUP BY c.id ORDER BY total DESC""",
        (d_from, d_to),
    )
    by_cat = await cursor.fetchall()
    categories = []
    for r in by_cat:
        pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
        categories.append(
            {
                "category_id": r["id"],
                "category_name": r["name"],
                "icon": r["icon"] or "",
                "total": int(r["total"]),
                "count": r["count"],
                "percentage": pct,
            }
        )

    # By user
    cursor = await db.execute(
        """SELECT t.user_id, u.display_name,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) as total_expense,
                  COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) as total_income
           FROM transactions t
           JOIN users u ON t.user_id = u.id
           WHERE COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           GROUP BY t.user_id ORDER BY total_expense DESC""",
        (d_from, d_to),
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
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Monthly summary for a given month (YYYY-MM). Default: current month."""
    today = date.today()
    m = month or today.strftime("%Y-%m")
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
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
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
        """SELECT c.id, c.name, c.icon, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t JOIN categories c ON t.category_id = c.id
           WHERE t.user_id = ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
             AND t.type = 'expense'
           GROUP BY c.id ORDER BY total DESC""",
        (current_user["id"], d_from, d_to),
    )
    categories = []
    for r in await cursor.fetchall():
        pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
        categories.append({
            "category_id": r["id"], "category_name": r["name"],
            "icon": r["icon"] or "", "total": int(r["total"]),
            "count": r["count"], "percentage": pct,
        })

    cursor = await db.execute(
        """SELECT COALESCE(t.date, substr(t.created_at,1,10)) as date,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) as expense,
                  COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) as income
           FROM transactions t
           WHERE t.user_id = ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           GROUP BY date ORDER BY date""",
        (current_user["id"], d_from, d_to),
    )
    daily_snapshot = [dict(r) for r in await cursor.fetchall()]

    return {
        "month": m,
        "total_income": int(income),
        "total_expense": int(expense),
        "balance": int(income - expense),
        "categories": categories,
        "daily_snapshot": daily_snapshot,
    }


@router.get("/current-month")
async def current_month_summary(
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Shorthand — monthly summary for the current month."""
    import calendar
    today = date.today()
    m = today.strftime("%Y-%m")
    d_from = f"{m}-01"
    d_to = today.isoformat()

    cursor = await db.execute(
        """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
           FROM transactions t
           WHERE t.user_id = ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
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
        """SELECT c.id, c.name, c.icon, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t JOIN categories c ON t.category_id = c.id
           WHERE t.user_id = ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
             AND t.type = 'expense'
           GROUP BY c.id ORDER BY total DESC""",
        (current_user["id"], d_from, d_to),
    )
    categories = []
    for r in await cursor.fetchall():
        pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
        categories.append({
            "category_id": r["id"], "category_name": r["name"],
            "icon": r["icon"] or "", "total": int(r["total"]),
            "count": r["count"], "percentage": pct,
        })

    cursor = await db.execute(
        """SELECT COALESCE(t.date, substr(t.created_at,1,10)) as date,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) as expense,
                  COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) as income
           FROM transactions t
           WHERE t.user_id = ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           GROUP BY date ORDER BY date""",
        (current_user["id"], d_from, d_to),
    )
    daily_snapshot = [dict(r) for r in await cursor.fetchall()]

    return {
        "month": m,
        "total_income": int(income),
        "total_expense": int(expense),
        "balance": int(income - expense),
        "categories": categories,
        "daily_snapshot": daily_snapshot,
    }
