"""Assemble GET /ui/bootstrap from Postgres; Redis TTL 1 hour."""

from __future__ import annotations

import json

from app.core.redis import get_redis
from app.database import CursorWrapper

CACHE_TTL_SEC = 3600
DEFAULT_LOCALE = "id-ID"


def cache_key(locale: str) -> str:
    return f"ui:bootstrap:{locale}"


class UiBootstrapService:
    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    async def get_bootstrap(self, locale: str = DEFAULT_LOCALE) -> dict:
        redis = await get_redis()
        key = cache_key(locale)
        cached = await redis.get(key)
        if cached:
            return json.loads(cached)

        payload = await self._load_from_db(locale)
        await redis.setex(
            key,
            CACHE_TTL_SEC,
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        )
        return payload

    async def _load_from_db(self, locale: str) -> dict:
        cursor = await self.db.execute(
            "SELECT key, value FROM ui_copy WHERE locale = ?",
            (locale,),
        )
        copy_rows = await cursor.fetchall()
        copy = {row["key"]: row["value"] for row in copy_rows}

        cursor = await self.db.execute("SELECT key, value FROM ui_config")
        cfg_rows = await cursor.fetchall()
        cfg = {}
        for row in cfg_rows:
            val = row["value"]
            if isinstance(val, str):
                val = json.loads(val)
            cfg[row["key"]] = val

        locale_val = cfg.get("locale", locale)
        if isinstance(locale_val, str) and locale_val.startswith('"'):
            locale_val = json.loads(locale_val)

        return {
            "locale": locale_val if isinstance(locale_val, str) else locale,
            "format": cfg.get("format") or {
                "currency": "IDR",
                "currency_prefix": "Rp",
                "group_sep": ".",
                "decimal_sep": ",",
            },
            "theme": {
                "light": cfg.get("theme.light") or {},
                "dark": cfg.get("theme.dark") or {},
            },
            "copy": copy,
            "flags": cfg.get("flags") or {"home_all_time": True},
        }
