from fastapi import APIRouter, Depends, HTTPException, Query
import aiosqlite
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user
from app.schemas.transaction import TransactionCreate, TransactionUpdate, PaginatedTransactions, PaginationMeta, TransferOwnerIn, TransferRequest, TransferResponse

router = APIRouter(prefix="/transactions", tags=["transactions"])


def _format_txn(row, cat_name="", cat_icon="", cat_name_en="", display_name=""):
    # sqlite3.Row doesn't support .get() — convert to dict for safe access
    r = dict(row)
    return {
        "id": r["id"],
        "amount": int(r["amount"]),
        "type": r["type"],
        "description": r.get("description", "") or "",
        "note": r.get("note", "") or "",
        "date": r.get("date") or r["created_at"][:10],
        "category": {
            "id": r["category_id"],
            "name": cat_name or r.get("category_name", "") or "",
            "icon": cat_icon or "",
            "name_en": cat_name_en or "",
        },
        "user": {
            "id": r.get("user_id", 1) or 1,
            "display_name": display_name or r.get("user_display_name", ""),
        },
        "created_at": r["created_at"],
        "updated_at": r.get("updated_at", r["created_at"]),
    }


@router.get("/household", response_model=PaginatedTransactions)
async def list_household_transactions(
    page: int = Query(1, ge=1),
    per_page: int = Query(100, ge=1, le=200),
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sort: str = Query("-date", pattern="^(date|-date|amount|-amount)$"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get transactions of all household members."""
    cursor = await db.execute(
        "SELECT household_id FROM household_members WHERE user_id = ?",
        (current_user["id"],),
    )
    hm = await cursor.fetchone()
    if not hm:
        raise HTTPException(status_code=404, detail="Not a member of any household")
    household_id = hm["household_id"]

    where = ["hm2.household_id = ?"]
    params: list = [household_id]
    if type:
        where.append("t.type = ?")
        params.append(type)
    if date_from:
        where.append("COALESCE(t.date, substr(t.created_at,1,10)) >= ?")
        params.append(date_from)
    if date_to:
        where.append("COALESCE(t.date, substr(t.created_at,1,10)) <= ?")
        params.append(date_to)

    order_map = {
        "date": "COALESCE(t.date, substr(t.created_at,1,10)) ASC",
        "-date": "COALESCE(t.date, substr(t.created_at,1,10)) DESC",
        "amount": "t.amount ASC",
        "-amount": "t.amount DESC",
    }
    order = order_map.get(sort, "COALESCE(t.date, substr(t.created_at,1,10)) DESC")

    join_clause = "FROM transactions t JOIN household_members hm2 ON hm2.user_id = t.user_id"

    cursor = await db.execute(
        f"SELECT COUNT(*) {join_clause} WHERE {' AND '.join(where)}", params
    )
    total = (await cursor.fetchone())[0]

    offset = (page - 1) * per_page
    cursor = await db.execute(
        f"""SELECT t.id, t.type, t.amount, t.category_id, t.category_name,
                   t.description, t.note, t.date, t.user_id, t.created_at,
                   c.name AS cat_name, c.icon AS cat_icon,
                   c.name_en AS cat_name_en,
                   u.display_name AS user_display_name
            {join_clause}
            LEFT JOIN categories c ON t.category_id = c.id
            LEFT JOIN users u ON t.user_id = u.id
            WHERE {' AND '.join(where)}
            ORDER BY {order}
            LIMIT ? OFFSET ?""",
        params + [per_page, offset],
    )
    rows = await cursor.fetchall()
    data = [_format_txn(r, r["cat_name"] or "", r["cat_icon"] or "", r["cat_name_en"] or "") for r in rows]

    return PaginatedTransactions(
        data=data,
        meta=PaginationMeta(
            page=page,
            per_page=per_page,
            total=total,
            total_pages=max(1, (total + per_page - 1) // per_page),
        ),
    )


@router.get("", response_model=PaginatedTransactions)
async def list_transactions(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    category_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sort: str = Query("-date", pattern="^(date|-date|amount|-amount|name|-name)$"),
    q: Optional[str] = Query(None, description="Search by description"),
    category_ids: Optional[str] = Query(None, description="Comma-separated category IDs"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    where = ["t.user_id = ?"]
    params: list = [current_user["id"]]
    if type:
        where.append("t.type = ?")
        params.append(type)
    if category_id:
        where.append("t.category_id = ?")
        params.append(category_id)
    if date_from:
        where.append("COALESCE(t.date, substr(t.created_at,1,10)) >= ?")
        params.append(date_from)
    if date_to:
        where.append("COALESCE(t.date, substr(t.created_at,1,10)) <= ?")
        params.append(date_to)

    if q:
        where.append("t.description LIKE ?")
        params.append(f"%{q}%")

    if category_ids:
        ids = [int(x.strip()) for x in category_ids.split(",") if x.strip().isdigit()]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            where.append(f"t.category_id IN ({placeholders})")
            params.extend(ids)

    order_map = {
        "date": "COALESCE(t.date, substr(t.created_at,1,10)) ASC",
        "-date": "COALESCE(t.date, substr(t.created_at,1,10)) DESC",
        "amount": "t.amount ASC",
        "-amount": "t.amount DESC",
        "name": "t.description ASC",
        "-name": "t.description DESC",
    }
    order = order_map.get(sort, "COALESCE(t.date, substr(t.created_at,1,10)) DESC")

    cursor = await db.execute(
        f"SELECT COUNT(*) FROM transactions t WHERE {' AND '.join(where)}", params
    )
    total = (await cursor.fetchone())[0]

    offset = (page - 1) * per_page
    cursor = await db.execute(
        f"""SELECT t.id, t.type, t.amount, t.category_id, t.category_name,
                   t.description, t.note, t.date, t.user_id, t.created_at,
                   c.name AS cat_name, c.icon AS cat_icon,
                   c.name_en AS cat_name_en,
                   u.display_name AS user_display_name
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            LEFT JOIN users u ON t.user_id = u.id
            WHERE {' AND '.join(where)}
            ORDER BY {order}
            LIMIT ? OFFSET ?""",
        params + [per_page, offset],
    )
    rows = await cursor.fetchall()

    data = [_format_txn(r, r["cat_name"] or "", r["cat_icon"] or "", r["cat_name_en"] or "") for r in rows]

    return PaginatedTransactions(
        data=data,
        meta=PaginationMeta(
            page=page,
            per_page=per_page,
            total=total,
            total_pages=max(1, (total + per_page - 1) // per_page),
        ),
    )


@router.post("", status_code=201)
async def create_transaction(
    data: TransactionCreate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT id, name, name_en, icon FROM categories WHERE id = ?", (data.category_id,)
    )
    cat = await cursor.fetchone()
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")

    cursor = await db.execute(
        """INSERT INTO transactions
           (user_id, category_id, category_name, type, amount, description, note, date)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            current_user["id"],
            data.category_id,
            cat["name"],
            data.type,
            data.amount,
            data.description,
            data.note,
            data.date,
        ),
    )
    await db.commit()
    new_id = cursor.lastrowid
    cursor = await db.execute(
        "SELECT id, type, amount, category_id, category_name, description, note, date, user_id, created_at FROM transactions WHERE id = ?", (new_id,)
    )
    row = await cursor.fetchone()
    # Fetch display_name from users table
    u = await (await db.execute("SELECT display_name FROM users WHERE id = ?", (current_user["id"],))).fetchone()
    return _format_txn(row, cat["name"], cat["icon"], cat["name_en"] or "", u["display_name"] if u else "")


@router.get("/{txn_id}")
async def get_transaction(
    txn_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT t.id, t.type, t.amount, t.category_id, t.category_name, t.description, t.note, t.date, t.user_id, t.created_at, u.display_name AS user_display_name FROM transactions t LEFT JOIN users u ON t.user_id = u.id WHERE t.id = ? AND t.user_id = ?",
        (txn_id, current_user["id"]),
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Transaction not found")
    c = await (
        await db.execute(
            "SELECT id, name, name_en, icon FROM categories WHERE id = ?", (row["category_id"],)
        )
    ).fetchone()
    return _format_txn(row, c["name"] if c else "", c["icon"] if c else "", c["name_en"] if c else "")


@router.put("/{txn_id}")
async def update_transaction(
    txn_id: int,
    data: TransactionUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT id FROM transactions WHERE id = ? AND user_id = ?",
        (txn_id, current_user["id"]),
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Transaction not found")

    updates = {}
    for field in ["type", "amount", "description", "note", "category_id", "date"]:
        val = getattr(data, field, None)
        if val is not None:
            if field == "category_id":
                c = await (
                    await db.execute(
                        "SELECT name FROM categories WHERE id = ?", (val,)
                    )
                ).fetchone()
                if not c:
                    raise HTTPException(status_code=404, detail="Category not found")
                updates["category_id"] = val
                updates["category_name"] = c["name"]
            else:
                updates[field] = val
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = ?" for k in updates)
    await db.execute(
        f"UPDATE transactions SET {set_clause} WHERE id = ?",
        list(updates.values()) + [txn_id],
    )
    await db.commit()

    cursor = await db.execute(
        "SELECT t.id, t.type, t.amount, t.category_id, t.category_name, t.description, t.note, t.date, t.user_id, t.created_at, u.display_name AS user_display_name FROM transactions t LEFT JOIN users u ON t.user_id = u.id WHERE t.id = ?", (txn_id,)
    )
    row = await cursor.fetchone()
    c = await (
        await db.execute(
            "SELECT id, name, name_en, icon FROM categories WHERE id = ?", (row["category_id"],)
        )
    ).fetchone()
    return _format_txn(row, c["name"] if c else "", c["icon"] if c else "", c["name_en"] if c else "")


@router.put("/{txn_id}/owner")
async def transfer_owner(
    txn_id: int,
    data: TransferOwnerIn,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Transfer transaction ownership to another household member."""
    # 1. Fetch transaction
    cursor = await db.execute(
        "SELECT id, user_id FROM transactions WHERE id = ?",
        (txn_id,),
    )
    txn = await cursor.fetchone()
    if not txn:
        raise HTTPException(status_code=404, detail="Transaction not found")

    # 2. Only current owner OR household admin can transfer
    cursor = await db.execute(
        "SELECT hm.role, hm.household_id FROM household_members hm WHERE hm.user_id = ?",
        (current_user["id"],),
    )
    hm = await cursor.fetchone()
    if not hm:
        raise HTTPException(status_code=404, detail="Not a member of any household")

    is_admin = hm["role"] == "admin"
    is_owner = txn["user_id"] == current_user["id"]

    if not (is_owner or is_admin):
        raise HTTPException(
            status_code=403,
            detail="Only the transaction owner or a household admin can transfer ownership",
        )

    household_id = hm["household_id"]

    # 3. Validate target user exists in the same household
    cursor = await db.execute(
        "SELECT user_id FROM household_members WHERE user_id = ? AND household_id = ?",
        (data.user_id, household_id),
    )
    if not await cursor.fetchone():
        raise HTTPException(
            status_code=400,
            detail="Target user is not a member of your household",
        )

    # 4. Perform transfer
    await db.execute(
        "UPDATE transactions SET user_id = ? WHERE id = ?",
        (data.user_id, txn_id),
    )
    await db.commit()

    # 5. Return updated transaction
    cursor = await db.execute(
        """SELECT t.id, t.type, t.amount, t.category_id, t.category_name,
                  t.description, t.note, t.date, t.user_id, t.created_at,
                  u.display_name AS user_display_name
           FROM transactions t
           LEFT JOIN users u ON t.user_id = u.id
           WHERE t.id = ?""",
        (txn_id,),
    )
    row = await cursor.fetchone()
    c = await (
        await db.execute(
            "SELECT id, name, name_en, icon FROM categories WHERE id = ?",
            (row["category_id"],),
        )
    ).fetchone()
    return _format_txn(row, c["name"] if c else "", c["icon"] if c else "", c["name_en"] if c else "")


@router.post("/transfer", response_model=TransferResponse, status_code=201)
async def transfer_balance(
    req: TransferRequest,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Transfer balance to household members. Creates paired expense/income transactions."""
    user_id = current_user["id"]

    # 1. Verify user is in a household
    cursor = await db.execute(
        "SELECT household_id, role FROM household_members WHERE user_id = ?",
        (user_id,),
    )
    member = await cursor.fetchone()
    if not member:
        raise HTTPException(status_code=400, detail="Not a member of any household")
    household_id = member["household_id"]

    # 2. Verify all recipients are in the same household
    recipient_ids = [t.user_id for t in req.transfers]
    placeholders = ",".join("?" * len(recipient_ids))
    cursor = await db.execute(
        f"SELECT user_id FROM household_members WHERE household_id = ? AND user_id IN ({placeholders})",
        (household_id, *recipient_ids),
    )
    valid_ids = {r["user_id"] for r in await cursor.fetchall()}
    for rid in recipient_ids:
        if rid not in valid_ids:
            raise HTTPException(
                status_code=400,
                detail=f"User {rid} is not a member of your household",
            )

    # 3. Ensure the special transfer categories exist
    cursor = await db.execute(
        "SELECT id, name, name_en, icon FROM categories WHERE name = ? AND type = ?",
        ("Transfer", "expense"),
    )
    expense_cat = await cursor.fetchone()
    if not expense_cat:
        await db.execute(
            "INSERT INTO categories (name, type, icon, is_default) VALUES (?, ?, ?, ?)",
            ("Transfer", "expense", "🔄", 1),
        )
        cursor = await db.execute(
            "SELECT id, name, name_en, icon FROM categories WHERE name = ? AND type = ?",
            ("Transfer", "expense"),
        )
        expense_cat = await cursor.fetchone()

    cursor = await db.execute(
        "SELECT id, name, name_en, icon FROM categories WHERE name = ? AND type = ?",
        ("Transfer", "income"),
    )
    income_cat = await cursor.fetchone()
    if not income_cat:
        await db.execute(
            "INSERT INTO categories (name, type, icon, is_default) VALUES (?, ?, ?, ?)",
            ("Transfer", "income", "🔄", 1),
        )
        cursor = await db.execute(
            "SELECT id, name, name_en, icon FROM categories WHERE name = ? AND type = ?",
            ("Transfer", "income"),
        )
        income_cat = await cursor.fetchone()

    expense_cat_id = expense_cat["id"]
    expense_cat_name = expense_cat["name"]
    expense_cat_name_en = expense_cat["name_en"] or ""
    expense_cat_icon = expense_cat["icon"]
    income_cat_id = income_cat["id"]
    income_cat_name = income_cat["name"]
    income_cat_name_en = income_cat["name_en"] or ""
    income_cat_icon = income_cat["icon"]

    # Get sender's display name
    cursor = await db.execute(
        "SELECT display_name FROM users WHERE id = ?", (user_id,)
    )
    sender_row = await cursor.fetchone()
    sender_name = sender_row["display_name"] if sender_row else current_user["username"]

    # 4. Create transactions
    results = []
    for t in req.transfers:
        # Get recipient's display name
        cursor = await db.execute(
            "SELECT display_name FROM users WHERE id = ?", (t.user_id,)
        )
        recipient = await cursor.fetchone()
        recipient_name = recipient["display_name"] if recipient else f"User {t.user_id}"

        # Sender expense
        cursor = await db.execute(
            "INSERT INTO transactions (type, amount, category_id, category_name, description, date, user_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            ("expense", t.amount, expense_cat_id, expense_cat_name,
             f"Transfer to {recipient_name}", req.date, user_id),
        )
        expense_id = cursor.lastrowid

        # Recipient income
        cursor = await db.execute(
            "INSERT INTO transactions (type, amount, category_id, category_name, description, date, user_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            ("income", t.amount, income_cat_id, income_cat_name,
             f"Transfer from {sender_name}", req.date, t.user_id),
        )
        income_id = cursor.lastrowid

        # Fetch both with JOINs for _format_txn
        cursor = await db.execute(
            """SELECT t.*, c.name AS cat_name, c.icon AS cat_icon,
                      c.name_en AS cat_name_en,
                      u.display_name AS user_display_name
               FROM transactions t
               LEFT JOIN categories c ON t.category_id = c.id
               LEFT JOIN users u ON t.user_id = u.id
               WHERE t.id = ?""",
            (expense_id,),
        )
        exp_row = await cursor.fetchone()

        cursor = await db.execute(
            """SELECT t.*, c.name AS cat_name, c.icon AS cat_icon,
                      c.name_en AS cat_name_en,
                      u.display_name AS user_display_name
               FROM transactions t
               LEFT JOIN categories c ON t.category_id = c.id
               LEFT JOIN users u ON t.user_id = u.id
               WHERE t.id = ?""",
            (income_id,),
        )
        inc_row = await cursor.fetchone()

        results.append({
            "sender_expense": _format_txn(exp_row, expense_cat_name, expense_cat_icon,
                                          expense_cat_name_en,
                                          exp_row["user_display_name"] or ""),
            "recipient_income": _format_txn(inc_row, income_cat_name, income_cat_icon,
                                            income_cat_name_en,
                                            inc_row["user_display_name"] or ""),
        })

    await db.commit()
    return {"transactions": results}


@router.delete("/{txn_id}", status_code=204)
async def delete_transaction(
    txn_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT id FROM transactions WHERE id = ? AND user_id = ?",
        (txn_id, current_user["id"]),
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Transaction not found")

    # Delete associated OCR jobs before deleting transaction
    cursor = await db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='ocr_jobs'"
    )
    if await cursor.fetchone():
        await db.execute(
            "DELETE FROM ocr_jobs WHERE transaction_id = ?",
            (txn_id,),
        )
    await db.execute("DELETE FROM transactions WHERE id = ?", (txn_id,))
    await db.commit()
