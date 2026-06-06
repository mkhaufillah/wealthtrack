"""Tests for uncovered backend endpoints.

Covers:
- POST /api/v1/ocr/process-and-save — OCR auto-save (background job)
- GET /api/v1/ocr/pending-count — OCR pending count
- POST /api/v1/ai/chat — Async AI chat
- GET /api/v1/ai/chat/messages — Chat messages list
- DELETE /api/v1/ai/chat/messages — Clear chat history
- GET /api/v1/summaries/all-time-category-balance — S&I and emergency fund balance
"""

import json
import struct
import zlib

import httpx
import pytest
from httpx import AsyncClient


# ──────────────────────────────────────────────
# Shared OCR helpers (same pattern as test_ocr.py)
# ──────────────────────────────────────────────

@pytest.fixture(autouse=True)
async def _mock_ocr_rate_limit(monkeypatch):
    """Bypass Redis rate limiter in all OCR tests — avoids event loop issues."""
    async def _noop(*args, **kwargs):
        pass
    monkeypatch.setattr("app.routers.ocr._check_rate_limit", _noop)


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


def _ensure_api_key():
    """Set a test API key if none is set; return saved value for restore."""
    from app.core.config import settings
    saved = settings.OPENCODE_GO_API_KEY
    if not saved:
        settings.OPENCODE_GO_API_KEY = "test-api-key"
    return saved


# ──────────────────────────────────────────────
# POST /api/v1/ocr/process-and-save
# ──────────────────────────────────────────────

class TestOcrProcessAndSave:
    """POST /api/v1/ocr/process-and-save — OCR auto-save (background job)"""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.post("/api/v1/ocr/process-and-save")
        assert resp.status_code == 401

    async def test_non_image_rejected(self, client: AsyncClient, filla_token: str):
        """Non-image file returns 400."""
        resp = await client.post(
            "/api/v1/ocr/process-and-save",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("test.txt", b"not an image", "text/plain")},
        )
        assert resp.status_code == 400
        assert "Unsupported image format" in resp.json()["detail"]

    async def test_large_file_rejected(self, client: AsyncClient, filla_token: str):
        """File > 10 MB returns 400."""
        large_data = b"x" * (11 * 1024 * 1024)
        resp = await client.post(
            "/api/v1/ocr/process-and-save",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("large.png", large_data, "image/png")},
        )
        assert resp.status_code == 400
        assert "too large" in resp.json()["detail"].lower()

    async def test_successful_creation(self, client: AsyncClient, filla_token: str):
        """Valid image creates OCR job and returns job_id immediately."""
        png_data = _make_tiny_png()
        resp = await client.post(
            "/api/v1/ocr/process-and-save",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("receipt.png", png_data, "image/png")},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "job_id" in data
        assert data["job_id"] > 0
        assert data["status"] == "processing"

    async def test_concurrent_job_rejected(self, client: AsyncClient, filla_token: str, db):
        """Second job while one is processing returns 429."""
        await db.execute(
            "INSERT INTO ocr_jobs (user_id, image_filename, status) VALUES (1, 'existing.png', 'processing')",
        )
        png_data = _make_tiny_png()
        resp = await client.post(
            "/api/v1/ocr/process-and-save",
            headers={"Authorization": f"Bearer {filla_token}"},
            files={"file": ("receipt.png", png_data, "image/png")},
        )
        assert resp.status_code == 429
        assert "already have an OCR job" in resp.json()["detail"].lower()


# ──────────────────────────────────────────────
# GET /api/v1/ocr/pending-count
# ──────────────────────────────────────────────

class TestOcrPendingCount:
    """GET /api/v1/ocr/pending-count — OCR pending count"""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.get("/api/v1/ocr/pending-count")
        assert resp.status_code == 401

    async def test_zero_when_no_jobs(self, client: AsyncClient, filla_token: str):
        """Returns count=0 when user has no processing jobs."""
        resp = await client.get(
            "/api/v1/ocr/pending-count",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["count"] == 0

    async def test_counts_only_processing_jobs(self, client: AsyncClient, filla_token: str, db):
        """Returns correct count of processing jobs for this user only."""
        # Two processing jobs for this user
        await db.execute(
            "INSERT INTO ocr_jobs (user_id, image_filename, status) VALUES (1, 'job1.png', 'processing')",
        )
        await db.execute(
            "INSERT INTO ocr_jobs (user_id, image_filename, status) VALUES (1, 'job2.png', 'processing')",
        )
        # Completed job (should not be counted)
        await db.execute(
            "INSERT INTO ocr_jobs (user_id, image_filename, status) VALUES (1, 'done.png', 'completed')",
        )
        # Processing job for another user (should not be counted)
        await db.execute(
            "INSERT INTO ocr_jobs (user_id, image_filename, status) VALUES (2, 'other.png', 'processing')",
        )

        resp = await client.get(
            "/api/v1/ocr/pending-count",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["count"] == 2

    async def test_reports_recent_failure(self, client: AsyncClient, filla_token: str, db):
        """Returns error info when there is a recent failure."""
        await db.execute(
            "INSERT INTO ocr_jobs (user_id, image_filename, status, error, created_at) "
            "VALUES (1, 'failed.png', 'failed', 'OCR failed. Please try again.', NOW())",
        )

        resp = await client.get(
            "/api/v1/ocr/pending-count",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["has_failure"] is True
        assert "error" in data
        assert data["failed_job_id"] is not None


# ──────────────────────────────────────────────
# POST /api/v1/ai/chat
# ──────────────────────────────────────────────

class TestAiChat:
    """POST /api/v1/ai/chat — Async AI chat"""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.post(
            "/api/v1/ai/chat",
            json={"question": "How can I save more?"},
        )
        assert resp.status_code == 401

    async def test_returns_500_without_api_key(self, client: AsyncClient, filla_token: str):
        """Returns 500 when API key is not configured."""
        saved_key = _ensure_api_key()
        settings_restored = False
        try:
            from app.core.config import settings
            settings.OPENCODE_GO_API_KEY = ""
            resp = await client.post(
                "/api/v1/ai/chat",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "How can I save more?"},
            )
            assert resp.status_code == 500
            assert "not configured" in resp.json()["detail"].lower()
        finally:
            if not settings_restored:
                from app.core.config import settings
                if saved_key:
                    settings.OPENCODE_GO_API_KEY = saved_key
                else:
                    settings.OPENCODE_GO_API_KEY = ""

    async def test_returns_message_ids(self, client: AsyncClient, filla_token: str):
        """Returns user_message_id and ai_message_id on success."""
        saved_key = _ensure_api_key()
        try:
            resp = await client.post(
                "/api/v1/ai/chat",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "How can I save more money?"},
            )
            assert resp.status_code == 200
            data = resp.json()
            assert "user_message_id" in data
            assert "ai_message_id" in data
            assert isinstance(data["user_message_id"], int)
            assert isinstance(data["ai_message_id"], int)
            assert data["user_message_id"] > 0
            assert data["ai_message_id"] > 0
        finally:
            from app.core.config import settings
            if saved_key:
                settings.OPENCODE_GO_API_KEY = saved_key
            else:
                settings.OPENCODE_GO_API_KEY = ""

    async def test_opus_requires_admin(self, client: AsyncClient, nahda_token: str):
        """Non-admin user gets 403 when requesting opus model."""
        saved_key = _ensure_api_key()
        try:
            resp = await client.post(
                "/api/v1/ai/chat",
                headers={"Authorization": f"Bearer {nahda_token}"},
                json={"question": "How am I doing?", "model": "opus"},
            )
            assert resp.status_code == 403
            assert "Advanced model" in resp.json()["detail"]
        finally:
            from app.core.config import settings
            if saved_key:
                settings.OPENCODE_GO_API_KEY = saved_key
            else:
                settings.OPENCODE_GO_API_KEY = ""

    async def test_retry_hides_old_ai_messages(self, client: AsyncClient, filla_token: str, db):
        """retry_parent_id marks old AI messages as 'error:hidden'."""
        saved_key = _ensure_api_key()
        try:
            # Insert a user message and linked AI message
            await db.execute(
                "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
                "VALUES (100, 1, 'user', 'Old question', 'complete', 'flash')",
            )
            await db.execute(
                "INSERT INTO ai_messages (id, user_id, role, content, status, model, parent_message_id) "
                "VALUES (101, 1, 'assistant', 'Old answer', 'complete', 'flash', 100)",
            )

            resp = await client.post(
                "/api/v1/ai/chat",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "Retry question", "retry_parent_id": 100},
            )
            assert resp.status_code == 200

            # Verify old AI message was hidden
            cursor = await db.execute(
                "SELECT status FROM ai_messages WHERE id = 101",
            )
            row = await cursor.fetchone()
            assert row["status"] == "error:hidden"
        finally:
            from app.core.config import settings
            if saved_key:
                settings.OPENCODE_GO_API_KEY = saved_key
            else:
                settings.OPENCODE_GO_API_KEY = ""

    async def test_saves_messages_to_db(self, client: AsyncClient, filla_token: str, db):
        """Creates user message and processing AI message in database."""
        saved_key = _ensure_api_key()
        try:
            resp = await client.post(
                "/api/v1/ai/chat",
                headers={"Authorization": f"Bearer {filla_token}"},
                json={"question": "What is my budget?"},
            )
            assert resp.status_code == 200
            data = resp.json()

            # Verify user message
            cursor = await db.execute(
                "SELECT role, content, status, model FROM ai_messages WHERE id = ?",
                (data["user_message_id"],),
            )
            user_msg = await cursor.fetchone()
            assert user_msg["role"] == "user"
            assert user_msg["content"] == "What is my budget?"
            assert user_msg["status"] == "complete"
            assert user_msg["model"] == "flash"

            # Verify AI message (processing placeholder)
            cursor = await db.execute(
                "SELECT role, content, status, model, parent_message_id FROM ai_messages WHERE id = ?",
                (data["ai_message_id"],),
            )
            ai_msg = await cursor.fetchone()
            assert ai_msg["role"] == "assistant"
            assert ai_msg["status"] == "processing"
            assert ai_msg["parent_message_id"] == data["user_message_id"]
        finally:
            from app.core.config import settings
            if saved_key:
                settings.OPENCODE_GO_API_KEY = saved_key
            else:
                settings.OPENCODE_GO_API_KEY = ""


# ──────────────────────────────────────────────
# GET /api/v1/ai/chat/messages
# ──────────────────────────────────────────────

class TestGetChatMessages:
    """GET /api/v1/ai/chat/messages — Chat messages list"""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.get("/api/v1/ai/chat/messages")
        assert resp.status_code == 401

    async def test_returns_empty_list(self, client: AsyncClient, filla_token: str):
        """Returns empty list when no messages exist."""
        resp = await client.get(
            "/api/v1/ai/chat/messages",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert len(data) == 0

    async def test_returns_user_messages_ordered(self, client: AsyncClient, filla_token: str, db):
        """Returns messages for the authenticated user in creation order."""
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (201, 1, 'user', 'Hello', 'complete', 'flash')",
        )
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model, parent_message_id) "
            "VALUES (202, 1, 'assistant', 'Hi there', 'complete', 'flash', 201)",
        )

        resp = await client.get(
            "/api/v1/ai/chat/messages",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2
        assert data[0]["id"] == 201
        assert data[0]["content"] == "Hello"
        assert data[1]["id"] == 202
        assert data[1]["content"] == "Hi there"

    async def test_excludes_error_hidden(self, client: AsyncClient, filla_token: str, db):
        """Excludes messages with status 'error:hidden'."""
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (301, 1, 'user', 'Visible', 'complete', 'flash')",
        )
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (302, 1, 'user', 'Hidden', 'error:hidden', 'flash')",
        )

        resp = await client.get(
            "/api/v1/ai/chat/messages",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        ids = [m["id"] for m in data]
        assert 301 in ids
        assert 302 not in ids

    async def test_scoped_to_current_user(self, client: AsyncClient, nahda_token: str, db):
        """Only returns messages for the authenticated user."""
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (401, 1, 'user', 'Filla msg', 'complete', 'flash')",
        )
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (402, 2, 'user', 'Nahda msg', 'complete', 'flash')",
        )

        resp = await client.get(
            "/api/v1/ai/chat/messages",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 1
        assert data[0]["content"] == "Nahda msg"


# ──────────────────────────────────────────────
# DELETE /api/v1/ai/chat/messages
# ──────────────────────────────────────────────

class TestDeleteChatMessages:
    """DELETE /api/v1/ai/chat/messages — Clear chat history"""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.delete("/api/v1/ai/chat/messages")
        assert resp.status_code == 401

    async def test_deletes_all_user_messages(self, client: AsyncClient, filla_token: str, db):
        """Deletes all messages for the authenticated user."""
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (501, 1, 'user', 'Msg 1', 'complete', 'flash')",
        )
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (502, 1, 'assistant', 'Answer 1', 'complete', 'flash')",
        )

        resp = await client.delete(
            "/api/v1/ai/chat/messages",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 204

        cursor = await db.execute(
            "SELECT COUNT(*) as count FROM ai_messages WHERE user_id = 1",
        )
        row = await cursor.fetchone()
        assert row["count"] == 0

    async def test_only_deletes_current_user(self, client: AsyncClient, filla_token: str, db):
        """Only deletes messages for the authenticated user, not others."""
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (601, 1, 'user', 'Filla msg', 'complete', 'flash')",
        )
        await db.execute(
            "INSERT INTO ai_messages (id, user_id, role, content, status, model) "
            "VALUES (602, 2, 'user', 'Nahda msg', 'complete', 'flash')",
        )

        resp = await client.delete(
            "/api/v1/ai/chat/messages",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 204

        cursor = await db.execute(
            "SELECT COUNT(*) as count FROM ai_messages WHERE user_id = 1",
        )
        assert (await cursor.fetchone())["count"] == 0

        cursor = await db.execute(
            "SELECT COUNT(*) as count FROM ai_messages WHERE user_id = 2",
        )
        assert (await cursor.fetchone())["count"] == 1

    async def test_empty_delete(self, client: AsyncClient, filla_token: str):
        """Deleting when no messages exist returns 204."""
        resp = await client.delete(
            "/api/v1/ai/chat/messages",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 204


# ──────────────────────────────────────────────
# GET /api/v1/summaries/all-time-category-balance
# ──────────────────────────────────────────────

class TestAllTimeCategoryBalance:
    """GET /api/v1/summaries/all-time-category-balance — S&I and emergency fund balance"""

    async def test_requires_auth(self, client: AsyncClient):
        """Returns 401 without token."""
        resp = await client.get("/api/v1/summaries/all-time-category-balance")
        assert resp.status_code == 401

    async def test_returns_zero_when_no_categories(self, client: AsyncClient, filla_token: str):
        """Returns zero balances when S&I and emergency fund categories don't exist."""
        resp = await client.get(
            "/api/v1/summaries/all-time-category-balance",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "savings_investment" in data
        assert "emergency_funds" in data
        assert data["savings_investment"]["balance"] == 0
        assert data["savings_investment"]["total_expense"] == 0
        assert data["savings_investment"]["total_income"] == 0
        assert data["emergency_funds"]["balance"] == 0
        assert data["emergency_funds"]["total_expense"] == 0
        assert data["emergency_funds"]["total_income"] == 0

    async def test_returns_correct_balance(self, client: AsyncClient, filla_token: str, db):
        """Returns correct balance with categories and transactions."""
        # Create Savings & Investment category
        await db.execute(
            "INSERT INTO categories (id, name, type, icon, is_default, sort_order, name_en, keywords) "
            "VALUES (100, 'Investasi', 'expense', '💰', 0, 10, 'Savings & Investment', '[]')",
        )
        # Create Emergency Funds category
        await db.execute(
            "INSERT INTO categories (id, name, type, icon, is_default, sort_order, name_en, keywords) "
            "VALUES (101, 'Darurat', 'expense', '🚨', 0, 11, 'Emergency Funds', '[]')",
        )

        # Savings: two expense transactions + one income transaction
        await db.execute(
            "INSERT INTO transactions (user_id, type, category_id, category_name, amount, description, date) "
            "VALUES (1, 'expense', 100, 'Investasi', 500000, 'Monthly investment', CURRENT_DATE)",
        )
        await db.execute(
            "INSERT INTO transactions (user_id, type, category_id, category_name, amount, description, date) "
            "VALUES (1, 'expense', 100, 'Investasi', 200000, 'Extra investment', CURRENT_DATE)",
        )
        await db.execute(
            "INSERT INTO transactions (user_id, type, category_id, category_name, amount, description, date) "
            "VALUES (1, 'income', 100, 'Investasi', 50000, 'Dividend', CURRENT_DATE)",
        )
        # Emergency fund: one expense transaction
        await db.execute(
            "INSERT INTO transactions (user_id, type, category_id, category_name, amount, description, date) "
            "VALUES (1, 'expense', 101, 'Darurat', 1000000, 'Emergency fund top-up', CURRENT_DATE)",
        )

        resp = await client.get(
            "/api/v1/summaries/all-time-category-balance",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()

        # S&I: expense=500000+200000=700000, income=50000, balance=700000-50000=650000
        assert data["savings_investment"]["total_expense"] == 700000
        assert data["savings_investment"]["total_income"] == 50000
        assert data["savings_investment"]["balance"] == 650000

        # Emergency: expense=1000000, income=0, balance=1000000-0=1000000
        assert data["emergency_funds"]["total_expense"] == 1000000
        assert data["emergency_funds"]["total_income"] == 0
        assert data["emergency_funds"]["balance"] == 1000000

    async def test_scoped_to_current_user(self, client: AsyncClient, nahda_token: str, db):
        """Only queries data for the authenticated user."""
        await db.execute(
            "INSERT INTO categories (id, name, type, icon, is_default, sort_order, name_en, keywords) "
            "VALUES (110, 'Investasi', 'expense', '💰', 0, 10, 'Savings & Investment', '[]')",
        )
        # Only user 1 has a transaction; nahda (user 2) should see zeros
        await db.execute(
            "INSERT INTO transactions (user_id, type, category_id, category_name, amount, description, date) "
            "VALUES (1, 'expense', 110, 'Investasi', 500000, 'Filla investment', CURRENT_DATE)",
        )

        resp = await client.get(
            "/api/v1/summaries/all-time-category-balance",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["savings_investment"]["balance"] == 0
        assert data["emergency_funds"]["balance"] == 0
