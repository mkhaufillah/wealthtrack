"""Household router — thin HTTP adapter.

All business logic lives in :mod:`app.services.household_service`.
The router handles HTTP concerns: parsing requests, authentication via
``get_current_user``, and translating service-layer exceptions to HTTP
responses.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.core.security import get_current_user
from app.core.vault_ctx import VaultRequiredError
from app.database import CursorWrapper, get_db
from app.schemas.household import (
    CreateHouseholdIn,
    HouseholdDetailOut,
    InviteCodeOut,
    JoinHouseholdIn,
)
from app.services.household_service import (
    AlreadyInHouseholdError,
    HouseholdService,
    InvalidInviteCodeError,
    InviteCodeGenerationError,
    NotInHouseholdError,
)
from app.services.vault_service import VaultService


class VaultWrapIn(BaseModel):
    wrapped_dek: str
    kdf_salt: str = ""
    kdf_params: str = ""


class VaultPubkeyIn(BaseModel):
    public_key: str


class VaultShareIn(BaseModel):
    target_user_id: int
    boxed_dek: str


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
        raise HTTPException(status_code=409, detail="Kamu sudah di keluarga")
    except InviteCodeGenerationError:
        raise HTTPException(
            status_code=500, detail="Gagal bikin kode undangan"
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
        raise HTTPException(status_code=409, detail="Kamu sudah di keluarga")
    except InvalidInviteCodeError:
        raise HTTPException(status_code=404, detail="Kode undangan gak valid")


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
            status_code=404, detail="Belum gabung keluarga"
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
            status_code=404, detail="Belum gabung keluarga"
        )


@router.post("/vault/seal")
async def vault_seal(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    try:
        return await VaultService(db).seal(current_user["id"])
    except VaultRequiredError:
        raise HTTPException(status_code=403, detail="err.vault_required")


@router.post("/vault/wrap")
async def vault_wrap(
    data: VaultWrapIn,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    try:
        return await VaultService(db).put_wrap(
            current_user["id"], data.wrapped_dek, data.kdf_salt, data.kdf_params
        )
    except VaultRequiredError:
        raise HTTPException(status_code=403, detail="err.vault_required")


@router.get("/vault/wrap")
async def vault_get_wrap(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    row = await VaultService(db).get_wrap(current_user["id"])
    if not row:
        raise HTTPException(status_code=404, detail="err.vault_pending")
    return row


@router.post("/vault/pubkey")
async def vault_pubkey(
    data: VaultPubkeyIn,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    try:
        return await VaultService(db).put_pubkey(current_user["id"], data.public_key)
    except VaultRequiredError:
        raise HTTPException(status_code=403, detail="err.vault_required")


@router.get("/vault/share-inbox")
async def vault_share_inbox(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    row = await VaultService(db).get_share(current_user["id"])
    if not row:
        raise HTTPException(status_code=404, detail="err.vault_pending")
    return row


@router.get("/vault/pubkeys")
async def vault_pubkeys(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    return {"keys": await VaultService(db).list_pubkeys(current_user["id"])}


@router.post("/vault/share")
async def vault_share(
    data: VaultShareIn,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    try:
        return await VaultService(db).put_share(
            current_user["id"], data.target_user_id, data.boxed_dek
        )
    except VaultRequiredError:
        raise HTTPException(status_code=403, detail="err.vault_required")
