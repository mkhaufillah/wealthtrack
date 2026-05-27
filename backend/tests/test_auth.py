"""Tests for /api/v1/auth endpoints."""

import pytest
from httpx import AsyncClient


class TestAuthLogin:
    async def test_login_success_filla(self, client: AsyncClient):
        """Login as filla returns valid token."""
        resp = await client.post(
            "/api/v1/auth/login",
            json={"username": "filla", "password": "password123"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"
        assert data["expires_in"] == 30 * 86400

    async def test_login_success_nahda(self, client: AsyncClient):
        """Login as nahda returns valid token."""
        resp = await client.post(
            "/api/v1/auth/login",
            json={"username": "nahda", "password": "password123"},
        )
        assert resp.status_code == 200
        assert "access_token" in resp.json()

    async def test_login_wrong_password(self, client: AsyncClient):
        """Wrong password returns 401."""
        resp = await client.post(
            "/api/v1/auth/login",
            json={"username": "filla", "password": "wrongpassword"},
        )
        assert resp.status_code == 401

    async def test_login_nonexistent_user(self, client: AsyncClient):
        """Non-existent user returns 401."""
        resp = await client.post(
            "/api/v1/auth/login",
            json={"username": "ghost", "password": "password123"},
        )
        assert resp.status_code == 401

    async def test_login_empty_body(self, client: AsyncClient):
        """Missing fields returns 422."""
        resp = await client.post("/api/v1/auth/login", json={})
        assert resp.status_code == 422


class TestAuthRegister:
    async def test_register_success(self, client: AsyncClient):
        """Register new user returns 201 with user data."""
        resp = await client.post(
            "/api/v1/auth/register",
            json={
                "username": "newuser",
                "display_name": "New User",
                "password": "securepass123",
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["username"] == "newuser"
        assert data["display_name"] == "New User"
        assert "id" in data
        assert "password" not in data  # password hash not exposed

    async def test_register_duplicate(self, client: AsyncClient):
        """Duplicate username returns 409."""
        await client.post(
            "/api/v1/auth/register",
            json={
                "username": "dupuser",
                "display_name": "Dup",
                "password": "securepass123",
            },
        )
        resp = await client.post(
            "/api/v1/auth/register",
            json={
                "username": "dupuser",
                "display_name": "Dup Again",
                "password": "anotherpass",
            },
        )
        assert resp.status_code == 409

    async def test_register_invalid_username(self, client: AsyncClient):
        """Username too short returns 422."""
        resp = await client.post(
            "/api/v1/auth/register",
            json={"username": "ab", "display_name": "Short", "password": "password123"},
        )
        assert resp.status_code == 422

    async def test_register_weak_password(self, client: AsyncClient):
        """Password too short returns 422."""
        resp = await client.post(
            "/api/v1/auth/register",
            json={"username": "validuser", "display_name": "Valid", "password": "12345"},
        )
        assert resp.status_code == 422


class TestAuthMe:
    async def test_me_success(self, client: AsyncClient, filla_token: str):
        """GET /me returns the authenticated user's profile."""
        resp = await client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["username"] == "filla"
        assert data["display_name"] == "Filla"
        assert data["role"] == "admin"
        assert "id" in data

    async def test_me_nahda(self, client: AsyncClient, nahda_token: str):
        """Nahda's profile shows nahda data."""
        resp = await client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["username"] == "nahda"
        assert data["display_name"] == "Nahda"

    async def test_me_no_token(self, client: AsyncClient):
        """No auth header returns 401 (FastAPI HTTPBearer default)."""
        resp = await client.get("/api/v1/auth/me")
        assert resp.status_code == 401

    async def test_me_invalid_token(self, client: AsyncClient):
        """Invalid token returns 401."""
        resp = await client.get(
            "/api/v1/auth/me",
            headers={"Authorization": "Bearer invalidtoken123"},
        )
        assert resp.status_code == 401

    async def test_me_fake_user_token(self, client: AsyncClient, fake_token: str):
        """Valid JWT but user doesn't exist returns 404."""
        resp = await client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {fake_token}"},
        )
        assert resp.status_code == 404


class TestUpdateProfile:
    async def test_update_display_name(self, client: AsyncClient, filla_token: str):
        """Update display name returns updated user."""
        resp = await client.put(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"display_name": "Filla Baru"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["display_name"] == "Filla Baru"
        assert data["username"] == "filla"

    async def test_update_no_token(self, client: AsyncClient):
        """Update without auth returns 401."""
        resp = await client.put(
            "/api/v1/auth/me",
            json={"display_name": "Hacker"},
        )
        assert resp.status_code == 401

    async def test_update_empty_name(self, client: AsyncClient, filla_token: str):
        """Empty display name returns 422."""
        resp = await client.put(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"display_name": ""},
        )
        assert resp.status_code == 422


class TestChangePassword:
    async def test_change_password_success(self, client: AsyncClient, filla_token: str):
        """Change password with correct current password succeeds."""
        resp = await client.put(
            "/api/v1/auth/password",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"current_password": "password123", "new_password": "newpass456"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["message"] == "Password updated successfully"

        # Can login with new password
        login_resp = await client.post(
            "/api/v1/auth/login",
            json={"username": "filla", "password": "newpass456"},
        )
        assert login_resp.status_code == 200

        # Old password no longer works
        old_login = await client.post(
            "/api/v1/auth/login",
            json={"username": "filla", "password": "password123"},
        )
        assert old_login.status_code == 401

    async def test_change_password_wrong_current(self, client: AsyncClient, filla_token: str):
        """Wrong current password returns 400."""
        resp = await client.put(
            "/api/v1/auth/password",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"current_password": "wrongpassword", "new_password": "newpass456"},
        )
        assert resp.status_code == 400
        assert "incorrect" in resp.json()["detail"].lower()

    async def test_change_password_no_token(self, client: AsyncClient):
        """Change password without auth returns 401."""
        resp = await client.put(
            "/api/v1/auth/password",
            json={"current_password": "pw", "new_password": "newpass456"},
        )
        assert resp.status_code == 401


class TestDeleteAccount:
    async def test_delete_account_success(self, client: AsyncClient, filla_token: str):
        """Delete account returns 204 and user can no longer access /me."""
        resp = await client.delete(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 204

        # User no longer exists
        me_resp = await client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert me_resp.status_code == 404

        # Login fails
        login_resp = await client.post(
            "/api/v1/auth/login",
            json={"username": "filla", "password": "password123"},
        )
        assert login_resp.status_code == 401

    async def test_delete_account_no_token(self, client: AsyncClient):
        """Delete without auth returns 401."""
        resp = await client.delete("/api/v1/auth/me")
        assert resp.status_code == 401
