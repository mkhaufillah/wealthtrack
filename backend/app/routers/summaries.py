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

    return {
        "date_from": d_from,
        "date_to": d_to,
        "total_income": int(income),
        "total_expense": int(expense),
        "balance": int(income - expense),
        "by_category": categories,
    }
