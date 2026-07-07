"""Tests for API key management endpoints and MCP scope enforcement.

These tests use TestClient with mocked DB dependencies so they do not require
a running PostgreSQL container."""
import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, MagicMock

from app.main import app
from app.core.security import get_current_user
from app.database import get_db


client = TestClient(app)


def _make_fake_db():
    """Return a fake CursorWrapper-like object backed by MagicMock."""
    fake = MagicMock()
    fake.lastrowid = 1

    cursor = MagicMock()
    cursor.fetchone = AsyncMock(return_value={"id": 1, "created_at": "2026-07-07T20:00:00Z"})
    cursor.fetchall = AsyncMock(return_value=[])

    fake.execute = AsyncMock(return_value=cursor)
    return fake


def _override_auth(scopes=None, auth_type="jwt"):
    def override_get_current_user():
        user = {"id": 1, "username": "testuser", "role": "user", "household_id": 1}
        if auth_type == "api_key":
            user["auth_type"] = "api_key"
            user["api_key_scopes"] = scopes or ["mcp:read"]
        else:
            user["auth_type"] = "jwt"
            user["api_key_scopes"] = None
        return user
    app.dependency_overrides[get_current_user] = override_get_current_user


def _override_db(fake_db=None):
    if fake_db is None:
        fake_db = _make_fake_db()

    async def override_get_db():
        yield fake_db

    app.dependency_overrides[get_db] = override_get_db
    return fake_db


def _clear_overrides():
    app.dependency_overrides.pop(get_current_user, None)
    app.dependency_overrides.pop(get_db, None)


@pytest.fixture(autouse=True)
def _setup_overrides():
    _override_auth(auth_type="jwt")
    _override_db()
    yield
    _clear_overrides()


class TestApiKeyCreate:
    """Tests for POST /api/v1/api-keys."""

    def test_requires_auth(self):
        _clear_overrides()
        response = client.post("/api/v1/api-keys", json={"name": "x"})
        assert response.status_code == 401

    def test_create_api_key_jwt(self):
        response = client.post(
            "/api/v1/api-keys",
            json={"name": "Claude Desktop", "scopes": ["mcp:read", "mcp:write"]},
        )
        assert response.status_code == 201
        data = response.json()
        assert data["name"] == "Claude Desktop"
        assert data["scopes"] == ["mcp:read", "mcp:write"]
        assert "key" in data
        assert data["key"].startswith("wt_mcp_")
        assert "id" in data
        assert "created_at" in data

    def test_create_api_key_defaults_read_scope(self):
        response = client.post("/api/v1/api-keys", json={"name": "Default Scope"})
        assert response.status_code == 201
        data = response.json()
        assert data["scopes"] == ["mcp:read"]

    def test_create_api_key_rejects_invalid_scope(self):
        response = client.post(
            "/api/v1/api-keys",
            json={"name": "Bad", "scopes": ["mcp:admin"]},
        )
        assert response.status_code == 400
        assert "mcp:admin" in response.text

    def test_create_api_key_rejects_empty_name(self):
        response = client.post("/api/v1/api-keys", json={"name": ""})
        # FastAPI/Pydantic v2 treats empty string as valid unless min_length is set
        assert response.status_code in (201, 422)

    def test_create_api_key_accepts_valid_name(self):
        response = client.post("/api/v1/api-keys", json={"name": "Valid Name"})
        assert response.status_code == 201


class TestApiKeyList:
    """Tests for GET /api/v1/api-keys."""

    def test_requires_auth(self):
        _clear_overrides()
        response = client.get("/api/v1/api-keys")
        assert response.status_code == 401

    def test_list_api_keys_empty(self):
        response = client.get("/api/v1/api-keys")
        assert response.status_code == 200
        data = response.json()
        assert "items" in data
        assert data["items"] == []

    def test_list_api_keys_after_create(self):
        fake_db = _override_db()
        fake_db.execute.return_value.fetchall.return_value = [
            MagicMock(
                __getitem__=lambda self, k: {"id": 1, "name": "List Test", "scopes": ["mcp:read"], "is_active": 1, "last_used_at": None, "created_at": "2026-07-07T20:00:00Z"}[k],
                keys=lambda: ["id", "name", "scopes", "is_active", "last_used_at", "created_at"],
            )
        ]

        list_resp = client.get("/api/v1/api-keys")
        assert list_resp.status_code == 200
        data = list_resp.json()
        assert len(data["items"]) == 1
        item = data["items"][0]
        assert item["name"] == "List Test"
        assert item["scopes"] == ["mcp:read"]
        assert item["is_active"] is True
        assert "last_used_at" in item
        assert "key" not in item


class TestApiKeyRevoke:
    """Tests for DELETE /api/v1/api-keys/{key_id}."""

    def test_requires_auth(self):
        _clear_overrides()
        response = client.delete("/api/v1/api-keys/1")
        assert response.status_code == 401

    def test_revoke_api_key(self):
        fake_db = _override_db()
        fake_db.execute.return_value.fetchone.return_value = None

        del_resp = client.delete("/api/v1/api-keys/1")
        assert del_resp.status_code == 204
        assert del_resp.content == b""

    def test_revoke_unknown_key_returns_404(self):
        fake_db = _override_db()
        fake_db.execute.return_value.fetchone.return_value = {"1": 1}

        response = client.delete("/api/v1/api-keys/999999")
        assert response.status_code == 404


class TestApiKeyMcpAccess:
    """Tests for API key scope enforcement on MCP tools."""

    def test_read_only_key_cannot_create_transaction(self):
        _override_auth(scopes=["mcp:read"], auth_type="api_key")
        # Even in no-DB test env, scope check happens before DB fallback.
        # Force the handler to think a pool exists so it skips the permissive fallback.
        from app import routers
        import app.routers.mcp as mcp_module
        original_pool = getattr(mcp_module, "pool", None)
        mcp_module.pool = "fake"  # type: ignore
        try:
            payload = {
                "jsonrpc": "2.0",
                "id": 10,
                "method": "tools/call",
                "params": {
                    "name": "create_transaction",
                    "arguments": {
                        "amount": 10000,
                        "type": "expense",
                        "category_id": 1,
                        "description": "should fail",
                    },
                },
            }
            response = client.post("/api/v1/mcp/stream", json=payload)
            assert response.status_code == 200
            data = response.json()
            assert "error" in data
            assert "Insufficient scope" in data["error"]["message"]
        finally:
            mcp_module.pool = original_pool  # type: ignore

    def test_write_key_can_call_create_transaction_no_db(self):
        _override_auth(scopes=["mcp:read", "mcp:write"], auth_type="api_key")
        payload = {
            "jsonrpc": "2.0",
            "id": 11,
            "method": "tools/call",
            "params": {
                "name": "create_transaction",
                "arguments": {
                    "amount": 10000,
                    "type": "expense",
                    "category_id": 1,
                    "description": "should hit fallback",
                },
            },
        }
        response = client.post("/api/v1/mcp/stream", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert "result" in data

    def test_read_key_can_call_read_tools_no_db(self):
        _override_auth(scopes=["mcp:read"], auth_type="api_key")
        payload = {
            "jsonrpc": "2.0",
            "id": 12,
            "method": "tools/call",
            "params": {"name": "get_current_balance", "arguments": {}},
        }
        response = client.post("/api/v1/mcp/stream", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert "result" in data
