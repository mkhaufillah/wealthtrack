from fastapi import APIRouter, Depends, HTTPException, Query
import aiosqlite
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user
from app.schemas.transaction import TransactionCreate, TransactionUpdate, PaginatedTransactions, PaginationMeta

router = APIRouter(prefix="/transactions", tags=["transactions"])


def _format_txn(row, cat_name="", cat_icon="", username=""):
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
        },
        "user": {
            "id": r.get("user_id", 1) or 1,
            "display_name": username or ("Nahda" if r.get("user_id") == 2 else "Filla"),
        },
        "created_at": r["created_at"],
        "updated_at": r.get("updated_at", r["created_at"]),
    }


@router.get("", response_model=PaginatedTransactions)
async def list_transactions(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    category_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sort: str = Query("-date", pattern="^(date|-date|amount|-amount)$"),
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

    order_map = {
        "date": "COALESCE(t.date, substr(t.created_at,1,10)) ASC",
        "-date": "COALESCE(t.date, substr(t.created_at,1,10)) DESC",
        "amount": "t.amount ASC",
        "-amount": "t.amount DESC",
    }
    order = order_map.get(sort, "COALESCE(t.date, substr(t.created_at,1,10)) DESC")

    cursor = await db.execute(
        f"SELECT COUNT(*) FROM transactions t WHERE {' AND '.join(where)}", params
    )
    total = (await cursor.fetchone())[0]

    offset = (page - 1) * per_page
    cursor = await db.execute(
        f"""SELECT t.* FROM transactions t
            WHERE {' AND '.join(where)}
            ORDER BY {order}
            LIMIT ? OFFSET ?""",
        params + [per_page, offset],
    )
    rows = await cursor.fetchall()

    data = []
    for r in rows:
        c = await (
            await db.execute(
                "SELECT id, name, icon FROM categories WHERE id = ?", (r["category_id"],)
            )
        ).fetchone()
        if c:
            data.append(_format_txn(r, c["name"], c["icon"]))
        else:
            data.append(_format_txn(r, r.get("category_name", "")))

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
        "SELECT id, name FROM categories WHERE id = ?", (data.category_id,)
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
    cursor = await db.execute("SELECT * FROM transactions WHERE id = ?", (new_id,))
    row = await cursor.fetchone()
    return _format_txn(row, cat["name"], "", current_user["username"])


@router.get("/{txn_id}")
async def get_transaction(
    txn_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT * FROM transactions WHERE id = ? AND user_id = ?",
        (txn_id, current_user["id"]),
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Transaction not found")
    c = await (
        await db.execute(
            "SELECT id, name, icon FROM categories WHERE id = ?", (row["category_id"],)
        )
    ).fetchone()
    return _format_txn(row, c["name"] if c else "", "", current_user["username"])


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
    for field in ["amount", "description", "note", "category_id", "date"]:
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

    cursor = await db.execute("SELECT * FROM transactions WHERE id = ?", (txn_id,))
    row = await cursor.fetchone()
    c = await (
        await db.execute(
            "SELECT id, name, icon FROM categories WHERE id = ?", (row["category_id"],)
        )
    ).fetchone()
    return _format_txn(row, c["name"] if c else "", "", current_user["username"])


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
    await db.execute("DELETE FROM transactions WHERE id = ?", (txn_id,))
    await db.commit()
