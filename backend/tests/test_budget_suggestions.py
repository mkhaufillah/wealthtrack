"""Tests for GET /budgets/suggestions endpoint."""

from httpx import AsyncClient


class TestBudgetSuggestions:
    async def test_requires_auth(self, client: AsyncClient):
        resp = await client.get("/api/v1/budgets/suggestions?month=2026-05")
        assert resp.status_code == 401

    async def test_empty_when_no_data(self, client: AsyncClient, empty_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-05",
            headers={"Authorization": f"Bearer {empty_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["items"] == []

    async def test_returns_suggestions(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data
        if data["items"]:
            item = data["items"][0]
            assert "category_id" in item
            assert "suggested_amount" in item
            assert item["suggested_amount"] > 0

    async def test_invalid_month_format(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-5",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422

    async def test_num_cycles_param(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-05&num_cycles=6",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data

    async def test_validates_num_cycles_range(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-05&num_cycles=0",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422
