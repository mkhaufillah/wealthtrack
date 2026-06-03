"""Redis-backed rate limiter — replaces slowapi and custom in-memory OCR limiter.

Usage:

    from app.core.rate_limiter import check_rate_limit

    # In endpoint:
    await check_rate_limit(f"ocr:{user_id}", max_requests=10, window_sec=86400)

    # Or as decorator (for FastAPI endpoints):
    @router.post("/ocr")
    @rate_limit("ocr", max_requests=10, window_sec=86400)
    async def ocr_endpoint(...):
"""
import time
from fastapi import HTTPException
from app.core.redis import get_redis


async def check_rate_limit(
    key: str,
    max_requests: int,
    window_sec: int = 60,
    error_message: str | None = None,
) -> None:
    """Sliding window rate limit check via Redis sorted set.

    Raises 429 if limit exceeded. Idempotent — call at the start of any
    endpoint that needs rate limiting.

    Args:
        key: Unique key (e.g. ``ocr:user_42``, ``ai:user_42``).
        max_requests: Max requests allowed within the window.
        window_sec: Window size in seconds.
        error_message: Custom 429 detail message.
    """
    redis = await get_redis()
    now = time.time()
    window_start = now - window_sec
    redis_key = f"ratelimit:{key}"

    # Remove old entries outside the window
    await redis.zremrangebyscore(redis_key, 0, window_start)

    # Count current entries in window
    count = await redis.zcard(redis_key)

    if count >= max_requests:
        raise HTTPException(
            status_code=429,
            detail=error_message or f"Rate limit exceeded: {max_requests}/{window_sec}s",
        )

    # Add current request timestamp and set TTL
    await redis.zadd(redis_key, {str(now): now})
    await redis.expire(redis_key, window_sec * 2)  # Cleanup after 2x window
