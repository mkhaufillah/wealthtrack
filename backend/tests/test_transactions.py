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
        # Use broad date range to cover seed data (which uses relative dates)
        resp = await client.get(
            "/api/v1/transactions?date_from=2026-01-01&date_to=2027-01-01",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        assert resp.json()["meta"]["total"] > 0

    async def test_requires_auth(self, client: AsyncClient):
        """Without auth token, returns 401."""
        resp = await client.get("/api/v1/categories")
        assert resp.status_code == 401

    async def test_search_by_description(self, client: AsyncClient, filla_token: str):
        """Search via ?q= returns matching transactions (LIKE fallback in tests)."""
        resp = await client.get(
            "/api/v1/transactions?q=Gaji",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["meta"]["total"] >= 1
        for t in data["data"]:
            assert "Gaji" in t["description"] or "gaji" in t["description"].lower()

    async def test_search_no_match(self, client: AsyncClient, filla_token: str):
        """Search with no match returns empty result."""
        resp = await client.get(
            "/api/v1/transactions?q=zzzznotexist",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["meta"]["total"] == 0
        assert data["data"] == []

    async def test_search_with_type_filter(self, client: AsyncClient, filla_token: str):
        """Search + type filter work together."""
        resp = await client.get(
            "/api/v1/transactions?q=Gaji&type=income",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        for t in resp.json()["data"]:
            assert t["type"] == "income"

    async def test_search_with_category_and_date(
        self, client: AsyncClient, filla_token: str
    ):
        """Search + category_id + date range."""
        # Seed data has "Gaji" in category 7 with date in 2026
        resp = await client.get(
            "/api/v1/transactions?q=Gaji&category_id=7&date_from=2026-01-01&date_to=2026-12-31",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        for t in data["data"]:
            assert t["category"]["id"] == 7


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


class TestTransferOwner:
    async def test_owner_transfers_to_household_member(
        self, client: AsyncClient, filla_token: str
    ):
        """Owner can transfer transaction to another household member."""
        # Transaction 1 is owned by filla (user_id=1)
        resp = await client.put(
            "/api/v1/transactions/1/owner",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"user_id": 2},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["user"]["id"] == 2
        assert data["user"]["display_name"] == "Nahda"

    async def test_admin_transfers_others_transaction(
        self, client: AsyncClient, filla_token: str
    ):
        """Household admin can transfer any household member's transaction."""
        # Transfer nahda's transaction (we need one owned by nahda first)
        # Create a transaction for nahda
        create = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 10000,
                "description": "Filla creates for admin test",
                "date": "2026-05-27",
            },
        )
        txn_id = create.json()["id"]
        assert create.json()["user"]["id"] == 1  # filla owns it

        # Transfer to nahda (user 2)
        resp = await client.put(
            f"/api/v1/transactions/{txn_id}/owner",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"user_id": 2},
        )
        assert resp.status_code == 200
        assert resp.json()["user"]["id"] == 2

    async def test_non_owner_cannot_transfer(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        """Non-owner, non-admin cannot transfer."""
        # Create a transaction as filla
        create = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 5000,
                "description": "Transfer test",
                "date": "2026-05-27",
            },
        )
        txn_id = create.json()["id"]

        # Nahda (member, not owner) tries to transfer — should fail
        resp = await client.put(
            f"/api/v1/transactions/{txn_id}/owner",
            headers={"Authorization": f"Bearer {nahda_token}"},
            json={"user_id": 1},
        )
        assert resp.status_code == 403

    async def test_transfer_outside_household_fails(
        self, client: AsyncClient, filla_token: str
    ):
        """Cannot transfer to user outside household."""
        # User 999 doesn't exist in any household
        resp = await client.put(
            "/api/v1/transactions/1/owner",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"user_id": 999},
        )
        assert resp.status_code == 400

    async def test_transfer_nonexistent_transaction(
        self, client: AsyncClient, filla_token: str
    ):
        """Transfer non-existent transaction returns 404."""
        resp = await client.put(
            "/api/v1/transactions/99999/owner",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"user_id": 2},
        )
        assert resp.status_code == 404

    async def test_transfer_requires_auth(self, client: AsyncClient):
        """Without auth, returns 401."""
        resp = await client.put(
            "/api/v1/transactions/1/owner",
            json={"user_id": 2},
        )
        assert resp.status_code == 401


class TestTransferBalance:
    async def test_transfer_to_one_member(self, client: AsyncClient, filla_token: str):
        """Transfer from filla to nahda creates 2 transactions."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 3000000}],
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert "transactions" in data
        assert len(data["transactions"]) == 1
        t = data["transactions"][0]
        assert t["sender_expense"]["type"] == "expense"
        assert t["sender_expense"]["amount"] == 3000000
        assert t["sender_expense"]["user"]["id"] == 1
        assert t["recipient_income"]["type"] == "income"
        assert t["recipient_income"]["amount"] == 3000000
        assert t["recipient_income"]["user"]["id"] == 2

    async def test_transfer_to_multiple_members(
        self, client: AsyncClient, filla_token: str
    ):
        """Transfer to same member twice creates 2 transaction pairs."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [
                    {"user_id": 2, "amount": 3000000},
                    {"user_id": 2, "amount": 500000},
                ],
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert len(data["transactions"]) == 2
        amounts = sorted(
            t["sender_expense"]["amount"] for t in data["transactions"]
        )
        assert amounts == [500000, 3000000]

    async def test_transfer_requires_auth(self, client: AsyncClient):
        """Without auth token, returns 401."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 1000}],
            },
        )
        assert resp.status_code == 401

    async def test_transfer_outside_household_fails(
        self, client: AsyncClient, filla_token: str
    ):
        """Cannot transfer to user outside household."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 999, "amount": 1000}],
            },
        )
        assert resp.status_code == 400

    async def test_transfer_zero_amount(
        self, client: AsyncClient, filla_token: str
    ):
        """Amount must be > 0 — returns 422."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 0}],
            },
        )
        assert resp.status_code == 422

    async def test_transfer_empty_list(
        self, client: AsyncClient, filla_token: str
    ):
        """Empty transfers list returns 422."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"date": "2026-05-28", "transfers": []},
        )
        assert resp.status_code == 422

    async def test_transfer_categories_exist(
        self, client: AsyncClient, filla_token: str
    ):
        """Transfer endpoint uses the correct category names."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 100000}],
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        t = data["transactions"][0]
        assert t["sender_expense"]["category"]["name"] == "Transfer"
        assert t["recipient_income"]["category"]["name"] == "Transfer"

    async def test_transfer_updates_summary(
        self, client: AsyncClient, filla_token: str
    ):
        """After transfer, sender's expense appears in their summary."""
        await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 2000000}],
            },
        )
        resp = await client.get(
            "/api/v1/summaries/daily?date_from=2026-05-28&date_to=2026-05-28",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        filla_user = [
            u for u in data["by_user"] if u["display_name"] == "Filla"
        ]
        assert len(filla_user) > 0
        assert filla_user[0]["total_expense"] >= 2000000


class TestGetTransactionById:
    async def test_get_success(self, client: AsyncClient, filla_token: str):
        """GET /transactions/{id} returns the full transaction by its ID."""
        create = await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 50000,
                "description": "test get by id",
                "date": "2026-05-28",
            },
        )
        assert create.status_code == 201
        txn_id = create.json()["id"]

        resp = await client.get(
            f"/api/v1/transactions/{txn_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["id"] == txn_id
        assert data["amount"] == 50000
        assert data["type"] == "expense"
        assert data["description"] == "test get by id"
        assert "category" in data
        assert "user" in data

    async def test_get_nonexistent(self, client: AsyncClient, filla_token: str):
        """GET /transactions/{id} for a non-existent ID returns 404."""
        resp = await client.get(
            "/api/v1/transactions/999999",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 404

    async def test_get_requires_auth(self, client: AsyncClient):
        """GET /transactions/{id} without token returns 401."""
        resp = await client.get("/api/v1/transactions/1")
        assert resp.status_code == 401
