"""Tests for the stateless KPR calculate endpoint."""
import httpx


async def _calc(client: httpx.AsyncClient, token: str, payload: dict) -> httpx.Response:
    return await client.post(
        "/api/v1/kpr/calculate",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
    )


async def test_calculate_requires_auth(client: httpx.AsyncClient):
    resp = await client.post("/api/v1/kpr/calculate", json={})
    assert resp.status_code == 401


async def test_calculate_fixed_known_case(client: httpx.AsyncClient, filla_token: str):
    """360-month, 7.5% fixed on Rp 360.000.000 loan -> a known amortization case."""
    payload = {
        "property_price": 500_000_000,
        "down_payment": 140_000_000,
        "tenor_months": 360,
        "interest_type": "fixed",
        "base_interest_rate": 0.075,
    }
    resp = await _calc(client, filla_token, payload)
    assert resp.status_code == 200
    data = resp.json()
    assert data["total_loan"] == 360_000_000
    assert data["total_months"] == 360
    # ~ Rp 2.517.172 at 7.5% / 360 on Rp 360.000.000. Allow a tight band.
    assert data["monthly_payment"] > 2_500_000
    assert data["monthly_payment"] < 2_530_000
    # Total payment is the sum of all monthly payments; last month is the
    # remainder after interest rounding, so allow a small band vs monthly*360.
    assert abs(data["total_payment"] - data["monthly_payment"] * 360) < 360 * 10
    assert data["total_interest"] > 100_000_000


async def test_calculate_total_loan_zero(client: httpx.AsyncClient, filla_token: str):
    resp = await _calc(client, filla_token, {
        "property_price": 100_000_000,
        "down_payment": 100_000_000,
        "tenor_months": 12,
        "interest_type": "fixed",
        "base_interest_rate": 0.075,
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["total_loan"] == 0
    assert data["monthly_payment"] == 0
    assert data["total_payment"] == 0


async def test_calculate_validates_tenor_range(client: httpx.AsyncClient, filla_token: str):
    resp = await _calc(client, filla_token, {
        "property_price": 500_000_000,
        "down_payment": 100_000_000,
        "tenor_months": 5,  # below min 12
        "interest_type": "fixed",
        "base_interest_rate": 0.075,
    })
    assert resp.status_code == 422


async def test_calculate_graduated(client: httpx.AsyncClient, filla_token: str):
    resp = await _calc(client, filla_token, {
        "property_price": 500_000_000,
        "down_payment": 200_000_000,
        "tenor_months": 120,
        "interest_type": "graduated",
        "base_interest_rate": 0.075,
        "graduated_increment": 0.005,
        "graduated_every_months": 12,
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["total_months"] == 120
    # First installment uses base rate, should be positive
    assert data["monthly_payment"] > 0
    assert data["total_interest"] > 0


async def test_calculate_mix(client: httpx.AsyncClient, filla_token: str):
    resp = await _calc(client, filla_token, {
        "property_price": 500_000_000,
        "down_payment": 200_000_000,
        "tenor_months": 120,
        "interest_type": "mix",
        "base_interest_rate": 0.075,
        "rate_periods": [
            {"period_start": 1, "period_end": 60, "interest_rate": 0.08, "rate_type": "fixed"},
            {"period_start": 61, "period_end": 120, "interest_rate": 0.09, "rate_type": "floating"},
        ],
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["total_months"] == 120
    assert data["monthly_payment"] > 0