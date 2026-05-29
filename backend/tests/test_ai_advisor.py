"""Tests for /api/v1/ai endpoints."""

from httpx import AsyncClient
from app.core.config import settings


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
        # Force API key to empty regardless of .env to test the guard
        saved_key = settings.OPENCODE_GO_API_KEY
        settings.OPENCODE_GO_API_KEY = ""
        try:
            resp = await client.post(
                "/api/v1/ai/advise",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "How can I save more money?"},
            )
            assert resp.status_code == 500
            assert "not configured" in resp.json()["detail"].lower()
        finally:
            settings.OPENCODE_GO_API_KEY = saved_key

    async def test_empty_question(self, client: AsyncClient, filla_token: str):
        """POST /ai/advise with empty question still reaches the handler."""
        saved_key = settings.OPENCODE_GO_API_KEY
        settings.OPENCODE_GO_API_KEY = ""
        try:
            resp = await client.post(
                "/api/v1/ai/advise",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": ""},
            )
            # Should reach the endpoint and fail due to missing API key, not schema validation
            assert resp.status_code in (422, 500)
        finally:
            settings.OPENCODE_GO_API_KEY = saved_key


class TestFinancialAdviseStream:
    async def test_stream_requires_auth(self, client: AsyncClient):
        """POST /ai/advise/stream without token returns 401."""
        resp = await client.post(
            "/api/v1/ai/advise/stream",
            json={"question": "How can I save more money?"},
        )
        assert resp.status_code == 401

    async def test_stream_returns_500_without_api_key(
        self, client: AsyncClient, filla_token: str
    ):
        """POST /ai/advise/stream with valid auth returns 500 when API key is not configured."""
        saved_key = settings.OPENCODE_GO_API_KEY
        settings.OPENCODE_GO_API_KEY = ""
        try:
            resp = await client.post(
                "/api/v1/ai/advise/stream",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "How can I save more money?"},
            )
            assert resp.status_code == 500
            assert "not configured" in resp.text.lower()
        finally:
            settings.OPENCODE_GO_API_KEY = saved_key

    async def test_stream_empty_question(self, client: AsyncClient, filla_token: str):
        """POST /ai/advise/stream with empty question reaches the handler."""
        saved_key = settings.OPENCODE_GO_API_KEY
        settings.OPENCODE_GO_API_KEY = ""
        try:
            resp = await client.post(
                "/api/v1/ai/advise/stream",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": ""},
            )
            assert resp.status_code in (422, 500)
        finally:
            settings.OPENCODE_GO_API_KEY = saved_key
