"""Tests for /api/v1/households endpoints."""

import aiosqlite
from httpx import AsyncClient
from app.core.security import create_access_token, hash_password


async def _create_user(db: aiosqlite.Connection, username: str, display_name: str) -> tuple[int, str]:
    """Insert a user directly into the DB and return (user_id, token)."""
    pw_hash = hash_password("password123")
    cursor = await db.execute(
        "INSERT INTO users (username, display_name, password_hash, role) VALUES (?, ?, ?, 'user')",
        (username, display_name, pw_hash),
    )
    await db.commit()
    uid = cursor.lastrowid
    token = create_access_token(user_id=uid, username=username)
    return uid, token


async def _cleanup_user(db: aiosqlite.Connection, user_id: int, household_id: int | None = None):
    """Remove a user and all their related records. Optionally remove a household."""
    if household_id:
        await db.execute("DELETE FROM household_members WHERE household_id = ?", (household_id,))
        await db.execute("DELETE FROM households WHERE id = ?", (household_id,))
    await db.execute("DELETE FROM household_members WHERE user_id = ?", (user_id,))
    await db.execute("DELETE FROM budgets WHERE user_id = ?", (user_id,))
    await db.execute("DELETE FROM transactions WHERE user_id = ?", (user_id,))
    await db.execute("DELETE FROM users WHERE id = ?", (user_id,))
    await db.commit()


class TestCreateHousehold:
    async def test_requires_auth(self, client: AsyncClient):
        """POST /households without token returns 401."""
        resp = await client.post(
            "/api/v1/households",
            json={"name": "New Household"},
        )
        assert resp.status_code == 401

    async def test_already_in_household(self, client: AsyncClient, filla_token: str):
        """User already in a household gets 409."""
        resp = await client.post(
            "/api/v1/households",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"name": "Another Home"},
        )
        assert resp.status_code == 409
        assert "Already in a household" in resp.json()["detail"]

    async def test_user_not_in_household_creates_one(
        self, client: AsyncClient, db: aiosqlite.Connection
    ):
        """A user not in any household can create one → 201."""
        uid, token = await _create_user(db, "newuser", "New User")

        resp = await client.post(
            "/api/v1/households",
            headers={"Authorization": f"Bearer {token}"},
            json={"name": "New Family"},
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["name"] == "New Family"
        assert data["created_by"] == uid
        assert len(data["invite_code"]) == 8
        household_id = data["id"]

        # Clean up
        await _cleanup_user(db, uid, household_id=household_id)


class TestJoinHousehold:
    async def test_requires_auth(self, client: AsyncClient):
        """POST /households/join without token returns 401."""
        resp = await client.post(
            "/api/v1/households/join",
            json={"invite_code": "ABCD1234"},
        )
        assert resp.status_code == 401

    async def test_already_in_household_join(self, client: AsyncClient, filla_token: str):
        """User already in a household gets 409 when trying to join another."""
        resp = await client.post(
            "/api/v1/households/join",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"invite_code": "ZZZZZZZZ"},
        )
        assert resp.status_code == 409
        assert "Already in a household" in resp.json()["detail"]

    async def test_second_user_joins_via_invite_code(
        self, client: AsyncClient, db: aiosqlite.Connection
    ):
        """A new user not in a household can join via invite code → 200."""
        # Create admin and a household
        admin_id, admin_token = await _create_user(db, "adminuser", "Admin User")

        create_resp = await client.post(
            "/api/v1/households",
            headers={"Authorization": f"Bearer {admin_token}"},
            json={"name": "Test Household"},
        )
        assert create_resp.status_code == 201
        invite_code = create_resp.json()["invite_code"]
        assert len(invite_code) == 8
        household_id = create_resp.json()["id"]

        # Create a second user to join
        joiner_id, joiner_token = await _create_user(db, "joiner", "Joiner")

        # Join via invite code
        resp = await client.post(
            "/api/v1/households/join",
            headers={"Authorization": f"Bearer {joiner_token}"},
            json={"invite_code": invite_code},
        )
        assert resp.status_code == 200
        assert "Joined" in resp.json()["message"]

        # Verify new user is now a member
        me_resp = await client.get(
            "/api/v1/households/me",
            headers={"Authorization": f"Bearer {joiner_token}"},
        )
        assert me_resp.status_code == 200
        assert me_resp.json()["household"]["name"] == "Test Household"

        # Clean up
        await _cleanup_user(db, joiner_id)
        await _cleanup_user(db, admin_id, household_id=household_id)

    async def test_join_invalid_code(self, client: AsyncClient, db: aiosqlite.Connection):
        """A user not in a household joining with invalid code → 404."""
        uid, token = await _create_user(db, "invalidjoiner", "InvalidJoiner")

        resp = await client.post(
            "/api/v1/households/join",
            headers={"Authorization": f"Bearer {token}"},
            json={"invite_code": "ZZZZZZZZ"},
        )
        assert resp.status_code == 404
        assert "Invalid invite code" in resp.json()["detail"]

        await _cleanup_user(db, uid)


class TestGetMyHousehold:
    async def test_me_success_filla(self, client: AsyncClient, filla_token: str):
        """GET /households/me returns filla's household details."""
        resp = await client.get(
            "/api/v1/households/me",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "household" in data
        assert "members" in data
        assert "is_admin" in data
        assert data["household"]["name"] == "Home"
        assert data["is_admin"] is True
        assert len(data["members"]) >= 2

    async def test_me_nahda(self, client: AsyncClient, nahda_token: str):
        """Nahda (household member) can also see the household."""
        resp = await client.get(
            "/api/v1/households/me",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["household"]["name"] == "Home"
        assert data["is_admin"] is False

    async def test_me_requires_auth(self, client: AsyncClient):
        """GET /households/me without token returns 401."""
        resp = await client.get("/api/v1/households/me")
        assert resp.status_code == 401

    async def test_me_fake_user(self, client: AsyncClient, fake_token: str):
        """Valid JWT but non-existent user returns 404."""
        resp = await client.get(
            "/api/v1/households/me",
            headers={"Authorization": f"Bearer {fake_token}"},
        )
        assert resp.status_code == 404

    async def test_me_not_in_household(self, client: AsyncClient, db: aiosqlite.Connection):
        """User not in a household gets 404."""
        uid, token = await _create_user(db, "solouser", "Solo User")

        resp = await client.get(
            "/api/v1/households/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 404
        assert "Not a member" in resp.json()["detail"]

        await _cleanup_user(db, uid)


class TestInviteCode:
    async def test_invite_code_success(self, client: AsyncClient, filla_token: str):
        """GET /households/invite-code returns the household invite code."""
        resp = await client.get(
            "/api/v1/households/invite-code",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "invite_code" in data
        assert len(data["invite_code"]) >= 8

    async def test_invite_code_requires_auth(self, client: AsyncClient):
        """GET /households/invite-code without token returns 401."""
        resp = await client.get("/api/v1/households/invite-code")
        assert resp.status_code == 401

    async def test_invite_code_not_member(self, client: AsyncClient, db: aiosqlite.Connection):
        """User not in a household cannot view invite code."""
        uid, token = await _create_user(db, "nocodeuser", "No Code User")

        resp = await client.get(
            "/api/v1/households/invite-code",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 404

        await _cleanup_user(db, uid)
