"""Tests for /api/v1/households endpoints."""

from httpx import AsyncClient


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
