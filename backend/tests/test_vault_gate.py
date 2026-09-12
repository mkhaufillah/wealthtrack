"""Vault gate: a sealed household without a key must answer 403, never 500.

Regression: ``GET /home`` used to raise ``VaultRequiredError`` straight out of
the service, so the client got a 500 "err.generic" and rendered a crash screen
instead of the vault gate (waiting page).
"""

from httpx import AsyncClient

from app.core.vault_ctx import VaultPendingError


class TestVaultRequiredContract:
    async def test_home_without_key_is_403_not_500(
        self, client: AsyncClient, filla_token: str
    ):
        """A sealed household + no X-Vault-Key header → 403 err.vault_required."""
        client.headers.pop("X-Vault-Key", None)

        resp = await client.get(
            "/api/v1/home",
            headers={"Authorization": f"Bearer {filla_token}"},
        )

        assert resp.status_code == 403, resp.text
        assert resp.json()["code"] == "err.vault_required"

    async def test_summaries_daily_without_key_is_403(
        self, client: AsyncClient, filla_token: str
    ):
        client.headers.pop("X-Vault-Key", None)

        resp = await client.get(
            "/api/v1/summaries/daily",
            headers={"Authorization": f"Bearer {filla_token}"},
        )

        assert resp.status_code == 403, resp.text
        assert resp.json()["code"] == "err.vault_required"

    async def test_vault_pending_maps_to_404(self):
        """``err.vault_pending`` (gembok not shared yet) stays a 404."""
        from starlette.requests import Request

        from app.main import vault_pending_exception_handler

        request = Request({"type": "http", "headers": []})
        resp = await vault_pending_exception_handler(request, VaultPendingError())

        assert resp.status_code == 404
        assert b"err.vault_pending" in resp.body

    async def test_handler_is_registered(self):
        from app.core.vault_ctx import VaultRequiredError as Err
        from app.main import app

        assert Err in app.exception_handlers


class TestDeviceClaim:
    """A member who picked the key up on a device counts as holding it.

    The app writes ``kdf_params='device'`` with an EMPTY body (no secret is
    stored) when the gembok arrives on a cold start — i.e. with no password in
    memory to build a password wrap. Without this marker the owner keeps seeing
    "Bagi gembok" and the member keeps seeing "menunggu kunci" until some later
    login, even though the member is already inside the vault.
    """

    async def _claim(self, client: AsyncClient, token: str):
        return await client.post(
            "/api/v1/households/vault/wrap",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "wrapped_dek": "",
                "kdf_salt": "device",
                "kdf_params": "device",
            },
        )

    async def _seed_owner_wrap(self, db):
        await db.execute(
            """INSERT INTO household_key_wraps
               (user_id, household_id, wrapped_dek, kdf_salt, kdf_params)
               VALUES (1, 1, 'blob', 'salt', 'argon2id:m=65536,t=3,p=1')
               ON CONFLICT DO NOTHING"""
        )

    async def test_device_claim_clears_owner_card(
        self, client: AsyncClient, db, filla_token: str, nahda_token: str
    ):
        await self._seed_owner_wrap(db)

        before = await client.get(
            "/api/v1/households/me",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert before.json()["vault_needs_share"] is True  # nahda has no key yet

        resp = await self._claim(client, nahda_token)
        assert resp.status_code == 200, resp.text

        after = await client.get(
            "/api/v1/households/me",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert after.json()["vault_needs_share"] is False
        assert after.json()["vault_ready"] is True

        member = await client.get(
            "/api/v1/households/me",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert member.json()["vault_ready"] is True
        assert member.json()["vault_needs_share"] is False

    async def test_device_claim_is_not_a_share_inbox_box(
        self, client: AsyncClient, nahda_token: str
    ):
        """The claim marker must never look like an unclaimed gembok."""
        assert (await self._claim(client, nahda_token)).status_code == 200

        inbox = await client.get(
            "/api/v1/households/vault/share-inbox",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert inbox.status_code == 404

        wrap = await client.get(
            "/api/v1/households/vault/wrap",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert wrap.status_code == 200
        assert wrap.json()["kdf_params"] == "device"
