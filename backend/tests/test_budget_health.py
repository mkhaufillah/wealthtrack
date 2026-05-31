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

    async def test_with_budgets_and_transactions(self, client: AsyncClient, filla_token: str):
        """Create a budget + an expense, then verify health projection reflects it."""
        # Create a budget for health category (id=6) in May 2026
        resp = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 6, "amount": 500000},
        )
        assert resp.status_code == 201

        # Create an expense transaction for health category
        from datetime import date
        today = date.today()
        resp = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "category_id": 6,
                "type": "expense",
                "amount": 100000,
                "description": "Test health expense",
                "date": today.isoformat(),
            },
        )
        assert resp.status_code == 201

        # Now check health endpoint
        resp = await client.get(
            "/api/v1/budgets/health?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["days_elapsed"] >= 1
        assert data["total_days"] >= 1
        assert data["cycle_progress_pct"] > 0
        assert len(data["categories"]) >= 1
        # Find our health category
        health = [c for c in data["categories"] if c["category_id"] == 6]
        assert len(health) == 1
        h = health[0]
        assert h["budget_amount"] == 500000
        assert h["actual_spent"] >= 100000
        assert h["daily_rate"] > 0
        assert h["health"] in ("healthy", "warning", "at_risk", "exhausted")
