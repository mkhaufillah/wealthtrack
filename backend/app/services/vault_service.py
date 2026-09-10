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
            cur = await self.db.execute(
                f"SELECT * FROM budgets WHERE user_id IN ({placeholders})",
                tuple(uids),
            )
            for r in await cur.fetchall():
                d = dict(r)
                if d.get("vault_blob"):
                    continue
                packed = pack_money(
                    dek,
                    amount=int(d.get("budget_amount") or 0),
                    category_id=d.get("category_id"),
                    category_name=d.get("category_name") or "",
                )
                await self.db.execute(
                    """UPDATE budgets SET vault_blob=?, amount_ord=?, category_trace=?,
                           budget_amount=0, category_name=? WHERE id=?""",
                    (
                        packed["vault_blob"],
                        packed["amount_ord"],
                        packed.get("category_trace") or "",
                        packed.get("category_name") or "",
                        d["id"],
                    ),
                )
            cur = await self.db.execute(
                f"SELECT * FROM bank_inbox WHERE user_id IN ({placeholders})",
                tuple(uids),
            )
            for r in await cur.fetchall():
                d = dict(r)
                if d.get("vault_blob"):
                    continue
                packed = pack_money(
                    dek,
                    amount=int(d.get("amount") or 0),
                    extra={
                        "title": d.get("title") or "",
                        "text": d.get("text") or "",
                        "merchant": d.get("merchant") or "",
                    },
                )
                await self.db.execute(
                    """UPDATE bank_inbox SET vault_blob=?, amount_ord=?,
                           amount=0, title='', text='', merchant='' WHERE id=?""",
                    (packed["vault_blob"], packed["amount_ord"], d["id"]),
                )
            await self._seal_named(
                dek,
                f"SELECT * FROM kpr_simulations WHERE user_id IN ({placeholders})",
                tuple(uids),
                amount_key="total_loan",
                extra_keys=("name", "property_price", "down_payment", "total_loan"),
                wipe="""UPDATE kpr_simulations SET vault_blob=?, amount_ord=?,
                    name='', property_price=0, down_payment=0, total_loan=0 WHERE id=?""",
            )
            await self._seal_named(
                dek,
                f"""SELECT kep.* FROM kpr_extra_payments kep
                    JOIN kpr_simulations ks ON ks.id = kep.simulation_id
                    WHERE ks.user_id IN ({placeholders})""",
                tuple(uids),
                amount_key="amount",
                extra_keys=(
                    "amount",
                    "old_remaining_balance",
                    "new_remaining_balance",
                    "old_installment",
                    "new_installment",
                    "total_interest_saved",
                ),
                wipe="UPDATE kpr_extra_payments SET vault_blob=?, amount_ord=?, amount=0 WHERE id=?",
            )
            await self._seal_named(
                dek,
                f"""SELECT kms.* FROM kpr_monthly_schedules kms
                    JOIN kpr_simulations ks ON ks.id = kms.simulation_id
                    WHERE ks.user_id IN ({placeholders})""",
                tuple(uids),
                amount_key="remaining_balance",
                extra_keys=("payment", "principal", "interest", "remaining_balance"),
                wipe="""UPDATE kpr_monthly_schedules SET vault_blob=?, amount_ord=?,
                    payment=0, principal=0, interest=0, remaining_balance=0 WHERE id=?""",
            )
            await self._seal_named(
                dek,
                f"SELECT * FROM credit_cards WHERE user_id IN ({placeholders})",
                tuple(uids),
                amount_key="credit_limit",
                extra_keys=("name", "credit_limit"),
                wipe="UPDATE credit_cards SET vault_blob=?, amount_ord=?, name='', credit_limit=0 WHERE id=?",
            )
            await self._seal_named(
                dek,
                f"""SELECT cct.* FROM credit_card_transactions cct
                    JOIN credit_cards cc ON cc.id = cct.card_id
                    WHERE cc.user_id IN ({placeholders})""",
                tuple(uids),
                amount_key="amount",
                extra_keys=("amount", "description"),
                wipe="UPDATE credit_card_transactions SET vault_blob=?, amount_ord=?, amount=0, description='' WHERE id=?",
            )
            await self._seal_named(
                dek,
                f"""SELECT cci.* FROM credit_card_installments cci
                    JOIN credit_cards cc ON cc.id = cci.card_id
                    WHERE cc.user_id IN ({placeholders})""",
                tuple(uids),
                amount_key="monthly_amount",
                extra_keys=("monthly_amount", "total_amount", "description"),
                wipe="""UPDATE credit_card_installments SET vault_blob=?, amount_ord=?,
                    monthly_amount=0, total_amount=0, description='' WHERE id=?""",
            )
            await self._seal_named(
                dek,
                f"SELECT * FROM ai_messages WHERE user_id IN ({placeholders})",
                tuple(uids),
                amount_key="amount",
                extra_keys=("content",),
                wipe="UPDATE ai_messages SET vault_blob=?, content='' WHERE id=?",
                skip_ord=True,
            )
            await self._seal_named(
                dek,
                f"SELECT * FROM ai_chat_summaries WHERE user_id IN ({placeholders})",
                tuple(uids),
                amount_key="amount",
                extra_keys=("summary",),
                wipe="UPDATE ai_chat_summaries SET vault_blob=?, summary='' WHERE user_id=?",
                skip_ord=True,
                id_key="user_id",
            )
        await self.db.execute(
            "UPDATE households SET vault_sealed = 1 WHERE id = ?",
            (hh_id,),
        )
        return {"sealed": True, "already": False, "transactions": n}

    async def _seal_named(
        self,
        dek: bytes,
        select_sql: str,
        params: tuple,
        *,
        amount_key: str,
        extra_keys: tuple[str, ...],
        wipe: str,
        skip_ord: bool = False,
        id_key: str = "id",
    ) -> None:
        cur = await self.db.execute(select_sql, params)
        for r in await cur.fetchall():
            d = dict(r)
            if d.get("vault_blob"):
                continue
            extra = {k: d.get(k) for k in extra_keys}
            packed = pack_money(
                dek,
                amount=int(d.get(amount_key) or 0),
                extra=extra,
            )
            if skip_ord:
                await self.db.execute(wipe, (packed["vault_blob"], d[id_key]))
            else:
                await self.db.execute(
                    wipe,
                    (packed["vault_blob"], packed["amount_ord"], d[id_key]),
                )

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
               WHERE household_id = ? AND user_id = ?
                 AND COALESCE(kdf_params, '') <> 'share'""",
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
                 kdf_params = EXCLUDED.kdf_params
               WHERE household_key_wraps.kdf_params = 'share'""",
            (hh_id, target_user_id, boxed_dek),
        )
        return {"ok": True}

    async def get_share(self, user_id: int) -> dict | None:
        hh_id = current_household_id()
        if hh_id is None:
            return None
        cur = await self.db.execute(
            """SELECT wrapped_dek AS boxed_dek, kdf_salt, kdf_params
               FROM household_key_wraps
               WHERE household_id = ? AND user_id = ?
                 AND kdf_params = 'share'""",
            (hh_id, user_id),
        )
        row = await cur.fetchone()
        return dict(row) if row else None
