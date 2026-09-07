"""UI bootstrap (public) and home dashboard (JWT)."""

from fastapi import APIRouter, Depends, Response

from app.core.security import get_current_user
from app.database import get_db, CursorWrapper
from app.services.home_service import HomeService
from app.services.ui_bootstrap_service import UiBootstrapService

router = APIRouter(tags=["ui"])


@router.get("/ui/bootstrap")
async def ui_bootstrap(
    response: Response,
    db: CursorWrapper = Depends(get_db),
):
    payload = await UiBootstrapService(db).get_bootstrap()
    response.headers["Cache-Control"] = "public, max-age=300"
    return payload


@router.get("/home")
async def home(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    return await HomeService(db).get_home(user_id=current_user["id"])
