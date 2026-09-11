"""Money writes always go to vault_blob. No plaintext amount columns."""

from __future__ import annotations

from app.core.vault_ctx import VaultRequiredError, current_dek
from app.core.vault_row import pack_money


def must_dek() -> bytes:
    dek = current_dek()
    if dek is None:
        raise VaultRequiredError()
    return dek


def pack_txn(
    *,
    amount: int,
    description: str = "",
    note: str = "",
    category_id: int | None = None,
    category_name: str = "",
) -> dict:
    return pack_money(
        must_dek(),
        amount=int(amount),
        description=description or "",
        note=note or "",
        category_id=category_id,
        category_name=category_name or "",
    )


pack_budget = pack_txn
