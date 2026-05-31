"""Tests for GET /budgets/health endpoint."""

from httpx import AsyncClient


class TestBudgetHealth:
    async def test_requires_auth(self, client: AsyncClient):
        resp = await client.get("/api/v1/budgets/health?month=2026-05")
        assert resp.status_code == 401

    async def test_returns_projections(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/health?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "days_elapsed" in data
        assert "total_days" in data
        assert "categories" in data

    async def test_invalid_month_format(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/health?month=2026-5",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422
