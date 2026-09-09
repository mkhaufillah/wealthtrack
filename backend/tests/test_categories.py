"""Tests for /api/v1/categories endpoints."""

from httpx import AsyncClient


class TestListCategories:
    async def test_list_all(self, client: AsyncClient, filla_token: str):
        """GET /categories returns all categories."""
        resp = await client.get(
            "/api/v1/categories",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) >= 6
        assert data[0]["name"] is not None
        assert data[0]["type"] in ("expense", "income")
        assert data[0]["copy_key"]
        assert data[0]["name_id"]
        assert data[0]["name_en"]
        assert "keywords" in data[0]
        assert isinstance(data[0]["keywords"], list)
        assert data[0]["icon"].startswith("strokeRounded")

    async def test_filter_expense(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/categories?type=expense",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        for cat in resp.json():
            assert cat["type"] == "expense"

    async def test_filter_income(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/categories?type=income",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        for cat in resp.json():
            assert cat["type"] == "income"

    async def test_requires_auth(self, client: AsyncClient):
        assert (await client.get("/api/v1/categories")).status_code == 401

    async def test_invalid_type(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/categories?type=invalid",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422


class TestCreateCategory:
    async def test_admin_can_create(self, client: AsyncClient, filla_token: str):
        resp = await client.post(
            "/api/v1/categories",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "name": "Kendaraan", "name_en": "Vehicles", "type": "expense",
                "icon": "strokeRoundedCar01",
                "keywords": ["mobil", "motor", "kendaraan"], "sort_order": 20,
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["name"] == "Kendaraan"
        assert data["name_id"] == "Kendaraan"
        assert data["name_en"] == "Vehicles"
        assert data["copy_key"].startswith("cat.n.custom.")
        assert data["type"] == "expense"
        assert data["icon"] == "strokeRoundedCar01"
        assert "mobil" in data["keywords"]

    async def test_invalid_icon_falls_back(self, client: AsyncClient, filla_token: str):
        resp = await client.post(
            "/api/v1/categories", headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Aneh", "type": "expense", "icon": "🚗"},
        )
        assert resp.status_code == 201
        assert resp.json()["icon"] == "strokeRoundedInvoice01"

    async def test_non_admin_cannot_create(self, client: AsyncClient, nahda_token: str):
        resp = await client.post(
            "/api/v1/categories", headers={"Authorization": f"Bearer {nahda_token}"},
            json={"name": "Test", "type": "expense"},
        )
        assert resp.status_code == 403

    async def test_duplicate_name_returns_409(self, client: AsyncClient, filla_token: str):
        resp = await client.post(
            "/api/v1/categories", headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Makanan & Minuman", "type": "expense"},
        )
        assert resp.status_code == 409

    async def test_create_requires_auth(self, client: AsyncClient):
        assert (await client.post("/api/v1/categories", json={"name": "Test", "type": "expense"})).status_code == 401


class TestUpdateCategory:
    async def test_admin_can_update(self, client: AsyncClient, filla_token: str):
        resp = await client.put(
            "/api/v1/categories/8", headers={"Authorization": f"Bearer {filla_token}"},
            json={"icon": "strokeRoundedLaptop", "keywords": ["freelance", "side job"]},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["icon"] == "strokeRoundedLaptop"
        assert "side job" in data["keywords"]

    async def test_non_admin_cannot_update(self, client: AsyncClient, nahda_token: str):
        assert (await client.put(
            "/api/v1/categories/8", headers={"Authorization": f"Bearer {nahda_token}"},
            json={"name": "Hacked"},
        )).status_code == 403

    async def test_update_nonexistent_returns_404(self, client: AsyncClient, filla_token: str):
        assert (await client.put(
            "/api/v1/categories/9999", headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Ghost"},
        )).status_code == 404

    async def test_cannot_edit_default_category(self, client: AsyncClient, filla_token: str):
        assert (await client.put(
            "/api/v1/categories/1", headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Edited"},
        )).status_code == 403

    async def test_duplicate_name_on_update(self, client: AsyncClient, filla_token: str):
        assert (await client.put(
            "/api/v1/categories/8", headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Gaji"},
        )).status_code == 409


class TestDeleteCategory:
    async def test_admin_deletes_unused_custom_category(self, client: AsyncClient, filla_token: str):
        created = await client.post(
            "/api/v1/categories", headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Buat Dihapus", "type": "expense", "icon": "strokeRoundedDelete01"},
        )
        assert created.status_code == 201
        category_id = created.json()["id"]
        deleted = await client.delete(
            f"/api/v1/categories/{category_id}",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert deleted.status_code == 204
        remaining = await client.get("/api/v1/categories", headers={"Authorization": f"Bearer {filla_token}"})
        assert category_id not in [c["id"] for c in remaining.json()]

    async def test_non_admin_cannot_delete(self, client: AsyncClient, nahda_token: str):
        resp = await client.delete("/api/v1/categories/8", headers={"Authorization": f"Bearer {nahda_token}"})
        assert resp.status_code == 403

    async def test_cannot_delete_default_category(self, client: AsyncClient, filla_token: str):
        resp = await client.delete("/api/v1/categories/1", headers={"Authorization": f"Bearer {filla_token}"})
        assert resp.status_code == 403

    async def test_cannot_delete_category_with_transactions(self, client: AsyncClient, filla_token: str):
        resp = await client.delete("/api/v1/categories/1", headers={"Authorization": f"Bearer {filla_token}"})
        assert resp.status_code == 403  # default guard wins before usage check
        # Category 2 is non-default and has seeded transactions.
        resp = await client.delete("/api/v1/categories/2", headers={"Authorization": f"Bearer {filla_token}"})
        assert resp.status_code == 409
        assert "transaksi" in resp.json()["detail"].lower()
