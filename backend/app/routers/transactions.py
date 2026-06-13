"""Transaction router — thin HTTP adapter.

Delegates all business logic to TransactionService.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.schemas.transaction import (
    TransactionCreate,
    TransactionUpdate,
    PaginatedTransactions,
    TransferOwnerIn,
    TransferRequest,
    TransferResponse,
)
from app.services.transaction_service import (
    TransactionService,
    TransactionNotFoundError,
    CategoryNotFoundError,
    NotHouseholdMemberError,
    ForbiddenError,
    NoFieldsToUpdateError,
    InvalidOperationError,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/transactions", tags=["transactions"])


def _handle_service_error(exc: Exception) -> None:
    """Convert service-layer exceptions to HTTP exceptions."""
    if isinstance(exc, TransactionNotFoundError):
        raise HTTPException(status_code=404, detail=str(exc))
    if isinstance(exc, CategoryNotFoundError):
        raise HTTPException(status_code=404, detail=str(exc))
    if isinstance(exc, NotHouseholdMemberError):
        raise HTTPException(status_code=404, detail=exc.detail)
    if isinstance(exc, ForbiddenError):
        raise HTTPException(status_code=403, detail=exc.detail)
    if isinstance(exc, InvalidOperationError):
        raise HTTPException(status_code=400, detail=exc.detail)
    if isinstance(exc, NoFieldsToUpdateError):
        raise HTTPException(status_code=400, detail=str(exc))
    # Re-raise unexpected errors
    raise


def _get_service(db: CursorWrapper) -> TransactionService:
    return TransactionService(db)


@router.get("/household", response_model=PaginatedTransactions)
async def list_household_transactions(
    page: int = Query(1, ge=1),
    per_page: int = Query(100, ge=1, le=200),
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sort: str = Query("-date", pattern="^(date|-date|amount|-amount)$"),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get transactions of all household members."""
    try:
        svc = _get_service(db)
        return await svc.list_household_transactions(
            user_id=current_user["id"],
            page=page,
            per_page=per_page,
            type=type,
            date_from=date_from,
            date_to=date_to,
            sort=sort,
        )
    except Exception as e:
        _handle_service_error(e)


@router.get("", response_model=PaginatedTransactions)
async def list_transactions(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    category_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sort: str = Query("-date", pattern="^(date|-date|amount|-amount|name|-name)$"),
    q: Optional[str] = Query(None, description="Search by description"),
    category_ids: Optional[str] = Query(None, description="Comma-separated category IDs"),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """List user's transactions with optional search."""
    try:
        svc = _get_service(db)
        return await svc.list_transactions(
            user_id=current_user["id"],
            page=page,
            per_page=per_page,
            type=type,
            category_id=category_id,
            date_from=date_from,
            date_to=date_to,
            sort=sort,
            q=q,
            category_ids=category_ids,
        )
    except Exception as e:
        _handle_service_error(e)


@router.post("", status_code=201)
async def create_transaction(
    data: TransactionCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Create a new transaction."""
    try:
        svc = _get_service(db)
        return await svc.create_transaction(data, current_user["id"])
    except Exception as e:
        _handle_service_error(e)


@router.get("/{txn_id}")
async def get_transaction(
    txn_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get a single transaction by ID."""
    try:
        svc = _get_service(db)
        return await svc.get_transaction(txn_id, current_user["id"])
    except Exception as e:
        _handle_service_error(e)


@router.put("/{txn_id}")
async def update_transaction(
    txn_id: int,
    data: TransactionUpdate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Update an existing transaction."""
    try:
        svc = _get_service(db)
        return await svc.update_transaction(txn_id, data, current_user["id"])
    except Exception as e:
        _handle_service_error(e)


@router.put("/{txn_id}/owner")
async def transfer_owner(
    txn_id: int,
    data: TransferOwnerIn,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Transfer transaction ownership to another household member."""
    try:
        svc = _get_service(db)
        return await svc.transfer_owner(txn_id, data, current_user["id"])
    except Exception as e:
        _handle_service_error(e)


@router.post("/transfer", response_model=TransferResponse, status_code=201)
async def transfer_balance(
    req: TransferRequest,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Transfer balance to household members. Creates paired expense/income transactions."""
    try:
        svc = _get_service(db)
        return await svc.transfer_balance(req, current_user["id"])
    except Exception as e:
        _handle_service_error(e)


@router.delete("/{txn_id}", status_code=204)
async def delete_transaction(
    txn_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete a transaction."""
    try:
        svc = _get_service(db)
        await svc.delete_transaction(txn_id, current_user["id"])
        return None
    except Exception as e:
        _handle_service_error(e)
