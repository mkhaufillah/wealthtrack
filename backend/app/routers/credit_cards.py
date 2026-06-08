from fastapi import APIRouter, Depends, HTTPException

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.schemas.credit_card import (
    CreditCardCreate,
    CreditCardUpdate,
    CreditCardOut,
    CreditCardTransactionCreate,
    CreditCardTransactionOut,
    CreditCardInstallmentCreate,
    CreditCardInstallmentUpdate,
    CreditCardInstallmentOut,
    NextMonthProjection,
)

router = APIRouter(prefix="/credit-cards", tags=["credit_cards"])


# ── helpers ──────────────────────────────────────────────────────────


async def _get_card_for_user(
    db: CursorWrapper, card_id: int, user_id: int
) -> dict:
    cursor = await db.execute(
        "SELECT * FROM credit_cards WHERE id = ?", (card_id,)
    )
    card = await cursor.fetchone()
    if not card:
        raise HTTPException(status_code=404, detail="Credit card not found")
    card = dict(card)
    if card["user_id"] != user_id:
        raise HTTPException(status_code=403, detail="Not your credit card")
    return card


# ── Next Month Projection ───────────────────────────────────────────


@router.get("/next-month-projection")
async def next_month_projection(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> NextMonthProjection:
    """Aggregate all active installments across cards for next month's projection.

    For each card, sums monthly_amount of installments where remaining_months > 0,
    grouped by card. Returns per-card breakdown plus grand total.
    """
    cursor = await db.execute(
        """SELECT
               cc.id AS card_id,
               cc.name AS card_name,
               COALESCE(SUM(cci.monthly_amount), 0) AS total_monthly
           FROM credit_cards cc
           LEFT JOIN credit_card_installments cci
               ON cci.card_id = cc.id AND cci.remaining_months > 0
           WHERE cc.user_id = ?
           GROUP BY cc.id, cc.name
           ORDER BY cc.name""",
        (current_user["id"],),
    )
    rows = await cursor.fetchall()

    per_card = []
    grand_total = 0
    total_installments = 0

    for r in rows:
        monthly = int(r["total_monthly"])
        if monthly > 0:
            total_installments += 1
        grand_total += monthly
        per_card.append({"card_id": r["card_id"], "card_name": r["card_name"], "total": monthly})

    # Count distinct active installments
    count_cursor = await db.execute(
        """SELECT COUNT(*) AS cnt
           FROM credit_card_installments cci
           JOIN credit_cards cc ON cc.id = cci.card_id
           WHERE cc.user_id = ? AND cci.remaining_months > 0""",
        (current_user["id"],),
    )
    count_row = await count_cursor.fetchone()
    if count_row:
        total_installments = count_row["cnt"]

    return NextMonthProjection(
        total_installments=total_installments,
        total_expected=grand_total,
        per_card=per_card,
    )


# ── Credit Cards CRUD ───────────────────────────────────────────────


@router.post("", status_code=201)
async def create_credit_card(
    data: CreditCardCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Create a new credit card for the current user."""
    cursor = await db.execute(
        """INSERT INTO credit_cards (user_id, name, card_number_last4, billing_date, due_date, credit_limit)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (
            current_user["id"],
            data.name,
            data.card_number_last4,
            data.billing_date,
            data.due_date,
            data.credit_limit,
        ),
    )
    card_id = cursor.lastrowid
    return await _get_card_for_user(db, card_id, current_user["id"])


@router.get("")
async def list_credit_cards(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[CreditCardOut]:
    """List all credit cards for the current user."""
    cursor = await db.execute(
        """SELECT
               cc.id, cc.user_id, cc.name, cc.card_number_last4,
               cc.billing_date, cc.due_date, cc.credit_limit, cc.created_at,
               COALESCE(active_inst.cnt, 0) AS active_installments
           FROM credit_cards cc
           LEFT JOIN (
               SELECT card_id, COUNT(*) AS cnt
               FROM credit_card_installments
               WHERE remaining_months > 0
               GROUP BY card_id
           ) active_inst ON active_inst.card_id = cc.id
           WHERE cc.user_id = ?
           ORDER BY cc.created_at DESC""",
        (current_user["id"],),
    )
    rows = await cursor.fetchall()
    return [CreditCardOut(**dict(r)) for r in rows]


@router.get("/{card_id}")
async def get_credit_card(
    card_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get a single credit card with its transactions and installments."""
    card = await _get_card_for_user(db, card_id, current_user["id"])

    # Fetch transactions
    txn_cursor = await db.execute(
        """SELECT id, card_id, description, amount, category_id,
                  transaction_date, is_installment, installment_id, created_at
           FROM credit_card_transactions
           WHERE card_id = ?
           ORDER BY transaction_date DESC""",
        (card_id,),
    )
    transactions = [dict(r) for r in await txn_cursor.fetchall()]

    # Fetch installments
    inst_cursor = await db.execute(
        """SELECT id, card_id, description, total_amount, monthly_amount,
                  total_months, remaining_months, start_month, created_at
           FROM credit_card_installments
           WHERE card_id = ?
           ORDER BY start_month DESC""",
        (card_id,),
    )
    installments = [dict(r) for r in await inst_cursor.fetchall()]

    return {
        **card,
        "transactions": transactions,
        "installments": installments,
    }


@router.put("/{card_id}")
async def update_credit_card(
    card_id: int,
    data: CreditCardUpdate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Update a credit card's non-sensitive fields."""
    await _get_card_for_user(db, card_id, current_user["id"])

    fields = []
    params = []

    if data.name is not None:
        fields.append("name = ?")
        params.append(data.name)
    if data.billing_date is not None:
        fields.append("billing_date = ?")
        params.append(data.billing_date)
    if data.due_date is not None:
        fields.append("due_date = ?")
        params.append(data.due_date)
    if data.credit_limit is not None:
        fields.append("credit_limit = ?")
        params.append(data.credit_limit)

    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update")

    params.append(card_id)
    await db.execute(
        f"UPDATE credit_cards SET {', '.join(fields)} WHERE id = ?",
        tuple(params),
    )

    return await _get_card_for_user(db, card_id, current_user["id"])


@router.delete("/{card_id}", status_code=204)
async def delete_credit_card(
    card_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete a credit card. Transactions and installments cascade via FK."""
    await _get_card_for_user(db, card_id, current_user["id"])
    await db.execute("DELETE FROM credit_cards WHERE id = ?", (card_id,))


# ── Transactions ────────────────────────────────────────────────────


@router.post("/{card_id}/transactions", status_code=201)
async def create_transaction(
    card_id: int,
    data: CreditCardTransactionCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Add a transaction to a credit card."""
    await _get_card_for_user(db, card_id, current_user["id"])

    cursor = await db.execute(
        """INSERT INTO credit_card_transactions
           (card_id, description, amount, category_id, transaction_date, is_installment, installment_id)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (
            card_id,
            data.description,
            data.amount,
            data.category_id,
            data.transaction_date,
            1 if data.is_installment else 0,
            data.installment_id,
        ),
    )
    txn_id = cursor.lastrowid

    txn_cursor = await db.execute(
        """SELECT id, card_id, description, amount, category_id,
                  transaction_date, is_installment, installment_id, created_at
           FROM credit_card_transactions WHERE id = ?""",
        (txn_id,),
    )
    row = await txn_cursor.fetchone()
    return CreditCardTransactionOut(**dict(row))


@router.get("/{card_id}/transactions")
async def list_transactions(
    card_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[CreditCardTransactionOut]:
    """List all transactions for a credit card."""
    await _get_card_for_user(db, card_id, current_user["id"])

    cursor = await db.execute(
        """SELECT id, card_id, description, amount, category_id,
                  transaction_date, is_installment, installment_id, created_at
           FROM credit_card_transactions
           WHERE card_id = ?
           ORDER BY transaction_date DESC""",
        (card_id,),
    )
    rows = await cursor.fetchall()
    return [CreditCardTransactionOut(**dict(r)) for r in rows]


@router.delete("/{card_id}/transactions/{txn_id}", status_code=204)
async def delete_transaction(
    card_id: int,
    txn_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete a transaction from a credit card."""
    await _get_card_for_user(db, card_id, current_user["id"])

    cursor = await db.execute(
        "SELECT id FROM credit_card_transactions WHERE id = ? AND card_id = ?",
        (txn_id, card_id),
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Transaction not found")

    await db.execute(
        "DELETE FROM credit_card_transactions WHERE id = ?", (txn_id,)
    )


# ── Installments ────────────────────────────────────────────────────


@router.post("/{card_id}/installments", status_code=201)
async def create_installment(
    card_id: int,
    data: CreditCardInstallmentCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Add an installment plan to a credit card."""
    await _get_card_for_user(db, card_id, current_user["id"])

    cursor = await db.execute(
        """INSERT INTO credit_card_installments
           (card_id, description, total_amount, monthly_amount, total_months, remaining_months, start_month)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (
            card_id,
            data.description,
            data.total_amount,
            data.monthly_amount,
            data.total_months,
            data.remaining_months,
            data.start_month,
        ),
    )
    inst_id = cursor.lastrowid

    inst_cursor = await db.execute(
        """SELECT id, card_id, description, total_amount, monthly_amount,
                  total_months, remaining_months, start_month, created_at
           FROM credit_card_installments WHERE id = ?""",
        (inst_id,),
    )
    row = await inst_cursor.fetchone()
    return CreditCardInstallmentOut(**dict(row))


@router.get("/{card_id}/installments")
async def list_installments(
    card_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[CreditCardInstallmentOut]:
    """List all installment plans for a credit card."""
    await _get_card_for_user(db, card_id, current_user["id"])

    cursor = await db.execute(
        """SELECT id, card_id, description, total_amount, monthly_amount,
                  total_months, remaining_months, start_month, created_at
           FROM credit_card_installments
           WHERE card_id = ?
           ORDER BY start_month DESC""",
        (card_id,),
    )
    rows = await cursor.fetchall()
    return [CreditCardInstallmentOut(**dict(r)) for r in rows]


@router.put("/{card_id}/installments/{inst_id}")
async def update_installment(
    card_id: int,
    inst_id: int,
    data: CreditCardInstallmentUpdate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Update an installment (e.g., decrement remaining_months)."""
    await _get_card_for_user(db, card_id, current_user["id"])

    cursor = await db.execute(
        "SELECT id FROM credit_card_installments WHERE id = ? AND card_id = ?",
        (inst_id, card_id),
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Installment not found")

    fields = []
    params = []

    if data.remaining_months is not None:
        fields.append("remaining_months = ?")
        params.append(data.remaining_months)

    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update")

    params.append(inst_id)
    await db.execute(
        f"UPDATE credit_card_installments SET {', '.join(fields)} WHERE id = ?",
        tuple(params),
    )

    inst_cursor = await db.execute(
        """SELECT id, card_id, description, total_amount, monthly_amount,
                  total_months, remaining_months, start_month, created_at
           FROM credit_card_installments WHERE id = ?""",
        (inst_id,),
    )
    row = await inst_cursor.fetchone()
    return CreditCardInstallmentOut(**dict(row))


@router.delete("/{card_id}/installments/{inst_id}", status_code=204)
async def delete_installment(
    card_id: int,
    inst_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete an installment plan."""
    await _get_card_for_user(db, card_id, current_user["id"])

    cursor = await db.execute(
        "SELECT id FROM credit_card_installments WHERE id = ? AND card_id = ?",
        (inst_id, card_id),
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Installment not found")

    await db.execute(
        "DELETE FROM credit_card_installments WHERE id = ?", (inst_id,)
    )

