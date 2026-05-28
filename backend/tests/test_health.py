"""Tests for /api/v1/health endpoint."""

from httpx import AsyncClient


class TestHealthCheck:
    async def test_health_returns_ok(self, client: AsyncClient):
        """GET /health returns 200 with status and database info."""
        resp = await client.get("/api/v1/health")
        assert resp.status_code == 200
        data = resp.json()
        assert "status" in data
        assert "database" in data
        assert data["status"] == "ok"
        assert data["database"] == "connected"
