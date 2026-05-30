from fastapi import APIRouter, Depends, Query, HTTPException, Request
import aiosqlite
import json
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user
from app.core.limiter import limiter
from app.schemas.category import CategoryOut, CategoryCreate, CategoryUpdate

router = APIRouter(prefix="/categories", tags=["categories"])


def _format_category(row) -> dict:
    """Format a category row into a response dict with parsed keywords."""
    result = dict(row)
    kw = row["keywords"]
    result["keywords"] = json.loads(kw) if kw else []
    return result


@router.get("", response_model=list[CategoryOut])
async def list_categories(
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    if type:
        cursor = await db.execute(
            "SELECT id, name, name_en, type, icon, is_default, keywords FROM categories WHERE type = ? ORDER BY sort_order",
            (type,),
        )
    else:
        cursor = await db.execute(
            "SELECT id, name, name_en, type, icon, is_default, keywords FROM categories ORDER BY type, sort_order"
        )
    rows = await cursor.fetchall()
    return [_format_category(r) for r in rows]


@router.post("", status_code=201, response_model=CategoryOut)
@limiter.limit("30/minute")
async def create_category(
    request: Request,
    data: CategoryCreate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only admin can create categories")

    cursor = await db.execute(
        "SELECT id FROM categories WHERE name = ? AND type = ?",
        (data.name, data.type),
    )
    if await cursor.fetchone():
        raise HTTPException(
            status_code=409,
            detail=f"Category '{data.name}' already exists for type '{data.type}'",
        )

    keywords_json = json.dumps(data.keywords) if data.keywords else "[]"
    cursor = await db.execute(
        """INSERT INTO categories (name, name_en, type, icon, keywords, sort_order)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (data.name, data.name_en, data.type, data.icon, keywords_json, data.sort_order),
    )
    await db.commit()

    cursor = await db.execute(
        "SELECT id, name, name_en, type, icon, is_default, keywords FROM categories WHERE id = ?",
        (cursor.lastrowid,),
    )
    return _format_category(await cursor.fetchone())


@router.put("/{category_id}", response_model=CategoryOut)
@limiter.limit("30/minute")
async def update_category(
    request: Request,
    category_id: int,
    data: CategoryUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only admin can update categories")

    cursor = await db.execute(
        "SELECT id, name, type, is_default FROM categories WHERE id = ?",
        (category_id,),
    )
    existing = await cursor.fetchone()
    if not existing:
        raise HTTPException(status_code=404, detail="Category not found")

    # Prevent editing system-default categories
    if existing["is_default"]:
        raise HTTPException(status_code=403, detail="Cannot edit default categories")

    # Check name uniqueness if renaming
    if data.name is not None and data.name != existing["name"]:
        cursor = await db.execute(
            "SELECT id FROM categories WHERE name = ? AND type = ? AND id != ?",
            (data.name, existing["type"], category_id),
        )
        if await cursor.fetchone():
            raise HTTPException(status_code=409, detail="Category name already exists for this type")

    updates = {}
    if data.name is not None:
        updates["name"] = data.name
    if data.name_en is not None:
        updates["name_en"] = data.name_en
    if data.icon is not None:
        updates["icon"] = data.icon
    if data.keywords is not None:
        updates["keywords"] = json.dumps(data.keywords)
    if data.sort_order is not None:
        updates["sort_order"] = data.sort_order

    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = ?" for k in updates)
    await db.execute(
        f"UPDATE categories SET {set_clause} WHERE id = ?",
        list(updates.values()) + [category_id],
    )
    await db.commit()

    cursor = await db.execute(
        "SELECT id, name, name_en, type, icon, is_default, keywords FROM categories WHERE id = ?",
        (category_id,),
    )
    return _format_category(await cursor.fetchone())
