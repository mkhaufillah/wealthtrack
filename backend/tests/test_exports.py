"""Tests for /api/v1/exports endpoints."""

from httpx import AsyncClient


class TestExportYearly:
    async def test_export_returns_xlsx(self, client: AsyncClient, filla_token: str):
        """GET /exports/yearly?year=2026 returns 200 with xlsx content-type."""
        resp = await client.get(
            "/api/v1/exports/yearly?year=2026",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        assert resp.headers["content-type"] == (
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )

    async def test_export_requires_auth(self, client: AsyncClient):
        """GET /exports/yearly without token returns 401."""
        resp = await client.get("/api/v1/exports/yearly?year=2026")
        assert resp.status_code == 401

    async def test_export_invalid_year(self, client: AsyncClient, filla_token: str):
        """GET /exports/yearly with year out of range returns 422."""
        resp = await client.get(
            "/api/v1/exports/yearly?year=1900",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422
