"""Tests for KPR (Mortgage) calculation engine and API endpoints."""

import pytest
from httpx import AsyncClient

from app.database import CursorWrapper
from app.services.kpr_engine import calculate_kpr, simulate_summary, RatePeriod


# ──────────────────────────────────────────────
# Engine tests (pure Python, no DB needed)
# ──────────────────────────────────────────────


class TestKprEngine:
    """Pure-python tests for KPR calculation engine."""

    def test_fixed_rate_calculation(self):
        """500jt loan, 15 years, 7.5% fixed."""
        result = calculate_kpr(
            total_loan=500000000,
            tenor_months=180,
            interest_type="fixed",
            base_interest_rate=0.075,
        )
        assert len(result) == 180
        summary = simulate_summary(result)
        assert summary["monthly_payment"] > 0
        assert summary["total_interest"] > 0
        # Last month remaining should be 0 or very small
        assert result[-1].remaining_balance <= 1000

    def test_graduated_rate_calculation(self):
        """Rate increases by 0.5% every 12 months."""
        result = calculate_kpr(
            total_loan=500000000,
            tenor_months=120,
            interest_type="graduated",
            base_interest_rate=0.07,
            graduated_increment=0.005,
        )
        assert len(result) == 120
        assert result[0].interest_rate < result[-1].interest_rate

    def test_mix_rate_calculation(self):
        """3 years fixed 6%, then floating 9%."""
        periods = [
            RatePeriod(1, 36, 0.06, "fixed"),
            RatePeriod(37, 120, 0.09, "floating"),
        ]
        result = calculate_kpr(
            total_loan=500000000,
            tenor_months=120,
            interest_type="mix",
            rate_periods=periods,
        )
        assert len(result) == 120
        assert abs(result[0].interest_rate - 0.06) < 0.001
        assert abs(result[35].interest_rate - 0.06) < 0.001  # month 36 still fixed
        assert abs(result[36].interest_rate - 0.09) < 0.001  # month 37 floating

    def test_amortization_sums(self):
        """Principal payments should sum to total loan."""
        result = calculate_kpr(
            total_loan=100000000,
            tenor_months=60,
            interest_type="fixed",
            base_interest_rate=0.06,
        )
        total_principal = sum(m.principal for m in result)
        assert abs(total_principal - 100000000) < 1000  # rounding tolerance

    def test_zero_interest(self):
        """Zero interest rate — payment = principal / months."""
        result = calculate_kpr(
            total_loan=12000000,
            tenor_months=12,
            interest_type="fixed",
            base_interest_rate=0.0,
        )
        assert len(result) == 12
        assert all(m.interest == 0 for m in result)
        assert all(m.payment == 1000000 for m in result)  # 12jt / 12 bulan

    def test_floating_rate_has_no_change(self):
        """Floating rate with no explicit periods defaults to base rate throughout."""
        result = calculate_kpr(
            total_loan=300000000,
            tenor_months=60,
            interest_type="floating",
            base_interest_rate=0.08,
        )
        assert len(result) == 60
        assert all(abs(m.interest_rate - 0.08) < 0.001 for m in result)

    def test_empty_schedule_summary(self):
        """simulate_summary returns zeros for empty schedule."""
        summary = simulate_summary([])
        assert summary["total_payment"] == 0
        assert summary["total_interest"] == 0
        assert summary["monthly_payment"] == 0
        assert summary["total_months"] == 0


# ──────────────────────────────────────────────
# API tests (need DB fixtures)
# ──────────────────────────────────────────────


class TestKprApiCreate:
    """POST /api/v1/kpr/simulations — Create KPR simulation."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.post("/api/v1/kpr/simulations")
        assert resp.status_code == 401

    async def test_create_fixed_rate(self, client: AsyncClient, filla_token: str):
        """Create simulation with fixed rate, verify schedule and summary."""
        response = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Test KPR",
                "property_price": 500000000,
                "down_payment": 50000000,
                "tenor_months": 120,
                "interest_type": "fixed",
                "base_interest_rate": 0.075,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert response.status_code == 201
        data = response.json()
        assert data["total_loan"] == 450000000  # 500jt - 50jt
        assert len(data["schedule"]) == 120
        assert "summary" in data
        assert data["name"] == "Test KPR"

    async def test_create_graduated_rate(self, client: AsyncClient, filla_token: str):
        """Create simulation with graduated rate."""
        response = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Graduated KPR",
                "property_price": 600000000,
                "down_payment": 100000000,
                "tenor_months": 180,
                "interest_type": "graduated",
                "base_interest_rate": 0.07,
                "graduated_increment": 0.005,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert response.status_code == 201
        data = response.json()
        assert data["total_loan"] == 500000000
        assert len(data["schedule"]) == 180
        assert data["schedule"][0]["interest_rate"] < data["schedule"][-1]["interest_rate"]


class TestKprApiList:
    """GET /api/v1/kpr/simulations — List KPR simulations."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.get("/api/v1/kpr/simulations")
        assert resp.status_code == 401

    async def test_list_empty(self, client: AsyncClient, filla_token: str):
        """Returns empty list when no simulations exist."""
        resp = await client.get(
            "/api/v1/kpr/simulations",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        assert isinstance(resp.json(), list)
        assert len(resp.json()) == 0

    async def test_list_returns_created(self, client: AsyncClient, filla_token: str):
        """Create two simulations, verify both appear in list."""
        for i in range(2):
            await client.post(
                "/api/v1/kpr/simulations",
                json={
                    "name": f"KPR {i}",
                    "property_price": 300000000,
                    "tenor_months": 60,
                    "interest_type": "fixed",
                    "base_interest_rate": 0.08,
                },
                headers={"Authorization": f"Bearer {filla_token}"},
            )

        resp = await client.get(
            "/api/v1/kpr/simulations",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2
        # List should not include schedule/summary (metadata only)
        assert "schedule" not in data[0]
        assert "summary" not in data[0]

    async def test_list_scoped_to_user(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        """Nahda's simulations are not visible to filla."""
        # Nahda creates one
        await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Nahda KPR",
                "property_price": 200000000,
                "tenor_months": 60,
                "interest_type": "fixed",
                "base_interest_rate": 0.07,
            },
            headers={"Authorization": f"Bearer {nahda_token}"},
        )

        # Filla sees zero
        resp = await client.get(
            "/api/v1/kpr/simulations",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        assert len(resp.json()) == 0


class TestKprApiDetail:
    """GET /api/v1/kpr/simulations/{id} — Get single simulation detail."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.get("/api/v1/kpr/simulations/1")
        assert resp.status_code == 401

    async def test_not_found(self, client: AsyncClient, filla_token: str):
        """Returns 404 for non-existent id."""
        resp = await client.get(
            "/api/v1/kpr/simulations/99999",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 404

    async def test_get_detail(self, client: AsyncClient, filla_token: str):
        """Get full detail with schedule and summary."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Detail Test",
                "property_price": 300000000,
                "tenor_months": 60,
                "interest_type": "fixed",
                "base_interest_rate": 0.08,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        response = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["name"] == "Detail Test"
        assert len(data["schedule"]) == 60
        assert "summary" in data
        assert data["summary"]["total_months"] == 60

    async def test_forbidden_other_user(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        """Other user's simulation returns 403."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Filla Secret",
                "property_price": 100000000,
                "tenor_months": 12,
                "interest_type": "fixed",
                "base_interest_rate": 0.05,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 403


class TestKprApiDelete:
    """DELETE /api/v1/kpr/simulations/{id} — Delete KPR simulation."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.delete("/api/v1/kpr/simulations/1")
        assert resp.status_code == 401

    async def test_delete_simulation(self, client: AsyncClient, filla_token: str):
        """Delete simulation and verify 404 on re-fetch."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Delete Test",
                "property_price": 100000000,
                "tenor_months": 12,
                "interest_type": "fixed",
                "base_interest_rate": 0.05,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        delete_resp = await client.delete(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert delete_resp.status_code == 204

        get_resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert get_resp.status_code == 404

    async def test_delete_not_found(self, client: AsyncClient, filla_token: str):
        """Deleting non-existent simulation returns 404."""
        resp = await client.delete(
            "/api/v1/kpr/simulations/99999",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 404

    async def test_delete_forbidden_other_user(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        """Cannot delete another user's simulation."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Filla's KPR",
                "property_price": 200000000,
                "tenor_months": 24,
                "interest_type": "fixed",
                "base_interest_rate": 0.06,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.delete(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 403


class TestKprApiUpdate:
    """PUT /api/v1/kpr/simulations/{id} — Update KPR simulation metadata."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.put("/api/v1/kpr/simulations/1")
        assert resp.status_code == 401

    async def test_update_name(self, client: AsyncClient, filla_token: str):
        """Update simulation name."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Old Name",
                "property_price": 300000000,
                "tenor_months": 60,
                "interest_type": "fixed",
                "base_interest_rate": 0.08,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.put(
            f"/api/v1/kpr/simulations/{sim_id}",
            json={"name": "New Name"},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["name"] == "New Name"

    async def test_update_property_price(
        self, client: AsyncClient, filla_token: str
    ):
        """Update property_price, verify total_loan is recalculated."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Price Test",
                "property_price": 500000000,
                "down_payment": 50000000,
                "tenor_months": 120,
                "interest_type": "fixed",
                "base_interest_rate": 0.075,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]
        assert create_resp.json()["total_loan"] == 450000000

        resp = await client.put(
            f"/api/v1/kpr/simulations/{sim_id}",
            json={"property_price": 600000000},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        # total_loan = 600000000 - 50000000 = 550000000
        assert data["total_loan"] == 550000000

    async def test_update_no_fields(self, client: AsyncClient, filla_token: str):
        """Sending empty body returns 400."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "No Fields",
                "property_price": 200000000,
                "tenor_months": 60,
                "interest_type": "fixed",
                "base_interest_rate": 0.07,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.put(
            f"/api/v1/kpr/simulations/{sim_id}",
            json={},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 400

    async def test_not_found(self, client: AsyncClient, filla_token: str):
        """Updating a non-existent simulation returns 404."""
        resp = await client.put(
            "/api/v1/kpr/simulations/99999",
            json={"name": "Ghost"},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 404

    async def test_forbidden_other_user(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        """Cannot update another user's simulation."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Filla's Sim",
                "property_price": 300000000,
                "tenor_months": 60,
                "interest_type": "fixed",
                "base_interest_rate": 0.08,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.put(
            f"/api/v1/kpr/simulations/{sim_id}",
            json={"name": "Hacked"},
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 403


class TestKprApiSchedule:
    """GET /api/v1/kpr/simulations/{id}/schedule — Get schedule items."""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.get("/api/v1/kpr/simulations/1/schedule")
        assert resp.status_code == 401

    async def test_full_schedule(self, client: AsyncClient, filla_token: str):
        """Get full amortization schedule."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Schedule Test",
                "property_price": 300000000,
                "tenor_months": 12,
                "interest_type": "fixed",
                "base_interest_rate": 0.06,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}/schedule",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert len(data) == 12
        assert "month_number" in data[0]
        assert "payment" in data[0]
        assert "principal" in data[0]
        assert "interest" in data[0]
        assert "remaining_balance" in data[0]

    async def test_single_month_filter(
        self, client: AsyncClient, filla_token: str
    ):
        """Filter schedule to a single month."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Month Filter",
                "property_price": 300000000,
                "tenor_months": 12,
                "interest_type": "fixed",
                "base_interest_rate": 0.06,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}/schedule",
            params={"month": 1},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, dict)  # single object, not list
        assert data["month_number"] == 1

    async def test_month_not_found(
        self, client: AsyncClient, filla_token: str
    ):
        """Requesting a month beyond tenor returns 404."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Out of Range",
                "property_price": 300000000,
                "tenor_months": 12,
                "interest_type": "fixed",
                "base_interest_rate": 0.06,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}/schedule",
            params={"month": 99},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 404

    async def test_forbidden_other_user(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        """Cannot access another user's schedule."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Filla Private",
                "property_price": 100000000,
                "tenor_months": 12,
                "interest_type": "fixed",
                "base_interest_rate": 0.05,
            },
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}/schedule",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 403
