from fastapi import APIRouter, Depends, HTTPException, Query
import aiosqlite
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user
from app.schemas.budget import BudgetCreate, BudgetResponse, BudgetSummaryItem, BudgetSummaryResponse, UnbudgetedExpense, BudgetSuggestion, BudgetSuggestionResponse
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
                  c.icon AS category_icon,
                  c.name_en AS category_name_en
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
            category_name_en=r["category_name_en"] or "",
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
        "SELECT id, name, name_en, icon FROM categories WHERE id = ?", (data.category_id,)
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
        category_name_en=cat["name_en"] or "",
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


@router.get("/summary", response_model=BudgetSummaryResponse)
async def budget_summary(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    use_cycle: bool = Query(False, description="Use user's billing cycle for actuals date range"),
    d_from_override: Optional[str] = Query(None, description="Override date_from for non-budget expense query"),
    d_to_override: Optional[str] = Query(None, description="Override date_to for non-budget expense query"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Budgets vs actual spending for a given month.

    Each budget uses its OWN stored cycle_on for computing actual_spent.
    Previously all budgets shared the first budget's cycle_on, causing
    confusing behavior where only the highest-budget category's cycle
    affected the summary (typically Food & Drinks).

    Also returns uncategorized_expenses — expenses in categories that
    don't have a budget, so users are aware of spending outside their
    budget plan. Uses the overall cycle range (d_from_override/d_to_override
    or user's cycle_start_day) for this query.
    """
    # Get all budgets for this month
    cursor = await db.execute(
        """SELECT b.id, b.category_id, b.category_name, b.budget_amount, b.cycle_on,
                  c.icon AS category_icon,
                  c.name_en AS category_name_en
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
            category_name_en=r["category_name_en"] or "",
            category_icon=r["category_icon"] or "📦",
            budget_amount=budget_amount,
            actual_spent=actual_spent,
            percentage=round(percentage, 1),
            remaining=budget_amount - actual_spent,
            cycle_on=cycle_on,
        ))

    # ── Unbudgeted expenses ──
    # Determine overall date range for non-budget expense query
    if use_cycle:
        if d_from_override and d_to_override:
            uncat_d_from = d_from_override
            uncat_d_to = d_to_override
        else:
            # Fall back to user's cycle_start_day
            uc = await db.execute(
                "SELECT cycle_start_day FROM users WHERE id = ?",
                (current_user["id"],),
            )
            urow = await uc.fetchone()
            cycle_day = urow["cycle_start_day"] if urow else 1
            from datetime import date as dt_date
            uf, ut = get_cycle_range_for_month(month, cycle_day)
            uncat_d_from = uf.isoformat()
            uncat_d_to = ut.isoformat()
    else:
        uncat_d_from = f"{month}-01"
        # Last day of month
        import calendar
        y, mo = map(int, month.split("-"))
        last_day = calendar.monthrange(y, mo)[1]
        uncat_d_to = f"{month}-{last_day:02d}"

    # Get budgeted category IDs
    budgeted_cat_ids = tuple(r["category_id"] for r in rows)

    uncategorized = []
    if budgeted_cat_ids:
        placeholders = ",".join("?" * len(budgeted_cat_ids))
        ucur = await db.execute(
            f"""SELECT t.category_id, c.name AS category_name, c.icon AS category_icon,
                       c.name_en AS category_name_en,
                       CAST(COALESCE(SUM(t.amount), 0) AS INTEGER) AS total
                FROM transactions t
                LEFT JOIN categories c ON t.category_id = c.id
                WHERE t.user_id = ?
                  AND t.type = 'expense'
                  AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
                  AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
                  AND t.category_id NOT IN ({placeholders})
                GROUP BY t.category_id
                ORDER BY total DESC""",
            (current_user["id"], uncat_d_from, uncat_d_to, *budgeted_cat_ids),
        )
        for urow in await ucur.fetchall():
            uncategorized.append(UnbudgetedExpense(
                category_id=urow["category_id"],
                category_name=urow["category_name"] or "Unknown",
                category_name_en=urow["category_name_en"] or "",
                category_icon=urow["category_icon"] or "📦",
                total=urow["total"],
            ))
    else:
        # No budgets at all — all expense categories are uncategorized
        ucur = await db.execute(
            """SELECT t.category_id, c.name AS category_name, c.icon AS category_icon,
                      c.name_en AS category_name_en,
                      CAST(COALESCE(SUM(t.amount), 0) AS INTEGER) AS total
               FROM transactions t
               LEFT JOIN categories c ON t.category_id = c.id
               WHERE t.user_id = ?
                 AND t.type = 'expense'
                 AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
                 AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
               GROUP BY t.category_id
               ORDER BY total DESC""",
            (current_user["id"], uncat_d_from, uncat_d_to),
        )
        for urow in await ucur.fetchall():
            uncategorized.append(UnbudgetedExpense(
                category_id=urow["category_id"],
                category_name=urow["category_name"] or "Unknown",
                category_name_en=urow["category_name_en"] or "",
                category_icon=urow["category_icon"] or "📦",
                total=urow["total"],
            ))

    return BudgetSummaryResponse(items=results, uncategorized_expenses=uncategorized)


@router.get("/suggestions", response_model=BudgetSuggestionResponse)
async def budget_suggestions(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    num_cycles: int = Query(3, ge=1, le=12),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Analyze historical spending and suggest budget amounts per category."""
    # Get user's cycle setting
    cursor = await db.execute(
        "SELECT cycle_start_day FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user_row = await cursor.fetchone()
    cycle_start_day = user_row["cycle_start_day"] if user_row else 1

    # Get historical data
    from app.utils.budget_ai import get_historical_spending

    history = await get_historical_spending(
        db,
        current_user["id"],
        cycle_start_day=cycle_start_day,
        num_cycles=num_cycles,
    )

    if not history:
        return BudgetSuggestionResponse(items=[])

    # Get existing budgets for this month
    cursor = await db.execute(
        "SELECT category_id, budget_amount FROM budgets WHERE month = ? AND user_id = ?",
        (month, current_user["id"]),
    )
    existing = {}
    async for r in cursor:
        existing[r["category_id"]] = r["budget_amount"]

    # Build suggestions
    items = []
    for h in history:
        cat_id = h["category_id"]
        raw = h["avg_amount"]
        # Round up to nearest 10k, min Rp10k
        suggested = ((raw + 9999) // 10000) * 10000
        if suggested < 10000:
            suggested = 10000

        items.append(BudgetSuggestion(
            category_id=cat_id,
            category_name=h["category_name"],
            category_name_en=h["category_name_en"],
            category_icon=h["category_icon"],
            suggested_amount=suggested,
            historical_avg=h["avg_amount"],
            historical_max=h["max_amount"],
            months_analyzed=h["months_analyzed"],
            has_budget=cat_id in existing,
            existing_amount=existing.get(cat_id, 0),
        ))

    total_suggested = sum(i.suggested_amount for i in items if not i.has_budget)

    # Fetch total income for the period
    d_from, d_to = get_cycle_range_for_month(month, cycle_start_day)
    cursor = await db.execute(
        """SELECT COALESCE(SUM(amount), 0) FROM transactions
           WHERE user_id = ? AND type = 'income'
             AND COALESCE(date, substr(created_at,1,10)) BETWEEN ? AND ?""",
        (current_user["id"], d_from.isoformat(), d_to.isoformat()),
    )
    row = await cursor.fetchone()
    total_income = row[0] if row else 0

    warning = ""
    if total_income > 0 and total_suggested > total_income:
        warning = (
            f"Suggested budgets (Rp{total_suggested:,}) exceed income "
            f"(Rp{total_income:,}). Consider reducing."
        )

    return BudgetSuggestionResponse(
        items=items,
        total_suggested=total_suggested,
        total_income=total_income,
        warning=warning,
    )
