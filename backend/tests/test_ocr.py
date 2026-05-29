"""Tests for /api/v1/ocr endpoints."""

import io
import json
import struct
import zlib

import httpx
import pytest
from httpx import AsyncClient


def _make_tiny_png() -> bytes:
    """Create a minimal valid 1x1 red PNG in-memory."""
    def _chunk(chunk_type: bytes, data: bytes) -> bytes:
        c = chunk_type + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    raw = b"\x00\xff\x00\x00\xff"
    idat = zlib.compress(raw)

    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", idat)
        + _chunk(b"IEND", b"")
    )


class MockOcrResponse:
    """Stand-in for httpx.Response returned by our mock."""

    def __init__(self, status_code=200, json_data=None):
        self.status_code = status_code
        self._json_data = json_data

    def json(self):
        return self._json_data


class MockOcrClient:
    """Replaces httpx.AsyncClient for OCR tests."""

    def __init__(self, *args, **kwargs):
        self.post_handler = None

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass

    async def post(self, *args, **kwargs):
        if self.post_handler:
            return await self.post_handler(*args, **kwargs)
        return MockOcrResponse(
            status_code=200,
            json_data={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps({
                                "amount": 50000,
                                "description": "Nasi Goreng",
                                "date": "2026-05-27",
                                "type": "expense",
                                "category_name": "Makanan & Minuman",
                            })
                        }
                    }
                ]
            },
        )


def _install_ocr_mock(monkeypatch, response=None, raise_exc=None):
    """Install MockOcrClient as httpx.AsyncClient in app.routers.ocr."""
    import app.routers.ocr as ocr_module

    class InstallableMockClient(MockOcrClient):
        async def post(self, *args, **kwargs):
            if raise_exc is not None:
                raise raise_exc
            if response is not None:
                return response
            return await super().post(*args, **kwargs)

    monkeypatch.setattr(ocr_module.httpx, "AsyncClient", InstallableMockClient)


class TestProcessOcr:
    async def test_requires_auth(self, client: AsyncClient):
        """POST /ocr/process without token returns 401."""
        resp = await client.post("/api/v1/ocr/process")
        assert resp.status_code == 401

    async def test_non_image_file_rejected(self, client: AsyncClient, filla_token: str):
        """POST /ocr/process with non-image file returns 400."""
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("test.txt", b"not an image", "text/plain")},
        )
        assert resp.status_code == 400
        assert "Only image files" in resp.json()["detail"]

    async def test_empty_upload_rejected(self, client: AsyncClient, filla_token: str):
        """POST /ocr/process without file field returns 422."""
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422

    async def test_large_file_rejected(self, client: AsyncClient, filla_token: str):
        """POST /ocr/process with file > 10 MB returns 400."""
        large_data = b"x" * (11 * 1024 * 1024)  # 11 MB
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("large.png", large_data, "image/png")},
        )
        assert resp.status_code == 400
        assert "too large" in resp.json()["detail"].lower()

    async def test_successful_ocr_parsing(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """POST /ocr/process with a valid image returns parsed transaction data."""
        _install_ocr_mock(monkeypatch)

        png_data = _make_tiny_png()
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("receipt.png", png_data, "image/png")},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["amount"] == 50000
        assert data["description"] == "Nasi Goreng"
        assert data["date"] == "2026-05-27"
        assert data["type"] == "expense"
        assert data["category_name"] == "Makanan & Minuman"
        assert "raw_text" in data

    async def test_ocr_api_error(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """Vision API returns non-200 status → 502."""
        _install_ocr_mock(
            monkeypatch,
            response=MockOcrResponse(status_code=500, json_data={}),
        )

        png_data = _make_tiny_png()
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("receipt.png", png_data, "image/png")},
        )
        assert resp.status_code == 502
        assert "Vision API error" in resp.json()["detail"]

    async def test_ocr_timeout(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """Vision API timeout → 504."""
        _install_ocr_mock(monkeypatch, raise_exc=httpx.TimeoutException("timed out"))

        png_data = _make_tiny_png()
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("receipt.png", png_data, "image/png")},
        )
        assert resp.status_code == 504
        assert "timed out" in resp.json()["detail"].lower()

    async def test_ocr_request_error(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """Vision API request failure → 502."""
        _install_ocr_mock(
            monkeypatch, raise_exc=httpx.RequestError("connection failed")
        )

        png_data = _make_tiny_png()
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("receipt.png", png_data, "image/png")},
        )
        assert resp.status_code == 502
        assert "connection failed" in resp.json()["detail"].lower()

    async def test_rate_limiting(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """After 10 OCR calls, the 11th returns 429."""
        import app.routers.ocr as ocr_module

        # Reset rate limiter for this user
        ocr_module._user_ocr_counts.clear()

        _install_ocr_mock(monkeypatch)

        png_data = _make_tiny_png()
        # Make 10 successful calls
        for i in range(10):
            resp = await client.post(
                "/api/v1/ocr/process",
                headers={"Authorization": f"Bearer {filla_token}"},
                files={"file": ("r.png", png_data, "image/png")},
            )
            assert resp.status_code == 200

        # 11th call should be rate-limited
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("r.png", png_data, "image/png")},
        )
        assert resp.status_code == 429
        assert "rate limit" in resp.json()["detail"].lower()

        # Clean up
        ocr_module._user_ocr_counts.clear()

    async def test_ocr_missing_api_key(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """When API key is missing, returns 500."""
        from app.core.config import settings

        saved = settings.OPENCODE_GO_API_KEY
        settings.OPENCODE_GO_API_KEY = ""
        try:
            png_data = _make_tiny_png()
            resp = await client.post(
                "/api/v1/ocr/process",
                headers={"Authorization": f"Bearer {filla_token}"},
                files={"file": ("receipt.png", png_data, "image/png")},
            )
            assert resp.status_code == 500
            assert "not configured" in resp.json()["detail"].lower()
        finally:
            settings.OPENCODE_GO_API_KEY = saved

    async def test_ocr_raw_text_fallback(
        self, client: AsyncClient, filla_token: str, monkeypatch
    ):
        """When the API returns non-JSON content, raw_text is populated."""
        _install_ocr_mock(
            monkeypatch,
            response=MockOcrResponse(
                status_code=200,
                json_data={
                    "choices": [
                        {
                            "message": {
                                "content": "This is not a receipt, it's a picture of a cat."
                            }
                        }
                    ]
                },
            ),
        )

        png_data = _make_tiny_png()
        resp = await client.post(
            "/api/v1/ocr/process",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("receipt.png", png_data, "image/png")},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["raw_text"] == "This is not a receipt, it's a picture of a cat."
        assert data["amount"] is None
