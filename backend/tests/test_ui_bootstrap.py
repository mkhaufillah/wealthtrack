"""GET /api/v1/ui/bootstrap — public copy/config from DB, Redis TTL 1h."""

import os

import pytest
import redis.asyncio as aioredis
from httpx import AsyncClient

from app.database import CursorWrapper

REDIS_KEYS = ("ui:bootstrap:id-ID", "ui:bootstrap:en-US")


async def _flush_bootstrap_cache():
    """Flush using a dedicated connection (not the global singleton), so
    pytest's function-scoped event loop stays consistent across tests."""
    r = aioredis.Redis.from_url(
        os.getenv("REDIS_URL", "redis://localhost:6379/0"),
        decode_responses=True,
    )
    try:
        await r.delete(*REDIS_KEYS)
    finally:
        await r.aclose()


@pytest.fixture(autouse=True)
async def _clean_bootstrap_cache():
    await _flush_bootstrap_cache()
    yield
    try:
        await _flush_bootstrap_cache()
    except Exception:
        pass
    # Reset the process-global redis singleton so a later test reconnects
    # in its own (fresh, function-scoped) event loop instead of a stale one.
    from app.core import redis as redis_mod
    old = redis_mod._redis
    redis_mod._redis = None
    if old is not None:
        try:
            await old.aclose()
        except Exception:
            pass


class TestUiBootstrap:
    async def test_bootstrap_public_no_jwt(self, client: AsyncClient):
        resp = await client.get("/api/v1/ui/bootstrap")
        assert resp.status_code == 200
        data = resp.json()
        assert data["locale"] == "id-ID"
        assert data["copy"]["home.hero_title"] == "Uang kamu"
        assert data["copy"]["auth.username"] == "Username"
        assert data["copy"]["auth.email"] == "Email"
        assert data["format"]["currency_prefix"] == "Rp"
        assert data["format"]["group_sep"] == "."
        assert data["theme"]["light"]["accent"].startswith("#")
        assert data["flags"]["home_all_time"] is True

    async def test_bootstrap_serves_db_not_hardcoded_only(
        self, client: AsyncClient, db: CursorWrapper
    ):
        await db.execute(
            "UPDATE ui_copy SET value = 'Uang tes' WHERE key = 'home.hero_title' AND locale = 'id-ID'"
        )
        await _flush_bootstrap_cache()
        resp = await client.get("/api/v1/ui/bootstrap")
        assert resp.status_code == 200
        assert resp.json()["copy"]["home.hero_title"] == "Uang tes"

    async def test_bootstrap_redis_hit_skips_db_update(
        self, client: AsyncClient, db: CursorWrapper
    ):
        first = await client.get("/api/v1/ui/bootstrap")
        assert first.status_code == 200
        assert first.json()["copy"]["home.hero_title"] == "Uang kamu"

        await db.execute(
            "UPDATE ui_copy SET value = 'Uang tes' WHERE key = 'home.hero_title' AND locale = 'id-ID'"
        )
        second = await client.get("/api/v1/ui/bootstrap")
        assert second.status_code == 200
        assert second.json()["copy"]["home.hero_title"] == "Uang kamu"

        import os

        import redis.asyncio as aioredis
        r = aioredis.Redis.from_url(
            os.getenv("REDIS_URL", "redis://localhost:6379/0"),
            decode_responses=True,
        )
        try:
            ttl = await r.ttl("ui:bootstrap:id-ID")
            assert 0 < ttl <= 3600
        finally:
            await r.aclose()

    async def test_bootstrap_cache_control(self, client: AsyncClient):
        resp = await client.get("/api/v1/ui/bootstrap")
        assert resp.status_code == 200
        assert "max-age=300" in (resp.headers.get("cache-control") or "")

    async def test_bootstrap_english(self, client: AsyncClient):
        resp = await client.get("/api/v1/ui/bootstrap?locale=en-US")
        assert resp.status_code == 200
        data = resp.json()
        assert data["locale"] == "en-US"
        assert data["copy"]["home.hero_title"] == "Your money"
        assert data["copy"]["home.income"] == "Income"
