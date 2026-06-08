"""Tests for Credit Card API endpoints."""

import pytest
from httpx import AsyncClient


# ── Credit Cards CRUD ────────────────────────────────────────────────


class TestCreateCreditCard:
    """POST /api/v1/credit-cards — Create a credit card."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.post(
            "/api/v1/credit-cards",
            json={"name": "BCA Visa", "billing_date": 5, "due_date": 20},
        )
        assert resp.status_code == 401

    async def test_create_card(self, client: AsyncClient, auth_headers: dict):
        """Create a card with full details."""
        response = await client.post(
            "/api/v1/credit-cards",
            json={
                "name": "BCA Visa",
                "card_number_last4": "1234",
                "billing_date": 5,
                "due_date": 20,
                "credit_limit": 10000000,
            },
            headers=auth_headers,
        )
        assert response.status_code == 201
        data = response.json()
        assert data["name"] == "BCA Visa"
        assert data["credit_limit"] == 10000000
        assert data["card_number_last4"] == "1234"
        assert data["billing_date"] == 5
        assert data["due_date"] == 20


class TestListCreditCards:
    """GET /api/v1/credit-cards — List credit cards."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.get("/api/v1/credit-cards")
        assert resp.status_code == 401

    async def test_list_empty(self, client: AsyncClient, auth_headers: dict):
        """Returns empty list initially."""
        response = await client.get("/api/v1/credit-cards", headers=auth_headers)
        assert response.status_code == 200
        assert isinstance(response.json(), list)
        assert len(response.json()) == 0

    async def test_create_and_list(self, client: AsyncClient, auth_headers: dict):
        """Create a card, then verify it appears in the list."""
        await client.post(
            "/api/v1/credit-cards",
            json={
                "name": "Mandiri",
                "card_number_last4": "5678",
                "billing_date": 10,
                "due_date": 25,
            },
            headers=auth_headers,
        )
        resp = await client.get("/api/v1/credit-cards", headers=auth_headers)
        assert len(resp.json()) == 1


class TestGetCreditCard:
    """GET /api/v1/credit-cards/{card_id} — Get single card detail."""

    async def test_not_found(self, client: AsyncClient, auth_headers: dict):
        """Returns 404 for non-existent card."""
        resp = await client.get("/api/v1/credit-cards/99999", headers=auth_headers)
        assert resp.status_code == 404

    async def test_get_card_detail(self, client: AsyncClient, auth_headers: dict):
        """Get card detail with transactions and installments."""
        create_resp = await client.post(
            "/api/v1/credit-cards",
            json={
                "name": "Detail Card",
                "card_number_last4": "0001",
                "billing_date": 5,
                "due_date": 20,
            },
            headers=auth_headers,
        )
        card_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/credit-cards/{card_id}", headers=auth_headers
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["name"] == "Detail Card"
        assert "transactions" in data
        assert "installments" in data


# ── Credit Card Transactions ─────────────────────────────────────────


class TestCreateTransaction:
    """POST /api/v1/credit-cards/{card_id}/transactions — Create transaction."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.post(
            "/api/v1/credit-cards/1/transactions",
            json={"description": "Beli kopi", "amount": 50000, "transaction_date": "2026-06-01"},
        )
        assert resp.status_code == 401

    async def test_create_transaction(self, client: AsyncClient, auth_headers: dict):
        """Create a card and add a transaction to it."""
        card_resp = await client.post(
            "/api/v1/credit-cards",
            json={
                "name": "BCA",
                "card_number_last4": "0001",
                "billing_date": 5,
                "due_date": 20,
            },
            headers=auth_headers,
        )
        card_id = card_resp.json()["id"]

        txn_resp = await client.post(
            f"/api/v1/credit-cards/{card_id}/transactions",
            json={
                "description": "Beli kopi",
                "amount": 50000,
                "transaction_date": "2026-06-01",
            },
            headers=auth_headers,
        )
        assert txn_resp.status_code == 201
        data = txn_resp.json()
        assert data["description"] == "Beli kopi"
        assert data["amount"] == 50000
        assert data["card_id"] == card_id

    async def test_transaction_on_nonexistent_card(
        self, client: AsyncClient, auth_headers: dict
    ):
        """Returns 404 for non-existent card."""
        resp = await client.post(
            "/api/v1/credit-cards/99999/transactions",
            json={
                "description": "Test",
                "amount": 10000,
                "transaction_date": "2026-06-01",
            },
            headers=auth_headers,
        )
        assert resp.status_code == 404


class TestListTransactions:
    """GET /api/v1/credit-cards/{card_id}/transactions — List transactions."""

    async def test_list_transactions(self, client: AsyncClient, auth_headers: dict):
        """List transactions for a card."""
        card_resp = await client.post(
            "/api/v1/credit-cards",
            json={
                "name": "BCA",
                "card_number_last4": "0002",
                "billing_date": 5,
                "due_date": 20,
            },
            headers=auth_headers,
        )
        card_id = card_resp.json()["id"]

        # Add two transactions
        await client.post(
            f"/api/v1/credit-cards/{card_id}/transactions",
            json={
                "description": "Beli kopi",
                "amount": 50000,
                "transaction_date": "2026-06-01",
            },
            headers=auth_headers,
        )
        await client.post(
            f"/api/v1/credit-cards/{card_id}/transactions",
            json={
                "description": "Beli bensin",
                "amount": 100000,
                "transaction_date": "2026-06-02",
            },
            headers=auth_headers,
        )

        resp = await client.get(
            f"/api/v1/credit-cards/{card_id}/transactions", headers=auth_headers
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2


# ── Credit Card Installments ─────────────────────────────────────────


class TestCreateInstallment:
    """POST /api/v1/credit-cards/{card_id}/installments — Create installment."""

    async def test_create_installment(self, client: AsyncClient, auth_headers: dict):
        """Create a card and add an installment plan."""
        card_resp = await client.post(
            "/api/v1/credit-cards",
            json={
                "name": "BCA",
                "card_number_last4": "0002",
                "billing_date": 5,
                "due_date": 20,
            },
            headers=auth_headers,
        )
        card_id = card_resp.json()["id"]

        inst_resp = await client.post(
            f"/api/v1/credit-cards/{card_id}/installments",
            json={
                "description": "iPhone 12",
                "total_amount": 12000000,
                "monthly_amount": 1000000,
                "total_months": 12,
                "remaining_months": 10,
                "start_month": "2026-01",
            },
            headers=auth_headers,
        )
        assert inst_resp.status_code == 201
        data = inst_resp.json()
        assert data["description"] == "iPhone 12"
        assert data["monthly_amount"] == 1000000
        assert data["remaining_months"] == 7  # = 12 - 5 elapsed (start Jan 2026, now Jun)


# ── Next Month Projection ────────────────────────────────────────────


class TestNextMonthProjection:
    """GET /api/v1/credit-cards/next-month-projection — Aggregated projection."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.get("/api/v1/credit-cards/next-month-projection")
        assert resp.status_code == 401

    async def test_empty_projection(self, client: AsyncClient, auth_headers: dict):
        """Returns zeroes when there are no installments."""
        resp = await client.get(
            "/api/v1/credit-cards/next-month-projection", headers=auth_headers
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_installments"] == 0
        assert data["total_expected"] == 0

    async def test_projection_with_installments(
        self, client: AsyncClient, auth_headers: dict
    ):
        """Two installments on one card are aggregated correctly."""
        card_resp = await client.post(
            "/api/v1/credit-cards",
            json={
                "name": "BCA",
                "card_number_last4": "0003",
                "billing_date": 5,
                "due_date": 20,
            },
            headers=auth_headers,
        )
        card_id = card_resp.json()["id"]

        # Add 2 installments
        await client.post(
            f"/api/v1/credit-cards/{card_id}/installments",
            json={
                "description": "Laptop",
                "total_amount": 15000000,
                "monthly_amount": 1250000,
                "total_months": 12,
                "remaining_months": 8,
                "start_month": "2026-01",
            },
            headers=auth_headers,
        )
        await client.post(
            f"/api/v1/credit-cards/{card_id}/installments",
            json={
                "description": "TV",
                "total_amount": 6000000,
                "monthly_amount": 500000,
                "total_months": 12,
                "remaining_months": 5,
                "start_month": "2026-03",
            },
            headers=auth_headers,
        )

        proj_resp = await client.get(
            "/api/v1/credit-cards/next-month-projection", headers=auth_headers
        )
        assert proj_resp.status_code == 200
        data = proj_resp.json()
        # total_expected is the sum of monthly_amounts
        assert data["total_expected"] == 1750000  # 1250000 + 500000
        # total_installments is the count of active installments
        assert data["total_installments"] == 2
        assert len(data["per_card"]) == 1  # both on the same card


# ── Delete & Cascade ─────────────────────────────────────────────────


class TestDeleteCreditCard:
    """DELETE /api/v1/credit-cards/{card_id} — Delete card (cascade)."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.delete("/api/v1/credit-cards/1")
        assert resp.status_code == 401

    async def test_delete_not_found(self, client: AsyncClient, auth_headers: dict):
        """Returns 404 for non-existent card."""
        resp = await client.delete("/api/v1/credit-cards/99999", headers=auth_headers)
        assert resp.status_code == 404

    async def test_delete_cascades(self, client: AsyncClient, auth_headers: dict):
        """Deleting a card removes its transactions and installments."""
        card_resp = await client.post(
            "/api/v1/credit-cards",
            json={
                "name": "Delete Test",
                "card_number_last4": "9999",
                "billing_date": 1,
                "due_date": 15,
            },
            headers=auth_headers,
        )
        card_id = card_resp.json()["id"]

        await client.post(
            f"/api/v1/credit-cards/{card_id}/transactions",
            json={
                "description": "Test",
                "amount": 10000,
                "transaction_date": "2026-06-01",
            },
            headers=auth_headers,
        )
        await client.post(
            f"/api/v1/credit-cards/{card_id}/installments",
            json={
                "description": "Test Installment",
                "total_amount": 100000,
                "monthly_amount": 10000,
                "total_months": 10,
                "remaining_months": 10,
                "start_month": "2026-01",
            },
            headers=auth_headers,
        )

        # Delete card
        del_resp = await client.delete(
            f"/api/v1/credit-cards/{card_id}", headers=auth_headers
        )
        assert del_resp.status_code == 204

        # Verify deleted
        get_resp = await client.get(
            f"/api/v1/credit-cards/{card_id}", headers=auth_headers
        )
        assert get_resp.status_code == 404

        # Verify transactions and installments also gone
        txn_resp = await client.get(
            f"/api/v1/credit-cards/{card_id}/transactions", headers=auth_headers
        )
        assert txn_resp.status_code == 404
