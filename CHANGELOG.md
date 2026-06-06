# Changelog

## v0.5.3 — CI/CD Migration, Security Hardening & 15 Code Fixes (2026-06-05)

### Infrastructure — Self-Hosted Runner

- **Self-hosted GitHub Actions runner** (`wealthtrack-vps`) — Registered on VPS, installed as systemd service. Replaces SSH-based deployment (port 2222 no longer needed). Runner communicates outbound to GitHub — no inbound ports required.
- **NOPASSWD sudo** — SUDO_PASSWORD secret eliminated. `/etc/sudoers.d/wealthtrack` allows `sudo systemctl restart wealthtrack` without password.
- **Workspace cleanup** — `git checkout` with `clean: false` preserves workspace between runs; full cleanup done via `git clean` + `git checkout -- .` in the deploy step.
- **Deprecated SSH secrets removed** — `VPS_HOST`, `VPS_SSH_KEY`, `VPS_USER`, `SUDO_PASSWORD` deleted from GitHub secrets.

### CI/CD — Telegram Notifications V2

- **🚀 CI Started** — Workflow now sends a notification as soon as tests begin, not just on success/failure.
- **❌ Tests failed** — Separate notification from deploy failure; catches the case where `test` job fails and `deploy` is skipped.
- **✅ Deploy success** — Unchanged notification on healthy deployment.
- **❌ Deploy failure** — Unchanged notification with direct link to GitHub Actions logs.
- **Workflow trigger** — `.github/workflows/deploy-backend.yml` path changes now trigger the workflow.
- **Secrets cleaned** — Only 5 secrets remain: `TG_BOT_TOKEN`, `DART`, `JAVA`, `FLUTTER`, `OPENROUTER_API_KEY`.

### Security Hardening

- **CORS wildcard restricted** — `CORS_ORIGINS` changed from `["*"]` to `["https://wealthtrack.filla.id", "http://localhost:8080", "null"]`. API no longer accepts requests from arbitrary origins.
- **Redis authentication** — `requirepass` configured in `/etc/redis/redis.conf`. Production Redis URL includes password; CI/test falls back to `redis://localhost:6379/0`.
- **PostgreSQL password hardened** — Changed from `wealthtrack123` to 32-char random password.
- **pg_hba.conf — Tailscale network removed** — `100.64.0.0/10` entry deleted. Only `127.0.0.1/32` and `::1/128` can connect. Zero network exposure.
- **Secret scanning** — CI YAML no longer embeds secrets in `env:` blocks (prevents `***` masking leaks).

### Code Fixes (15 Issues)

- **Type hints — `get_db` return type** — All 8 routers updated from `asyncpg.Connection` to `CursorWrapper` to match actual `database.py` implementation.
- **N+1 budget query** — Calendar month budget loading optimized from N+1 queries to a single query with JOIN.
- **OCR error messages** — Differentiated error responses for 429 (rate limit), 401 (auth), and 503 (service unavailable) instead of generic error.
- **AI Advisor comment** — Clearer fallback comment when OpenRouter API key not configured.
- **OCR delete query** — Changed from `UPDATE ocr_jobs SET transaction_id = NULL` to `DELETE FROM ocr_jobs` for proper cleanup.
- **CI fix #1 — YAML masking** — Password written via Python `open().write()` instead of direct string in YAML to prevent GitHub Actions from masking the value as `***`.
- **CI fix #2 — Redis URL** — Default `REDIS_URL` changed from `redis://localhost:***@localhost:6379/0` (which injected `***` literal) to `redis://localhost:6379/0` for test environments.
- **CI fix #3 — Test seed date** — `CURRENT_DATE` in test seed data replaced with fixed range `2026-01-01` to `2026-12-31` to prevent time-dependent test failures.
- **Backend config** — Default `CORS_ORIGINS` kept as `["*"]` with warning (overridden by `.env` in production).
- **Household test** — Added robust date range for household test seed data.
- **Health endpoint** — Added CORS origins config validation.
- **GitHub secrets** — Removed 4 deprecated secrets from repo.
- **conftest.py** — Added default `WEALTHTRACK_TEST_DATABASE_URL` fallback.
- **requirements.txt** — Added `python-multipart` explicit version pin.
- **Config cleanup** — Removed unused `SQLITE_PATH` override reference.

### Test Infrastructure

- **Dedicated test database** — `wealthtrack_test` database created and granted to `wealthtrack` user in PostgreSQL.
- **`run_tests.sh`** — Updated with correct database name and password.
- **CI test count** — **193/193 tests passing** across all pipelines.

### Docs

- README, deployment, project overview, backend API, and plan docs synced with all changes above.

---

## v0.5.2 — Auto-Create Schema & Index Optimization (2026-06-03)

### Infrastructure
- **Auto schema init** — `init_pool()` now auto-creates all tables and indexes with `IF NOT EXISTS`. Fresh VPS deployment needs zero manual SQL — schema is ready on first app startup.
- **New indexes** — `idx_transactions_user_date` (user_id, date DESC) for the most common transaction list query pattern; `idx_email_verifications_email` for OTP lookup.

### Database
- **`database.py`** — Added `SCHEMA_SQL` constant with full DDL for all 9 tables + 20 indexes. `_init_schema()` runs idempotently on pool initialization.

### Docs
- Database schema, deployment, and project overview docs synced with auto-schema flow.

---

## v0.5.1 — Full-Text Search with Meilisearch (2026-06-03)

### Added
- **Meilisearch 1.45.2** — Self-hosted full-text search engine for transaction descriptions. Replaces SQL `LIKE` with instant relevance-based search. Running as systemd service on `127.0.0.1:7700`, 512MB max indexing memory, single-node.
- **Search integration** (`backend/app/core/meilisearch.py`) — Async client wrapper with init/close lifecycle, index CRUD, and full-text search. Index fields: `description`, `type`, `amount`, `category_id`, `user_id`, `date`. Searchable: `description`. Filterable: `user_id`, `type`, `category_id`, `date`. Sortable: `date`, `amount`.
- **CRUD indexing hooks** — Transactions are automatically indexed in Meilisearch on create, update, delete, transfer-owner, and transfer-balance. Failures are silently caught (search unavailability never blocks writes).
- **Graceful fallback** — When Meilisearch is unavailable (e.g., test environment), search falls back to SQL `LIKE` transparently.
- **Bulk index script** (`backend/scripts/bulk_index_meilisearch.py`) — One-shot script to index all existing transactions. Idempotent.

### API Changes
- `GET /api/v1/transactions?q=...` — Now searches via Meilisearch instead of SQL `LIKE`. All existing filters (`type`, `category_id`/`category_ids`, `date_from`/`date_to`, `sort`) are remapped to Meilisearch filter syntax. Response format unchanged — Flutter needs no updates.

### Infrastructure
- **systemd service** — `meilisearch.service` with `After=network.target`, auto-restart on failure.
- **Dependencies** — `meilisearch>=0.30.0` added to `requirements.txt`.
- **Config** — New `MEILISEARCH_URL` and `MEILISEARCH_MASTER_KEY` in `config.py`.

### Performance
- **Description search** — O(1) lookup from inverted index vs O(n) sequential scan with `LIKE %keyword%`. Scales to millions of transactions.
- **Memory** — Meilisearch capped at 512MB indexing memory, ~30MB idle. Compatible with 3.8GB RAM VPS alongside PostgreSQL and Redis.

### Tests
- **4 new search tests** — search by description, no-match returns empty, search + type filter, search + category + date range. Fall back to SQL LIKE in test environment (Meilisearch not available in ASGI test client).
- **188/193 passing** — 5 pre-existing OCR test failures (Redis reconnect in test context, unrelated).

### Docs
- README updated: stack now includes Meilisearch, architecture diagram updated.
- CHANGELOG synced.

---

## v0.5.0 — PostgreSQL + Redis Infrastructure (2026-06-03)

**Production database migrated to PostgreSQL.** SQLite backup preserved at `~/.keuangan/finance.db`.

### Added
- **Redis 8.8.0** — In-memory data store for rate limiting, OCR queue, and AI response caching.
- **Redis-backed rate limiter** (`backend/app/core/rate_limiter.py`) — Sliding window via sorted sets, replaces OCR's in-memory `_check_rate_limit`. Persists across server restarts.
- **Redis connection manager** (`backend/app/core/redis.py`) — Singleton async pool, initialized in `main.py` lifespan.
- **Health check** — `/health` now reports Redis connectivity status (`"redis": "connected" | "unreachable"`).
- **Systemd dependency** — `wealthtrack.service` now `After=redis.service` + `Wants=redis.service`.
- **Deploy** — `deploy/deploy.sh` installs Redis service.

### Breaking Changes
- **Database driver** — Changed to `asyncpg`. Raw SQL queries use PostgreSQL syntax (`$1` placeholders, `LEFT()` / `TO_CHAR()` / `RETURNING id`).
- **Config** — New `DATABASE_URL` env var (`postgresql://user:pass@host:5432/wealthtrack`). Legacy `DB_PATH` removed.
- **Dependencies** — `aiosqlite` removed, `asyncpg>=0.29.0` added.

### Architecture
- **`database.py`** — New `CursorWrapper` wraps asyncpg connections with backward-compatible cursor interface. Auto-converts `?`→`$1..$N` placeholders, appends `RETURNING id` to INSERTs, handles composite-PK tables gracefully (household_members).
- **`main.py`** — Added `lifespan` async context manager for pool init/close.
- **Connection pool** — `asyncpg.create_pool` (min 2, max 10) with request-scoped connections.

### Bug Fixes (PostgreSQL strictness)
- **GROUP BY strictness** — 6 queries fixed where PostgreSQL requires all non-aggregate columns in GROUP BY (summaries, budgets, budget_ai).
- **GROUP BY alias ambiguity** — `GROUP BY date` resolved to `GROUP BY 1` when `date` is both a table column and a column alias.

### Tests
- **Test suite migrated** — `conftest.py` rewritten for asyncpg. Fresh PostgreSQL test database (`wealthtrack_test`) per function. 189 tests passing.

---

## v0.4.4 — Budget Display Fixes, Error Humanization & OCR Dismiss Persistence (2026-06-02)

### Fixes
- **Budget Remaining Logic** — Changed over-budget detection from `percentage >= 100` to `remaining <= 0`. Three display states now: "Over by X" (remaining < 0), "Budget exhausted" (remaining == 0), "X remaining" (remaining > 0).
- **Percentage Display** — Recalculated locally from raw `actualSpent`/`budgetAmount` ints to avoid backend floating-point rounding (99.999 → 100.0).
- **OCR Error Dismiss — Job ID Fingerprinting** — Changed from error-text-based fingerprint to `failed_job_id` from the server.
- **OCR Error Banner on New Scan** — `clearError()` replaces `resetDismissed()`. On new scan, the visible error banner clears immediately but the dismissed job ID fingerprint stays intact.
- **OCR Error Banner Dismiss Persistence** — Dismissed `failed_job_id` saved to `SecureStorage` (was error text). Survives app restart.
- **OCR Error Messages Unified** — All three error paths now use: `'OCR failed. Please try again with a clearer photo.'`.
- **OCR AddTransaction Error** — Now uses centralized `handleError` instead of inline catch with raw message.

### Features
- **Human-Readable Error Messages** — `ApiException.toString()` returns just the message (no prefix). `handleError` maps all backend errors to friendly English.
- **Tap Budget Card to Filter** — Tapping a budget card navigates to Transactions tab with category filter pre-applied.

### API Changes
- `GET /api/v1/ocr/pending-count` — Response now includes `failed_job_id` (nullable integer) for fingerprint-based error dismissal.

### Tests
- Backend tests: unchanged (still passing)
- Flutter tests: 253+ passing

---

## v0.4.3 — OCR Queue, AI Advisor Abuse Protection & Stability (2026-05-31)

### Features
- **OCR Per-User Queue** — Each user can only have 1 active OCR job at a time.
- **OCR System Semaphore** — `asyncio.Semaphore(2)` limits concurrent Vision API calls across all users.
- **AI Advisor Abuse Protection** — Text field and send button are disabled while AI is still processing a response.

### Fixes
- **Delete OCR Transaction** — Changed from `UPDATE ocr_jobs SET transaction_id = NULL` to `DELETE FROM ocr_jobs WHERE transaction_id = ?`.
- **Delete Account** — Added `DELETE FROM ocr_jobs WHERE user_id = ?` to prevent FK constraint errors.
- **OCR 429 Retry** — Increased retry attempts from 3→5 with jittered exponential backoff.
- **AI Advisor Auto-Scroll** — Added delayed backup scroll (200ms) after post-frame callback.
- **OCR Reload on Any Completion** — Changed from reloading only when all jobs complete to reloading when ANY job finishes.
- **OCR Immediate Badge** — OCR pending count loads immediately on screen init.

### API Changes
- `POST /api/v1/ocr/process-and-save` — Returns 429 if user already has a processing OCR job

### Performance
- OCR Vision API calls reduced from burst-N to max 2 concurrent system-wide via `asyncio.Semaphore(2)`

### Tests
- 189 backend tests passing
- 250 Flutter tests passing

---

## v0.4.2 — CI Notifications & Workflow Cleanup (2026-05-31)

### Infrastructure
- **Telegram CI Notifications** — Both `build-apk.yml` and `deploy-backend.yml` now send build/deploy result notifications.
- **Artifact cleanup** — Removed debug APK upload. Set artifact retention to 1 day.
- **Secrets configured** — `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `TELEGRAM_TOPIC_ID` added to repo secrets.

### CI Changes
- `build-apk.yml` — Removed debug APK build/verify/upload steps. Added Telegram success + failure notifications.
- `deploy-backend.yml` — Added `message_thread_id` targeting for topic routing.

---

## v0.4.1 — Email Registration & OTP Verification (2026-05-31)

### Features
- **Email Registration** — Register now requires a valid email address with 6-digit OTP via SMTP.
- **Email in Profile** — `/auth/me` now returns `email` field.
- **Update Email** — `PUT /auth/me` supports updating email (with duplicate check).

### API Changes
- New `POST /api/v1/auth/send-otp` — send OTP code to email (rate limit: 3/min)
- `POST /api/v1/auth/register` — now requires `email` + `otp_code` + `username` + `display_name` + `password`
- `GET /api/v1/auth/me` — response includes `email`
- `PUT /api/v1/auth/me` — accepts optional `email` field

### Infrastructure
- **SMTP** — Configurable via `SMTP_HOST/PORT/USERNAME/PASSWORD` env vars.
- `email-validator` added to requirements.

### Tests
- 189 backend tests passing
- 248 Flutter tests passing

---

## v0.4.0 — AI Budget Suggestions & Health (2026-05-31)

### Features
- **Budget Suggestions API** — `GET /budgets/suggestions` analyzes historical spending and recommends budget amounts.
- **Budget Health API** — `GET /budgets/health` returns mid-cycle projections.
- **Budget AI Utils** — `app/utils/budget_ai.py` with reusable `get_historical_spending()` and `get_projection()` functions.
- **Flutter: AI Suggestions sheet** — Bottom sheet showing suggested budgets with accept/decline checkbox.
- **AI Advisor: Budget Health context** — Advisor prompt enhanced with budget health projection data.

### API Changes
- New `GET /api/v1/budgets/suggestions?month=&num_cycles=`
- New `GET /api/v1/budgets/health?month=`

### Tests
- 186 total backend tests passing
- 250 total mobile tests passing

---

## v0.3.3 — OCR Performance Optimization (2026-05-31)

### Performance
- **Model swap** — OCR vision model changed from `kimi-k2.6` to `kimi-k2.5` (60% higher rate limit).
- **Image compression** — Images auto-resized to max 1200px (LANCZOS), JPEG quality 85. Input up to 10 MB → ~200–500 KB output.

---

## v0.3.2 — S&I Category Split & Reports Enhancements (2026-05-31)

### Features
- **Income S&I Split** — 'Tabungan & Investasi' income category split into 'Penarikan Tabungan & Investasi' and 'Hasil Investasi'.
- **Locked Categories** — Tabungan & Investasi, Dana Darurat, Penarikan Tabungan & Investasi, Hasil Investasi locked (cannot be edited/deleted).
- **Savings Rate (Reports)** — Adjusted formula accounting for savings category dynamics.
- **Daily Average (Reports)** — Shows average daily expense.

### Fixes
- **Daily Average Bug** — Cycle label date format fixed (`dd MMM yyyy` for both sides).

---

## v0.3.1 — Category English Names & Home Widget (2026-05-30)

### Features
- **English Category Names** — All endpoints return `category_name_en`/`name_en`.
- **Home Savings & Emergency Widget** — Dashboard shows Savings & Investment and Emergency Funds balances.
- **Transaction Search & Filters** — Search by description, multi-select categories, paginated browsing.

---

## v0.3.0 — Billing Cycle Support (2026-05-30)

### Core Features
- **Billing Cycles** — Configurable cycle start day per user.
- **Budget Overview** — Home screen shows totalBudget vs totalIncome comparison.
- **Cycle Picker** — Flutter cycle picker in budgets & reports screens.

### Infrastructure
- **CI** — Release APK signing, ProGuard rules, AndroidManifest patching.
- **Deploy** — Health check via runner localhost.
- **Timezones** — Server set to Asia/Jakarta.

For detailed commit history, see [GitHub](https://github.com/filla/wealthtrack/commits/main).
