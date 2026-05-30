"""Tests for /api/v1/ai endpoints."""

import json

import httpx
import pytest
from httpx import AsyncClient
from app.core.config import settings


# ──────────────────────────────────────────────
# Helpers for mocking the AI API
# ──────────────────────────────────────────────

class MockAIResponse:
    """Stand-in for httpx.Response returned by /advise (non-streaming)."""

    def __init__(self, status_code=200, content="Test answer"):
        self.status_code = status_code
        self._content = content

    def json(self):
        return {"choices": [{"message": {"content": self._content}}]}


class MockAIStreamResponse:
    """Simulates the streaming API response."""

    def __init__(self, status_code=200, tokens=None):
        self.status_code = status_code
        self._tokens = tokens or ["Hello", " ", "world"]
        self._lines = []
        for t in self._tokens:
            self._lines.append(f"data: {json.dumps({'choices': [{'delta': {'content': t}}]})}\n\n")
        self._lines.append("data: [DONE]\n\n")

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass

    async def aiter_lines(self):
        for line in self._lines:
            yield line

    async def aread(self):
        return b""


class MockAsyncClient:
    """Replaces httpx.AsyncClient for AI advisor tests."""

    def __init__(self, *args, **kwargs):
        self.stream_handler = None
        self.post_handler = None

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass

    async def post(self, *args, **kwargs):
        if self.post_handler:
            return await self.post_handler(*args, **kwargs)
        return MockAIResponse()

    def stream(self, method, url, **kwargs):
        class StreamContext:
            def __init__(self, handler):
                self.handler = handler

            async def __aenter__(self):
                if self.handler:
                    return await self.handler()
                return MockAIStreamResponse()

            async def __aexit__(self, *args):
                pass

        return StreamContext(self.stream_handler)


def _install_ai_mock(monkeypatch, post_result=None, stream_result=None, stream_raise=None):
    """Install MockAsyncClient as httpx.AsyncClient in app.routers.ai_advisor."""
    import app.routers.ai_advisor as ai_module

    class InstallableMockClient(MockAsyncClient):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            if post_result is not None:
                async def _post_handler(*a, **kw):
                    return post_result
                self.post_handler = _post_handler
            if stream_result is not None:

                async def _stream_handler():
                    if stream_raise:
                        raise stream_raise
                    return stream_result

                self.stream_handler = _stream_handler

    monkeypatch.setattr(ai_module.httpx, "AsyncClient", InstallableMockClient)


def _setup_api_key():
    """Ensure API key is set, return saved value for restore."""
    saved = settings.OPENCODE_GO_API_KEY
    if not saved:
        settings.OPENCODE_GO_API_KEY = "test-api-key"
    return saved


# ──────────────────────────────────────────────
# Tests
# ──────────────────────────────────────────────

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
            assert resp.status_code in (422, 500)
        finally:
            settings.OPENCODE_GO_API_KEY = saved_key

    async def test_successful_advise(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """POST /ai/advise returns answer from the model."""
        saved = _setup_api_key()
        try:
            _install_ai_mock(
                monkeypatch,
                post_result=MockAIResponse(
                    status_code=200,
                    content="You should save 20% of your income each month.",
                ),
            )

            resp = await client.post(
                "/api/v1/ai/advise",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "How can I save more money?"},
            )
            assert resp.status_code == 200
            data = resp.json()
            assert "answer" in data
            assert "model_used" in data
            assert "save 20%" in data["answer"]
            assert data["model_used"] == "flash"
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_advise_with_history(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """POST /ai/advise with chat history passes it as context."""
        saved = _setup_api_key()
        try:
            _install_ai_mock(
                monkeypatch,
                post_result=MockAIResponse(status_code=200, content="Based on your history..."),
            )

            resp = await client.post(
                "/api/v1/ai/advise",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={
                    "question": "What about my budget?",
                    "history": [
                        {"role": "user", "content": "How much did I spend last month?"},
                        {"role": "assistant", "content": "You spent Rp2,000,000."},
                    ],
                },
            )
            assert resp.status_code == 200
            data = resp.json()
            assert "answer" in data
            assert data["model_used"] == "flash"
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_model_flash_selection(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """flash model is selected by default."""
        saved = _setup_api_key()
        try:
            _install_ai_mock(
                monkeypatch,
                post_result=MockAIResponse(status_code=200, content="Flash answer"),
            )

            resp = await client.post(
                "/api/v1/ai/advise",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={
                    "question": "How am I doing?",
                    "model": "flash",
                },
            )
            assert resp.status_code == 200
            data = resp.json()
            assert data["model_used"] == "flash"
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_opus_requires_admin_role(
        self, client: AsyncClient, nahda_token: str, monkeypatch
    ):
        """Non-admin user gets 403 when requesting opus model."""
        saved = _setup_api_key()
        try:
            resp = await client.post(
                "/api/v1/ai/advise",
                headers={"Authorization": f"Bearer {nahda_token}"},
                json={
                    "question": "How am I doing?",
                    "model": "opus",
                },
            )
            assert resp.status_code == 403
            assert "Advanced model" in resp.json()["detail"]
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_opus_allowed_for_admin(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """Admin user can use opus model (would fail at API call without mock, but 403 not raised)."""
        saved = _setup_api_key()
        try:
            _install_ai_mock(
                monkeypatch,
                post_result=MockAIResponse(status_code=200, content="Opus answer"),
            )

            resp = await client.post(
                "/api/v1/ai/advise",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={
                    "question": "How am I doing?",
                    "model": "opus",
                },
            )
            # Should not be 403 — admin is allowed
            assert resp.status_code != 403
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_ai_api_error(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """AI API returns non-200 → 502."""
        saved = _setup_api_key()
        try:
            _install_ai_mock(
                monkeypatch,
                post_result=MockAIResponse(status_code=502, content="Bad Gateway"),
            )

            resp = await client.post(
                "/api/v1/ai/advise",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "How am I doing?"},
            )
            assert resp.status_code == 502
            assert "AI API error" in resp.json()["detail"]
        finally:
            settings.OPENCODE_GO_API_KEY = saved


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
        """POST /ai/advise/stream returns 500 when API key is not configured."""
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

    async def test_stream_returns_tokens(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """POST /ai/advise/stream yields SSE tokens."""
        saved = _setup_api_key()
        try:
            expected_tokens = ["Halo", " ", "saya", " ", "asisten", " ", "keuangan"]
            stream_resp = MockAIStreamResponse(
                status_code=200, tokens=expected_tokens
            )
            _install_ai_mock(monkeypatch, stream_result=stream_resp)

            resp = await client.post(
                "/api/v1/ai/advise/stream",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "Halo, apa kabar?"},
            )
            assert resp.status_code == 200
            assert resp.headers["content-type"] == "text/event-stream; charset=utf-8"

            body = resp.text
            # Check each token appears in the SSE stream
            for token in expected_tokens:
                assert token in body

            # Check [DONE] sentinel
            assert "[DONE]" in body
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_stream_malformed_sse(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """Malformed SSE lines (e.g. non-JSON data) are skipped gracefully."""
        saved = _setup_api_key()
        try:
            import app.routers.ai_advisor as ai_module

            class MalformedStream:
                def __init__(self):
                    self.status_code = 200

                async def __aenter__(self):
                    return self

                async def __aexit__(self, *args):
                    pass

                async def aiter_lines(self):
                    yield "data: valid_token\n\n"
                    yield "not a data line\n"
                    yield "data: not json\n"
                    yield "data: {\"choices\": [{\"delta\": {\"content\": \"OK\"}}]}\n\n"
                    yield "data: [DONE]\n\n"

                async def aread(self):
                    return b""

            class MalformedStreamClient(MockAsyncClient):
                def stream(self, method, url, **kwargs):
                    class StreamContext:
                        async def __aenter__(s):
                            return MalformedStream()

                        async def __aexit__(s, *a):
                            pass

                    return StreamContext()

            monkeypatch.setattr(ai_module.httpx, "AsyncClient", MalformedStreamClient)

            resp = await client.post(
                "/api/v1/ai/advise/stream",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "Halo"},
            )
            assert resp.status_code == 200
            body = resp.text
            # valid_token should be present (from the SSE line that has JSON-like content... actually
            # "data: valid_token\n\n" is not proper SSE JSON, so it would be skipped.
            # Only the last valid JSON line produces output
            assert "OK" in body
            assert "[DONE]" in body
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_stream_api_error(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """Streaming API returns non-200 status → error in SSE."""
        saved = _setup_api_key()
        try:
            import app.routers.ai_advisor as ai_module

            class ErrorStream:
                def __init__(self):
                    self.status_code = 500

                async def __aenter__(self):
                    return self

                async def __aexit__(self, *args):
                    pass

                async def aiter_lines(self):
                    yield ""

                async def aread(self):
                    return b"Server Error"

            class ErrorStreamClient(MockAsyncClient):
                def stream(self, method, url, **kwargs):
                    class StreamContext:
                        async def __aenter__(s):
                            return ErrorStream()

                        async def __aexit__(s, *a):
                            pass

                    return StreamContext()

            monkeypatch.setattr(ai_module.httpx, "AsyncClient", ErrorStreamClient)

            resp = await client.post(
                "/api/v1/ai/advise/stream",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "Test"},
            )
            assert resp.status_code == 200  # SSE responses always 200
            body = resp.text
            assert "error" in body
            assert "500" in body
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_stream_with_history(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """Stream with chat history works."""
        saved = _setup_api_key()
        try:
            stream_resp = MockAIStreamResponse(
                status_code=200, tokens=["Answer with context"]
            )
            _install_ai_mock(monkeypatch, stream_result=stream_resp)

            resp = await client.post(
                "/api/v1/ai/advise/stream",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={
                    "question": "What about my budget?",
                    "history": [
                        {"role": "user", "content": "How much did I spend?"},
                        {"role": "assistant", "content": "You spent Rp1,000,000."},
                    ],
                },
            )
            assert resp.status_code == 200
            assert "Answer with context" in resp.text
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_stream_opus_requires_admin_role(
        self, client: AsyncClient, nahda_token: str, monkeypatch
    ):
        """Stream: non-admin user gets 403 when requesting opus model."""
        saved = _setup_api_key()
        try:
            resp = await client.post(
                "/api/v1/ai/advise/stream",
                headers={"Authorization": f"Bearer {nahda_token}"},
                json={
                    "question": "How am I doing?",
                    "model": "opus",
                },
            )
            assert resp.status_code == 403
            assert "Advanced model" in resp.text
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_stream_opus_allowed_for_admin(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """Stream: admin user can use opus model (403 not raised)."""
        saved = _setup_api_key()
        try:
            stream_resp = MockAIStreamResponse(
                status_code=200, tokens=["Admin opus answer"]
            )
            _install_ai_mock(monkeypatch, stream_result=stream_resp)

            resp = await client.post(
                "/api/v1/ai/advise/stream",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={
                    "question": "How am I doing?",
                    "model": "opus",
                },
            )
            # Should not be 403 — admin is allowed
            assert resp.status_code != 403
        finally:
            settings.OPENCODE_GO_API_KEY = saved
