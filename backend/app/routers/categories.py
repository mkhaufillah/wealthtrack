from fastapi import APIRouter, Depends, Query
import aiosqlite
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user
from app.schemas.category import CategoryOut

router = APIRouter(prefix="/categories", tags=["categories"])


@router.get("", response_model=list[CategoryOut])
async def list_categories(
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    if type:
        cursor = await db.execute(
            "SELECT * FROM categories WHERE type = ? ORDER BY sort_order", (type,)
        )
    else:
        cursor = await db.execute("SELECT * FROM categories ORDER BY type, sort_order")
    rows = await cursor.fetchall()
    return [dict(r) for r in rows]
