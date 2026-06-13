"""Health check service — encapsulates DB and Redis health logic."""
from app.database import CursorWrapper
from app.core.redis import get_redis


class HealthService:
    """Service for checking API dependencies' health."""

    def __init__(self, db: CursorWrapper):
        self.db = db

    async def check(self) -> dict:
        """Check DB and Redis connectivity. Returns status dict."""
        db_ok = False
        redis_ok = False

        # DB ping
        try:
            cursor = await self.db.execute("SELECT 1")
            await cursor.fetchone()
            db_ok = True
        except Exception:
            pass

        # Redis ping
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
