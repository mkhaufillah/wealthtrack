"""Category Service — pure business logic, no FastAPI dependency.

Encapsulates all category CRUD operations with admin-gated access
and keyword JSON parsing.

Usage::

    service = CategoryService(db)
    categories = await service.list_categories(type="expense")
"""

import json
import re
from typing import Optional

from app.database import CursorWrapper


ICON_RE = re.compile(r"^strokeRounded[A-Za-z0-9]{1,48}$")
DEFAULT_ICON = "strokeRoundedInvoice01"


def normalize_icon(icon: Optional[str]) -> str:
    value = (icon or "").strip()
    if ICON_RE.fullmatch(value):
        return value
    return DEFAULT_ICON


class CategoryNotFoundError(Exception):
    """Raised when a category does not exist."""

    def __init__(self, category_id: int) -> None:
        self.category_id = category_id
        super().__init__("Kategori gak ketemu")


class CategoryNameConflictError(Exception):
    """Raised when a category name already exists for the given type."""

    def __init__(self, name: str, type_: str) -> None:
        self.name = name
        self.type = type_
        super().__init__("Nama kategori ini sudah ada")


class DefaultCategoryEditError(Exception):
    """Raised when trying to edit or delete a system-default category."""

    def __init__(self, category_id: int) -> None:
        self.category_id = category_id
        super().__init__("Kategori bawaan gak bisa diubah atau dihapus")


class CategoryInUseError(Exception):
    """Raised when a category is referenced by financial history."""

    def __init__(self, category_id: int) -> None:
        self.category_id = category_id
        super().__init__("Kategori ini sudah dipakai transaksi, jadi gak bisa dihapus")


class NotAuthorizedError(Exception):
    """Raised when a non-admin user attempts an admin-only operation."""

    def __init__(self, action: str = "melakukan ini") -> None:
        super().__init__(f"Cuma admin yang bisa {action}")


class CategoryService:
    """Service for all category operations.

    Instantiate with a ``CursorWrapper`` (from ``app.database.get_db``).
    All methods return plain dicts / lists — no FastAPI types.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    @staticmethod
    def _format_category(row) -> dict:
        """Format a category DB row into a response dict with parsed keywords."""
        result = dict(row)
        kw = row["keywords"]
        result["keywords"] = json.loads(kw) if kw else []
        result["copy_key"] = (row.get("copy_key") if hasattr(row, "get") else result.get("copy_key")) or ""
        name = result.get("name") or ""
        result["name_id"] = (result.get("name_id") or "").strip() or name
        result["name_en"] = (result.get("name_en") or "").strip() or result["name_id"]
        return result

    _LIST_SQL = (
        "SELECT id, name, type, icon, is_default, keywords, copy_key, "
        "COALESCE((SELECT value FROM ui_copy WHERE key = categories.copy_key AND locale = 'id-ID'), name) AS name_id, "
        "COALESCE((SELECT value FROM ui_copy WHERE key = categories.copy_key AND locale = 'en-US'), name) AS name_en "
        "FROM categories"
    )

    async def list_categories(
        self,
        type_filter: Optional[str] = None,
    ) -> list[dict]:
        """Return all categories, optionally filtered by *type_filter*.

        Results are ordered by type (if unfiltered) and then ``sort_order``.
        """
        if type_filter:
            cursor = await self.db.execute(
                self._LIST_SQL + " WHERE type = ? ORDER BY sort_order",
                (type_filter,),
            )
        else:
            cursor = await self.db.execute(
                self._LIST_SQL + " ORDER BY type, sort_order"
            )
        rows = await cursor.fetchall()
        return [self._format_category(r) for r in rows]

    async def create_category(
        self,
        current_user: dict,
        name: str,
        type_: str,
        icon: str,
        keywords: list[str],
        sort_order: int,
        name_en: Optional[str] = None,
    ) -> dict:
        """Create a new category.

        Raises ``NotAuthorizedError`` if *current_user* is not admin.
        Raises ``CategoryNameConflictError`` if the name already exists for the given type.

        Returns the created category dict.
        """
        if current_user["role"] != "admin":
            raise NotAuthorizedError("bikin kategori")

        cursor = await self.db.execute(
            "SELECT id FROM categories WHERE name = ? AND type = ?",
            (name, type_),
        )
        if await cursor.fetchone():
            raise CategoryNameConflictError(name, type_)

        keywords_json = json.dumps(keywords) if keywords else "[]"
        icon = normalize_icon(icon)
        cursor = await self.db.execute(
            "INSERT INTO categories (name, type, icon, keywords, sort_order) "
            "VALUES (?, ?, ?, ?, ?)",
            (name, type_, icon, keywords_json, sort_order),
        )
        new_id = cursor.lastrowid
        copy_key = f"cat.n.custom.{new_id}"
        await self.db.execute(
            "UPDATE categories SET copy_key = ? WHERE id = ?",
            (copy_key, new_id),
        )
        await self._upsert_copy(copy_key, name, locale="id-ID")
        await self._upsert_copy(copy_key, (name_en or name).strip() or name, locale="en-US")
        cursor = await self.db.execute(
            self._LIST_SQL + " WHERE id = ?",
            (new_id,),
        )
        return self._format_category(await cursor.fetchone())

    async def update_category(
        self,
        current_user: dict,
        category_id: int,
        name: Optional[str] = None,
        icon: Optional[str] = None,
        keywords: Optional[list[str]] = None,
        sort_order: Optional[int] = None,
        name_en: Optional[str] = None,
    ) -> dict:
        """Update an existing category.

        Raises ``NotAuthorizedError`` if *current_user* is not admin.
        Raises ``CategoryNotFoundError`` if the category does not exist.
        Raises ``DefaultCategoryEditError`` if the category is a system default.
        Raises ``CategoryNameConflictError`` if the new name conflicts.

        Returns the updated category dict.
        """
        if current_user["role"] != "admin":
            raise NotAuthorizedError("ubah kategori")

        cursor = await self.db.execute(
            "SELECT id, name, type, is_default, copy_key FROM categories WHERE id = ?",
            (category_id,),
        )
        existing = await cursor.fetchone()
        if not existing:
            raise CategoryNotFoundError(category_id)
        existing = dict(existing)

        if existing["is_default"]:
            raise DefaultCategoryEditError(category_id)

        if name is not None and name != existing["name"]:
            cursor = await self.db.execute(
                "SELECT id FROM categories WHERE name = ? AND type = ? AND id != ?",
                (name, existing["type"], category_id),
            )
            if await cursor.fetchone():
                raise CategoryNameConflictError(name, existing["type"])

        updates = {}
        copy_key = existing.get("copy_key") or f"cat.n.custom.{category_id}"
        if not existing.get("copy_key"):
            updates["copy_key"] = copy_key
        if name is not None:
            updates["name"] = name
            await self._upsert_copy(copy_key, name, locale="id-ID")
        if name_en is not None:
            await self._upsert_copy(copy_key, name_en, locale="en-US")
        if icon is not None:
            updates["icon"] = normalize_icon(icon)
        if keywords is not None:
            updates["keywords"] = json.dumps(keywords)
        if sort_order is not None:
            updates["sort_order"] = sort_order

        if not updates and name is None and name_en is None:
            raise ValueError("Gak ada yang diubah")
        if updates:
            set_clause = ", ".join(f"{k} = ?" for k in updates)
            await self.db.execute(
                f"UPDATE categories SET {set_clause} WHERE id = ?",
                list(updates.values()) + [category_id],
            )

        cursor = await self.db.execute(
            self._LIST_SQL + " WHERE id = ?",
            (category_id,),
        )
        return self._format_category(await cursor.fetchone())

    async def delete_category(self, current_user: dict, category_id: int) -> None:
        """Delete an unused custom category. Financial history is never altered."""
        if current_user["role"] != "admin":
            raise NotAuthorizedError("hapus kategori")

        cursor = await self.db.execute(
            "SELECT id, is_default FROM categories WHERE id = ?", (category_id,)
        )
        existing = await cursor.fetchone()
        if not existing:
            raise CategoryNotFoundError(category_id)
        if existing["is_default"]:
            raise DefaultCategoryEditError(category_id)

        from app.core.vault import category_trace
        from app.core.vault_ctx import current_dek

        dek = current_dek()
        if dek is not None:
            cursor = await self.db.execute(
                "SELECT id FROM transactions WHERE category_trace = ? LIMIT 1",
                (category_trace(dek, int(category_id)),),
            )
            if await cursor.fetchone():
                raise CategoryInUseError(category_id)
            cursor = await self.db.execute(
                "SELECT id FROM budgets WHERE category_trace = ? LIMIT 1",
                (category_trace(dek, int(category_id)),),
            )
            if await cursor.fetchone():
                raise CategoryInUseError(category_id)

        await self.db.execute("DELETE FROM categories WHERE id = ?", (category_id,))

    async def _user_locale(self, current_user: dict) -> str:
        from app.core.i18n import DEFAULT_LOCALE, normalize_locale

        cursor = await self.db.execute(
            "SELECT locale FROM users WHERE id = ?",
            (current_user["id"],),
        )
        row = await cursor.fetchone()
        if not row:
            return DEFAULT_LOCALE
        return normalize_locale(row["locale"] if "locale" in row.keys() else None)

    async def _upsert_copy(self, key: str, value: str, locale: str | None = None) -> None:
        from app.core.i18n import SUPPORTED_LOCALES, bust_bootstrap_cache, normalize_locale

        locales = [normalize_locale(locale)] if locale else list(SUPPORTED_LOCALES)
        for loc in locales:
            await self.db.execute(
                """INSERT INTO ui_copy (key, value, locale)
                   VALUES (?, ?, ?)
                   ON CONFLICT (key, locale) DO UPDATE SET value = excluded.value""",
                (key, value, loc),
            )
        await bust_bootstrap_cache()
