"""Redis-backed rate limiter — atomic sliding window via Lua script.

Replaces slowapi and custom in-memory OCR limiter.

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

# Lua script: atomic sliding window check-and-add.
# Returns {allowed: 1/0, current_count: int}.
_SLIDING_WINDOW_LUA = """
local key = KEYS[1]
local max = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local window_start = now - window

redis.call('zremrangebyscore', key, 0, window_start)
local count = redis.call('zcard', key)

if count >= max then
    return {0, count}
end

redis.call('zadd', key, now, tostring(now))
local new_count = count + 1
redis.call('expire', key, window * 2)
return {1, new_count}
"""


async def check_rate_limit(
    key: str,
    max_requests: int,
    window_sec: int = 60,
    error_message: str | None = None,
) -> None:
    """Sliding window rate limit check via Redis Lua script.

    Atomic check-and-add prevents TOCTOU race conditions where two
    concurrent requests could both pass the guard before either appends.

    Raises 429 if limit exceeded.

    Args:
        key: Unique key (e.g. ``ocr:user_42``, ``ai:user_42``).
        max_requests: Max requests allowed within the window.
        window_sec: Window size in seconds.
        error_message: Custom 429 detail message.
    """
    redis = await get_redis()
    now = time.time()
    redis_key = f"ratelimit:{key}"

    result = await redis.eval(
        _SLIDING_WINDOW_LUA,
        1,
        redis_key,
        max_requests, window_sec, now,
    )

    allowed, current_count = result  # [1, count] or [0, count]

    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=error_message or f"Rate limit exceeded: {max_requests}/{window_sec}s",
        )
