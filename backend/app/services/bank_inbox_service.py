"""Bank notification inbox — drafts until the user confirms."""
from __future__ import annotations

from datetime import datetime, timezone

from app.services.bank_parser import fingerprint, parse_notification


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
        return _item(dict(row))

    async def list_items(self, user_id: int, status: str = "pending") -> dict:
        allowed = {"pending", "confirmed", "rejected"}
        if status not in allowed:
            raise BankInboxError("Status gak dikenal")
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
        return {
            "items": [_item(dict(r)) for r in rows],
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

    async def confirm(self, item_id: int, user_id: int, category_id: int | None) -> dict:
        row = await self._get_owned(item_id, user_id)
        if row["status"] != "pending":
            raise BankInboxError("Draf ini sudah diproses")
        if not row.get("parsed") or not row.get("amount"):
            raise BankInboxError("Nominal belum kebaca, isi manual dulu")
        txn_type = row.get("txn_type") or "expense"
        cat_id = category_id
        if cat_id is None:
            cat_id = await self._default_category(txn_type)
        cat = await (
            await self.db.execute(
                "SELECT id, name FROM categories WHERE id = ?",
                (cat_id,),
            )
        ).fetchone()
        if not cat:
            raise BankInboxError("Kategori gak ketemu", 404)
        date = (row.get("posted_at") or _now())[:10]
        desc = (row.get("merchant") or "").strip() or f"Notif {row.get('bank') or 'bank'}"
        note = f"{row.get('title') or ''} {row.get('text') or ''}".strip()[:500]
        cursor = await self.db.execute(
            """INSERT INTO transactions
               (user_id, category_id, category_name, type, amount, description, note, date, source)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'bank_notif')""",
            (
                user_id,
                cat["id"],
                cat["name"],
                txn_type,
                int(row["amount"]),
                desc[:255],
                note,
                date,
            ),
        )
        txn_id = cursor.lastrowid
        await self.db.execute(
            """UPDATE bank_inbox
               SET status = 'confirmed', transaction_id = ?
               WHERE id = ?""",
            (txn_id, item_id),
        )
        fresh = await self._get_owned(item_id, user_id)
        return _item(fresh)

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
