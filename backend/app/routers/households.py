import secrets
import string

from fastapi import APIRouter, Depends, HTTPException
import asyncpg

from app.database import get_db
from app.core.security import get_current_user
from app.schemas.household import (
    CreateHouseholdIn,
    JoinHouseholdIn,
    HouseholdOut,
    HouseholdDetailOut,
    MemberOut,
    InviteCodeOut,
)

router = APIRouter(prefix="/households", tags=["households"])


def _generate_invite_code(length: int = 8) -> str:
    """Generate a random alphanumeric invite code."""
    alphabet = string.ascii_uppercase + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


async def _ensure_not_in_household(db: asyncpg.Connection, user_id: int):
    """Raise 409 if user is already in a household."""
    cursor = await db.execute(
        "SELECT household_id FROM household_members WHERE user_id = ?",
        (user_id,),
    )
    if await cursor.fetchone():
        raise HTTPException(status_code=409, detail="Already in a household")


async def _get_household_for_user(db: asyncpg.Connection, user_id: int) -> dict:
    """Get the household the user belongs to, or raise 404."""
    cursor = await db.execute(
        """SELECT h.id, h.name, h.invite_code, h.created_by, h.created_at
           FROM households h
           JOIN household_members hm ON hm.household_id = h.id
           WHERE hm.user_id = ?""",
        (user_id,),
    )
    hh = await cursor.fetchone()
    if not hh:
        raise HTTPException(status_code=404, detail="Not a member of any household")
    return dict(hh)


@router.post("", status_code=201)
async def create_household(
    data: CreateHouseholdIn,
    db: asyncpg.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Create a new household. User becomes admin. Generates unique invite code."""
    await _ensure_not_in_household(db, current_user["id"])

    # Generate unique invite code
    for _ in range(10):
        code = _generate_invite_code()
        cursor = await db.execute(
            "SELECT id FROM households WHERE invite_code = ?", (code,)
        )
        if not await cursor.fetchone():
            break
    else:
        raise HTTPException(status_code=500, detail="Failed to generate unique invite code")

    cursor = await db.execute(
        "INSERT INTO households (name, invite_code, created_by) VALUES (?, ?, ?)",
        (data.name, code, current_user["id"]),
    )
    hh_id = cursor.lastrowid

    await db.execute(
        "INSERT INTO household_members (user_id, household_id, role) VALUES (?, ?, 'admin')",
        (current_user["id"], hh_id),
    )
    # auto-committed

    return {
        "id": hh_id,
        "name": data.name,
        "invite_code": code,
        "created_by": current_user["id"],
        "created_at": "",  # caller can refetch via GET /me for timestamps
    }


@router.post("/join")
async def join_household(
    data: JoinHouseholdIn,
    db: asyncpg.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Join an existing household using invite code."""
    await _ensure_not_in_household(db, current_user["id"])

    cursor = await db.execute(
        "SELECT id FROM households WHERE invite_code = ?",
        (data.invite_code,),
    )
    hh = await cursor.fetchone()
    if not hh:
        raise HTTPException(status_code=404, detail="Invalid invite code")

    await db.execute(
        "INSERT INTO household_members (user_id, household_id, role) VALUES (?, ?, 'member')",
        (current_user["id"], hh["id"]),
    )
    # auto-committed

    return {"message": "Joined household successfully"}


@router.get("/me")
async def get_my_household(
    db: asyncpg.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> HouseholdDetailOut:
    """Get the current user's household details and members."""
    hh = await _get_household_for_user(db, current_user["id"])

    cursor = await db.execute(
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
        is_admin=current_user["id"] == hh["created_by"],
    )


@router.get("/invite-code")
async def get_invite_code(
    db: asyncpg.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> InviteCodeOut:
    """Get the invite code for the current user's household."""
    hh = await _get_household_for_user(db, current_user["id"])
    return InviteCodeOut(invite_code=hh["invite_code"])
