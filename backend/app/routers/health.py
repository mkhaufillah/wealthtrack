"""Health check endpoint — used by monitoring / load balancer."""

from fastapi import APIRouter, Depends
import asyncpg

from app.database import get_db

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check(db: asyncpg.Connection = Depends(get_db)):
    """Return API & DB health status."""
    try:
        cursor = await db.execute("SELECT 1")
        await cursor.fetchone()
        db_ok = True
    except Exception:
        db_ok = False

    return {
        "status": "ok" if db_ok else "degraded",
        "database": "connected" if db_ok else "unreachable",
    }
