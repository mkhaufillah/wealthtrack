"""Transaction service — pure business logic, no FastAPI dependency.

Encapsulates all transaction CRUD, pagination, search (Meilisearch + SQL LIKE
fallback), owner transfer, and balance transfer logic.
"""

from __future__ import annotations

import logging
from typing import Optional

from app.database import CursorWrapper
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
        super().__init__("No fields to update")


class InvalidOperationError(Exception):
    """Raised when a business-rule violation occurs."""

    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(detail)


# ── Helpers ─────────────────────────────────────────────────────────


def _format_txn(row, cat_name="", cat_icon="", cat_name_en="", display_name=""):
    """Convert an asyncpg Record (or dict) to the standard transaction dict."""
    r = dict(row)
    return {
        "id": r["id"],
        "amount": int(r["amount"]),
        "type": r["type"],
        "description": r.get("description", "") or "",
        "note": r.get("note", "") or "",
        "date": r.get("date") or r["created_at"][:10],
        "category": {
            "id": r["category_id"],
            "name": cat_name or r.get("category_name", "") or "",
            "icon": cat_icon or "",
            "name_en": cat_name_en or "",
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
SELECT t.id, t.type, t.amount, t.category_id, t.category_name,
       t.description, t.note, t.date, t.user_id, t.created_at,
       c.name AS cat_name, c.icon AS cat_icon,
       c.name_en AS cat_name_en,
       u.display_name AS user_display_name
FROM transactions t
LEFT JOIN categories c ON t.category_id = c.id
LEFT JOIN users u ON t.user_id = u.id"""

_ORDER_MAP = {
    "date": "COALESCE(t.date, LEFT(t.created_at::text, 10)) ASC",
    "-date": "COALESCE(t.date, LEFT(t.created_at::text, 10)) DESC",
    "amount": "t.amount ASC",
    "-amount": "t.amount DESC",
    "name": "t.description ASC",
    "-name": "t.description DESC",
}

_DATE_COALESCE = "COALESCE(t.date, LEFT(t.created_at::text, 10))"


# ── Service ─────────────────────────────────────────────────────────


class TransactionService:
    """Service layer for transaction operations.

    Instantiated with a ``CursorWrapper`` obtained from the FastAPI
    ``get_db`` dependency.  All business logic lives here, not in the
    router.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    # ── Household helpers ────────────────────────────────────────────

    async def _get_user_household(self, user_id: int) -> tuple[int, str]:
        """Return (household_id, role) for the user.

        Raises NotHouseholdMemberError if the user is not in any household.
        """
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
            "SELECT id, name, name_en, icon FROM categories WHERE id = ?",
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
        join_clause = (
            "FROM transactions t "
            "JOIN household_members hm2 ON hm2.user_id = t.user_id"
        )

        cursor = await self.db.execute(
            f"SELECT COUNT(*) {join_clause} WHERE {' AND '.join(where)}", params
        )
        total = (await cursor.fetchone())[0]

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
            _format_txn(r, r["cat_name"] or "", r["cat_icon"] or "", r["cat_name_en"] or "")
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
            return await self._search_with_meili(
                user_id, q.strip(), page, per_page,
                type, category_id, date_from, date_to, sort, category_ids,
            )

        # ── No search query — use direct SQL ──
        return await self._list_with_sql(
            user_id, page, per_page,
            type, category_id, date_from, date_to, sort, category_ids,
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
            _format_txn(r, r["cat_name"] or "", r["cat_icon"] or "", r["cat_name_en"] or "")
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
        if category_ids:
            ids = [int(x.strip()) for x in category_ids.split(",") if x.strip().isdigit()]
            if ids:
                placeholders = ",".join("?" for _ in ids)
                where.append(f"t.category_id IN ({placeholders})")
                params.extend(ids)
        elif category_id:
            where.append("t.category_id = ?")
            params.append(category_id)
        if date_from:
            where.append(f"{_DATE_COALESCE} >= ?")
            params.append(date_from)
        if date_to:
            where.append(f"{_DATE_COALESCE} <= ?")
            params.append(date_to)
        where.append("t.description LIKE ?")
        params.append(f"%{q}%")

        order = _ORDER_MAP.get(sort, f"{_DATE_COALESCE} DESC")

        cursor = await self.db.execute(
            f"SELECT COUNT(*) FROM transactions t WHERE {' AND '.join(where)}",
            params,
        )
        total = (await cursor.fetchone())[0]

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
            _format_txn(r, r["cat_name"] or "", r["cat_icon"] or "", r["cat_name_en"] or "")
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
        if category_id:
            where.append("t.category_id = ?")
            params.append(category_id)
        if date_from:
            where.append(f"{_DATE_COALESCE} >= ?")
            params.append(date_from)
        if date_to:
            where.append(f"{_DATE_COALESCE} <= ?")
            params.append(date_to)
        if category_ids:
            ids = [int(x.strip()) for x in category_ids.split(",") if x.strip().isdigit()]
            if ids:
                placeholders = ",".join("?" for _ in ids)
                where.append(f"t.category_id IN ({placeholders})")
                params.extend(ids)

        order = _ORDER_MAP.get(sort, f"{_DATE_COALESCE} DESC")

        cursor = await self.db.execute(
            f"SELECT COUNT(*) FROM transactions t WHERE {' AND '.join(where)}", params
        )
        total = (await cursor.fetchone())[0]

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
            _format_txn(r, r["cat_name"] or "", r["cat_icon"] or "", r["cat_name_en"] or "")
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

        cursor = await self.db.execute(
            """INSERT INTO transactions
               (user_id, category_id, category_name, type, amount, description, note, date)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                user_id,
                data.category_id,
                cat["name"],
                data.type,
                data.amount,
                data.description,
                data.note,
                data.date,
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
            cat.get("name_en", "") or "",
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
            c.get("name_en", "") if c else "",
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

        set_clause = ", ".join(f"{k} = ?" for k in updates)
        await self.db.execute(
            f"UPDATE transactions SET {set_clause} WHERE id = ?",
            list(updates.values()) + [txn_id],
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
            c.get("name_en", "") if c else "",
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
            raise InvalidOperationError("Target user is not a member of your household")

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
            c.get("name_en", "") if c else "",
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
        expense_cat_name_en = expense_cat.get("name_en", "") or ""
        expense_cat_icon = expense_cat.get("icon", "")
        income_cat_id = income_cat["id"]
        income_cat_name = income_cat["name"]
        income_cat_name_en = income_cat.get("name_en", "") or ""
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

            # Sender expense
            cursor = await self.db.execute(
                """INSERT INTO transactions
                   (type, amount, category_id, category_name, description, date, user_id)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    "expense",
                    t.amount,
                    expense_cat_id,
                    expense_cat_name,
                    f"Transfer to {recipient_name}",
                    req.date,
                    user_id,
                ),
            )
            expense_id = cursor.lastrowid

            # Recipient income
            cursor = await self.db.execute(
                """INSERT INTO transactions
                   (type, amount, category_id, category_name, description, date, user_id)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    "income",
                    t.amount,
                    income_cat_id,
                    income_cat_name,
                    f"Transfer from {sender_name}",
                    req.date,
                    t.user_id,
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
                    expense_cat_name_en,
                    exp_row["user_display_name"] or "",
                ),
                "recipient_income": _format_txn(
                    inc_row,
                    income_cat_name,
                    income_cat_icon,
                    income_cat_name_en,
                    inc_row["user_display_name"] or "",
                ),
            })

        return {"transactions": results}

    async def _get_or_create_transfer_category(self, ttype: str) -> dict:
        """Find the 'Transfer' category for the given type, creating it if missing."""
        cursor = await self.db.execute(
            "SELECT id, name, name_en, icon FROM categories WHERE name = ? AND type = ?",
            ("Transfer", ttype),
        )
        cat = await cursor.fetchone()
        if cat:
            return dict(cat)

        await self.db.execute(
            "INSERT INTO categories (name, type, icon, is_default) VALUES (?, ?, ?, ?)",
            ("Transfer", ttype, "🔄", 1),
        )
        cursor = await self.db.execute(
            "SELECT id, name, name_en, icon FROM categories WHERE name = ? AND type = ?",
            ("Transfer", ttype),
        )
        cat = await cursor.fetchone()
        return dict(cat) if cat else {"id": 0, "name": "Transfer", "name_en": "", "icon": "🔄"}

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
            "DELETE FROM transactions WHERE id = ?", (txn_id,)
        )

        await self._remove_from_meili(txn_id)
