# Backend Architecture Reference

**See also:** [Project Overview](01-project-overview.md) · [Database Schema](02-database-schema.md) · [Backend API](03-backend-api.md) · [Deployment](07-deployment.md)

This document describes the **current production architecture** of the WealthTrack backend (v0.7.1). Source files in `backend/` remain the authoritative reference.

---

## Overview

WealthTrack's backend is a **FastAPI** application (Python 3.11+) using **asyncpg** for PostgreSQL with raw SQL (no ORM). It serves a Flutter mobile client and the Hermes AI agent via 12 API routers. Most business logic is inlined in the routers; two standalone engine modules (`kpr_engine.py`, `web_search.py`) handle computationally intensive or cross-cutting logic.

**Stack at a glance:**

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Framework | FastAPI 0.115+ | HTTP routing, dependency injection, OpenAPI docs |
| Database | PostgreSQL 16 + asyncpg | Relational data, connection pooling |
| Search | Meilisearch 1.12 | Full-text transaction search |
| Cache / Rate-limiting | Redis 7 | In-memory rate limiting (Lua sliding window) |
| AI Inference | OpenCode Go API | AI Advisor (DeepSeek Flash V4) + OCR (Kimi K2.5 vision) |
| Web Search | Brave Search API | Real-time financial data for AI Advisor |
| Reverse Proxy | Nginx | TLS termination, static file serving |
| CI/CD | Self-hosted GitHub runner | Automated deploy via `deploy.sh` |

---

## Project Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI app factory, lifespan, CORS, router registration
│   ├── database.py             # asyncpg pool manager, CursorWrapper, _init_schema(), get_db()
│   │
│   ├── core/
│   │   ├── config.py           # Pydantic-Settings, env loading (backend/.env, ~/.hermes/.env)
│   │   ├── security.py         # JWT encode/decode, bcrypt hashing, get_current_user()
│   │   ├── rate_limiter.py     # Redis-backed sliding window rate limiter (Lua script)
│   │   ├── limiter.py          # SlowAPI Limiter instance for IP-based rate limiting
│   │   ├── email.py            # SMTP email sending, OTP generation
│   │   ├── redis.py            # Redis connection manager (async singleton)
│   │   └── meilisearch.py      # Meilisearch client init, index CRUD, async search wrappers
│   │
│   ├── routers/                # 12 route modules, each → APIRouter
│   │   ├── auth.py             # /auth (send-otp, register, login, me, password, delete)
│   │   ├── categories.py       # /categories (list, admin CRUD)
│   │   ├── transactions.py     # /transactions (CRUD, transfer, search via Meilisearch)
│   │   ├── summaries.py        # /summaries (daily, monthly, household, cycle-aware)
│   │   ├── budgets.py          # /budgets (CRUD, summary, suggestions, health projection)
│   │   ├── exports.py          # /exports (yearly Excel download)
│   │   ├── households.py       # /households (create, join, members, invite codes)
│   │   ├── health.py           # /health (API + DB + Redis status)
│   │   ├── credit_cards.py     # /credit-cards (CRUD, transactions, installments, projections)
│   │   ├── ocr.py              # /ocr (process, process-and-save, pending-count)
│   │   ├── kpr.py              # /kpr (simulations, schedule, extra payments)
│   │   └── ai_advisor.py       # /ai (advise — streaming financial advice)
│   │
│   ├── schemas/                # Pydantic models for request/response validation
│   │   ├── user.py, category.py, transaction.py, budget.py
│   │   ├── household.py, credit_card.py, kpr.py, ocr.py
│   │   └── __init__.py
│   │
│   ├── services/               # Standalone engine modules
│   │   ├── kpr_engine.py       # Pure-Python amortization calculator
│   │   └── web_search.py       # Brave Search API client + keyword detection
│   │
│   ├── utils/
│   │   ├── cycle.py            # Billing cycle date range (custom cycle_start_day)
│   │   └── budget_ai.py        # Budget health projection logic
│   │
│   └── prompts/
│       └── ai_advisor.py       # (reserved for extracted prompt templates)
│
├── tests/                      # pytest + pytest-asyncio (313 tests)
│   ├── conftest.py             # Test fixtures, seed data, DB setup
│   ├── test_auth.py            # Registration, login, OTP flow
│   ├── test_transactions.py    # CRUD, ownership, transfers
│   ├── test_budgets.py         # CRUD, suggestions, health
│   ├── test_ai_advisor.py      # AI context building
│   ├── test_ocr.py             # OCR processing
│   ├── test_health.py          # Health check
│   ├── test_households.py      # Household management
│   ├── test_categories.py      # Category CRUD
│   ├── test_credit_cards.py    # Credit card + installment logic
│   ├── test_kpr.py             # KPR simulations + extra payments
│   ├── test_summaries.py       # Summary endpoints
│   ├── test_exports.py         # Excel export
│   ├── test_budget_health.py   # Budget health projection
│   ├── test_budget_suggestions.py
│   └── test_new_endpoints.py   # Catch-all for new additions
│
├── scripts/
│   └── migrate_v0_7_1.py       # Schema migration helper
│
├── requirements.txt
├── Dockerfile
└── .env.example
```

---

## Application Lifespan & Startup

`backend/app/main.py` defines the FastAPI application with a **lifespan** context manager:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_pool()           # Create asyncpg pool, run _init_schema()
    await init_redis()          # Connect to Redis
    await init_meilisearch()    # Ensure Meilisearch index exists
    yield
    # Shutdown — cancel background tasks, close connections
    for task in set(background_tasks):
        task.cancel()
    if background_tasks:
        done, pending = await asyncio.wait(background_tasks, timeout=10.0)
    background_tasks.clear()
    await close_pool()
    await close_redis()
    close_meilisearch()
```

### Database Initialization (`_init_schema()`)

Located in `backend/app/database.py`. On every application start, `_init_schema()` executes a large `SCHEMA_SQL` string containing all `CREATE TABLE IF NOT EXISTS` statements, followed by `ALTER TABLE ADD COLUMN IF NOT EXISTS` for columns added in later iterations. This means:

- **No separate migration tool** — the schema stays in sync automatically.
- **Idempotent** — safe to run on every restart.
- **Migrations** use `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` statements appended to `SCHEMA_SQL` (e.g., `kpr_simulations.household_id`, `credit_cards.household_id`).

Tables created:
- `users`, `email_verifications`, `categories`
- `transactions`, `budgets`, `households`, `household_members`
- `ocr_jobs`, `ai_messages`
- `kpr_simulations`, `kpr_rate_periods`, `kpr_monthly_schedules`, `kpr_extra_payments`
- `credit_cards`, `credit_card_transactions`, `credit_card_installments`

---

## Connection Pooling

The database module maintains a global **asyncpg connection pool** wrapped in a `CursorWrapper` that provides a cursor-like API.

### CursorWrapper

The `CursorWrapper` class (`backend/app/database.py`) wraps an asyncpg connection and provides:

```python
await db.execute(sql, params)   # Returns self for chaining
await cursor.fetchone()         # Returns first row or None
await cursor.fetchall()         # Returns list of rows
cursor.lastrowid                # Returns last inserted id (via RETURNING)
async for row in cursor:        # Iterates over fetched rows
await db.close()                # Releases connection back to pool
```

Key features:
- **`?` placeholder to `$1, $2, ...` conversion** — transparently translates SQLite-style `?` to PostgreSQL `$N` positional parameters.
- **Auto `RETURNING id`** — appends `RETURNING id` to INSERT statements that don't have one, enabling `lastrowid`.
- **`.transaction()` context manager** — wraps multiple statements in a single PostgreSQL transaction with automatic rollback on failure.
- **Auto-commit** — each standalone `execute()` is auto-committed (single-statement transactions).

### Pool Settings

```python
pool = await asyncpg.create_pool(
    dsn=settings.DATABASE_URL,
    min_size=2,
    max_size=10,
    command_timeout=30,
)
```

- **`min_size=2`**: Two connections always ready.
- **`max_size=10`**: Up to 10 concurrent connections under load.
- Every router endpoint uses `Depends(get_db)` to get a pooled connection wrapped in `CursorWrapper`.

### Redis Connection

Redis is used for rate-limiting and is connected via `redis.asyncio`:

```python
# backend/app/core/redis.py
async def get_redis() -> aioredis.Redis:
    if _redis is None:
        _redis = aioredis.Redis.from_url(settings.REDIS_URL, decode_responses=True)
    return _redis
```

---

## Router Architecture (12 Routers)

All routers are registered in `main.py` under the `/api/v1` prefix:

| Router | Prefix | Key Endpoints | Notes |
|--------|--------|--------------|-------|
| `auth.py` | `/auth` | `POST /send-otp`, `POST /register`, `POST /login`, `GET /me`, `PUT /me`, `PUT /password`, `DELETE /me` | OTP email verification, JWT, account deletion (cascading) |
| `categories.py` | `/categories` | `GET /`, `POST /`, `PUT /{id}`, `DELETE /{id}` | Admin CRUD, keyword management |
| `transactions.py` | `/transactions` | CRUD, `POST /transfer`, `GET /search`, `GET /unbudgeted` | Meilisearch-powered search, cross-user transfer |
| `summaries.py` | `/summaries` | `GET /daily`, `GET /current-month`, `GET /monthly`, `GET /household` | Cycle-aware summaries, paginated daily breakdown |
| `budgets.py` | `/budgets` | CRUD, `GET /summary`, `GET /suggestions`, `GET /health` | Budget health projection, AI-powered suggestions |
| `exports.py` | `/exports` | `GET /yearly?year=2026` | Excel download (XLSX) grouped by month |
| `households.py` | `/households` | `POST /`, `POST /join`, `GET /me`, `POST /invite`, `DELETE /{user_id}` | Invite codes, member management |
| `health.py` | `/health` | `GET /` | Returns `status`, `database`, `redis` state |
| `credit_cards.py` | `/credit-cards` | CRUD, `GET /next-month-projection`, card transactions, installments | Household-aware ownership |
| `ocr.py` | `/ocr` | `POST /process`, `POST /process-and-save`, `GET /pending-count` | Vision AI + background auto-save |
| `kpr.py` | `/kpr` | CRUD simulations, `GET /.../schedule`, extra payment preview/commit | Pure-python amortization engine |
| `ai_advisor.py` | `/ai` | `POST /advise` (streaming) | Context builder, web search, model routing |

Each router follows the same pattern:
1. Accept request via Pydantic schema.
2. Execute business logic inline (or call `kpr_engine.py` / `web_search.py`).
3. Return Pydantic response model.

---

## Authentication & Security

### OTP-Based Registration Flow

WealthTrack uses **email OTP** for registration (not traditional username/password signup):

```
1. POST /auth/send-otp  →  Server generates 6-digit OTP, stores in email_verifications table
2. User receives email with OTP (expires in 10 minutes)
3. POST /auth/register   →  Server verifies OTP, marks as used, creates user + hashed password
```

### JWT Flow

1. **Login** (`POST /auth/login`) — verifies username + bcrypt password, issues JWT.
2. **Token payload**: `sub` (user_id), `username`, `role`, `exp` (30 days).
3. **Protected endpoints** use `Depends(get_current_user)` which decodes the Bearer token via `HTTPBearer`.
4. **Role-based access**: Some endpoints check `current_user["role"] == "admin"`.

### Rate Limiting

Two-layer approach:

1. **SlowAPI** (IP-based) — used for auth endpoints: `3/minute` for OTP, `5/minute` for register, `10/minute` for login.
2. **Redis sliding window Lua script** — used for OCR (30/day) and AI Advisor (20/day). Atomic check-and-add prevents TOCTOU races.

### CORS

Restricted to explicit origins (no wildcard):
```
CORS_ORIGINS=["https://wealthtrack.filla.id","http://localhost:8080","null"]
```

### Password Security

- bcrypt hashing via `passlib.CryptContext`.
- Passwords never stored in plaintext.
- Token expiry: 30 days (configurable via `ACCESS_TOKEN_EXPIRE_DAYS`).

---

## Rate Limiting — Redis Sliding Window

`backend/app/core/rate_limiter.py` implements a Redis-backed sliding window rate limiter using an atomic Lua script:

```lua
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
redis.call('expire', key, window * 2)
return {1, count + 1}
```

Usage in endpoints:

```python
from app.core.rate_limiter import check_rate_limit

await check_rate_limit(
    key=f"ocr:user_{user_id}",
    max_requests=30,
    window_sec=86400,  # 24 hours
    error_message="OCR rate limit: max 30/day",
)
```

---

## Meilisearch Integration

Full-text search across transactions is powered by **Meilisearch** running on the same VPS (port 7700).

### Index Configuration

```python
INDEX_NAME = "transactions"
SEARCHABLE_ATTRIBUTES = ["description"]
FILTERABLE_ATTRIBUTES = ["user_id", "type", "category_id", "date"]
SORTABLE_ATTRIBUTES = ["date", "amount"]
```

### How It Works

1. **Indexing**: After every transaction insert/update, the router calls `index_document()` from `app.core.meilisearch` to sync the document (runs in a thread pool via `anyio.to_thread.run_sync`).
2. **Querying**: `GET /api/v1/transactions/search?q=...` searches Meilisearch and returns matching transaction IDs, then fetches full rows from PostgreSQL.
3. **Deletion**: `delete_document()` removes the document from the index when a transaction is deleted.
4. **Bulk operations**: `bulk_index_documents()` and `clear_index()` are available for migration scripts.

### Key files

- `backend/app/core/meilisearch.py` — Client initialization, index creation, all CRUD operations.
- All Meilisearch calls are synchronous and wrapped in `anyio.to_thread.run_sync()` for async compatibility.

---

## OCR Scanner (`/ocr`)

### Architecture

```
[Mobile: camera/gallery image]
        │
        ▼
[Backend POST /ocr/process (multipart/form-data)]
  ├── 1. Rate limit check (Redis: 30/day per user)
  ├── 2. Validate image: magic bytes (JPEG/PNG/WebP), size < 10MB
  ├── 3. Compress: resize to max 1200px, re-encode as JPEG quality 85
  ├── 4. Base64-encode and send to OpenCode Go API
  │     - Model: kimi-k2.5 (vision capable)
  │     - Prompt includes valid categories from DB
  │
  ├── 5. Parse JSON response
  ├── 6. Validate category against PostgreSQL (not AI hallucination)
  ├── 7. Return OCR result → mobile pre-fills Add Transaction form
  └── 8. (Optional) process-and-save → background task auto-creates transaction
```

### Image Validation

Before sending to the vision API, the backend validates:
- **Magic bytes** — checks `\xff\xd8\xff` (JPEG), `\x89PNG\r\n\x1a\n` (PNG), `RIFF` (WebP).
- **File size** — rejects images > 10 MB.
- **Compression** — resizes if longest side > 1200px, re-encodes as JPEG quality 85.
- **Supported MIME**: `image/jpeg`, `image/png`, `image/webp`, `image/heic`, `image/heif`.

### Background Auto-Save

`POST /ocr/process-and-save` runs the OCR pipeline as a background `asyncio.Task`:
- Creates an `ocr_jobs` record with status `processing`.
- Saves the raw image to disk (`settings.OCR_IMAGE_DIR`).
- Runs vision API with retry (5 attempts, exponential backoff for 429).
- On success, automatically creates a transaction and updates the job status to `completed`.
- On failure, updates the job status to `failed` with an error message.

### Rate Limiting

- **30 OCR scans/day per user** (Redis sliding window).
- **Per-user queue** — only one processing job allowed at a time (rejects with 429).
- **System-wide semaphore** — max 2 concurrent Vision API calls across all users.

---

## KPR Engine

`backend/app/services/kpr_engine.py` is a **pure-Python amortization calculator** with no external dependencies.

### Supported Interest Types

| Type | Description |
|------|-------------|
| `fixed` | Single fixed annual rate throughout loan term |
| `floating` | Single floating rate throughout (no automatic adjustment) |
| `graduated` | Rate increases by `graduated_increment` every `graduated_every_months` periods |
| `mix` | Custom rate periods defined by the user (e.g., 3 years fixed → floating) |

### Core Algorithm

The engine implements the standard amortization formula:

```
M = P * (r * (1+r)^n) / ((1+r)^n - 1)
```

Where `M` = monthly payment, `P` = principal, `r` = monthly interest rate, `n` = number of months.

All calculations use `Decimal` for exact integer (IDR) arithmetic.

### Features

- `calculate_kpr()` — Returns full `list[MonthlySchedule]` for the entire loan term.
- `simulate_summary()` — Aggregates total payment, total interest, monthly payment.
- `apply_extra_payment()` — Applies extra payment at a specific month with two reduction options:
  - **Opsi A (installment)**: Keep same tenor, recalculate lower monthly payment.
  - **Opsi B (tenor)**: Keep same payment, shorten tenor.
- `preview_extra_payment()` — Shows both options side-by-side without side effects.

### Database Integration

The KPR router (`/kpr`) persists simulations in three tables:
- `kpr_simulations` — Metadata (property price, loan amount, tenor, interest type).
- `kpr_rate_periods` — Rate periods for "mix" interest type.
- `kpr_monthly_schedules` — Full amortization schedule (one row per month).
- `kpr_extra_payments` — Record of applied extra payments with before/after state.

Household sharing: Simulations can be shared with household members via `household_id`.

---

## AI Advisor (`/ai/advise`)

### Architecture

```
[Mobile: user asks financial question]
        │
        ▼
[Backend POST /api/v1/ai/advise]
  ├── 1. Build context — query DB for user's financial summary
  │     - Current cycle income/expense/balance
  │     - Per-category breakdown with member attribution
  │     - 6-cycle trend (cycle-aware, not calendar month)
  │     - Budget vs actual with health projection
  │     - Recent transactions (last 15)
  │     - All-time category balances (S&I, Dana Darurat)
  │     - Household-level debt summary (KPR + CC)
  │     - Per-member activity summary
  │
  ├── 2. (Optional) Web search — Brave Search API
  │     - Triggered by keyword matching in _should_search()
  │     - 160+ high-confidence keywords (financial terms, market data)
  │     - Results injected as [Hasil Pencarian Web] section
  │
  ├── 3. Route to model:
  │     - Default: DeepSeek Flash V4 (via OpenCode Go API /zen/go/v1)
  │     - Admin users only: Claude Opus (via OpenRouter)
  │
  ├── 4. Stream response → mobile chat UI (SSE-style)
  │
  └── 5. Rate-limit: 20 queries/day per user (Redis sliding window)
```

### Key files

- `backend/app/routers/ai_advisor.py` — Streaming endpoint (893 lines), context builder, prompt construction.
- `backend/app/services/web_search.py` — Brave Search API client with comprehensive keyword detection.
- `backend/app/utils/cycle.py` — Billing cycle date range utilities.
- `backend/app/utils/budget_ai.py` — Budget health projection engine.
- `backend/app/prompts/ai_advisor.py` — Reserved for extracted system prompt templates.

### Debt Context

The context builder is **household-aware** — it queries KPR simulations and credit card data across all household members, computing:
- Total outstanding KPR balance (per-simulation, per-member).
- Current-month credit card transactions (non-installment).
- Active installment plans with remaining amounts.
- Per-member debt breakdown with interest type categorization.

---

## Web Search (`web_search.py`)

`backend/app/services/web_search.py` provides the Brave Search API integration for the AI Advisor.

### Keyword Detection

Two-tier system:
- **HIGH_CONFIDENCE** (160+ terms) — Always triggers web search. Covers: monetary policy, currency rates, stock market, gold prices, KPR, credit cards, inflation, crypto, etc.
- **MEDIUM_KEYWORDS** — Triggers search on any match. Covers: trending terms, recommendations, comparisons, predictions, guides.

### API Client

```python
async def search_web(query: str, count: int = 5) -> list[dict]:
    # Returns [{"title", "snippet", "url"}, ...]
    # Returns empty list on error or missing API key
```

Results are formatted as `[Hasil Pencarian Web]` section and injected into the AI Advisor prompt.

---

## Testing

WealthTrack uses **pytest** + **pytest-asyncio** with a dedicated PostgreSQL test database.

### Test Infrastructure

- **15 test files** with **313 test functions** across all 12 routers.
- `conftest.py` provides:
  - `TEST_DB_URL` — separate test database (default: `wealthtrack_test`).
  - Drop-all-tables + re-create at module setup.
  - Seed data: 2 default users, 8 categories, 5 transactions.
  - `ASGITransport`-based `AsyncClient` for HTTP-free FastAPI testing.
  - Token generation helpers (`create_access_token`).
- All tests run against a real PostgreSQL database (no mocking).

### Running Tests

```bash
cd ~/dev/wealthtrack
source .venv/bin/activate
pytest backend/tests/ -v --asyncio-mode=auto
```

### Test Coverage

| Test File | Focus |
|-----------|-------|
| `test_auth.py` | Registration, login, OTP verification, password change, account deletion |
| `test_transactions.py` | CRUD, ownership enforcement, transfers, search |
| `test_budgets.py` | CRUD, month-scoped queries, suggestions, health |
| `test_summaries.py` | Cycle-aware daily/monthly/household summaries |
| `test_ai_advisor.py` | Context building, prompt construction |
| `test_ocr.py` | Image validation, processing, background auto-save |
| `test_kpr.py` | Simulation CRUD, schedule calculation, extra payments |
| `test_credit_cards.py` | Card CRUD, transactions, installments, projections |
| `test_households.py` | Create, join, invite codes, member management |
| `test_categories.py` | Category CRUD, keyword management |
| `test_exports.py` | Excel generation, data formatting |
| `test_health.py` | Health check endpoint responses |
| `test_budget_health.py` | Budget health projection logic |
| `test_budget_suggestions.py` | AI-powered budget suggestions |
| `test_new_endpoints.py` | Catch-all for new additions |

---

## Environment Variables

All configuration is loaded via **pydantic-settings** from two `.env` files (in order of precedence):

1. `backend/.env` — Primary config (checked into `.gitignore`).
2. `~/.hermes/.env` — Hermes fallback (shared secrets).

```bash
# Application
APP_NAME=WealthTrack API
VERSION=0.5.0
DEBUG=False

# JWT
SECRET_KEY=...                              # Random 32-byte hex, default warns if unchanged
ACCESS_TOKEN_EXPIRE_DAYS=30
ALGORITHM=HS256

# CORS — restricted (no wildcard)
CORS_ORIGINS=["https://wealthtrack.filla.id","http://localhost:8080","null"]

# Database
DATABASE_URL=postgresql://wealthtrack:***@localhost:5432/wealthtrack

# Redis
REDIS_URL=redis://:<password>@localhost:6379/0

# Search
MEILISEARCH_URL=http://localhost:7700
MEILISEARCH_MASTER_KEY=...                  # Random 32-char

# OCR & AI Advisor
OPENCODE_GO_API_KEY=sk-...                  # From OpenCode Go

# AI Advisor — optional premium model
OPENROUTER_API_KEY=sk-or-...                # For Claude Opus (admin only)

# AI Advisor — optional web search
BRAVE_SEARCH_API_KEY=...                    # Brave Search for real-time data

# SMTP (OTP email)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=...                           # SMTP login username
SMTP_PASSWORD=...                           # SMTP login password
EMAIL_FROM=wealthtrack@example.com          # Sender email address
EMAIL_FROM_NAME=WealthTrack                 # Sender display name

# OCR storage
OCR_IMAGE_DIR=/var/data/wealthtrack/ocr     # Where uploaded images are saved
```

---

## Key Design Decisions

1. **Inline business logic in routers** — Unlike a traditional service-layer pattern, most business logic lives directly in the router files. Only computationally intensive or cross-cutting logic is extracted to `services/` (`kpr_engine.py`, `web_search.py`). This keeps the codebase simple and avoids over-abstracting for a team of one.

2. **CursorWrapper adapter** — Provides a cursor-like API on top of asyncpg (with `?` → `$N` placeholder conversion, auto `RETURNING id`, `.transaction()` support). This simplifies the migration path from SQLite during development.

3. **Auto-schema init** — `_init_schema()` runs `CREATE TABLE IF NOT EXISTS` and `ALTER TABLE ADD COLUMN IF NOT EXISTS` on every startup. No migration tooling needed for schema changes.

4. **Async everywhere** — FastAPI + asyncpg + httpx (for AI calls) — fully asynchronous, non-blocking I/O.

5. **Redis for rate limiting** — In-memory dicts are unreliable across restarts; Redis provides persistence and works across multiple workers. The Lua script ensures atomic check-and-add operations.

6. **Category keywords as JSON** — Categories have a `keywords TEXT` column storing a JSON array. This is populated via admin CRUD and used by OCR for category validation.

7. **No ORM** — Raw asyncpg queries with manual mapping. Keeps full control over SQL and performance.

8. **Cycle-aware financial periods** — Users can set a custom `cycle_start_day` (e.g., 25th) so their financial period runs from day N of month M to day N-1 of month M+1, instead of the fixed calendar month.

9. **Household-aware data model** — KPR simulations and credit cards can be shared across household members via `household_id`. Summaries and AI context aggregate data across all members.

---

## Deployment

See [Deployment](07-deployment.md) for the full CI/CD pipeline. Key points:

- **Host binding**: `127.0.0.1:8080` (behind Nginx).
- **Process manager**: systemd service for FastAPI + Uvicorn.
- **CI/CD**: Self-hosted GitHub runner triggers `deploy.sh` on push to `main`.
- **Health check**: `GET /api/v1/health` returns `{"status": "ok", "database": "connected", "redis": "connected"}`.
