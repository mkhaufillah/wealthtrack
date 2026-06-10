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
            RatePeriod(37, 120, 0.09, "floating")]
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
                "base_interest_rate": 0.075},
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
                "graduated_increment": 0.005},
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
                    "base_interest_rate": 0.08},
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
                "base_interest_rate": 0.07},
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
                "base_interest_rate": 0.08},
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
                "base_interest_rate": 0.05},
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
                "base_interest_rate": 0.05},
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
                "base_interest_rate": 0.06},
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
                "base_interest_rate": 0.08},
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
                "base_interest_rate": 0.075},
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
                "base_interest_rate": 0.07},
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
                "base_interest_rate": 0.08},
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
                "base_interest_rate": 0.06},
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
                "base_interest_rate": 0.06},
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
                "base_interest_rate": 0.06},
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
                "base_interest_rate": 0.05},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}/schedule",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 403


# ──────────────────────────────────────────────
# Extra Payment — Engine Tests
# ──────────────────────────────────────────────


class TestExtraPaymentEngine:
    """Pure-python tests for extra payment engine."""

    def _make_schedule(self):
        """Create a standard 120-month schedule for testing."""
        return calculate_kpr(
            total_loan=500000000,
            tenor_months=120,
            interest_type="fixed",
            base_interest_rate=0.0899,
        )

    def test_extra_payment_tenor_reduction(self):
        """Opsi B — extra payment reduces tenor, keeps same installment."""
        schedule = self._make_schedule()
        from app.services.kpr_engine import apply_extra_payment

        result = apply_extra_payment(
            schedule=schedule,
            extra_amount=50000000,
            apply_month=24,
            reduction_type="tenor",
            start_month=1,
            start_year=2026,
        )

        assert result.old_installment == result.new_installment  # Same payment
        assert result.new_remaining_months < result.old_remaining_months  # Shorter tenor
        assert result.total_interest_saved > 0  # Saved some interest
        assert result.new_end_date < result.original_end_date  # Ends sooner
        assert len(result.schedule) < len(schedule)  # Total schedule shorter

    def test_extra_payment_installment_reduction(self):
        """Opsi A — extra payment reduces installment, keeps same tenor."""
        schedule = self._make_schedule()
        from app.services.kpr_engine import apply_extra_payment

        result = apply_extra_payment(
            schedule=schedule,
            extra_amount=50000000,
            apply_month=24,
            reduction_type="installment",
            start_month=1,
            start_year=2026,
        )

        assert result.new_installment < result.old_installment  # Lower payment
        assert result.new_remaining_months == result.old_remaining_months  # Same tenor
        assert result.total_interest_saved > 0
        # Combined schedule = months before + remaining months = len original
        assert len(result.schedule) == len(schedule)

    def test_extra_payment_basic_tenor(self):
        """Extra payment reduces remaining months."""
        schedule = self._make_schedule()
        from app.services.kpr_engine import apply_extra_payment

        result = apply_extra_payment(
            schedule=schedule,
            extra_amount=100000000,
            apply_month=12,
            reduction_type="tenor",
        )

        assert result.new_remaining_months < result.old_remaining_months
        assert result.total_interest_saved > 0

    def test_extra_payment_first_month(self):
        """Extra payment at month 1 (before first payment)."""
        schedule = self._make_schedule()
        from app.services.kpr_engine import apply_extra_payment

        result = apply_extra_payment(
            schedule=schedule,
            extra_amount=50000000,
            apply_month=1,
            reduction_type="installment",
        )

        assert result.new_installment < result.old_installment
        assert result.new_remaining_months == result.old_remaining_months

    def test_extra_payment_full_payoff(self):
        """Extra payment large enough to almost pay off the loan."""
        schedule = self._make_schedule()
        from app.services.kpr_engine import apply_extra_payment

        # Pay off remaining balance at month 60
        remaining_at_60 = schedule[59].remaining_balance  # before month 60

        result = apply_extra_payment(
            schedule=schedule,
            extra_amount=remaining_at_60,
            apply_month=60,
            reduction_type="tenor",
        )

        # Should finish in 1 more month or less
        assert result.new_remaining_months <= 2

    def test_preview_returns_both_options(self):
        """Preview should return comparison of both options."""
        schedule = self._make_schedule()
        from app.services.kpr_engine import preview_extra_payment

        preview = preview_extra_payment(
            schedule=schedule,
            extra_amount=50000000,
            apply_month=24,
            start_month=1,
            start_year=2026,
        )

        assert preview.option_installment is not None
        assert preview.option_tenor is not None
        assert preview.option_installment.new_installment < preview.option_tenor.new_installment
        assert preview.option_tenor.new_remaining_months < preview.option_installment.new_remaining_months

    def test_extra_payment_multiple_applied(self):
        """Multiple extra payments stack correctly."""
        schedule = self._make_schedule()
        from app.services.kpr_engine import apply_extra_payment

        # First extra at month 12
        r1 = apply_extra_payment(
            schedule=schedule, extra_amount=25000000,
            apply_month=12, reduction_type="installment",
        )
        # Second extra at month 36 (on the modified schedule)
        r2 = apply_extra_payment(
            schedule=r1.schedule, extra_amount=25000000,
            apply_month=36, reduction_type="installment",
        )

        assert r2.new_installment < r1.new_installment  # Kedua extra turunkan cicilan
        assert r2.total_interest_saved > 0
        # r1 saves more total interest because it's applied earlier (month 12 vs 36)


# ──────────────────────────────────────────────
# Extra Payment — API Tests
# ──────────────────────────────────────────────


@pytest.mark.asyncio
class TestExtraPaymentAPI:
    """API tests for extra payment endpoints."""

    async def _create_sim(self, client, token) -> int:
        resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Extra Payment Test",
                "property_price": 700000000,
                "down_payment": 200000000,
                "tenor_months": 120,
                "interest_type": "fixed",
                "base_interest_rate": 0.0899,
                "start_month": 1,
                "start_year": 2026},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 201
        return resp.json()["id"]

    async def test_preview_no_schedule(self, client, auth_headers, filla_token):
        """Preview without schedule should fail."""
        resp = await client.post(
            "/api/v1/kpr/simulations/999/extra-payments/preview",
            json={"amount": 50000000, "apply_month": 24},
            headers=auth_headers,
        )
        assert resp.status_code == 404

    async def test_preview_returns_comparison(
        self, client, auth_headers, filla_token
    ):
        """Preview returns both reduction options."""
        sim_id = await self._create_sim(client, filla_token)

        resp = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments/preview",
            json={"amount": 50000000, "apply_month": 24},
            headers=auth_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "option_installment" in data
        assert "option_tenor" in data
        assert "comparison" in data

        opt_a = data["option_installment"]
        opt_b = data["option_tenor"]
        assert opt_a["new_installment"] > 0
        assert opt_b["new_tenor"] > 0
        assert opt_a["new_installment"] < opt_b["new_installment"]
        assert opt_b["new_tenor"] < opt_a["new_tenor"]

    async def test_commit_tenor_reduction(
        self, client, auth_headers, filla_token
    ):
        """Commit extra payment with tenor reduction."""
        sim_id = await self._create_sim(client, filla_token)

        resp = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={
                "amount": 50000000,
                "apply_month": 24,
                "reduction_type": "tenor"},
            headers=auth_headers,
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["id"] > 0
        assert data["reduction_type"] == "tenor"
        assert data["new_remaining_months"] < data["old_remaining_months"]
        assert data["new_installment"] == data["old_installment"]

    async def test_commit_installment_reduction(
        self, client, auth_headers, filla_token
    ):
        """Commit extra payment with installment reduction."""
        sim_id = await self._create_sim(client, filla_token)

        resp = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={
                "amount": 50000000,
                "apply_month": 12,
                "reduction_type": "installment"},
            headers=auth_headers,
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["reduction_type"] == "installment"
        assert data["new_installment"] < data["old_installment"]
        assert data["new_remaining_months"] == data["old_remaining_months"]

    async def test_list_extra_payments(
        self, client, auth_headers, filla_token
    ):
        """List extra payments for a simulation."""
        sim_id = await self._create_sim(client, filla_token)

        # Create two extra payments
        await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 25000000, "apply_month": 12, "reduction_type": "installment"},
            headers=auth_headers,
        )
        await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 25000000, "apply_month": 36, "reduction_type": "tenor"},
            headers=auth_headers,
        )

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            headers=auth_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2

    async def test_delete_extra_payment(
        self, client, auth_headers, filla_token
    ):
        """Delete extra payment and verify it's gone."""
        sim_id = await self._create_sim(client, filla_token)

        # Create & capture ID
        create_resp = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 50000000, "apply_month": 24, "reduction_type": "tenor"},
            headers=auth_headers,
        )
        ep_id = create_resp.json()["id"]

        # Delete
        resp = await client.delete(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments/{ep_id}",
            headers=auth_headers,
        )
        assert resp.status_code == 204

        # Verify gone
        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            headers=auth_headers,
        )
        assert len(resp.json()) == 0

    async def test_delete_restores_schedule(
        self, client, auth_headers, filla_token
    ):
        """After deleting extra payment, schedule should be original length."""
        sim_id = await self._create_sim(client, filla_token)

        # Get original schedule length
        sim_resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers=auth_headers,
        )
        orig_schedule_count = len(sim_resp.json()["schedule"])

        # Add extra payment (tenor reduction shrinks schedule)
        ep_resp = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 100000000, "apply_month": 12, "reduction_type": "tenor"},
            headers=auth_headers,
        )
        ep_id = ep_resp.json()["id"]

        # Verify schedule got shorter
        sim_after = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers=auth_headers,
        )
        assert len(sim_after.json()["schedule"]) < orig_schedule_count

        # Delete extra payment
        await client.delete(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments/{ep_id}",
            headers=auth_headers,
        )

        # Verify schedule restored to original length
        sim_restored = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers=auth_headers,
        )
        assert len(sim_restored.json()["schedule"]) == orig_schedule_count

    async def test_forbidden_other_user_extra(
        self, client, filla_token, nahda_token
    ):
        """Another user cannot access extra payments of other simulation."""
        sim_id = await self._create_sim(client, filla_token)

        resp = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments/preview",
            json={"amount": 50000000, "apply_month": 24},
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 403


    async def test_apply_month_after_tenor_months(
        self, client, auth_headers, filla_token
    ):
        """Extra payment with apply_month > tenor_months returns 400."""
        sim_id = await self._create_sim(client, filla_token)

        resp = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 50000000, "apply_month": 200,
                  "reduction_type": "tenor"},
            headers=auth_headers,
        )
        assert resp.status_code == 400
        assert "apply_month" in resp.text.lower()

    async def test_apply_month_backwards(
        self, client, auth_headers, filla_token
    ):
        """Extra payment with apply_month before last existing one returns 400."""
        sim_id = await self._create_sim(client, filla_token)

        # Commit first extra at month 24
        resp1 = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 25000000, "apply_month": 24,
                  "reduction_type": "tenor"},
            headers=auth_headers,
        )
        assert resp1.status_code == 201

        # Try to add second extra at month 12 (before month 24) — should fail
        resp2 = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 25000000, "apply_month": 12,
                  "reduction_type": "tenor"},
            headers=auth_headers,
        )
        assert resp2.status_code == 400
        assert "apply_month" in resp2.text.lower()


# ──────────────────────────────────────────────
# Household Debt — API Tests
# ──────────────────────────────────────────────


@pytest.mark.asyncio
class TestKPRHousehold:
    """Household-scoped KPR tests."""

    async def test_create_with_household_id(
        self, client, auth_headers, filla_token
    ):
        """Can create a simulation with household_id."""
        resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Household KPR",
                "property_price": 500000000,
                "tenor_months": 120,
                "interest_type": "fixed",
                "base_interest_rate": 0.0899,
                "household_id": 1},
            headers=auth_headers,
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data.get("household_id") == 1

    async def test_household_member_can_access(
        self, client, filla_token, nahda_token
    ):
        """Nahda can access Filla's simulation if shared via household."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Shared KPR",
                "property_price": 300000000,
                "tenor_months": 60,
                "interest_type": "fixed",
                "base_interest_rate": 0.075,
                "household_id": 1},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 200

    async def test_non_household_member_blocked(
        self, client, filla_token, empty_token
    ):
        """Non-household member cannot access shared simulation."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "Private Shared",
                "property_price": 200000000,
                "tenor_months": 36,
                "interest_type": "fixed",
                "base_interest_rate": 0.06,
                "household_id": 1},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers={"Authorization": f"Bearer {empty_token}"},
        )
        assert resp.status_code == 403

    async def test_private_simulation_not_visible_to_others(
        self, client, filla_token, nahda_token
    ):
        """Personal sim (no household_id) stays private."""
        create_resp = await client.post(
            "/api/v1/kpr/simulations",
            json={
                "name": "My Private KPR",
                "property_price": 400000000,
                "tenor_months": 120,
                "interest_type": "fixed",
                "base_interest_rate": 0.08},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        sim_id = create_resp.json()["id"]

        resp = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 403
