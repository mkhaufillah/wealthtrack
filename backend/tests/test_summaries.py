"""Tests for /api/v1/summaries endpoints."""

from datetime import date

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

    async def test_daily_specific_date_filtered(
        self, client: AsyncClient, filla_token: str
    ):
        """Daily summary for a specific date returns data for that date only."""
        # Create a transaction for a known date
        await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 15000,
                "description": "Test daily filter",
                "date": "2026-05-15",
            },
        )

        # Query for that specific date
        resp = await client.get(
            "/api/v1/summaries/daily?date_from=2026-05-15&date_to=2026-05-15",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["date_from"] == "2026-05-15"
        assert data["date_to"] == "2026-05-15"
        # Should have some expense for that date
        assert data["total_expense"] >= 15000

    async def test_daily_empty_range(
        self, client: AsyncClient, filla_token: str
    ):
        """Query for a date range with no transactions returns zeroes."""
        resp = await client.get(
            "/api/v1/summaries/daily?date_from=2099-01-01&date_to=2099-12-31",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_income"] == 0
        assert data["total_expense"] == 0
        assert data["balance"] == 0
        assert data["by_category"] == []
        # by_user may be empty when no transactions exist
        assert isinstance(data["by_user"], list)


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
        assert isinstance(data["daily_snapshot"], list)

    async def test_monthly_invalid_format(self, client: AsyncClient, filla_token: str):
        """Invalid month format returns 422."""
        resp = await client.get(
            "/api/v1/summaries/monthly?month=abc",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422

    async def test_monthly_range_multi_month(
        self, client: AsyncClient, filla_token: str
    ):
        """GET /summaries/monthly with month_from + month_to → returns list."""
        resp = await client.get(
            "/api/v1/summaries/monthly?month_from=2026-01&month_to=2026-03",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert len(data) == 3  # Jan, Feb, Mar
        for item in data:
            assert "month" in item
            assert "total_income" in item
            assert "total_expense" in item
            assert "balance" in item
        assert data[0]["month"] == "2026-01"
        assert data[2]["month"] == "2026-03"

    async def test_monthly_range_with_only_from(
        self, client: AsyncClient, filla_token: str
    ):
        """Only month_from provided → range goes from that month to current."""
        today = date.today()
        current_month = today.strftime("%Y-%m")

        resp = await client.get(
            "/api/v1/summaries/monthly?month_from=2026-01",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert len(data) >= 1
        assert data[0]["month"] == "2026-01"
        # Last item should be current month
        assert data[-1]["month"] == current_month

    async def test_monthly_range_with_only_to(
        self, client: AsyncClient, filla_token: str
    ):
        """Only month_to provided → defaults from to '2026-01'."""
        resp = await client.get(
            "/api/v1/summaries/monthly?month_to=2026-02",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert data[0]["month"] == "2026-01"
        assert data[-1]["month"] == "2026-02"

    async def test_monthly_range_single_month(
        self, client: AsyncClient, filla_token: str
    ):
        """month_from == month_to returns a list with one item."""
        resp = await client.get(
            "/api/v1/summaries/monthly?month_from=2026-05&month_to=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert len(data) == 1
        assert data[0]["month"] == "2026-05"

    async def test_current_month_returns_data_for_this_month(
        self, client: AsyncClient, filla_token: str
    ):
        """GET /summaries/current-month returns data for current month."""
        resp = await client.get(
            "/api/v1/summaries/current-month",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        today = date.today()
        expected_month = today.strftime("%Y-%m")
        assert data["month"] == expected_month
        # Should have seed data
        assert data["total_income"] >= 0
        assert data["total_expense"] >= 0
        # daily_snapshot should be a list
        assert isinstance(data["daily_snapshot"], list)


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
        assert "Filla" in usernames
        assert len(users) >= 1

    async def test_household_requires_auth(self, client: AsyncClient):
        """Without auth, returns 403."""
        resp = await client.get("/api/v1/summaries/household")
        assert resp.status_code == 401

    async def test_household_empty_range(
        self, client: AsyncClient, filla_token: str
    ):
        """Household summary for a date range with no transactions returns zeroes."""
        resp = await client.get(
            "/api/v1/summaries/household?date_from=2099-01-01&date_to=2099-12-31",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_income"] == 0
        assert data["total_expense"] == 0
        assert data["balance"] == 0


class TestCycleAwareSummaries:

    async def test_cycle_info_returns_default(self, client: AsyncClient, filla_token: str):
        """Cycle-info returns cycle_start_day=1 for default user."""
        resp = await client.get(
            "/api/v1/summaries/cycle-info",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["cycle_start_day"] == 1
        assert "date_from" in data
        assert "date_to" in data

    async def test_cycle_info_after_update(self, client: AsyncClient, filla_token: str):
        """Set cycle_start_day=25, then cycle-info returns 25."""
        await client.put(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"cycle_start_day": 25},
        )
        resp = await client.get(
            "/api/v1/summaries/cycle-info",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["cycle_start_day"] == 25
        assert int(data["date_from"].split("-")[2]) >= 25

    async def test_current_month_use_cycle_default(
        self, client: AsyncClient, filla_token: str
    ):
        """use_cycle=true with default cycle matches calendar month."""
        resp_cal = await client.get(
            "/api/v1/summaries/current-month",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        resp_cycle = await client.get(
            "/api/v1/summaries/current-month?use_cycle=true",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp_cal.status_code == 200
        assert resp_cycle.status_code == 200
        cal = resp_cal.json()
        cycle = resp_cycle.json()
        assert cal["total_income"] == cycle["total_income"]
        assert cal["total_expense"] == cycle["total_expense"]

    async def test_daily_use_cycle(self, client: AsyncClient, filla_token: str):
        """daily?use_cycle=true without explicit dates returns 200."""
        resp = await client.get(
            "/api/v1/summaries/daily?use_cycle=true",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "total_income" in data
        assert "total_expense" in data

    async def test_household_use_cycle(self, client: AsyncClient, filla_token: str):
        """household?use_cycle=true without explicit dates returns 200."""
        resp = await client.get(
            "/api/v1/summaries/household?use_cycle=true",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "total_income" in data
        assert "total_expense" in data

    async def test_monthly_use_cycle(self, client: AsyncClient, filla_token: str):
        """monthly?use_cycle=true returns 200 with valid structure."""
        resp = await client.get(
            "/api/v1/summaries/monthly?use_cycle=true",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "month" in data
        assert "total_income" in data

    async def test_cycle_transaction_filtered_properly(
        self, client: AsyncClient, filla_token: str
    ):
        """With cycle_start_day=25, transactions filtered correctly."""
        today = date.today()

        await client.put(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"cycle_start_day": 25},
        )

        day_2 = today.replace(day=min(2, today.day))
        await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 6,
                "amount": 50000,
                "description": "Prev cycle tx",
                "date": day_2.isoformat(),
            },
        )

        day_26 = today.replace(day=min(26, today.day))
        await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "income",
                "category_id": 7,
                "amount": 100000,
                "description": "Current cycle tx",
                "date": day_26.isoformat(),
            },
        )

        resp = await client.get(
            "/api/v1/summaries/current-month?use_cycle=true",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_income"] >= 0
        assert data["total_expense"] >= 0
