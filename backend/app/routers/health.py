"""Health check endpoint — used by monitoring / load balancer."""
from fastapi import APIRouter, Depends

from app.database import CursorWrapper, get_db
from app.services.health_service import HealthService

router = APIRouter(tags=["health"])


@router.get("/health")
@router.head("/health")
async def health_check(db: CursorWrapper = Depends(get_db)):
    """Return API, DB & Redis health status."""
    service = HealthService(db)
    return await service.check()
