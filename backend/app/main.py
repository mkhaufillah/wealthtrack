import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.config import settings
from app.core.i18n import error_body, locale_from_request
from app.core.limiter import limiter
from app.core.meilisearch import close_meilisearch, init_meilisearch
from app.core.redis import close_redis, init_redis
from app.core.vault_ctx import VaultPendingError, VaultRequiredError
from app.database import background_tasks, close_pool, init_pool
from app.routers import (
    ai_advisor,
    api_keys,
    auth,
    bank_inbox,
    budgets,
    categories,
    credit_cards,
    exports,
    health,
    households,
    kpr,
    mcp,
    ocr,
    summaries,
    transactions,
    ui,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_pool()
    await init_redis()
    await init_meilisearch()
    # Drop leftover receipt images from a crashed/restarted OCR job.
    try:
        from app.services.ocr_service import sweep_ocr_images

        sweep_ocr_images()
    except Exception:
        pass
    yield
    # Cancel all tracked background tasks gracefully
    for task in set(background_tasks):
        task.cancel()
    if background_tasks:
        await asyncio.wait(
            background_tasks, timeout=10.0
        )
    background_tasks.clear()
    await close_pool()
    await close_redis()
    close_meilisearch()


app = FastAPI(title=settings.APP_NAME, version=settings.VERSION, lifespan=lifespan)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(SlowAPIMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "Accept", "X-Requested-With", "X-Locale", "X-Vault-Key"],
)


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    loc = locale_from_request(request.headers)
    detail = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
    return JSONResponse(status_code=exc.status_code, content=error_body(loc, detail))


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    loc = locale_from_request(request.headers)
    return JSONResponse(status_code=422, content=error_body(loc, "err.validation"))


@app.exception_handler(VaultRequiredError)
async def vault_required_exception_handler(request: Request, exc: VaultRequiredError):
    """No usable vault key on this request → 403, never a 500 stacktrace.

    Home/summaries used to blow up with a 500 when the client sent no key,
    which the app surfaced as a generic crash screen instead of the vault
    gate. Same contract as the other vault routes (403 err.vault_required).
    """
    loc = locale_from_request(request.headers)
    return JSONResponse(
        status_code=403, content=error_body(loc, "err.vault_required")
    )


@app.exception_handler(VaultPendingError)
async def vault_pending_exception_handler(request: Request, exc: VaultPendingError):
    """Key not shared yet (owner hasn't sent the gembok) → 404 err.vault_pending."""
    loc = locale_from_request(request.headers)
    return JSONResponse(
        status_code=404, content=error_body(loc, "err.vault_pending")
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    loc = locale_from_request(request.headers)
    return JSONResponse(status_code=500, content=error_body(loc, "err.generic"))


app.include_router(auth.router, prefix="/api/v1")
app.include_router(categories.router, prefix="/api/v1")
app.include_router(transactions.router, prefix="/api/v1")
app.include_router(summaries.router, prefix="/api/v1")
app.include_router(health.router, prefix="/api/v1")
app.include_router(households.router, prefix="/api/v1")
app.include_router(exports.router, prefix="/api/v1")
app.include_router(budgets.router, prefix="/api/v1")
app.include_router(credit_cards.router, prefix="/api/v1")
app.include_router(ocr.router, prefix="/api/v1")
app.include_router(kpr.router, prefix="/api/v1")
app.include_router(ai_advisor.router, prefix="/api/v1")
app.include_router(api_keys.router, prefix="/api/v1")
app.include_router(ui.router, prefix="/api/v1")
app.include_router(bank_inbox.router, prefix="/api/v1")

app.include_router(mcp.router, prefix="/api/v1/mcp", tags=["mcp"])
