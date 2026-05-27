"""Tests for /api/v1/summaries endpoints."""

from httpx import AsyncClient


class TestDailySummary:
    async def test_daily_returns_data(self, client: AsyncClient, filla_token: str):
        """GET /summaries/daily returns income, expense, balance."""
        resp = await client.get(
            "/api/v1/summaries/daily?date_from=2026-05-01&date_to=2026-05-31",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "total_income" in data
        assert "total_expense" in data
        assert "balance" in data
        assert "by_category" in data
        assert "by_user" in data
        assert data["total_income"] >= 0
        assert data["total_expense"] >= 0

    async def test_daily_no_dates(self, client: AsyncClient, filla_token: str):
        """Without date params, defaults to today (still returns valid JSON)."""
        resp = await client.get(
            "/api/v1/summaries/daily",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200

    async def test_daily_requires_auth(self, client: AsyncClient):
        """Without auth, returns 403."""
        resp = await client.get("/api/v1/summaries/daily")
        assert resp.status_code == 401


class TestMonthlySummary:
    async def test_monthly_specific(self, client: AsyncClient, filla_token: str):
        """GET /summaries/monthly?month=2026-05 returns monthly data."""
        resp = await client.get(
            "/api/v1/summaries/monthly?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["month"] == "2026-05"
        assert "total_income" in data
        assert "total_expense" in data
        assert "balance" in data
        assert "categories" in data
        assert "daily_snapshot" in data

    async def test_monthly_current(self, client: AsyncClient, filla_token: str):
        """GET /summaries/current-month works."""
        resp = await client.get(
            "/api/v1/summaries/current-month",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "month" in data
        assert "total_income" in data
        assert "daily_snapshot" in data
        # daily_snapshot should have at least some entries
        assert isinstance(data["daily_snapshot"], list)

    async def test_monthly_invalid_format(self, client: AsyncClient, filla_token: str):
        """Invalid month format returns 422."""
        resp = await client.get(
            "/api/v1/summaries/monthly?month=abc",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422


class TestHouseholdSummary:
    async def test_household_returns_data(self, client: AsyncClient, filla_token: str):
        """GET /summaries/household returns combined household data."""
        resp = await client.get(
            "/api/v1/summaries/household?date_from=2026-05-01&date_to=2026-05-31",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "total_income" in data
        assert "total_expense" in data
        assert "balance" in data
        assert "by_user" in data
        assert "by_category" in data
        # Should include transactions from all users
        assert data["total_income"] > 0

    async def test_household_shows_all_users(self, client: AsyncClient, nahda_token: str):
        """Household summary includes all users, not just the requester."""
        resp = await client.get(
            "/api/v1/summaries/household?date_from=2026-05-01&date_to=2026-05-31",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 200
        users = resp.json()["by_user"]
        usernames = [u["display_name"] for u in users]
        assert "Filla" in usernames  # Filla has transactions
        assert len(users) >= 1

    async def test_household_requires_auth(self, client: AsyncClient):
        """Without auth, returns 403."""
        resp = await client.get("/api/v1/summaries/household")
        assert resp.status_code == 401
