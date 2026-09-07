"""UI bootstrap (public) and home dashboard (JWT)."""
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel

from app.core.redis import get_redis
from app.core.security import get_current_user
from app.database import get_db, CursorWrapper
from app.services.home_service import HomeService
from app.services.ui_bootstrap_service import UiBootstrapService, cache_key

router = APIRouter(tags=["ui"])


class CopyUpdateIn(BaseModel):
    value: str


def _require_admin(current_user: dict) -> None:
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Cuma admin yang bisa ubah copy")


@router.get("/ui/bootstrap")
async def ui_bootstrap(
    response: Response,
    db: CursorWrapper = Depends(get_db),
):
    payload = await UiBootstrapService(db).get_bootstrap()
    response.headers["Cache-Control"] = "public, max-age=300"
    return payload


@router.get("/home")
async def home(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    return await HomeService(db).get_home(user_id=current_user["id"])


# ── Admin: ui_copy editor ─────────────────────────────────────────────


@router.get("/ui/copy")
async def list_copy(
    search: str = "",
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """List ui_copy rows (id-ID). Admin only."""
    _require_admin(current_user)
    if search:
        like = f"%{search}%"
        cursor = await db.execute(
            "SELECT key, value FROM ui_copy WHERE locale = 'id-ID' "
            "AND (key ILIKE ? OR value ILIKE ?) ORDER BY key",
            (like, like),
        )
    else:
        cursor = await db.execute(
            "SELECT key, value FROM ui_copy WHERE locale = 'id-ID' ORDER BY key"
        )
    rows = await cursor.fetchall()
    return {"items": [{"key": r["key"], "value": r["value"]} for r in rows]}


@router.put("/ui/copy/{key}")
async def update_copy(
    key: str,
    data: CopyUpdateIn,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Upsert one ui_copy row (id-ID) and bust the bootstrap cache. Admin only."""
    _require_admin(current_user)
    await db.execute(
        """INSERT INTO ui_copy (key, value, locale)
           VALUES (?, ?, 'id-ID')
           ON CONFLICT (key, locale) DO UPDATE SET value = excluded.value""",
        (key, data.value),
    )
    redis = await get_redis()
    await redis.delete(cache_key("id-ID"))
    return {"key": key, "value": data.value}