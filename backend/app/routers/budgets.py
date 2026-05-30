from fastapi import APIRouter, Depends, HTTPException, Query
import aiosqlite
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user
from app.schemas.budget import BudgetCreate, BudgetResponse, BudgetSummaryItem
from app.utils.cycle import get_cycle_range_for_month

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

    # Get user's current cycle setting (fallback)
    cycle_cursor = await db.execute(
        "SELECT cycle_start_day FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user_row = await cycle_cursor.fetchone()
    user_cycle = user_row["cycle_start_day"] if user_row else 1

    # Determine cycle_on: explicit override > existing budget's cycle > user's current setting
    explicit_cycle = data.cycle_on  # may be None

    # Upsert: if same user+month+category exists, update amount (optionally cycle_on)
    cursor = await db.execute(
        "SELECT id, cycle_on FROM budgets WHERE user_id = ? AND month = ? AND category_id = ?",
        (current_user["id"], data.month, data.category_id),
    )
    existing = await cursor.fetchone()

    if existing:
        cycle_on = explicit_cycle if explicit_cycle is not None else existing["cycle_on"]
        await db.execute(
            "UPDATE budgets SET budget_amount = ?, category_name = ?, cycle_on = ? WHERE id = ?",
            (data.amount, cat["name"], cycle_on, existing["id"]),
        )
        await db.commit()
        budget_id = existing["id"]
    else:
        cycle_on = explicit_cycle if explicit_cycle is not None else user_cycle
        cursor = await db.execute(
            """INSERT INTO budgets (user_id, month, category_id, category_name, budget_amount, cycle_on)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (current_user["id"], data.month, data.category_id, cat["name"], data.amount, cycle_on),
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
    """Budgets vs actual spending for a given month.

    Each budget uses its OWN stored cycle_on for computing actual_spent.
    Previously all budgets shared the first budget's cycle_on, causing
    confusing behavior where only the highest-budget category's cycle
    affected the summary (typically Food & Drinks).
    """
    # Get all budgets for this month
    cursor = await db.execute(
        """SELECT b.id, b.category_id, b.category_name, b.budget_amount, b.cycle_on,
                  c.icon AS category_icon
           FROM budgets b
           LEFT JOIN categories c ON b.category_id = c.id
           WHERE b.month = ? AND b.user_id = ?
           ORDER BY b.budget_amount DESC""",
        (month, current_user["id"]),
    )
    rows = await cursor.fetchall()

    results = []
    for r in rows:
        budget_amount = r["budget_amount"]
        cycle_on = r["cycle_on"]

        # Compute date range from this budget's own cycle_on
        if use_cycle:
            d_from, d_to = get_cycle_range_for_month(month, cycle_on)
            d_from_str = d_from.isoformat()
            d_to_str = d_to.isoformat()
        else:
            d_from_str = f"{month}-01"
            d_to_str = f"{month}-31"

        # Query actual spending for this specific category + cycle range
        cur = await db.execute(
            """SELECT COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS actual_spent
               FROM transactions t
               WHERE t.category_id = ? AND t.user_id = ?
                 AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
                 AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?""",
            (r["category_id"], current_user["id"], d_from_str, d_to_str),
        )
        row = await cur.fetchone()
        actual_spent = row[0] if row is not None else 0

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
            cycle_on=cycle_on,
        ))

    return results
