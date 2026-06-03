from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi import Request
from fastapi.responses import JSONResponse

from slowapi import _rate_limit_exceeded_handler
from slowapi.middleware import SlowAPIMiddleware
from slowapi.errors import RateLimitExceeded

from contextlib import asynccontextmanager

from app.core.config import settings
from app.core.limiter import limiter
from app.database import init_pool, close_pool
from app.core.redis import init_redis, close_redis
from app.routers import auth, categories, transactions, summaries, health, households, exports, budgets, ocr, ai_advisor


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_pool()
    await init_redis()
    yield
    await close_pool()
    await close_redis()


app = FastAPI(title=settings.APP_NAME, version=settings.VERSION, lifespan=lifespan)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(SlowAPIMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Catch unhandled exceptions & return consistent JSON."""
    # FastAPI / Starlette HTTPException subclasses are handled natively;
    # this only catches truly unexpected errors (DB crashes, type errors, etc.)
    return JSONResponse(
        status_code=500,
        content={
            "detail": {
                "code": "INTERNAL_ERROR",
                "message": "An unexpected error occurred",
            }
        },
    )


app.include_router(auth.router, prefix="/api/v1")
app.include_router(categories.router, prefix="/api/v1")
app.include_router(transactions.router, prefix="/api/v1")
app.include_router(summaries.router, prefix="/api/v1")
app.include_router(health.router, prefix="/api/v1")
app.include_router(households.router, prefix="/api/v1")
app.include_router(exports.router, prefix="/api/v1")
app.include_router(budgets.router, prefix="/api/v1")
app.include_router(ocr.router, prefix="/api/v1")
app.include_router(ai_advisor.router, prefix="/api/v1")
