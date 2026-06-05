"""Health check endpoint — used by monitoring / load balancer."""
from fastapi import APIRouter, Depends

from app.database import get_db, CursorWrapper
from app.core.redis import get_redis

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check(db : CursorWrapper = Depends(get_db)):
    """Return API, DB & Redis health status."""
    try:
        cursor = await db.execute("SELECT 1")
        await cursor.fetchone()
        db_ok = True
    except Exception:
        db_ok = False

    redis_ok = False
    try:
        r = await get_redis()
        await r.ping()
        redis_ok = True
    except Exception:
        pass

    is_ok = db_ok and redis_ok
    return {
        "status": "ok" if is_ok else "degraded",
        "database": "connected" if db_ok else "unreachable",
        "redis": "connected" if redis_ok else "unreachable",
    }
