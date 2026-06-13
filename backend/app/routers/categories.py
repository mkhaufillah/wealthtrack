from fastapi import APIRouter, Depends, Query, HTTPException, Request
from typing import Optional

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.core.limiter import limiter
from app.schemas.category import CategoryOut, CategoryCreate, CategoryUpdate
from app.services.category_service import (
    CategoryService,
    CategoryNotFoundError,
    CategoryNameConflictError,
    DefaultCategoryEditError,
    NotAuthorizedError,
)

router = APIRouter(prefix="/categories", tags=["categories"])


def _handle_service_error(exc: Exception) -> None:
    """Convert a service-layer domain exception to an HTTPException."""
    if isinstance(exc, NotAuthorizedError):
        raise HTTPException(status_code=403, detail=str(exc))
    if isinstance(exc, CategoryNotFoundError):
        raise HTTPException(status_code=404, detail=str(exc))
    if isinstance(exc, CategoryNameConflictError):
        raise HTTPException(status_code=409, detail=str(exc))
    if isinstance(exc, DefaultCategoryEditError):
        raise HTTPException(status_code=403, detail=str(exc))
    if isinstance(exc, ValueError):
        raise HTTPException(status_code=400, detail=str(exc))
    raise


@router.get("", response_model=list[CategoryOut])
async def list_categories(
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    service = CategoryService(db)
    return await service.list_categories(type_filter=type)


@router.post("", status_code=201, response_model=CategoryOut)
@limiter.limit("30/minute")
async def create_category(
    request: Request,
    data: CategoryCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    service = CategoryService(db)
    try:
        return await service.create_category(
            current_user=current_user,
            name=data.name,
            name_en=data.name_en,
            type_=data.type,
            icon=data.icon,
            keywords=data.keywords,
            sort_order=data.sort_order,
        )
    except (NotAuthorizedError, CategoryNameConflictError) as exc:
        _handle_service_error(exc)


@router.put("/{category_id}", response_model=CategoryOut)
@limiter.limit("30/minute")
async def update_category(
    request: Request,
    category_id: int,
    data: CategoryUpdate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    service = CategoryService(db)
    try:
        return await service.update_category(
            current_user=current_user,
            category_id=category_id,
            name=data.name,
            name_en=data.name_en,
            icon=data.icon,
            keywords=data.keywords,
            sort_order=data.sort_order,
        )
    except (
        NotAuthorizedError,
        CategoryNotFoundError,
        CategoryNameConflictError,
        DefaultCategoryEditError,
        ValueError,
    ) as exc:
        _handle_service_error(exc)
