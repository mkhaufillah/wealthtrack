"""Transaction service — pure business logic, no FastAPI dependency.

Encapsulates all transaction CRUD, pagination, search (Meilisearch + SQL LIKE
fallback), owner transfer, and balance transfer logic.
"""

from __future__ import annotations

import logging
from typing import Optional

from app.database import CursorWrapper
from app.core.vault_query import append_category_filter
from app.core.meilisearch import (
    index_document,
    delete_document,
    search_descriptions,
    get_total_count as meili_total_count,
)
from app.schemas.transaction import (
    TransactionCreate,
    TransactionUpdate,
    TransferOwnerIn,
    TransferRequest,
    PaginatedTransactions,
    PaginationMeta,
)

logger = logging.getLogger(__name__)


# ── Domain exceptions ───────────────────────────────────────────────


class TransactionNotFoundError(Exception):
    """Raised when a transaction does not exist or does not belong to the user."""

    def __init__(self, txn_id: int) -> None:
        self.txn_id = txn_id
        super().__init__(f"Transaction {txn_id} not found")


class CategoryNotFoundError(Exception):
    """Raised when a category does not exist."""

    def __init__(self, category_id: int) -> None:
        self.category_id = category_id
        super().__init__(f"Category {category_id} not found")


class NotHouseholdMemberError(Exception):
    """Raised when the user is not a member of any household."""

    def __init__(self, detail: str = "Not a member of any household") -> None:
        self.detail = detail
        super().__init__(detail)


class ForbiddenError(Exception):
    """Raised when the user lacks permission for an operation."""

    def __init__(self, detail: str = "Forbidden") -> None:
        self.detail = detail
        super().__init__(detail)


class NoFieldsToUpdateError(Exception):
    """Raised when an update request provides no fields to change."""

    def __init__(self) -> None:
        super().__init__("Gak ada yang diubah")


class InvalidOperationError(Exception):
    """Raised when a business-rule violation occurs."""

    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(detail)


# ── Helpers ─────────────────────────────────────────────────────────


def _format_txn(row, cat_name="", cat_icon="", display_name=""):
    """Convert an asyncpg Record (or dict) to the standard transaction dict."""
    from app.core.vault_ctx import current_dek
    from app.core.vault_row import unpack_money

    r = unpack_money(current_dek(), dict(row))
    return {
        "id": r["id"],
        "amount": int(r.get("amount") or 0),
        "type": r["type"],
        "description": r.get("description", "") or "",
        "note": r.get("note", "") or "",
        "date": r.get("date") or r["created_at"][:10],
        "category": {
            "id": r["category_id"],
            "name": cat_name or r.get("category_name", "") or "",
            "icon": cat_icon or "",
            "copy_key": r.get("cat_copy_key") or "",
        },
        "user": {
            "id": r.get("user_id", 1) or 1,
            "display_name": display_name or r.get("user_display_name", ""),
        },
        "created_at": r["created_at"],
        "updated_at": r.get("updated_at", r["created_at"]),
    }


# ── SQL helpers (shared query fragments) ─────────────────────────────


_SELECT_TXN = """\
SELECT t.id, t.type, t.category_id,
       t.date, t.user_id, t.created_at, t.source,
       t.vault_blob, t.amount_ord, t.category_trace,
       c.name AS cat_name, c.icon AS cat_icon, c.copy_key AS cat_copy_key,
       u.display_name AS user_display_name
FROM transactions t
LEFT JOIN categories c ON t.category_id = c.id
LEFT JOIN users u ON t.user_id = u.id"""

_ORDER_MAP = {
    "date": "COALESCE(t.date, LEFT(t.created_at::text, 10)) ASC",
    "-date": "COALESCE(t.date, LEFT(t.created_at::text, 10)) DESC",
    "amount": "t.amount_ord ASC NULLS LAST",
    "-amount": "t.amount_ord DESC NULLS LAST",
}

_DATE_COALESCE = "COALESCE(t.date, LEFT(t.created_at::text, 10))"


# ── Service ─────────────────────────────────────────────────────────


class TransactionService:
    """Service layer for transaction operations.

    Instantiated with a ``CursorWrapper`` obtained from the FastAPI
    ``get_db`` dependency.  All business logic lives here, not in the
    router.
    """

    def __init__(self, db: CursorWrapper = None) -> None:
        self.db = db

    # ── Household helpers ────────────────────────────────────────────

    async def _get_user_household(self, user_id: int) -> tuple[int, str]:
        """Return (household_id, role) for the user.

        Raises NotHouseholdMemberError if the user is not in any household.
        """
        if self.db is None:
            raise NotHouseholdMemberError()
        cursor = await self.db.execute(
            "SELECT household_id, role FROM household_members WHERE user_id = ?",
            (user_id,),
        )
        hm = await cursor.fetchone()
        if not hm:
            raise NotHouseholdMemberError()
        return hm["household_id"], hm["role"]

    async def _get_category(self, category_id: int) -> dict | None:
        cursor = await self.db.execute(
            "SELECT id, name, icon FROM categories WHERE id = ?",
            (category_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def _index_meili(self, txn: dict) -> None:
        """Best-effort index a transaction dict in Meilisearch."""
        try:
            await index_document(txn)
        except Exception as e:
            logger.warning("Meilisearch indexing error: %s", e)

    async def _remove_from_meili(self, txn_id: int) -> None:
        """Best-effort remove a transaction from Meilisearch."""
        try:
            await delete_document(txn_id)
        except Exception as e:
            logger.warning("Meilisearch delete error: %s", e)

    # ── Household listing ───────────────────────────────────────────

    async def list_household_transactions(
        self,
        user_id: int,
        page: int = 1,
        per_page: int = 100,
        type: str | None = None,
        date_from: str | None = None,
        date_to: str | None = None,
        sort: str = "-date",
    ) -> PaginatedTransactions:
        """Get transactions of all household members."""
        household_id, _ = await self._get_user_household(user_id)

        where = ["hm2.household_id = ?"]
        params: list = [household_id]
        if type:
            where.append("t.type = ?")
            params.append(type)
        if date_from:
            where.append(f"{_DATE_COALESCE} >= ?")
            params.append(date_from)
        if date_to:
            where.append(f"{_DATE_COALESCE} <= ?")
            params.append(date_to)

        order = _ORDER_MAP.get(sort, f"{_DATE_COALESCE} DESC")
        join_clause = "JOIN household_members hm2 ON hm2.user_id = t.user_id"

        cursor = await self.db.execute(
            f"SELECT COUNT(*) as count FROM ({_SELECT_TXN} {join_clause} WHERE {' AND '.join(where)}) AS sub",
            params,
        )
        row = await cursor.fetchone()
        total = row["count"] if row else 0

        offset = (page - 1) * per_page
        cursor = await self.db.execute(
            f"""{_SELECT_TXN}
            {join_clause}
            WHERE {' AND '.join(where)}
            ORDER BY {order}
            LIMIT ? OFFSET ?""",
            params + [per_page, offset],
        )
        rows = await cursor.fetchall()
        data = [
            _format_txn(r, r["cat_name"] or "", r["cat_icon"] or "")
            for r in rows
        ]

        return PaginatedTransactions(
            data=data,
            meta=PaginationMeta(
                page=page,
                per_page=per_page,
                total=total,
                total_pages=max(1, (total + per_page - 1) // per_page),
            ),
        )

    # ── User listing (with Meilisearch search) ───────────────────────

    async def list_transactions(
        self,
        user_id: int,
        page: int = 1,
        per_page: int = 50,
        type: str | None = None,
        category_id: int | None = None,
        date_from: str | None = None,
        date_to: str | None = None,
        sort: str = "-date",
        q: str | None = None,
        category_ids: str | None = None,
    ) -> PaginatedTransactions:
        """List user's transactions with optional search (Meilisearch + SQL fallback)."""
        # ── If search query provided, use Meilisearch ──
        if q and q.strip():
            return await self._search_vault(
                user_id, q.strip(), page, per_page,
                type, category_id, date_from, date_to, sort, category_ids,
            )

        # ── No search query — use direct SQL ──
        return await self._list_with_sql(
            user_id, page, per_page,
            type, category_id, date_from, date_to, sort, category_ids,
        )

    async def _search_vault(
        self,
        user_id: int,
        q: str,
        page: int,
        per_page: int,
        type: str | None,
        category_id: int | None,
        date_from: str | None,
        date_to: str | None,
        sort: str,
        category_ids: str | None,
    ) -> PaginatedTransactions:
        """Decrypt-then-filter. Meili has no description after seal."""
        batch = await self._list_with_sql(
            user_id, 1, 5000,
            type, category_id, date_from, date_to, sort, category_ids,
        )
        needle = q.lower()

        def _hay(row) -> str:
            if isinstance(row, dict):
                cat = row.get("category") or {}
                return f"{row.get('description') or ''} {row.get('note') or ''} {cat.get('name') or ''}"
            cat = getattr(row, "category", None)
            name = getattr(cat, "name", "") if cat is not None else ""
            return f"{getattr(row, 'description', '')} {getattr(row, 'note', '')} {name}"

        matched = [row for row in batch.data if needle in _hay(row).lower()]
        total = len(matched)
        start = (page - 1) * per_page
        page_rows = matched[start:start + per_page]
        return PaginatedTransactions(
            data=page_rows,
            meta=PaginationMeta(
                page=page,
                per_page=per_page,
                total=total,
                total_pages=max(1, (total + per_page - 1) // per_page) if total else 0,
            ),
        )

    async def _search_with_meili(
        self,
        user_id: int,
        q: str,
        page: int,
        per_page: int,
        type: str | None,
        category_id: int | None,
        date_from: str | None,
        date_to: str | None,
        sort: str,
        category_ids: str | None,
    ) -> PaginatedTransactions:
        """Search via Meilisearch, falling back to SQL LIKE on failure."""
        meili_filters: list[str] = [f"user_id = {user_id}"]
        if type:
            meili_filters.append(f'type = "{type}"')
        if category_ids:
            ids = [int(x.strip()) for x in category_ids.split(",") if x.strip().isdigit()]
            if ids:
                meili_filters.append(
                    f"category_id IN [{', '.join(str(i) for i in ids)}]"
                )
        elif category_id:
            meili_filters.append(f"category_id = {category_id}")
        if date_from:
            meili_filters.append(f'date >= "{date_from}"')
        if date_to:
            meili_filters.append(f'date <= "{date_to}"')

        sort_map = {
            "date": ["date:asc"],
            "-date": ["date:desc"],
            "amount": ["amount:asc"],
            "-amount": ["amount:desc"],
            "name": ["description:asc"],
            "-name": ["description:desc"],
        }
        meili_sort = sort_map.get(sort)

        offset = (page - 1) * per_page

        try:
            total = await meili_total_count(q, meili_filters or None)
            matching_ids = await search_descriptions(
                q,
                filters=meili_filters or None,
                sort=meili_sort,
                offset=offset,
                limit=per_page,
            )
        except Exception:
            # Meilisearch unavailable — fall back to SQL LIKE
            return await self._sql_like_fallback(
                user_id, q, page, per_page,
                type, category_id, date_from, date_to, sort, category_ids,
            )

        if not matching_ids:
            return PaginatedTransactions(
                data=[],
                meta=PaginationMeta(page=page, per_page=per_page, total=0, total_pages=0),
            )

        # Fetch from PostgreSQL preserving Meilisearch order
        placeholders = ",".join("?" for _ in matching_ids)
        order_clause = (
            f"array_position(ARRAY[{placeholders}]::int[], t.id)"
        )

        cursor = await self.db.execute(
            f"""{_SELECT_TXN}
            WHERE t.id IN ({placeholders})
            ORDER BY {order_clause}""",
            *matching_ids, *matching_ids,
        )
        rows = await cursor.fetchall()
        data = [
            _format_txn(r, r["cat_name"] or "", r["cat_icon"] or "")
            for r in rows
        ]

        return PaginatedTransactions(
            data=data,
            meta=PaginationMeta(
                page=page,
                per_page=per_page,
                total=total,
                total_pages=max(1, (total + per_page - 1) // per_page),
            ),
        )

    async def _sql_like_fallback(
        self,
        user_id: int,
        q: str,
        page: int,
        per_page: int,
        type: str | None,
        category_id: int | None,
        date_from: str | None,
        date_to: str | None,
        sort: str,
        category_ids: str | None,
    ) -> PaginatedTransactions:
        """SQL LIKE fallback when Meilisearch is unavailable."""
        where = ["t.user_id = ?"]
        params: list = [user_id]
        if type:
            where.append("t.type = ?")
            params.append(type)
        append_category_filter(where, params, category_id, category_ids)
        if date_from:
            where.append(f"{_DATE_COALESCE} >= ?")
            params.append(date_from)
        if date_to:
            where.append(f"{_DATE_COALESCE} <= ?")
            params.append(date_to)
        # description lives in vault_blob; LIKE plaintext is gone.

        order = _ORDER_MAP.get(sort, f"{_DATE_COALESCE} DESC")

        cursor = await self.db.execute(
            f"SELECT COUNT(*) as count FROM transactions t WHERE {' AND '.join(where)}",
            params,
        )
        row = await cursor.fetchone()
        total = row["count"] if row else 0

        offset = (page - 1) * per_page
        cursor = await self.db.execute(
            f"""{_SELECT_TXN}
            WHERE {' AND '.join(where)}
            ORDER BY {order}
            LIMIT ? OFFSET ?""",
            params + [per_page, offset],
        )
        rows = await cursor.fetchall()
        data = [
            _format_txn(r, r["cat_name"] or "", r["cat_icon"] or "")
            for r in rows
        ]

        return PaginatedTransactions(
            data=data,
            meta=PaginationMeta(
                page=page,
                per_page=per_page,
                total=total,
                total_pages=max(1, (total + per_page - 1) // per_page),
            ),
        )

    async def _list_with_sql(
        self,
        user_id: int,
        page: int,
        per_page: int,
        type: str | None,
        category_id: int | None,
        date_from: str | None,
        date_to: str | None,
        sort: str,
        category_ids: str | None,
    ) -> PaginatedTransactions:
        """Direct SQL listing (no search query)."""
        where = ["t.user_id = ?"]
        params: list = [user_id]
        if type:
            where.append("t.type = ?")
            params.append(type)
        append_category_filter(where, params, category_id, category_ids)
        if date_from:
            where.append(f"{_DATE_COALESCE} >= ?")
            params.append(date_from)
        if date_to:
            where.append(f"{_DATE_COALESCE} <= ?")
            params.append(date_to)

        order = _ORDER_MAP.get(sort, f"{_DATE_COALESCE} DESC")

        cursor = await self.db.execute(
            f"SELECT COUNT(*) as count FROM transactions t WHERE {' AND '.join(where)}", params
        )
        row = await cursor.fetchone()
        total = row["count"] if row else 0

        offset = (page - 1) * per_page
        cursor = await self.db.execute(
            f"""{_SELECT_TXN}
            WHERE {' AND '.join(where)}
            ORDER BY {order}
            LIMIT ? OFFSET ?""",
            params + [per_page, offset],
        )
        rows = await cursor.fetchall()
        data = [
            _format_txn(r, r["cat_name"] or "", r["cat_icon"] or "")
            for r in rows
        ]

        return PaginatedTransactions(
            data=data,
            meta=PaginationMeta(
                page=page,
                per_page=per_page,
                total=total,
                total_pages=max(1, (total + per_page - 1) // per_page),
            ),
        )

    # ── CRUD ─────────────────────────────────────────────────────────

    async def create_transaction(
        self, data: TransactionCreate, user_id: int
    ) -> dict:
        """Create a new transaction.

        Returns the formatted transaction dict.
        """
        cat = await self._get_category(data.category_id)
        if not cat:
            raise CategoryNotFoundError(data.category_id)

        from app.core.vault_write import pack_txn

        packed = pack_txn(
            amount=int(data.amount),
            description=data.description or "",
            note=data.note or "",
            category_id=data.category_id,
            category_name=cat["name"],
        )
        cursor = await self.db.execute(
            """INSERT INTO transactions
               (user_id, category_id, type, date, source,
                vault_blob, amount_ord, category_trace)
               VALUES (?, ?, ?, ?, 'manual', ?, ?, ?)""",
            (
                user_id,
                packed.get("category_id"),
                data.type,
                data.date,
                packed["vault_blob"],
                packed["amount_ord"],
                packed.get("category_trace") or "",
            ),
        )
        new_id = cursor.lastrowid

        cursor = await self.db.execute(
            "SELECT * FROM transactions WHERE id = ?", (new_id,)
        )
        row = await cursor.fetchone()

        u = await (
            await self.db.execute(
                "SELECT display_name FROM users WHERE id = ?", (user_id,)
            )
        ).fetchone()

        txn_dict = _format_txn(
            row,
            cat["name"],
            cat["icon"],
            u["display_name"] if u else "",
        )

        await self._index_meili(dict(row))
        return txn_dict

    async def get_transaction(
        self, txn_id: int, user_id: int
    ) -> dict:
        """Get a single transaction by ID (scoped to the user)."""
        cursor = await self.db.execute(
            f"""{_SELECT_TXN}
            WHERE t.id = ? AND t.user_id = ?""",
            (txn_id, user_id),
        )
        row = await cursor.fetchone()
        if not row:
            raise TransactionNotFoundError(txn_id)

        c = await self._get_category(row["category_id"])
        return _format_txn(
            row,
            c["name"] if c else "",
            c["icon"] if c else "",
        )

    async def update_transaction(
        self, txn_id: int, data: TransactionUpdate, user_id: int
    ) -> dict:
        """Update an existing transaction.  Returns the updated transaction dict.

        Only the fields provided in ``data`` are changed.
        """
        cursor = await self.db.execute(
            "SELECT id FROM transactions WHERE id = ? AND user_id = ?",
            (txn_id, user_id),
        )
        if not await cursor.fetchone():
            raise TransactionNotFoundError(txn_id)

        from app.core.vault_row import open_row
        from app.core.vault_write import pack_txn

        cur = await self.db.execute("SELECT * FROM transactions WHERE id = ?", (txn_id,))
        current = open_row(dict(await cur.fetchone() or {}))

        updates: dict[str, object] = {}
        for field in ["type", "amount", "description", "note", "category_id", "date"]:
            val = getattr(data, field, None)
            if val is not None:
                if field == "category_id":
                    c = await self._get_category(val)
                    if not c:
                        raise CategoryNotFoundError(val)
                    updates["category_id"] = val
                    updates["category_name"] = c["name"]
                else:
                    updates[field] = val

        if not updates:
            raise NoFieldsToUpdateError()

        merged = {**current, **updates}
        cat_id = merged.get("category_id")
        cat_name = merged.get("category_name") or ""
        if cat_id and not cat_name:
            c = await self._get_category(int(cat_id))
            cat_name = c["name"] if c else ""
        packed = pack_txn(
            amount=int(merged.get("amount") or 0),
            description=merged.get("description") or "",
            note=merged.get("note") or "",
            category_id=int(cat_id) if cat_id is not None else None,
            category_name=cat_name,
        )
        await self.db.execute(
            """UPDATE transactions SET
                 type=?, date=?,
                 vault_blob=?, amount_ord=?, category_trace=?,
                 category_id=?
               WHERE id=?""",
            (
                merged.get("type"),
                merged.get("date"),
                packed["vault_blob"],
                packed["amount_ord"],
                packed.get("category_trace") or "",
                packed.get("category_id"),
                txn_id,
            ),
        )

        cursor = await self.db.execute(
            f"""{_SELECT_TXN}
            WHERE t.id = ?""",
            (txn_id,),
        )
        row = await cursor.fetchone()
        c = await self._get_category(row["category_id"])

        await self._index_meili(dict(row))

        return _format_txn(
            row,
            c["name"] if c else "",
            c["icon"] if c else "",
        )

    # ── Owner transfer ───────────────────────────────────────────────

    async def transfer_owner(
        self, txn_id: int, data: TransferOwnerIn, user_id: int
    ) -> dict:
        """Transfer transaction ownership to another household member.

        Returns the updated transaction dict.
        """
        # 1. Fetch transaction
        cursor = await self.db.execute(
            "SELECT id, user_id FROM transactions WHERE id = ?",
            (txn_id,),
        )
        txn = await cursor.fetchone()
        if not txn:
            raise TransactionNotFoundError(txn_id)

        # 2. Get user's household info
        household_id, role = await self._get_user_household(user_id)

        is_admin = role == "admin"
        is_owner = txn["user_id"] == user_id

        if not (is_owner or is_admin):
            raise ForbiddenError(
                "Only the transaction owner or a household admin can transfer ownership"
            )

        # 3. Validate target user exists in the same household
        cursor = await self.db.execute(
            "SELECT user_id FROM household_members WHERE user_id = ? AND household_id = ?",
            (data.user_id, household_id),
        )
        if not await cursor.fetchone():
            raise InvalidOperationError("Bukan anggota keluarga kamu")

        # 4. Perform transfer
        await self.db.execute(
            "UPDATE transactions SET user_id = ? WHERE id = ?",
            (data.user_id, txn_id),
        )

        # 5. Return updated transaction
        cursor = await self.db.execute(
            f"""{_SELECT_TXN}
            WHERE t.id = ?""",
            (txn_id,),
        )
        row = await cursor.fetchone()
        c = await self._get_category(row["category_id"])

        await self._index_meili(dict(row))

        return _format_txn(
            row,
            c["name"] if c else "",
            c["icon"] if c else "",
        )

    # ── Balance transfer ─────────────────────────────────────────────

    async def transfer_balance(
        self, req: TransferRequest, user_id: int
    ) -> dict:
        """Transfer balance to household members.

        Creates paired expense/income transactions for each recipient.
        Returns ``{"transactions": [{"sender_expense": ..., "recipient_income": ...}, ...]}``.
        """
        # 1. Verify user is in a household
        household_id, _ = await self._get_user_household(user_id)

        # 2. Verify all recipients are in the same household
        recipient_ids = [t.user_id for t in req.transfers]
        placeholders = ",".join("?" for _ in recipient_ids)
        cursor = await self.db.execute(
            f"SELECT user_id FROM household_members WHERE household_id = ? AND user_id IN ({placeholders})",
            (household_id, *recipient_ids),
        )
        valid_ids = {r["user_id"] for r in await cursor.fetchall()}
        for rid in recipient_ids:
            if rid not in valid_ids:
                raise InvalidOperationError(
                    f"User {rid} is not a member of your household"
                )

        # 3. Ensure the special transfer categories exist
        expense_cat = await self._get_or_create_transfer_category("expense")
        income_cat = await self._get_or_create_transfer_category("income")

        expense_cat_id = expense_cat["id"]
        expense_cat_name = expense_cat["name"]
        expense_cat_icon = expense_cat.get("icon", "")
        income_cat_id = income_cat["id"]
        income_cat_name = income_cat["name"]
        income_cat_icon = income_cat.get("icon", "")

        # Get sender's display name
        cursor = await self.db.execute(
            "SELECT display_name FROM users WHERE id = ?", (user_id,)
        )
        sender_row = await cursor.fetchone()
        sender_name = sender_row["display_name"] if sender_row else f"User {user_id}"

        # 4. Create transactions
        results = []
        for t in req.transfers:
            # Get recipient's display name
            cursor = await self.db.execute(
                "SELECT display_name FROM users WHERE id = ?", (t.user_id,)
            )
            recipient_row = await cursor.fetchone()
            recipient_name = (
                recipient_row["display_name"] if recipient_row else f"User {t.user_id}"
            )

            from app.core.vault_write import pack_txn

            packed_exp = pack_txn(
                amount=int(t.amount),
                description=f"Transfer ke {recipient_name}",
                category_id=expense_cat_id,
                category_name=expense_cat_name,
            )
            cursor = await self.db.execute(
                """INSERT INTO transactions
                   (type, category_id, date, user_id, vault_blob, amount_ord, category_trace)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    "expense",
                    packed_exp.get("category_id"),
                    req.date,
                    user_id,
                    packed_exp["vault_blob"],
                    packed_exp["amount_ord"],
                    packed_exp.get("category_trace") or "",
                ),
            )
            expense_id = cursor.lastrowid

            packed_inc = pack_txn(
                amount=int(t.amount),
                description=f"Transfer dari {sender_name}",
                category_id=income_cat_id,
                category_name=income_cat_name,
            )
            cursor = await self.db.execute(
                """INSERT INTO transactions
                   (type, category_id, date, user_id, vault_blob, amount_ord, category_trace)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    "income",
                    packed_inc.get("category_id"),
                    req.date,
                    t.user_id,
                    packed_inc["vault_blob"],
                    packed_inc["amount_ord"],
                    packed_inc.get("category_trace") or "",
                ),
            )
            income_id = cursor.lastrowid

            # Fetch both with JOINs for _format_txn
            cursor = await self.db.execute(
                f"""{_SELECT_TXN}
                WHERE t.id = ?""",
                (expense_id,),
            )
            exp_row = await cursor.fetchone()

            cursor = await self.db.execute(
                f"""{_SELECT_TXN}
                WHERE t.id = ?""",
                (income_id,),
            )
            inc_row = await cursor.fetchone()

            # Index both in Meilisearch
            await self._index_meili(dict(exp_row))
            await self._index_meili(dict(inc_row))

            results.append({
                "sender_expense": _format_txn(
                    exp_row,
                    expense_cat_name,
                    expense_cat_icon,
                    exp_row["user_display_name"] or "",
                ),
                "recipient_income": _format_txn(
                    inc_row,
                    income_cat_name,
                    income_cat_icon,
                    inc_row["user_display_name"] or "",
                ),
            })

        return {"transactions": results}

    async def _get_or_create_transfer_category(self, ttype: str) -> dict:
        """Find the 'Transfer' category for the given type, creating it if missing."""
        cursor = await self.db.execute(
            "SELECT id, name, icon FROM categories WHERE name = ? AND type = ?",
            ("Transfer", ttype),
        )
        cat = await cursor.fetchone()
        if cat:
            return dict(cat)

        await self.db.execute(
            "INSERT INTO categories (name, type, icon, is_default) VALUES (?, ?, ?, ?)",
            ("Transfer", ttype, "strokeRoundedExchange01", 1),
        )
        cursor = await self.db.execute(
            "SELECT id, name, icon FROM categories WHERE name = ? AND type = ?",
            ("Transfer", ttype),
        )
        cat = await cursor.fetchone()
        return dict(cat) if cat else {"id": 0, "name": "Transfer", "icon": "strokeRoundedExchange01"}

    # ── Delete ───────────────────────────────────────────────────────

    async def delete_transaction(self, txn_id: int, user_id: int) -> None:
        """Delete a transaction (scoped to the user).

        Also cleans up associated OCR jobs and removes the document from
        Meilisearch.
        """
        cursor = await self.db.execute(
            "SELECT id FROM transactions WHERE id = ? AND user_id = ?",
            (txn_id, user_id),
        )
        if not await cursor.fetchone():
            raise TransactionNotFoundError(txn_id)

        # Delete associated OCR jobs before deleting transaction
        cursor = await self.db.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema='public' AND table_name='ocr_jobs'"
        )
        if await cursor.fetchone():
            await self.db.execute(
                "DELETE FROM ocr_jobs WHERE transaction_id = ?",
                (txn_id,),
            )

        await self.db.execute(
            "UPDATE bank_inbox SET transaction_id = NULL WHERE transaction_id = ?",
            (txn_id,),
        )

        await self.db.execute(
            "DELETE FROM transactions WHERE id = ?", (txn_id,)
        )

        await self._remove_from_meili(txn_id)
