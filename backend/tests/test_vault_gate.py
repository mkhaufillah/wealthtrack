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
