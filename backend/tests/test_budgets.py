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

    async def test_list_shows_created_budgets(
        self, client: AsyncClient, filla_token: str
    ):
        """Create a budget, then list → verify it appears."""
        # Create a budget
        create = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 1, "amount": 500000},
        )
        assert create.status_code == 201

        # List budgets
        resp = await client.get(
            "/api/v1/budgets?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) >= 1
        # Find our budget
        match = [b for b in data if b["category_id"] == 1]
        assert len(match) >= 1
        assert match[0]["amount"] == 500000

    async def test_list_other_user_budgets_not_visible(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        """Nahda creates a budget, filla can't see it."""
        # Nahda creates a budget
        await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {nahda_token}"},
            json={"month": "2026-05", "category_id": 2, "amount": 300000},
        )

        # Filla lists — should not see nahda's budget
        resp = await client.get(
            "/api/v1/budgets?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        data = resp.json()
        assert not any(b["category_id"] == 2 for b in data)


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

    async def test_upsert_same_category_month_updates(
        self, client: AsyncClient, filla_token: str
    ):
        """POST /budgets with same user+month+category → update (upsert)."""
        # Create first
        create1 = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-06", "category_id": 1, "amount": 300000},
        )
        assert create1.status_code == 201
        budget_id = create1.json()["id"]
        assert create1.json()["amount"] == 300000

        # Upsert with different amount
        create2 = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-06", "category_id": 1, "amount": 500000},
        )
        assert create2.status_code == 201
        # Should have the SAME id (updated, not created new)
        assert create2.json()["id"] == budget_id
        assert create2.json()["amount"] == 500000

    async def test_upsert_returns_updated_data(
        self, client: AsyncClient, filla_token: str
    ):
        """After upsert, listing shows the updated values."""
        # Create
        await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-07", "category_id": 3, "amount": 200000},
        )

        # Upsert with new amount
        await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-07", "category_id": 3, "amount": 750000},
        )

        # List and verify
        resp = await client.get(
            "/api/v1/budgets?month=2026-07",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        data = resp.json()
        match = [b for b in data if b["category_id"] == 3]
        assert len(match) == 1
        assert match[0]["amount"] == 750000


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
        create = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 1, "amount": 200000},
        )
        budget_id = create.json()["id"]

        resp = await client.delete(
            f"/api/v1/budgets/{budget_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 204

    async def test_delete_other_user_budget(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        """Delete another user's budget → 404 (not found for that user)."""
        # Filla creates a budget
        create = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 1, "amount": 100000},
        )
        budget_id = create.json()["id"]

        # Nahda tries to delete it — should get 404 because the query filters by user_id
        resp = await client.delete(
            f"/api/v1/budgets/{budget_id}",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 404


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

    async def test_summary_shows_budget_details(
        self, client: AsyncClient, filla_token: str
    ):
        """Create budget with actual spending → summary shows percentage, remaining."""
        # Create a budget
        await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 1, "amount": 100000},
        )

        # Get summary
        resp = await client.get(
            "/api/v1/budgets/summary?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) >= 1
        item = [s for s in data if s["category_id"] == 1][0]
        assert item["budget_amount"] == 100000
        assert "actual_spent" in item
        assert "percentage" in item
        assert "remaining" in item

    async def test_summary_with_transactions(
        self, client: AsyncClient, filla_token: str
    ):
        """Budget with a transaction for the same category shows actual_spent."""
        # Create a budget for category 1 (Makanan) with amount 500000
        await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 1, "amount": 500000},
        )

        # Seed data already has a 50000 expense for category 1 on day 2 of this month
        # Create another expense to verify actual_spent
        await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 30000,
                "description": "Extra expense for budget test",
                "date": "2026-05-15",
            },
        )

        # Get summary
        resp = await client.get(
            "/api/v1/budgets/summary?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        item = [s for s in data if s["category_id"] == 1][0]
        assert item["budget_amount"] == 500000
        # actual_spent should include seed transaction (50000) + new one (30000)
        assert item["actual_spent"] >= 80000
        assert item["percentage"] > 0
        assert item["remaining"] == item["budget_amount"] - item["actual_spent"]
