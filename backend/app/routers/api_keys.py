"""API key management for long-lived MCP authentication."""
from typing import Optional

from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException

from app.core.security import get_current_user
from app.database import get_db, CursorWrapper
from app.services.api_key_service import ApiKeyService

router = APIRouter(prefix="/api-keys", tags=["api-keys"])


class CreateApiKeyIn(BaseModel):
    name: str
    scopes: list[str] = ["mcp:read"]


@router.post("", status_code=201)
async def create_api_key(
    body: CreateApiKeyIn,
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    """Create a new API key. The plaintext key is returned only once."""
    if db is None:
        raise HTTPException(status_code=503, detail="Database not available")

    # Validate scopes
    allowed = {"mcp:read", "mcp:write"}
    invalid = set(body.scopes) - allowed
    if invalid:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid scopes: {sorted(invalid)}. Allowed: {sorted(allowed)}",
        )

    service = ApiKeyService(db)
    return await service.create_key(
        user_id=current_user["id"],
        name=body.name,
        scopes=body.scopes,
    )


@router.get("")
async def list_api_keys(
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    """List API keys for the authenticated user."""
    if db is None:
        raise HTTPException(status_code=503, detail="Database not available")
    service = ApiKeyService(db)
    return {"items": await service.list_keys(current_user["id"])}


@router.delete("/{key_id}", status_code=204)
async def revoke_api_key(
    key_id: int,
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    """Revoke an API key."""
    if db is None:
        raise HTTPException(status_code=503, detail="Database not available")
    service = ApiKeyService(db)
    revoked = await service.revoke_key(current_user["id"], key_id)
    if not revoked:
        raise HTTPException(status_code=404, detail="API key not found")
    return None
