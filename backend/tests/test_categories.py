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
