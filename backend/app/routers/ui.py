"""UI bootstrap (public) and home dashboard (JWT)."""
import json

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel

from app.core.redis import get_redis
from app.core.security import get_current_user
from app.core.theme_presets import resolve_theme_preset
from app.database import get_db, CursorWrapper
from app.services.home_service import HomeService
from app.services.ui_bootstrap_service import UiBootstrapService, cache_key

router = APIRouter(tags=["ui"])


class CopyUpdateIn(BaseModel):
    value: str


class ConfigUpdateIn(BaseModel):
    value: dict | None = None
    preset: str | None = None


# Keys admins may edit through the app. Theme tokens are preset-based
# (audited palettes only — no arbitrary hex input).
EDITABLE_CONFIG_KEYS = {"format", "flags", "theme.light", "theme.dark"}
THEME_KEYS = {"theme.light", "theme.dark"}


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


# ── Admin: ui_config editor ───────────────────────────────────────────


@router.get("/ui/config")
async def list_config(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """List ui_config rows (raw JSON values). Admin only."""
    _require_admin(current_user)
    cursor = await db.execute("SELECT key, value FROM ui_config ORDER BY key")
    rows = await cursor.fetchall()
    items = []
    for r in rows:
        val = r["value"]
        if isinstance(val, str):
            val = json.loads(val)
        items.append({"key": r["key"], "value": val})
    return {"items": items}


@router.put("/ui/config/{key}")
async def update_config(
    key: str,
    data: ConfigUpdateIn,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Upsert one ui_config row and bust bootstrap cache.

    - ``format`` / ``flags``: body ``{"value": {...}}`` (JSON).
    - ``theme.light`` / ``theme.dark``: body ``{"preset": "..."}`` — resolved
      from the audited presets (no arbitrary hex input).
    """
    _require_admin(current_user)
    if key not in EDITABLE_CONFIG_KEYS:
        raise HTTPException(
            status_code=422,
            detail=f"Key config {key} gak dikenal atau gak bisa diubah via app",
        )

    if key in THEME_KEYS:
        if not data.preset:
            raise HTTPException(
                status_code=422,
                detail='Theme pakai preset. Kirim {"preset": "peach"} misalnya',
            )
        mode = "light" if key == "theme.light" else "dark"
        try:
            stored = resolve_theme_preset(mode, data.preset)
        except KeyError:
            raise HTTPException(
                status_code=422,
                detail=f"Preset tema {data.preset} gak dikenal",
            )
    else:
        if data.value is None:
            raise HTTPException(
                status_code=422,
                detail="Body harus berisi value",
            )
        stored = data.value

    await db.execute(
        """INSERT INTO ui_config (key, value)
           VALUES (?, ?::jsonb)
           ON CONFLICT (key) DO UPDATE SET value = excluded.value""",
        (key, json.dumps(stored)),
    )
    redis = await get_redis()
    await redis.delete(cache_key("id-ID"))
    return {"key": key, "value": stored}