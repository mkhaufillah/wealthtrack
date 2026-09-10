"""Seal household money rows and store wraps/pubkeys."""

from __future__ import annotations

from app.core.vault_ctx import (
    VaultRequiredError,
    current_dek,
    current_household_id,
)
from app.core.vault_row import pack_money
from app.database import CursorWrapper


class VaultService:
    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    async def _member_ids(self, hh_id: int) -> list[int]:
        cur = await self.db.execute(
            "SELECT user_id FROM household_members WHERE household_id = ?",
            (hh_id,),
        )
        return [int(r["user_id"]) for r in await cur.fetchall()]

    async def seal(self, user_id: int) -> dict:
        dek = current_dek()
        hh_id = current_household_id()
        if dek is None or hh_id is None:
            raise VaultRequiredError()
        await self.db.execute("SELECT pg_advisory_xact_lock(?)", (hh_id,))
        cur = await self.db.execute(
            "SELECT COALESCE(vault_sealed, 0) AS s FROM households WHERE id = ?",
            (hh_id,),
        )
        row = await cur.fetchone()
        if row and int(row["s"] or 0) == 1:
            return {"sealed": True, "already": True}
        uids = await self._member_ids(hh_id)
        if user_id not in uids:
            raise VaultRequiredError()
        n = 0
        if uids:
            placeholders = ",".join("?" * len(uids))
            cur = await self.db.execute(
                f"SELECT * FROM transactions WHERE user_id IN ({placeholders})",
                tuple(uids),
            )
            for r in await cur.fetchall():
                d = dict(r)
                if d.get("vault_blob"):
                    continue
                packed = pack_money(
                    dek,
                    amount=int(d.get("amount") or 0),
                    description=d.get("description") or "",
                    note=d.get("note") or "",
                    category_id=d.get("category_id"),
                    category_name=d.get("category_name") or "",
                )
                await self.db.execute(
                    """UPDATE transactions
                       SET vault_blob=?, amount_ord=?, category_trace=?,
                           amount=0, description='', note='', category_name='',
                           category_id=NULL
                       WHERE id=?""",
                    (
                        packed["vault_blob"],
                        packed["amount_ord"],
                        packed.get("category_trace") or "",
                        d["id"],
                    ),
                )
                n += 1
        await self.db.execute(
            "UPDATE households SET vault_sealed = 1 WHERE id = ?",
            (hh_id,),
        )
        return {"sealed": True, "already": False, "transactions": n}

    async def put_wrap(
        self, user_id: int, wrapped_dek: str, kdf_salt: str, kdf_params: str
    ) -> dict:
        hh_id = current_household_id()
        if hh_id is None:
            raise VaultRequiredError()
        await self.db.execute(
            """INSERT INTO household_key_wraps
               (household_id, user_id, wrapped_dek, kdf_salt, kdf_params)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT (household_id, user_id) DO UPDATE SET
                 wrapped_dek = EXCLUDED.wrapped_dek,
                 kdf_salt = EXCLUDED.kdf_salt,
                 kdf_params = EXCLUDED.kdf_params""",
            (hh_id, user_id, wrapped_dek, kdf_salt, kdf_params),
        )
        return {"ok": True}

    async def get_wrap(self, user_id: int) -> dict | None:
        hh_id = current_household_id()
        if hh_id is None:
            return None
        cur = await self.db.execute(
            """SELECT wrapped_dek, kdf_salt, kdf_params
               FROM household_key_wraps
               WHERE household_id = ? AND user_id = ?""",
            (hh_id, user_id),
        )
        row = await cur.fetchone()
        return dict(row) if row else None

    async def put_pubkey(self, user_id: int, public_key: str) -> dict:
        hh_id = current_household_id()
        if hh_id is None:
            raise VaultRequiredError()
        await self.db.execute(
            """INSERT INTO household_vault_pubkeys (user_id, household_id, public_key)
               VALUES (?, ?, ?)
               ON CONFLICT (user_id) DO UPDATE SET
                 household_id = EXCLUDED.household_id,
                 public_key = EXCLUDED.public_key""",
            (user_id, hh_id, public_key),
        )
        return {"ok": True}

    async def list_pubkeys(self, user_id: int) -> list[dict]:
        hh_id = current_household_id()
        if hh_id is None:
            return []
        cur = await self.db.execute(
            """SELECT user_id, public_key FROM household_vault_pubkeys
               WHERE household_id = ? AND user_id != ?""",
            (hh_id, user_id),
        )
        return [dict(r) for r in await cur.fetchall()]

    async def put_share(self, user_id: int, target_user_id: int, boxed_dek: str) -> dict:
        hh_id = current_household_id()
        if hh_id is None or current_dek() is None:
            raise VaultRequiredError()
        await self.db.execute(
            """INSERT INTO household_key_wraps
               (household_id, user_id, wrapped_dek, kdf_salt, kdf_params)
               VALUES (?, ?, ?, 'x25519', 'share')
               ON CONFLICT (household_id, user_id) DO UPDATE SET
                 wrapped_dek = EXCLUDED.wrapped_dek,
                 kdf_salt = EXCLUDED.kdf_salt,
                 kdf_params = EXCLUDED.kdf_params""",
            (hh_id, target_user_id, boxed_dek),
        )
        return {"ok": True}
