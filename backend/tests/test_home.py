"""GET /api/v1/home — personal all-time dashboard payload with display strings."""

from httpx import AsyncClient


class TestHome:
    async def test_home_requires_auth(self, client: AsyncClient):
        resp = await client.get("/api/v1/home")
        assert resp.status_code in (401, 403)

    async def test_home_amount_display_personal(
        self, client: AsyncClient, filla_token: str, nahda_token: str
    ):
        await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 1234567,
                "description": "Filla home marker",
                "date": "2020-06-01",
            },
        )
        await client.post(
            "/api/v1/transactions",
            headers={"Authorization": f"Bearer {nahda_token}"},
            json={
                "type": "expense",
                "category_id": 1,
                "amount": 7654321,
                "description": "Nahda home marker",
                "date": "2020-06-01",
            },
        )

        filla = await client.get(
            "/api/v1/home",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        nahda = await client.get(
            "/api/v1/home",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        household = await client.get(
            "/api/v1/summaries/household",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert filla.status_code == 200
        assert nahda.status_code == 200
        fh = filla.json()["hero"]
        nh = nahda.json()["hero"]
        assert fh["amount_display"].startswith("Rp") or fh["amount_display"].startswith("-Rp")
        assert fh["income_display"].startswith("Rp")
        assert fh["expense_display"].startswith("Rp")
        assert fh["expense"] >= 1234567
        assert nh["expense"] >= 7654321
        assert fh["expense"] != nh["expense"]
        assert fh["expense"] < household.json()["total_expense"]
        assert "pots" in filla.json()
        assert "savings_display" in filla.json()["pots"]
        assert "debt_summary" in filla.json()
        assert "recent" in filla.json()
