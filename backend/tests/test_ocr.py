"""Tests for /api/v1/ocr endpoints."""

from httpx import AsyncClient


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
