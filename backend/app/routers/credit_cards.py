from fastapi import APIRouter, Depends, HTTPException

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.schemas.credit_card import (
    CreditCardCreate,
    CreditCardUpdate,
    CreditCardOut,
    CreditCardTransactionCreate,
    CreditCardTransactionOut,
    CreditCardInstallmentCreate,
    CreditCardInstallmentOut,
    NextMonthProjection,
)
from app.services.credit_card_service import (
    CreditCardService,
    CreditCardNotFoundError,
    CreditCardForbiddenError,
    TransactionNotFoundError,
    InstallmentNotFoundError,
)

router = APIRouter(prefix="/credit-cards", tags=["credit_cards"])


# ── helpers ──────────────────────────────────────────────────────────


def _get_service(db: CursorWrapper) -> CreditCardService:
    return CreditCardService(db)


def _map_exceptions(e: Exception) -> HTTPException:
    if isinstance(e, CreditCardNotFoundError):
        return HTTPException(status_code=404, detail=str(e))
    if isinstance(e, CreditCardForbiddenError):
        return HTTPException(status_code=403, detail=str(e))
    if isinstance(e, (TransactionNotFoundError, InstallmentNotFoundError)):
        return HTTPException(status_code=404, detail=str(e))
    if isinstance(e, ValueError):
        return HTTPException(status_code=400, detail=str(e))
    raise  # re-raise unexpected errors


# ── Next Month Projection ───────────────────────────────────────────


@router.get("/next-month-projection")
async def next_month_projection(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> NextMonthProjection:
    svc = _get_service(db)
    try:
        return await svc.next_month_projection(current_user["id"])
    except Exception as e:
        raise _map_exceptions(e) from e


# ── Credit Cards CRUD ───────────────────────────────────────────────


@router.post("", status_code=201)
async def create_credit_card(
    data: CreditCardCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> CreditCardOut:
    svc = _get_service(db)
    try:
        result = await svc.create_credit_card(data, current_user["id"])
        return CreditCardOut(**result)
    except Exception as e:
        raise _map_exceptions(e) from e


@router.get("")
async def list_credit_cards(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[CreditCardOut]:
    svc = _get_service(db)
    try:
        results = await svc.list_credit_cards(current_user["id"])
        return [CreditCardOut(**r) for r in results]
    except Exception as e:
        raise _map_exceptions(e) from e


@router.get("/{card_id}")
async def get_credit_card(
    card_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> dict:
    svc = _get_service(db)
    try:
        return await svc.get_credit_card(card_id, current_user["id"])
    except Exception as e:
        raise _map_exceptions(e) from e


@router.put("/{card_id}")
async def update_credit_card(
    card_id: int,
    data: CreditCardUpdate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> CreditCardOut:
    svc = _get_service(db)
    try:
        result = await svc.update_credit_card(card_id, data, current_user["id"])
        return CreditCardOut(**result)
    except Exception as e:
        raise _map_exceptions(e) from e


@router.delete("/{card_id}", status_code=204)
async def delete_credit_card(
    card_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> None:
    svc = _get_service(db)
    try:
        await svc.delete_credit_card(card_id, current_user["id"])
    except Exception as e:
        raise _map_exceptions(e) from e


# ── Transactions ────────────────────────────────────────────────────


@router.post("/{card_id}/transactions", status_code=201)
async def create_transaction(
    card_id: int,
    data: CreditCardTransactionCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> CreditCardTransactionOut:
    svc = _get_service(db)
    try:
        result = await svc.create_transaction(card_id, data, current_user["id"])
        return CreditCardTransactionOut(**result)
    except Exception as e:
        raise _map_exceptions(e) from e


@router.get("/{card_id}/transactions")
async def list_transactions(
    card_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[CreditCardTransactionOut]:
    svc = _get_service(db)
    try:
        results = await svc.list_transactions(card_id, current_user["id"])
        return [CreditCardTransactionOut(**r) for r in results]
    except Exception as e:
        raise _map_exceptions(e) from e


@router.delete("/{card_id}/transactions/{txn_id}", status_code=204)
async def delete_transaction(
    card_id: int,
    txn_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> None:
    svc = _get_service(db)
    try:
        await svc.delete_transaction(card_id, txn_id, current_user["id"])
    except Exception as e:
        raise _map_exceptions(e) from e


# ── Installments ────────────────────────────────────────────────────


@router.post("/{card_id}/installments", status_code=201)
async def create_installment(
    card_id: int,
    data: CreditCardInstallmentCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> CreditCardInstallmentOut:
    svc = _get_service(db)
    try:
        result = await svc.create_installment(card_id, data, current_user["id"])
        return CreditCardInstallmentOut(**result)
    except Exception as e:
        raise _map_exceptions(e) from e


@router.get("/{card_id}/installments")
async def list_installments(
    card_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[CreditCardInstallmentOut]:
    svc = _get_service(db)
    try:
        results = await svc.list_installments(card_id, current_user["id"])
        return [CreditCardInstallmentOut(**r) for r in results]
    except Exception as e:
        raise _map_exceptions(e) from e


@router.delete("/{card_id}/installments/{inst_id}", status_code=204)
async def delete_installment(
    card_id: int,
    inst_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> None:
    svc = _get_service(db)
    try:
        await svc.delete_installment(card_id, inst_id, current_user["id"])
    except Exception as e:
        raise _map_exceptions(e) from e
