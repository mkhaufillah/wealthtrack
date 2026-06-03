"""Redis connection manager — singleton pool for async redis."""
import redis.asyncio as aioredis
from app.core.config import settings

_redis: aioredis.Redis | None = None


async def get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.Redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
        )
    return _redis


async def init_redis():
    """Initialize and verify Redis connection (called on startup)."""
    r = await get_redis()
    await r.ping()


async def close_redis():
    global _redis
    if _redis is not None:
        await _redis.aclose()
        _redis = None
