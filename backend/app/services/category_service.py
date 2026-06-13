"""Category Service — pure business logic, no FastAPI dependency.

Encapsulates all category CRUD operations with admin-gated access
and keyword JSON parsing.

Usage::

    service = CategoryService(db)
    categories = await service.list_categories(type="expense")
"""

import json
from typing import Optional

from app.database import CursorWrapper


# ── Domain exceptions ────────────────────────────────────────────────


class CategoryNotFoundError(Exception):
    """Raised when a category does not exist."""

    def __init__(self, category_id: int) -> None:
        self.category_id = category_id
        super().__init__(f"Category {category_id} not found")


class CategoryNameConflictError(Exception):
    """Raised when a category name already exists for the given type."""

    def __init__(self, name: str, type_: str) -> None:
        self.name = name
        self.type = type_
        super().__init__(f"Category '{name}' already exists for type '{type_}'")


class DefaultCategoryEditError(Exception):
    """Raised when trying to edit a system-default category."""

    def __init__(self, category_id: int) -> None:
        self.category_id = category_id
        super().__init__(f"Category {category_id} is a system default and cannot be edited")


class NotAuthorizedError(Exception):
    """Raised when a non-admin user attempts an admin-only operation."""

    def __init__(self, action: str = "perform this action") -> None:
        super().__init__(f"Only admin can {action}")


# ── Service ──────────────────────────────────────────────────────────


class CategoryService:
    """Service for all category operations.

    Instantiate with a ``CursorWrapper`` (from ``app.database.get_db``).
    All methods return plain dicts / lists — no FastAPI types.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    # ── Helpers ──────────────────────────────────────────────────────

    @staticmethod
    def _format_category(row) -> dict:
        """Format a category DB row into a response dict with parsed keywords."""
        result = dict(row)
        kw = row["keywords"]
        result["keywords"] = json.loads(kw) if kw else []
        return result

    # ── Core CRUD ────────────────────────────────────────────────────

    async def list_categories(
        self,
        type_filter: Optional[str] = None,
    ) -> list[dict]:
        """Return all categories, optionally filtered by *type_filter*.

        Results are ordered by type (if unfiltered) and then ``sort_order``.
        """
        if type_filter:
            cursor = await self.db.execute(
                "SELECT id, name, name_en, type, icon, is_default, keywords "
                "FROM categories WHERE type = ? ORDER BY sort_order",
                (type_filter,),
            )
        else:
            cursor = await self.db.execute(
                "SELECT id, name, name_en, type, icon, is_default, keywords "
                "FROM categories ORDER BY type, sort_order"
            )
        rows = await cursor.fetchall()
        return [self._format_category(r) for r in rows]

    async def create_category(
        self,
        current_user: dict,
        name: str,
        name_en: str,
        type_: str,
        icon: str,
        keywords: list[str],
        sort_order: int,
    ) -> dict:
        """Create a new category.

        Raises ``NotAuthorizedError`` if *current_user* is not admin.
        Raises ``CategoryNameConflictError`` if the name already exists for the given type.

        Returns the created category dict.
        """
        if current_user["role"] != "admin":
            raise NotAuthorizedError("create categories")

        cursor = await self.db.execute(
            "SELECT id FROM categories WHERE name = ? AND type = ?",
            (name, type_),
        )
        if await cursor.fetchone():
            raise CategoryNameConflictError(name, type_)

        keywords_json = json.dumps(keywords) if keywords else "[]"
        cursor = await self.db.execute(
            "INSERT INTO categories (name, name_en, type, icon, keywords, sort_order) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (name, name_en, type_, icon, keywords_json, sort_order),
        )

        cursor = await self.db.execute(
            "SELECT id, name, name_en, type, icon, is_default, keywords FROM categories WHERE id = ?",
            (cursor.lastrowid,),
        )
        return self._format_category(await cursor.fetchone())

    async def update_category(
        self,
        current_user: dict,
        category_id: int,
        name: Optional[str] = None,
        name_en: Optional[str] = None,
        icon: Optional[str] = None,
        keywords: Optional[list[str]] = None,
        sort_order: Optional[int] = None,
    ) -> dict:
        """Update an existing category.

        Raises ``NotAuthorizedError`` if *current_user* is not admin.
        Raises ``CategoryNotFoundError`` if the category does not exist.
        Raises ``DefaultCategoryEditError`` if the category is a system default.
        Raises ``CategoryNameConflictError`` if the new name conflicts.

        Returns the updated category dict.
        """
        if current_user["role"] != "admin":
            raise NotAuthorizedError("update categories")

        cursor = await self.db.execute(
            "SELECT id, name, type, is_default FROM categories WHERE id = ?",
            (category_id,),
        )
        existing = await cursor.fetchone()
        if not existing:
            raise CategoryNotFoundError(category_id)

        # Prevent editing system-default categories
        if existing["is_default"]:
            raise DefaultCategoryEditError(category_id)

        # Check name uniqueness if renaming
        if name is not None and name != existing["name"]:
            cursor = await self.db.execute(
                "SELECT id FROM categories WHERE name = ? AND type = ? AND id != ?",
                (name, existing["type"], category_id),
            )
            if await cursor.fetchone():
                raise CategoryNameConflictError(name, existing["type"])

        # Build dynamic UPDATE
        updates = {}
        if name is not None:
            updates["name"] = name
        if name_en is not None:
            updates["name_en"] = name_en
        if icon is not None:
            updates["icon"] = icon
        if keywords is not None:
            updates["keywords"] = json.dumps(keywords)
        if sort_order is not None:
            updates["sort_order"] = sort_order

        if not updates:
            raise ValueError("No fields to update")

        set_clause = ", ".join(f"{k} = ?" for k in updates)
        await self.db.execute(
            f"UPDATE categories SET {set_clause} WHERE id = ?",
            list(updates.values()) + [category_id],
        )

        cursor = await self.db.execute(
            "SELECT id, name, name_en, type, icon, is_default, keywords FROM categories WHERE id = ?",
            (category_id,),
        )
        return self._format_category(await cursor.fetchone())
