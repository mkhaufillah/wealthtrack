"""Request-scoped vault key. Never log dek."""

from __future__ import annotations

from contextvars import ContextVar

from fastapi import HTTPException, Request

from app.core.vault import parse_dek

_dek: ContextVar[bytes | None] = ContextVar("vault_dek", default=None)
_sealed: ContextVar[bool] = ContextVar("vault_sealed", default=False)
_hh: ContextVar[int | None] = ContextVar("vault_hh", default=None)


class VaultRequiredError(Exception):
    def __init__(self) -> None:
        super().__init__("err.vault_required")


class VaultPendingError(Exception):
    def __init__(self) -> None:
        super().__init__("err.vault_pending")


def current_dek() -> bytes | None:
    return _dek.get()


def current_sealed() -> bool:
    return _sealed.get()


def current_household_id() -> int | None:
    return _hh.get()


def set_dek(dek: bytes | None) -> None:
    _dek.set(dek)


async def bind_vault_from_request(request: Request, user: dict, db) -> None:
    _dek.set(None)
    _sealed.set(False)
    _hh.set(None)
    uid = user.get("id")
    raw = request.headers.get("x-vault-key") or request.headers.get("X-Vault-Key")
    if raw:
        try:
            _dek.set(parse_dek(raw))
        except ValueError:
            raise HTTPException(status_code=400, detail="err.vault_required") from None
    if not uid:
        return
    try:
        cursor = await db.execute(
            """SELECT h.id, COALESCE(h.vault_sealed, 0) AS vault_sealed
               FROM households h
               JOIN household_members hm ON hm.household_id = h.id
               WHERE hm.user_id = ?""",
            (uid,),
        )
        row = await cursor.fetchone()
    except Exception:
        return
    if not row:
        return
    _hh.set(int(row["id"]))
    _sealed.set(int(row["vault_sealed"] or 0) == 1)
