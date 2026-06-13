"""Household router — thin HTTP adapter.

All business logic lives in :mod:`app.services.household_service`.
The router handles HTTP concerns: parsing requests, authentication via
``get_current_user``, and translating service-layer exceptions to HTTP
responses.
"""

from fastapi import APIRouter, Depends, HTTPException

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.schemas.household import (
    CreateHouseholdIn,
    JoinHouseholdIn,
    HouseholdDetailOut,
    InviteCodeOut,
)
from app.services.household_service import (
    HouseholdService,
    AlreadyInHouseholdError,
    NotInHouseholdError,
    InvalidInviteCodeError,
    InviteCodeGenerationError,
)

router = APIRouter(prefix="/households", tags=["households"])


def _get_service(db: CursorWrapper) -> HouseholdService:
    """Factory — keep router stateless."""
    return HouseholdService(db)


@router.post("", status_code=201)
async def create_household(
    data: CreateHouseholdIn,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Create a new household. User becomes admin. Generates unique invite code."""
    service = _get_service(db)
    try:
        return await service.create_household(data, current_user["id"])
    except AlreadyInHouseholdError:
        raise HTTPException(status_code=409, detail="Already in a household")
    except InviteCodeGenerationError:
        raise HTTPException(
            status_code=500, detail="Failed to generate unique invite code"
        )


@router.post("/join")
async def join_household(
    data: JoinHouseholdIn,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Join an existing household using invite code."""
    service = _get_service(db)
    try:
        return await service.join_household(data, current_user["id"])
    except AlreadyInHouseholdError:
        raise HTTPException(status_code=409, detail="Already in a household")
    except InvalidInviteCodeError:
        raise HTTPException(status_code=404, detail="Invalid invite code")


@router.get("/me", response_model=HouseholdDetailOut)
async def get_my_household(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get the current user's household details and members."""
    service = _get_service(db)
    try:
        return await service.get_my_household(current_user["id"])
    except NotInHouseholdError:
        raise HTTPException(
            status_code=404, detail="Not a member of any household"
        )


@router.get("/invite-code", response_model=InviteCodeOut)
async def get_invite_code(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get the invite code for the current user's household."""
    service = _get_service(db)
    try:
        return await service.get_invite_code(current_user["id"])
    except NotInHouseholdError:
        raise HTTPException(
            status_code=404, detail="Not a member of any household"
        )
