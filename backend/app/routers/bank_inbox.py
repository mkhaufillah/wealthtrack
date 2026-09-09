"""Bank notification inbox — thin HTTP adapter."""
from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.security import get_current_user
from app.database import get_db
from app.schemas.bank_inbox import BankInboxConfirmIn, BankInboxIn, BankInboxItem, BankInboxList
from app.services.bank_inbox_service import BankInboxError, BankInboxService

router = APIRouter(prefix="/bank-inbox", tags=["bank-inbox"])


def _raise(exc: BankInboxError) -> None:
    raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post("", response_model=BankInboxItem)
async def ingest(
    body: BankInboxIn,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    svc = BankInboxService(db)
    try:
        return await svc.ingest(
            current_user["id"],
            body.package,
            body.title,
            body.text,
            body.posted_at,
        )
    except BankInboxError as exc:
        _raise(exc)


@router.get("", response_model=BankInboxList)
async def list_inbox(
    status: str = Query(default="all"),
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    svc = BankInboxService(db)
    try:
        return await svc.list_items(current_user["id"], status)
    except BankInboxError as exc:
        _raise(exc)


@router.post("/{item_id}/confirm", response_model=BankInboxItem)
async def confirm(
    item_id: int,
    body: BankInboxConfirmIn | None = None,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    svc = BankInboxService(db)
    try:
        category_id = body.category_id if body else None
        return await svc.confirm(item_id, current_user["id"], category_id)
    except BankInboxError as exc:
        _raise(exc)


@router.post("/{item_id}/reject", response_model=BankInboxItem)
async def reject(
    item_id: int,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    svc = BankInboxService(db)
    try:
        return await svc.reject(item_id, current_user["id"])
    except BankInboxError as exc:
        _raise(exc)
