"""Bank notification inbox — drafts until the user confirms."""
from __future__ import annotations

from datetime import datetime, timezone

from app.services.bank_parser import fingerprint, parse_notification
from app.services.bank_match import find_pair, suggest_category_id


class BankInboxError(Exception):
    def __init__(self, detail: str, status_code: int = 400):
        self.detail = detail
        self.status_code = status_code
        super().__init__(detail)


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def _item(row: dict) -> dict:
    amount = row.get("amount")
    return {
        "id": row["id"],
        "bank": row.get("bank"),
        "package": row["package"],
        "title": row.get("title") or "",
        "text": row.get("text") or "",
        "posted_at": row.get("posted_at") or "",
        "amount": amount,
        "type": row.get("txn_type"),
        "merchant": row.get("merchant") or "",
        "parsed": bool(row.get("parsed")),
        "status": row["status"],
        "transaction_id": row.get("transaction_id"),
        "created_at": row.get("created_at") or "",
        "suggested_category_id": row.get("suggested_category_id"),
        "pair_id": row.get("pair_id"),
        "internal_suggested": bool(row.get("internal_suggested")),
    }


class BankInboxService:
    def __init__(self, db):
        self.db = db

    async def ingest(self, user_id: int, package: str, title: str, text: str, posted_at: str) -> dict:
        parsed = parse_notification(package, title, text)
        if not parsed["bank"]:
            raise BankInboxError("Paket ini bukan app bank yang didukung", 422)
        posted = posted_at.strip() or _now()
        blob = f"{title} {text}".strip()
        fp = fingerprint(package, posted, parsed["amount"], blob)

        existing = await (
            await self.db.execute(
                """SELECT * FROM bank_inbox
                   WHERE user_id = ? AND fingerprint = ?""",
                (user_id, fp),
            )
        ).fetchone()
        if existing:
            listed = await self.list_items(user_id, "pending")
            for it in listed["items"]:
                if it["id"] == existing["id"]:
                    return it
            return _item(dict(existing))

        cursor = await self.db.execute(
            """INSERT INTO bank_inbox
               (user_id, package, bank, title, text, posted_at, amount, txn_type,
                merchant, parsed, status, fingerprint, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)""",
            (
                user_id,
                package,
                parsed["bank"],
                title or "",
                text or "",
                posted,
                parsed["amount"],
                parsed["type"],
                parsed["merchant"],
                1 if parsed["parsed"] else 0,
                fp,
                _now(),
            ),
        )
        new_id = cursor.lastrowid
        row = await (
            await self.db.execute("SELECT * FROM bank_inbox WHERE id = ?", (new_id,))
        ).fetchone()
        listed = await self.list_items(user_id, "pending")
        for it in listed["items"]:
            if it["id"] == new_id:
                return it
        return _item(dict(row))

    async def list_items(self, user_id: int, status: str = "all") -> dict:
        allowed = {"pending", "confirmed", "rejected", "all"}
        if status not in allowed:
            raise BankInboxError("Status gak dikenal")
        if status == "all":
            rows = await (
                await self.db.execute(
                    """SELECT * FROM bank_inbox
                       WHERE user_id = ?
                       ORDER BY CASE status
                            WHEN 'pending' THEN 0
                            WHEN 'confirmed' THEN 1
                            ELSE 2
                       END,
                       posted_at DESC, id DESC""",
                    (user_id,),
                )
            ).fetchall()
        else:
            rows = await (
                await self.db.execute(
                    """SELECT * FROM bank_inbox
                       WHERE user_id = ? AND status = ?
                       ORDER BY posted_at DESC, id DESC""",
                    (user_id, status),
                )
            ).fetchall()
        count_row = await (
            await self.db.execute(
                """SELECT COUNT(*) AS cnt FROM bank_inbox
                   WHERE user_id = ? AND status = 'pending'""",
                (user_id,),
            )
        ).fetchone()
        pending = int(count_row["cnt"] if count_row else 0)
        raw_items = [dict(r) for r in rows]
        cats = await self._category_rows()
        items = []
        for d in raw_items:
            blob = f"{d.get('title') or ''} {d.get('text') or ''} {d.get('merchant') or ''}"
            ttype = d.get("txn_type") or "expense"
            sug = suggest_category_id(cats, blob, ttype)
            pair = find_pair(raw_items, d) if d.get("status") == "pending" else None
            d["suggested_category_id"] = sug
            d["pair_id"] = pair
            d["internal_suggested"] = pair is not None
            items.append(_item(d))
        return {
            "items": items,
            "pending_count": pending,
        }

    async def _get_owned(self, item_id: int, user_id: int) -> dict:
        row = await (
            await self.db.execute(
                "SELECT * FROM bank_inbox WHERE id = ? AND user_id = ?",
                (item_id, user_id),
            )
        ).fetchone()
        if not row:
            raise BankInboxError("Draf gak ketemu", 404)
        return dict(row)

    async def _default_category(self, txn_type: str) -> int:
        row = await (
            await self.db.execute(
                """SELECT id FROM categories
                   WHERE type = ?
                   ORDER BY is_default DESC, sort_order ASC, id ASC
                   LIMIT 1""",
                (txn_type,),
            )
        ).fetchone()
        if not row:
            raise BankInboxError("Belum ada kategori buat jenis ini")
        return int(row["id"])

    async def confirm(
        self,
        item_id: int,
        user_id: int,
        category_id: int | None,
        internal: bool = False,
        pair_id: int | None = None,
    ) -> dict:
        if internal:
            return await self._confirm_internal(item_id, user_id, pair_id)
        row = await self._get_owned(item_id, user_id)
        if row["status"] != "pending":
            raise BankInboxError("Draf ini sudah diproses")
        if not row.get("parsed") or not row.get("amount"):
            raise BankInboxError("Nominal belum kebaca, isi manual dulu")
        txn_type = row.get("txn_type") or "expense"
        cat_id = category_id
        if cat_id is None:
            blob = f"{row.get('title') or ''} {row.get('text') or ''} {row.get('merchant') or ''}"
            cats = await self._category_rows()
            cat_id = suggest_category_id(cats, blob, txn_type)
        if cat_id is None:
            cat_id = await self._lainnya_category(txn_type)
        return await self._write_txn(row, user_id, cat_id, "bank_notif")

    async def _lainnya_category(self, txn_type: str) -> int:
        row = await (
            await self.db.execute(
                "SELECT id FROM categories WHERE name = 'Lainnya' AND type = ? LIMIT 1",
                (txn_type,),
            )
        ).fetchone()
        if row:
            return int(row["id"])
        return await self._default_category(txn_type)

    async def _write_txn(self, row: dict, user_id: int, cat_id: int, source: str) -> dict:
        cat = await (
            await self.db.execute(
                "SELECT id, name FROM categories WHERE id = ?",
                (cat_id,),
            )
        ).fetchone()
        if not cat:
            raise BankInboxError("Kategori gak ketemu", 404)
        txn_type = row.get("txn_type") or "expense"
        date = (row.get("posted_at") or _now())[:10]
        desc = (row.get("merchant") or "").strip() or f"Notif {row.get('bank') or 'bank'}"
        note = f"{row.get('title') or ''} {row.get('text') or ''}".strip()[:500]
        cursor = await self.db.execute(
            """INSERT INTO transactions
               (user_id, category_id, category_name, type, amount, description, note, date, source)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                user_id,
                cat["id"],
                cat["name"],
                txn_type,
                int(row["amount"]),
                desc[:255],
                note,
                date,
                source,
            ),
        )
        txn_id = cursor.lastrowid
        await self.db.execute(
            """UPDATE bank_inbox
               SET status = 'confirmed', transaction_id = ?
               WHERE id = ?""",
            (txn_id, row["id"]),
        )
        fresh = await self._get_owned(row["id"], user_id)
        return _item(fresh)

    async def _confirm_internal(self, item_id: int, user_id: int, pair_id: int | None) -> dict:
        if not pair_id:
            raise BankInboxError("Pasangan transfer gak ada")
        row = await self._get_owned(item_id, user_id)
        other = await self._get_owned(pair_id, user_id)
        if find_pair([row, other], row) != pair_id:
            raise BankInboxError("Ini bukan transfer antar rekening sendiri")
        exp_id = await self._transfer_category("expense")
        inc_id = await self._transfer_category("income")
        first = row if (row.get("txn_type") or "expense") == "expense" else other
        second = other if first is row else row
        await self._write_txn(first, user_id, exp_id if (first.get("txn_type") or "expense") == "expense" else inc_id, "internal_transfer")
        await self._write_txn(second, user_id, exp_id if (second.get("txn_type") or "expense") == "expense" else inc_id, "internal_transfer")
        fresh = await self._get_owned(item_id, user_id)
        return _item(fresh)

    async def _transfer_category(self, ttype: str) -> int:
        row = await (
            await self.db.execute(
                "SELECT id FROM categories WHERE name = ? AND type = ?",
                ("Transfer", ttype),
            )
        ).fetchone()
        if row:
            return int(row["id"])
        return await self._default_category(ttype)

    async def _category_rows(self) -> list[dict]:
        rows = await (
            await self.db.execute(
                "SELECT id, name, type, keywords FROM categories"
            )
        ).fetchall()
        return [dict(r) for r in rows]

    async def reject(self, item_id: int, user_id: int) -> dict:
        row = await self._get_owned(item_id, user_id)
        if row["status"] != "pending":
            raise BankInboxError("Draf ini sudah diproses")
        await self.db.execute(
            "UPDATE bank_inbox SET status = 'rejected' WHERE id = ?",
            (item_id,),
        )
        fresh = await self._get_owned(item_id, user_id)
        return _item(fresh)

    async def delete_item(self, item_id: int, user_id: int) -> None:
        row = await self._get_owned(item_id, user_id)
        await self.db.execute(
            "DELETE FROM bank_inbox WHERE id = ?",
            (row["id"],),
        )
