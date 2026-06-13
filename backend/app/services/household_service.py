"""Household Service — pure business logic, no FastAPI dependency.

Encapsulates all household management logic: creation, joining via
invite code, membership queries, and invite code retrieval.

Usage::

    service = HouseholdService(db)
    result = await service.create_household(data, user_id)
"""

from __future__ import annotations

import secrets
import string

from app.database import CursorWrapper
from app.schemas.household import (
    CreateHouseholdIn,
    JoinHouseholdIn,
    HouseholdOut,
    HouseholdDetailOut,
    MemberOut,
    InviteCodeOut,
)


# ── Domain exceptions ───────────────────────────────────────────────


class AlreadyInHouseholdError(Exception):
    """Raised when a user tries to create/join a household but is already in one."""

    def __init__(self) -> None:
        super().__init__("Already in a household")


class NotInHouseholdError(Exception):
    """Raised when a user who is not a member of any household tries an operation."""

    def __init__(self) -> None:
        super().__init__("Not a member of any household")


class InvalidInviteCodeError(Exception):
    """Raised when the provided invite code does not match any household."""

    def __init__(self) -> None:
        super().__init__("Invalid invite code")


class InviteCodeGenerationError(Exception):
    """Raised when a unique invite code cannot be generated after retries."""

    def __init__(self) -> None:
        super().__init__("Failed to generate unique invite code")


# ── Helpers ─────────────────────────────────────────────────────────


def _generate_invite_code(length: int = 8) -> str:
    """Generate a random alphanumeric invite code."""
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


# ── Service ─────────────────────────────────────────────────────────


class HouseholdService:
    """Service layer for household operations.

    Instantiated with a ``CursorWrapper`` (from ``app.database.get_db``).
    All methods return plain dicts / Pydantic models — no FastAPI types.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    # ── Internal helpers ───────────────────────────────────────────

    async def _ensure_not_in_household(self, user_id: int) -> None:
        """Raise ``AlreadyInHouseholdError`` if user is already a member."""
        cursor = await self.db.execute(
            "SELECT household_id FROM household_members WHERE user_id = ?",
            (user_id,),
        )
        if await cursor.fetchone():
            raise AlreadyInHouseholdError()

    async def _get_household_for_user(self, user_id: int) -> dict:
        """Return the household dict the user belongs to.

        Raises ``NotInHouseholdError`` if the user is not a member of any
        household.
        """
        cursor = await self.db.execute(
            """SELECT h.id, h.name, h.invite_code, h.created_by, h.created_at
               FROM households h
               JOIN household_members hm ON hm.household_id = h.id
               WHERE hm.user_id = ?""",
            (user_id,),
        )
        hh = await cursor.fetchone()
        if not hh:
            raise NotInHouseholdError()
        return dict(hh)

    # ── Create household ───────────────────────────────────────────

    async def create_household(
        self, data: CreateHouseholdIn, user_id: int
    ) -> dict:
        """Create a new household. *user_id* becomes admin.

        Generates a unique invite code (with up to 10 retries).
        Returns a dict compatible with ``HouseholdOut``.
        """
        await self._ensure_not_in_household(user_id)

        # Generate unique invite code
        for _ in range(10):
            code = _generate_invite_code()
            cursor = await self.db.execute(
                "SELECT id FROM households WHERE invite_code = ?",
                (code,),
            )
            if not await cursor.fetchone():
                break
        else:
            raise InviteCodeGenerationError()

        cursor = await self.db.execute(
            "INSERT INTO households (name, invite_code, created_by) VALUES (?, ?, ?)",
            (data.name, code, user_id),
        )
        hh_id = cursor.lastrowid

        await self.db.execute(
            "INSERT INTO household_members (user_id, household_id, role) VALUES (?, ?, 'admin')",
            (user_id, hh_id),
        )
        # auto-committed

        return {
            "id": hh_id,
            "name": data.name,
            "invite_code": code,
            "created_by": user_id,
            "created_at": "",  # caller can refetch via GET /me for timestamps
        }

    # ── Join household ─────────────────────────────────────────────

    async def join_household(
        self, data: JoinHouseholdIn, user_id: int
    ) -> dict:
        """Join an existing household using an invite code.

        Returns a confirmation message dict.
        """
        await self._ensure_not_in_household(user_id)

        cursor = await self.db.execute(
            "SELECT id FROM households WHERE invite_code = ?",
            (data.invite_code,),
        )
        hh = await cursor.fetchone()
        if not hh:
            raise InvalidInviteCodeError()

        await self.db.execute(
            "INSERT INTO household_members (user_id, household_id, role) VALUES (?, ?, 'member')",
            (user_id, hh["id"]),
        )
        # auto-committed

        return {"message": "Joined household successfully"}

    # ── Get my household ───────────────────────────────────────────

    async def get_my_household(
        self, user_id: int
    ) -> HouseholdDetailOut:
        """Return the current user's household with members.

        Returns a ``HouseholdDetailOut`` Pydantic model.
        """
        hh = await self._get_household_for_user(user_id)

        cursor = await self.db.execute(
            """SELECT u.id as user_id, u.display_name, hm.role, hm.joined_at
               FROM household_members hm
               JOIN users u ON hm.user_id = u.id
               WHERE hm.household_id = ?
               ORDER BY hm.joined_at""",
            (hh["id"],),
        )
        members = [dict(r) for r in await cursor.fetchall()]

        return HouseholdDetailOut(
            household=HouseholdOut(
                id=hh["id"],
                name=hh["name"],
                invite_code=hh["invite_code"],
                created_by=hh["created_by"],
                created_at=hh["created_at"],
            ),
            members=[
                MemberOut(
                    user_id=m["user_id"],
                    display_name=m["display_name"],
                    role=m["role"],
                    joined_at=m["joined_at"],
                )
                for m in members
            ],
            is_admin=user_id == hh["created_by"],
        )

    # ── Get invite code ────────────────────────────────────────────

    async def get_invite_code(self, user_id: int) -> InviteCodeOut:
        """Return the invite code for the user's household."""
        hh = await self._get_household_for_user(user_id)
        return InviteCodeOut(invite_code=hh["invite_code"])
