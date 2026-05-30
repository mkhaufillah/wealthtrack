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
        """Create a budget, then list verify it appears."""
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

        # Filla lists should not see nahda's budget
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
        """POST /budgets with same user+month+category update (upsert)."""
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
        """Delete another user's budget 404 (not found for that user)."""
        # Filla creates a budget
        create = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 1, "amount": 100000},
        )
        budget_id = create.json()["id"]

        # Nahda tries to delete it should get 404 because the query filters by user_id
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
        """Create budget with actual spending summary shows percentage, remaining."""
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

    async def test_cycle_on_stored_on_create(
        self, client: AsyncClient, filla_token: str, db
    ):
        """Creating a budget stores the current user's cycle setting."""
        resp = await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 6, "amount": 100000},
        )
        assert resp.status_code == 201

        cursor = await db.execute(
            "SELECT cycle_on FROM budgets WHERE user_id = 1 AND month = '2026-05' AND category_id = 6"
        )
        row = await cursor.fetchone()
        assert row is not None
        # Default cycle is 1
        assert row["cycle_on"] == 1

    async def test_upsert_keeps_original_cycle_on(
        self, client: AsyncClient, filla_token: str, db
    ):
        """Updating a budget amount keeps the original cycle_on."""
        # Create budget with cycle=1
        await client.post(
            "/api/v1/budgets",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"month": "2026-05", "category_id": 6, "amount": 100000},
        )

        # Update user cycle to 25
        await db.execute("UPDATE users SET cycle_start_day = 25 WHERE id = 1")
        await db.commit()

        try:
            # Upsert the same budget (different amount)
            await client.post(
                "/api/v1/budgets",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"month": "2026-05", "category_id": 6, "amount": 200000},
            )

            # Verify cycle_on is still 1 (kept original)
            cursor = await db.execute(
                "SELECT cycle_on, budget_amount FROM budgets WHERE user_id = 1 AND month = '2026-05' AND category_id = 6"
            )
            row = await cursor.fetchone()
            assert row is not None
            assert row["cycle_on"] == 1, "Upsert should NOT update cycle_on"
            assert row["budget_amount"] == 200000, "Amount should be updated"
        finally:
            # Restore cycle
            await db.execute("UPDATE users SET cycle_start_day = 1 WHERE id = 1")
            await db.commit()

    async def test_summary_uses_stored_cycle_on_range(
        self, client: AsyncClient, filla_token: str, db
    ):
        """Summary with use_cycle=true uses the budget's stored cycle_on, not current user setting."""
        # Create a transaction outside standard calendar range but inside cycle-25 range
        # With cycle=25: month "2026-05" range = Apr 25 to May 24
        # Transaction on Apr 26 is outside calendar (May 1-31) but inside cycle range
        await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 50000,
                "description": "Cycle range test",
                "date": "2026-04-26",
            },
        )

        # Update user cycle to 25
        await db.execute("UPDATE users SET cycle_start_day = 25 WHERE id = 1")
        await db.commit()

        try:
            # Create a budget for 2026-05 with cycle=25
            await client.post(
                "/api/v1/budgets",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"month": "2026-05", "category_id": 1, "amount": 500000},
            )

            # Verify budget has cycle_on=25
            cursor = await db.execute(
                "SELECT cycle_on FROM budgets WHERE user_id = 1 AND month = '2026-05' AND category_id = 1"
            )
            row = await cursor.fetchone()
            assert row is not None
            assert row["cycle_on"] == 25

            # Now change user's cycle back to 1
            await db.execute("UPDATE users SET cycle_start_day = 1 WHERE id = 1")
            await db.commit()

            # Get summary with use_cycle=true
            # Should use budget's stored cycle_on=25, NOT current user cycle=1
            # With cycle=25, range for '2026-05' = Apr 25 to May 24
            # Apr 26 transaction should be INCLUDED (inside cycle range)
            # Seed transaction for cat 1 (at May 25) should NOT be counted (outside cycle range)
            resp = await client.get(
                "/api/v1/budgets/summary?month=2026-05&use_cycle=true",
                headers={"Authorization": f"Bearer {filla_token}"},
            )
            assert resp.status_code == 200
            data = resp.json()
            item = [s for s in data if s["category_id"] == 1][0]
            # Only the Apr 26 transaction (50000) is inside cycle range
            # Seed cat-1 (May 25) is outside cycle range
            assert item["actual_spent"] == 50000, (
                f"Expected 50000 (only Apr 26 inside cycle=25 range), got {item['actual_spent']}"
            )
        finally:
            await db.execute("UPDATE users SET cycle_start_day = 1 WHERE id = 1")
            await db.commit()
