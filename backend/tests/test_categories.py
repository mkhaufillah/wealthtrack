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
        assert len(data) >= 6  # at least seed categories
        assert data[0]["name"] is not None
        assert data[0]["type"] in ("expense", "income")
        assert "name_en" in data[0]
        assert "keywords" in data[0]
        assert isinstance(data[0]["keywords"], list)

    async def test_filter_expense(self, client: AsyncClient, filla_token: str):
        """GET /categories?type=expense returns only expense categories."""
        resp = await client.get(
            "/api/v1/categories?type=expense",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        for cat in resp.json():
            assert cat["type"] == "expense"

    async def test_filter_income(self, client: AsyncClient, filla_token: str):
        """GET /categories?type=income returns only income categories."""
        resp = await client.get(
            "/api/v1/categories?type=income",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        for cat in resp.json():
            assert cat["type"] == "income"

    async def test_requires_auth(self, client: AsyncClient):
        """Without auth token, returns 401."""
        resp = await client.get("/api/v1/categories")
        assert resp.status_code == 401

    async def test_invalid_type(self, client: AsyncClient, filla_token: str):
        """Invalid type parameter returns 422."""
        resp = await client.get(
            "/api/v1/categories?type=invalid",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422


class TestCreateCategory:
    async def test_admin_can_create(self, client: AsyncClient, filla_token: str):
        """Admin can create a new category."""
        resp = await client.post(
            "/api/v1/categories",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "name": "Kendaraan",
                "name_en": "Vehicle",
                "type": "expense",
                "icon": "🚗",
                "keywords": ["mobil", "motor", "kendaraan"],
                "sort_order": 20,
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["name"] == "Kendaraan"
        assert data["name_en"] == "Vehicle"
        assert data["type"] == "expense"
        assert "mobil" in data["keywords"]

    async def test_non_admin_cannot_create(self, client: AsyncClient, nahda_token: str):
        """Non-admin gets 403."""
        resp = await client.post(
            "/api/v1/categories",
            headers={"Authorization": f"Bearer {nahda_token}"},
            json={"name": "Test", "type": "expense"},
        )
        assert resp.status_code == 403

    async def test_duplicate_name_returns_409(self, client: AsyncClient, filla_token: str):
        """Duplicate category name+type returns 409."""
        resp = await client.post(
            "/api/v1/categories",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Makanan & Minuman", "type": "expense"},
        )
        assert resp.status_code == 409

    async def test_create_requires_auth(self, client: AsyncClient):
        """Without auth returns 401."""
        resp = await client.post(
            "/api/v1/categories",
            json={"name": "Test", "type": "expense"},
        )
        assert resp.status_code == 401


class TestUpdateCategory:
    async def test_admin_can_update(self, client: AsyncClient, filla_token: str):
        """Admin can update a category."""
        resp = await client.put(
            "/api/v1/categories/8",  # Freelance (not default)
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"name_en": "Freelance Work", "keywords": ["freelance", "side job"]},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["name_en"] == "Freelance Work"
        assert "side job" in data["keywords"]

    async def test_non_admin_cannot_update(self, client: AsyncClient, nahda_token: str):
        """Non-admin gets 403."""
        resp = await client.put(
            "/api/v1/categories/8",
            headers={"Authorization": f"Bearer {nahda_token}"},
            json={"name_en": "Hacked"},
        )
        assert resp.status_code == 403

    async def test_update_nonexistent_returns_404(self, client: AsyncClient, filla_token: str):
        """Updating non-existent category returns 404."""
        resp = await client.put(
            "/api/v1/categories/9999",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Ghost"},
        )
        assert resp.status_code == 404

    async def test_cannot_edit_default_category(self, client: AsyncClient, filla_token: str):
        """Default categories (is_default=1) cannot be edited."""
        resp = await client.put(
            "/api/v1/categories/1",  # Makanan & Minuman (is_default=1)
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"name_en": "Edited"},
        )
        assert resp.status_code == 403

    async def test_duplicate_name_on_update(self, client: AsyncClient, filla_token: str):
        """Renaming to an existing name returns 409."""
        resp = await client.put(
            "/api/v1/categories/8",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Gaji"},
        )
        assert resp.status_code == 409

