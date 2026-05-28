"""Tests for /api/v1/budgets endpoints."""

from httpx import AsyncClient


class TestListBudgets:
    async def test_list_requires_month(self, client: AsyncClient, filla_token: str):
        """GET /budgets without month returns 422."""
        resp = await client.get(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422

    async def test_list_returns_empty(self, client: AsyncClient, filla_token: str):
        """GET /budgets?month=2026-05 returns empty list initially."""
        resp = await client.get(
            "/api/v1/budgets?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert len(data) == 0

    async def test_list_requires_auth(self, client: AsyncClient):
        """GET /budgets without token returns 401."""
        resp = await client.get("/api/v1/budgets?month=2026-05")
        assert resp.status_code == 401


class TestCreateBudget:
    async def test_create_success(self, client: AsyncClient, filla_token: str):
        """POST /budgets creates a new budget and returns 201."""
        resp = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "month": "2026-05",
                "category_id": 1,
                "amount": 500000,
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["id"] is not None
        assert data["month"] == "2026-05"
        assert data["category_id"] == 1
        assert data["amount"] == 500000
        assert "category_name" in data
        assert "category_icon" in data

    async def test_create_requires_auth(self, client: AsyncClient):
        """POST /budgets without token returns 401."""
        resp = await client.post(
            "/api/v1/budgets",
            json={"month": "2026-05", "category_id": 1, "amount": 100000},
        )
        assert resp.status_code == 401

    async def test_create_nonexistent_category(self, client: AsyncClient, filla_token: str):
        """POST /budgets with invalid category_id returns 404."""
        resp = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 999, "amount": 100000},
        )
        assert resp.status_code == 404


class TestDeleteBudget:
    async def test_delete_requires_auth(self, client: AsyncClient):
        """DELETE /budgets/{id} without token returns 401."""
        resp = await client.delete("/api/v1/budgets/1")
        assert resp.status_code == 401

    async def test_delete_nonexistent(self, client: AsyncClient, filla_token: str):
        """DELETE /budgets/{id} with non-existent id returns 404."""
        resp = await client.delete(
            "/api/v1/budgets/99999",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 404

    async def test_delete_own_budget(self, client: AsyncClient, filla_token: str):
        """Create then delete a budget returns 204."""
        # Create first
        create = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 1, "amount": 200000},
        )
        budget_id = create.json()["id"]

        # Delete
        resp = await client.delete(
            f"/api/v1/budgets/{budget_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 204


class TestBudgetSummary:
    async def test_summary_requires_month(self, client: AsyncClient, filla_token: str):
        """GET /budgets/summary without month returns 422."""
        resp = await client.get(
            "/api/v1/budgets/summary",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422

    async def test_summary_returns_empty(self, client: AsyncClient, filla_token: str):
        """GET /budgets/summary?month=2026-05 returns empty list when no budgets exist."""
        resp = await client.get(
            "/api/v1/budgets/summary?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)

    async def test_summary_requires_auth(self, client: AsyncClient):
        """GET /budgets/summary without token returns 401."""
        resp = await client.get("/api/v1/budgets/summary?month=2026-05")
        assert resp.status_code == 401
