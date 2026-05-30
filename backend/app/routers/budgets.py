from fastapi import APIRouter, Depends, HTTPException, Query
import aiosqlite
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user
from app.schemas.budget import BudgetCreate, BudgetResponse, BudgetSummaryItem

router = APIRouter(prefix="/budgets", tags=["budgets"])


@router.get("", response_model=list[BudgetResponse])
async def list_budgets(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        """SELECT b.id, b.month, b.category_id, b.category_name, b.budget_amount,
                  c.icon AS category_icon
           FROM budgets b
           LEFT JOIN categories c ON b.category_id = c.id
           WHERE b.month = ? AND b.user_id = ?
           ORDER BY b.budget_amount DESC""",
        (month, current_user["id"]),
    )
    rows = await cursor.fetchall()
    return [
        BudgetResponse(
            id=r["id"],
            month=r["month"],
            category_id=r["category_id"],
            category_name=r["category_name"],
            category_icon=r["category_icon"] or "📦",
            amount=r["budget_amount"],
        )
        for r in rows
    ]


@router.post("", status_code=201, response_model=BudgetResponse)
async def create_or_update_budget(
    data: BudgetCreate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    # Validate category exists
    cursor = await db.execute(
        "SELECT id, name, icon FROM categories WHERE id = ?", (data.category_id,)
    )
    cat = await cursor.fetchone()
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")

    # Upsert: if same user+month+category exists, update amount
    cursor = await db.execute(
        "SELECT id FROM budgets WHERE user_id = ? AND month = ? AND category_id = ?",
        (current_user["id"], data.month, data.category_id),
    )
    existing = await cursor.fetchone()

    if existing:
        await db.execute(
            "UPDATE budgets SET budget_amount = ?, category_name = ? WHERE id = ?",
            (data.amount, cat["name"], existing["id"]),
        )
        await db.commit()
        budget_id = existing["id"]
    else:
        cursor = await db.execute(
            """INSERT INTO budgets (user_id, month, category_id, category_name, budget_amount)
               VALUES (?, ?, ?, ?, ?)""",
            (current_user["id"], data.month, data.category_id, cat["name"], data.amount),
        )
        await db.commit()
        budget_id = cursor.lastrowid
        if budget_id is None:
            raise HTTPException(status_code=500, detail="Failed to create budget")

    return BudgetResponse(
        id=budget_id,
        month=data.month,
        category_id=data.category_id,
        category_name=cat["name"],
        category_icon=cat["icon"] or "📦",
        amount=data.amount,
    )


@router.delete("/{budget_id}", status_code=204)
async def delete_budget(
    budget_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT id FROM budgets WHERE id = ? AND user_id = ?",
        (budget_id, current_user["id"]),
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Budget not found")
    await db.execute("DELETE FROM budgets WHERE id = ?", (budget_id,))
    await db.commit()


@router.get("/summary", response_model=list[BudgetSummaryItem])
async def budget_summary(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    use_cycle: bool = Query(False, description="Use user's billing cycle for actuals date range"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Budgets vs actual spending for a given month."""
    # Determine date range for actuals
    if use_cycle:
        from app.utils.cycle import get_cycle_range
        from datetime import date
        cycle_cursor = await db.execute(
            "SELECT COALESCE(cycle_start_day, 1) as cycle_start_day FROM users WHERE id = ?",
            (current_user["id"],),
        )
        cycle_row = await cycle_cursor.fetchone()
        cycle_start_day = cycle_row["cycle_start_day"] if cycle_row else 1
        d_from, d_to = get_cycle_range(date.today(), cycle_start_day)
        d_from_str = d_from.isoformat()
        d_to_str = d_to.isoformat()
    else:
        d_from_str = f"{month}-01"
        d_to_str = f"{month}-31"

    cursor = await db.execute(
        """SELECT b.id, b.category_id, b.category_name, b.budget_amount,
                  c.icon AS category_icon,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS actual_spent
           FROM budgets b
           LEFT JOIN categories c ON b.category_id = c.id
           LEFT JOIN transactions t ON t.category_id = b.category_id
               AND t.user_id = b.user_id
               AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
               AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           WHERE b.month = ? AND b.user_id = ?
           GROUP BY b.category_id, b.category_name, b.budget_amount, c.icon
           ORDER BY b.budget_amount DESC""",
        (
            d_from_str,
            d_to_str,
            month,
            current_user["id"],
        ),
    )
    rows = await cursor.fetchall()
    results = []
    for r in rows:
        budget_amount = r["budget_amount"]
        actual_spent = r["actual_spent"]
        percentage = (actual_spent / budget_amount * 100) if budget_amount > 0 else 0
        results.append(BudgetSummaryItem(
            id=r["id"],
            category_id=r["category_id"],
            category_name=r["category_name"],
            category_icon=r["category_icon"] or "📦",
            budget_amount=budget_amount,
            actual_spent=actual_spent,
            percentage=round(percentage, 1),
            remaining=budget_amount - actual_spent,
        ))
    return results
