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

    async def test_marks_existing_budgets(self, client: AsyncClient, filla_token: str):
        """Budget suggestions should mark categories that already have a budget."""
        # Create a budget first
        resp = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 1, "amount": 1000000},
        )
        assert resp.status_code == 201

        # Get suggestions
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["items"]) > 0
        food = [i for i in data["items"] if i["category_id"] == 1]
        if food:
            # Category 1 (Food) should be marked as having a budget
            assert food[0]["has_budget"] is True
            assert food[0]["existing_amount"] == 1000000
