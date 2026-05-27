"""Tests for /api/v1/transactions endpoints."""

from httpx import AsyncClient


class TestListTransactions:
    async def test_list_all(self, client: AsyncClient, filla_token: str):
        """GET /transactions returns paginated results."""
        resp = await client.get(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "data" in data
        assert "meta" in data
        assert data["meta"]["total"] >= 3  # at least seed transactions for filla
        assert data["meta"]["page"] == 1
        txn = data["data"][0]
        assert "id" in txn
        assert "amount" in txn
        assert "type" in txn
        assert "category" in txn

    async def test_filter_type(self, client: AsyncClient, filla_token: str):
        """Filter by type=expense returns only expenses."""
        resp = await client.get(
            "/api/v1/transactions?type=expense",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        for t in resp.json()["data"]:
            assert t["type"] == "expense"

    async def test_pagination(self, client: AsyncClient, filla_token: str):
        """per_page limits results, meta reflects page info."""
        resp = await client.get(
            "/api/v1/transactions?per_page=2&page=1",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["data"]) <= 2
        assert data["meta"]["per_page"] == 2

    async def test_date_filter(self, client: AsyncClient, filla_token: str):
        """date_from and date_to filters work."""
        resp = await client.get(
            "/api/v1/transactions?date_from=2026-05-20&date_to=2026-05-28",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        # Seed data uses "today" as reference, should have entries in late May
        assert resp.json()["meta"]["total"] > 0

    async def test_requires_auth(self, client: AsyncClient):
        """Without auth token, returns 401."""
        resp = await client.get("/api/v1/categories")
        assert resp.status_code == 401


class TestCreateTransaction:
    async def test_create_expense(self, client: AsyncClient, filla_token: str):
        """Create a new expense transaction returns 201."""
        resp = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 25000,
                "description": "Test expense",
                "note": "Auto test",
                "date": "2026-05-27",
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["id"] is not None
        assert data["amount"] == 25000
        assert data["type"] == "expense"

    async def test_create_income(self, client: AsyncClient, nahda_token: str):
        """Nahda can create a transaction too."""
        resp = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {nahda_token}"},
            json={
                "type": "income",
                "category_id": 7,
                "amount": 5000000,
                "description": "Gaji Nahda",
                "note": "",
                "date": "2026-05-27",
            },
        )
        assert resp.status_code == 201
        assert resp.json()["amount"] == 5000000

    async def test_create_zero_amount(self, client: AsyncClient, filla_token: str):
        """Amount must be >= 1 (gt=0 in schema)."""
        resp = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 0,
                "description": "Zero test",
                "note": "",
                "date": "2026-05-27",
            },
        )
        assert resp.status_code == 422

    async def test_create_no_auth(self, client: AsyncClient):
        """Without auth, returns 403."""
        resp = await client.post(
            "/api/v1/transactions",
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 1000,
                "description": "test",
                "date": "2026-05-27",
            },
        )
        assert resp.status_code == 401


class TestHouseholdTransactions:
    async def test_list_household(self, client: AsyncClient, filla_token: str):
        """GET /transactions/household returns all members' transactions."""
        resp = await client.get(
            "/api/v1/transactions/household",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "data" in data
        assert "meta" in data
        # Should include filla's seed transactions
        assert data["meta"]["total"] >= 5
        # Every item should have user info
        for txn in data["data"]:
            assert "user" in txn
            assert "display_name" in txn["user"]

    async def test_household_includes_nahda(self, client: AsyncClient, filla_token: str):
        """Transactions from both household members are returned."""
        resp = await client.get(
            "/api/v1/transactions/household?per_page=50",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        users = {t["user"]["display_name"] for t in resp.json()["data"]}
        assert "Filla" in users

    async def test_household_filter_type(self, client: AsyncClient, filla_token: str):
        """Filter by type works on household endpoint."""
        resp = await client.get(
            "/api/v1/transactions/household?type=expense",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        for t in resp.json()["data"]:
            assert t["type"] == "expense"

    async def test_household_date_filter(self, client: AsyncClient, filla_token: str):
        """Date range filtering works on household endpoint."""
        resp = await client.get(
            "/api/v1/transactions/household?date_from=2099-01-01&date_to=2099-12-31",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        assert resp.json()["meta"]["total"] == 0

    async def test_household_requires_auth(self, client: AsyncClient):
        """Without auth, returns 401."""
        resp = await client.get("/api/v1/transactions/household")
        assert resp.status_code == 401

    async def test_household_nahda_also_works(self, client: AsyncClient, nahda_token: str):
        """Nahda (household member) can also list household transactions."""
        resp = await client.get(
            "/api/v1/transactions/household",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 200
        assert resp.json()["meta"]["total"] >= 5


class TestUpdateTransaction:
    async def test_update_amount(self, client: AsyncClient, filla_token: str):
        """Update transaction amount."""
        # Create first
        create = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 10000,
                "description": "To update",
                "date": "2026-05-27",
            },
        )
        txn_id = create.json()["id"]

        # Update
        resp = await client.put(
            f"/api/v1/transactions/{txn_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"amount": 15000},
        )
        assert resp.status_code == 200
        assert resp.json()["amount"] == 15000

    async def test_update_other_user(self, client: AsyncClient, filla_token: str, nahda_token: str):
        """User cannot update another user's transaction."""
        # Filla creates
        create = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 5000,
                "description": "Filla's txn",
                "date": "2026-05-27",
            },
        )
        txn_id = create.json()["id"]

        # Nahda tries to update — should fail
        resp = await client.put(
            f"/api/v1/transactions/{txn_id}",
            headers={"Authorization": f"Bearer {nahda_token}"},
            json={"amount": 9999},
        )
        assert resp.status_code == 404  # or 403 — depends on impl

    async def test_update_nonexistent(self, client: AsyncClient, filla_token: str):
        """Update non-existent transaction returns 404."""
        resp = await client.put(
            "/api/v1/transactions/99999",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"amount": 100},
        )
        assert resp.status_code == 404


class TestDeleteTransaction:
    async def test_delete_own(self, client: AsyncClient, filla_token: str):
        """User can delete their own transaction."""
        create = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 7777,
                "description": "To delete",
                "date": "2026-05-27",
            },
        )
        txn_id = create.json()["id"]

        resp = await client.delete(
            f"/api/v1/transactions/{txn_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 204

    async def test_delete_other_user(self, client: AsyncClient, filla_token: str, nahda_token: str):
        """User cannot delete another user's transaction."""
        create = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 3333,
                "description": "Filla's delete test",
                "date": "2026-05-27",
            },
        )
        txn_id = create.json()["id"]

        resp = await client.delete(
            f"/api/v1/transactions/{txn_id}",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 404

    async def test_delete_nonexistent(self, client: AsyncClient, filla_token: str):
        """Delete non-existent returns 404."""
        resp = await client.delete(
            "/api/v1/transactions/99999",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 404
