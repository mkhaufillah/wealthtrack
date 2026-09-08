"""Tests for /api/v1/health endpoint."""

from httpx import AsyncClient


class TestHealthCheck:
    async def test_health_returns_ok(self, client: AsyncClient):
        """GET /health returns 200 with database + redis connected."""
        resp = await client.get("/api/v1/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["database"] == "connected"
        assert data["redis"] == "connected"

    async def test_health_head(self, client: AsyncClient):
        """HEAD /health is also served (LB probes)."""
        resp = await client.head("/api/v1/health")
        assert resp.status_code == 200

    async def test_health_service_degraded(
        self, client: AsyncClient, monkeypatch
    ):
        """When Redis is down, status becomes degraded but still 200."""
        import app.services.health_service as hs

        async def _broken_ping():
            raise RuntimeError("redis down")

        class _BrokenRedis:
            async def ping(self):
                raise RuntimeError("redis down")

        async def _broken_get_redis():
            return _BrokenRedis()

        monkeypatch.setattr(hs, "get_redis", _broken_get_redis)
        resp = await client.get("/api/v1/health")
        # DB still ok, redis unreachable -> degraded
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "degraded"
        assert data["database"] == "connected"
        assert data["redis"] == "unreachable"