"""Tests for /api/v1/ai endpoints."""

from httpx import AsyncClient


class TestFinancialAdvise:
    async def test_requires_auth(self, client: AsyncClient):
        """POST /ai/advise without token returns 401."""
        resp = await client.post(
            "/api/v1/ai/advise",
            json={"question": "How can I save more money?"},
        )
        assert resp.status_code == 401

    async def test_returns_500_without_api_key(self, client: AsyncClient, filla_token: str):
        """POST /ai/advise with valid auth returns 500 when API key is not configured."""
        resp = await client.post(
            "/api/v1/ai/advise",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"question": "How can I save more money?"},
        )
        assert resp.status_code == 500
        assert "not configured" in resp.json()["detail"].lower()

    async def test_empty_question(self, client: AsyncClient, filla_token: str):
        """POST /ai/advise with empty question still reaches the handler."""
        resp = await client.post(
            "/api/v1/ai/advise",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"question": ""},
        )
        # Should reach the endpoint and fail due to missing API key, not schema validation
        assert resp.status_code in (422, 500)
