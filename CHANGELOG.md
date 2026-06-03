# Changelog

## v0.5.0 — SQLite → PostgreSQL Migration (2026-06-03)

**Backend database migrated from SQLite to PostgreSQL.**

### Breaking Changes
- **Database driver** — `aiosqlite` replaced with `asyncpg`. All raw SQL queries rewritten for PostgreSQL (`$1` placeholders, `LEFT()` instead of `substr()`, `TO_CHAR()` instead of `strftime()`, `RETURNING id` instead of `lastrowid`).
- **Config** — New `DATABASE_URL` env var (`postgresql://user:pass@host:5432/wealthtrack`). Legacy `DB_PATH` retained for reference.
- **Dependencies** — `aiosqlite` removed from `requirements.txt`, `asyncpg>=0.29.0` added.

### Migration Tooling
- **`backend/scripts/export_to_postgres.py`** — Standalone Python script that reads SQLite data and outputs a pure PostgreSQL SQL dump. Zero SQLite dependency in the output. Use for VPS migration: `psql -U wealthtrack -d wealthtrack -f postgres_migration.sql`.
- **PostgreSQL migration applied** — All 9 tables migrated: users (2), categories (22), transactions (50), budgets (18), households (1), household_members (2), ocr_jobs (16), ai_messages (16), email_verifications (10). Sequences reset.
- **SQLite file preserved** — `~/.keuangan/finance.db` kept as backup, not deleted.

### Architecture
- **`database.py`** — New `CursorWrapper` wraps asyncpg connections with backward-compatible cursor interface. Auto-converts `?`→`$1..$N` placeholders, appends `RETURNING id` to INSERTs, handles composite-PK tables gracefully (household_members).
- **`main.py`** — Added `lifespan` async context manager for pool init/close.
- **Connection pool** — `asyncpg.create_pool` (min 2, max 10) with request-scoped connections.

### Bug Fixes (PostgreSQL strictness)
- **GROUP BY strictness** — 6 queries fixed where PostgreSQL requires all non-aggregate columns in GROUP BY (summaries, budgets, budget_ai). SQLite was lenient about this.
- **GROUP BY alias ambiguity** — `GROUP BY date` resolved to `GROUP BY 1` when `date` is both a table column and a column alias.

### Tests
- **Test suite migrated** — `conftest.py` rewritten for asyncpg. Fresh PostgreSQL test database (`wealthtrack_test`) per function. 189 tests passing.
- **`test_households.py`** — Removed `aiosqlite` imports, `await db.commit()` calls, switched to `$1` placeholders.

### Docs
- Architecture, schema, and deployment docs updated for PostgreSQL.
- PostgreSQL migration guide added.

---

## v0.4.4 — Budget Display Fixes, Error Humanization & OCR Dismiss Persistence (2026-06-02)

### Fixes
- **Budget Remaining Logic** — Changed over-budget detection from `percentage >= 100` to `remaining <= 0`. Three display states now: "Over by X" (remaining < 0), "Budget exhausted" (remaining == 0), "X remaining" (remaining > 0). Fixes: budget exhausted shown when actually Rp1.000 over; negative "Over by -10.000" shown when actually Rp10.000 remaining.
- **Percentage Display** — Recalculated locally from raw `actualSpent`/`budgetAmount` ints to avoid backend floating-point rounding (99.999 → 100.0). Display floors at 1 decimal (98.8727 → 98.8%).
- **OCR Error Dismiss — Job ID Fingerprinting** — Changed from error-text-based fingerprint to `failed_job_id` from the server. Previously, dismissing with fingerprint-by-text meant all future failures (same "OCR failed..." text) were also suppressed — even from new scan attempts. Now each OCR job has a unique ID: dismissing job 5 only suppresses job 5; job 6's failure shows regardless of same error text.
- **OCR Error Banner on New Scan** — `clearError()` replaces `resetDismissed()`. On new scan, the visible error banner clears immediately but the dismissed job ID fingerprint stays intact. Old error stays suppressed while new job processes. Fixes: old error reappearing "below loading overlay" on `/transactions` after starting a new scan.
- **OCR Error Banner Dismiss Persistence** — Dismissed `failed_job_id` saved to `SecureStorage` (was error text). Survives app restart.
- **OCR Error Messages Unified** — All three error paths (Vision API error, JSON parse error, generic exception) now use: `'OCR failed. Please try again with a clearer photo.'`. No more raw technical messages.
- **OCR AddTransaction Error** — Now uses centralized `handleError` instead of inline catch with raw message.

### Features
- **Human-Readable Error Messages** — `ApiException.toString()` returns just the message (no prefix). `handleError` maps all backend errors to friendly English:
  - Login/register errors → clear actionable text
  - Network/timeout → "No internet connection. Please check and try again."
  - 401 → "Session expired. Please login again."
  - 429 → "Too many requests. Please wait a moment."
  - Unrecognized → "Something went wrong. Please try again."
- **Tap Budget Card to Filter** — Tapping a budget card navigates to Transactions tab with category filter pre-applied.

### API Changes
- `GET /api/v1/ocr/pending-count` — Response now includes `failed_job_id` (nullable integer) for fingerprint-based error dismissal.

### Tests
- Backend tests: unchanged (still passing)
- Flutter tests: 253+ passing

### Docs
- CHANGELOG, Flutter mobile docs (section 13 budget display, section 15 error handling), OCR scanner doc (error banner, job ID fingerprinting) synced.

---

## v0.4.3 — OCR Queue, AI Advisor Abuse Protection & Stability (2026-05-31)

### Features
- **OCR Per-User Queue** — Each user can only have 1 active OCR job at a time. Attempting to upload another invoice while one is processing returns 429. Prevents user-level spam.
- **OCR System Semaphore** — `asyncio.Semaphore(2)` limits concurrent Vision API calls across all users. Prevents rate limit bursts on OpenCode Go.
- **AI Advisor Abuse Protection** — Text field and send button are disabled while AI is still processing a response. Re-enabled only when response completes or errors. Prevents double-send cost.

### Fixes
- **Delete OCR Transaction** — Changed from `UPDATE ocr_jobs SET transaction_id = NULL` to `DELETE FROM ocr_jobs WHERE transaction_id = ?`. Cleaner data cleanup.
- **Delete Account** — Added `DELETE FROM ocr_jobs WHERE user_id = ?` to prevent FK constraint errors on account deletion.
- **OCR 429 Retry** — Increased retry attempts from 3→5 with jittered exponential backoff (1s×jitter → 8s×jitter, random 0.5-1.5x). Spreads retry timing to avoid thundering herd.
- **AI Advisor Auto-Scroll** — Added delayed backup scroll (200ms) after post-frame callback to handle late MarkdownBody layout. Scroll now reaches bottom 100% of the time.
- **OCR Reload on Any Completion** — Changed from reloading only when all jobs complete (`next == 0`) to reloading when ANY job finishes (`next < previous`). Transaction list and dashboard refresh incrementally.
- **OCR Immediate Badge** — OCR pending count loads immediately on screen init instead of waiting for the first 5-second poll tick. Add transaction screen also triggers a load before navigation.

### API Changes
- `POST /api/v1/ocr/process-and-save` — Returns 429 if user already has a processing OCR job
- `POST /api/v1/ocr/process` — No change (uses separate endpoint)

### Performance
- OCR Vision API calls reduced from burst-N to max 2 concurrent system-wide via `asyncio.Semaphore(2)`

### Tests
- 189 backend tests passing
- 250 Flutter tests passing

### Docs
- CHANGELOG, README, OCR scanner doc synced with new protections.

---

## v0.4.2 — CI Notifications & Workflow Cleanup (2026-05-31)

### Infrastructure
- **Telegram CI Notifications** — Both `build-apk.yml` and `deploy-backend.yml` now send build/deploy result notifications to dedicated **🤖 Deployment** topic in Forum Anak Intern group.
- **Artifact cleanup** — Removed debug APK upload (saves ~76MB/run). Set artifact retention to 1 day (was 90 days). Prevents GitHub Actions storage quota exhaustion.
- **Secrets configured** — `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `TELEGRAM_TOPIC_ID` added to repo secrets.

### CI Changes
- `build-apk.yml` — Removed debug APK build/verify/upload steps. Added Telegram success + failure notifications with commit SHA and run link.
- `deploy-backend.yml` — Added `message_thread_id` targeting to route notifications to **🤖 Deployment** topic (previously sent to General).

### Docs
- CHANGELOG, deployment doc synced with CI notification setup.

## v0.4.1 — Email Registration & OTP Verification (2026-05-31)

### Features
- **Email Registration** — Register now requires a valid email address. User enters email → receives 6-digit OTP via SMTP → enters OTP to complete registration.
- **Email in Profile** — `/auth/me` now returns `email` field. Profile screen displays email below username.
- **Seed Emails** — Filla: `khaufillahmohammad@gmail.com`, Nahda: `nahdanurfitriana3@gmail.com`.
- **Update Email** — `PUT /auth/me` supports updating email (with duplicate check).

### API Changes
- New `POST /api/v1/auth/send-otp` — send OTP code to email (rate limit: 3/min)
- `POST /api/v1/auth/register` — now requires `email` + `otp_code` + `username` + `display_name` + `password`
- `GET /api/v1/auth/me` — response includes `email`
- `PUT /api/v1/auth/me` — accepts optional `email` field

### Infrastructure
- **SMTP** — Configurable via `SMTP_HOST/PORT/USERNAME/PASSWORD` env vars. Gmail App Password integration.
- **Migration** — `email TEXT` column added to `users`, `email_verifications` table created, unique partial index on email.
- `email-validator` added to requirements.

### Tests
- 189 backend tests passing (new: send-otp success, invalid email, register without OTP, email in /me).
- 248 Flutter tests passing (fixed mock signatures, updated register screen tests for email/OTP flow).

### Docs
- CHANGELOG, README, database schema, backend API, Flutter docs synced with new email feature.

### Features
- **Budget Suggestions API** — `GET /budgets/suggestions` analyzes last 3-12 billing cycles of historical spending and recommends budget amounts per expense category. Suggestion = historical average rounded up to nearest Rp10k (min Rp10k). Detects existing budgets and warns if total suggested exceeds income.
- **Budget Health API** — `GET /budgets/health` returns mid-cycle projections: daily spending rate, projected end-of-cycle total, and per-category health status (healthy/warning/at_risk/exhausted).
- **Budget AI Utils** — `app/utils/budget_ai.py` with reusable `get_historical_spending()` and `get_projection()` functions.
- **Flutter: AI Suggestions sheet** — Bottom sheet showing suggested budgets per category with accept/decline checkbox, Select All/Clear, and "Apply N Budgets" button. Accessible from FAB and empty state on budgets screen.
- **AI Advisor: Budget Health context** — Advisor prompt enhanced with budget health projection data: days elapsed, cycle progress %, per-category health status (✅ Aman/⚠️ Hati-hati/🔴 Berisiko/❌ Habis), and projected overrun alerts. Analysis guidelines updated to recommend using projection data.
- **AI Advisor: Enhanced CARA MENGANALISIS** — Point 1 updated to explicitly use mid-cycle projection data for over-budget warnings.

### API Changes
- New `GET /api/v1/budgets/suggestions?month=&num_cycles=`
- New `GET /api/v1/budgets/health?month=`

### Tests
- 186 total backend tests passing (2 new: budget health projection + has_budget flag).
- 17 new mobile provider tests for budget suggestion (load, toggleAccept, toggleSelectAll, applySelected).
- 250 total mobile tests passing.

### Fixes
- **Transactions sort sheet** — FAB now hides when sort sheet is open (same pattern as category filter), shows again on dismiss.
- **Budgets screen dual FAB** — Increase bottom padding 80→140 for clearance with 2 FABs. Home "View All" button now uses `context.go` to navigate to bottom nav tab instead of pushing a new page.

### Docs
- README, backend API docs, Flutter mobile docs, and plan all synced with full v0.4.0 scope.

## v0.3.3 — OCR Performance Optimization (2026-05-31)

### Performance
- **Model swap** — OCR vision model changed from `kimi-k2.6` to `kimi-k2.5`. Rate limit increased from 1,150 → 1,850 per 5 hours (60% higher). Original m2.5 was text-only, m2.7 didn't process receipt text properly. |
- **Image compression** — Images are auto-resized to max 1200px on longest side (LANCZOS), converted to JPEG quality 85. Input up to 10 MB → ~200–500 KB output. Reduces upload time and API processing latency.

### Dependencies
- Added `Pillow>=10.0.0` to `requirements.txt`.

### Docs
- OCR scanner documentation updated to reflect new model, compression step, and architecture diagram.

## v0.3.2 — S&I Category Split & Reports Enhancements (2026-05-31)

### Features
- **Income S&I Split** — 'Tabungan & Investasi' income category (id=4) split into two: 'Penarikan Tabungan & Investasi' (Savings & Investment Disbursed) and new 'Hasil Investasi' (Savings & Investment Return). Each has separate keyword mappings for Hermes OCR classification.
- **Locked Categories** — Tabungan & Investasi (expense id=13, income id=4), Dana Darurat (expense id=18, income id=19), Penarikan Tabungan & Investasi, and Hasil Investasi are now locked (is_default=1) — cannot be edited or deleted via admin CRUD.
- **Savings Rate (Reports)** — Reports screen now shows adjusted savings rate using formula: ((income − expense) + (savings_expense − savings_disbursed)) / income × 100%. Savings & Investment Return is excluded. Replaces old raw formula.
- **Daily Average (Reports)** — Reports screen shows average daily expense (totalExpense / cycleDays) below savings rate.

### Fixes
- **Daily Average Bug** — Cycle label used 'dd MMM' for dFrom (no year) → DateFormat.parse fell back to 2000 → day diff ~9500 days → wrong value. Fixed with 'dd MMM yyyy' for both sides.

### API Changes
- **all-time-category-balance** — Return excluded from balance. Balance = Savings & Investment (expense) − Savings & Investment Disbursed (income).
- **Monthly report** — Response includes 'income_categories' array alongside 'categories' (expense).
- **AI Advisor** — All-time balance prompt uses dynamic breakdown (saved/withdrawn/return), handles legacy category names.

### Migration
- migrate_db.py: steps 17-18 handle S&I split idempotently.

### Docs
- API spec, Flutter (section 14), Admin Category CRUD, README updated.

---

## v0.3.1 — Category English Names & Home Widget (2026-05-30)

### Features
- **English Category Names (`category_name_en`)** — All endpoints (transactions, budgets, reports, summaries) now return `category_name_en`/`name_en` from the DB. Flutter UI uses `name_en` as primary display, falls back to Indonesian `category_name`.
- **Home Savings & Emergency Widget** — Dashboard now shows Savings & Investment and Emergency Funds balances from `/summaries/all-time-category-balance` endpoint.
- **Budget Exhausted Message** — Overspent budget categories show an "exhausted" label when percentage ≥ 100%.
- **Lainnya Locked** — "Lainnya" category cannot be edited or deleted via admin CRUD.
- **Transaction Search & Filters** — Search by description, filter by type (All/Expense/Income) and multi-select categories, sort by newest/oldest/highest/lowest/name A–Z/Z–A, paginated browsing with page controls.

### Fixes
- **category_translator.dart** — `translateCategory()` removed; category translation is now server-side via `name_en`. Flutter simply displays the field from the API response.
- **Home Savings Widget (bug)** — `_loadAllTimeBalances()` cast API response as `List?` but backend returns a `Map` (`savings_investment`/`emergency_funds` keys). Runtime error → catch → always Rp0. Fixed by parsing `data['savings_investment']['balance']` and `data['emergency_funds']['balance']` directly.
- **Test Fixtures** — Updated all Flutter test mock data to include `category_name_en`/`name_en` for consistency with new response shape.
- **Home Screen Tests** — Fixed timing-dependent assertions to match actual post-`load()` state.

### Docs
- API spec updated with `category_name_en`/`name_en` in all response examples
- README synced with new features (AI Advisor card, savings widget, budget exhausted, category CRUD)
- Flutter docs updated for name_en display logic

## v0.3.0 — Billing Cycle Support (2026-05-30)

### Core Features

- **Billing Cycles** — Configurable cycle start day per user, budgets & reports align to cycle date range, cycle-on overrides in budget create/upsert
- **Budget Overview** — Home screen shows totalBudget vs totalIncome comparison + non-budget expenses
- **Cycle Picker** — Flutter cycle picker in budgets & reports screens replacing calendar month view

### Fixes

- **Cycle Logic** — 4 major cycle bugs: correct date range per cycle, month label = START month, each budget uses its own cycle_on for actual_spent, cycle-info accepts `?date=` param, monthly endpoints accept `d_from/d_to_override`
- **UI Consistency** — Dark mode dropdown fix, default view loads correct month (not last), balance per month, color audit fixes across all screens, keyboard UX, edit type, screen refresh after mutations
- **Device Date** — Backend `/current-month` accepts `?ref_date=YYYY-MM-DD` so device date overrides server date

### Infrastructure

- **CI** — Release APK signing, debug + release APK both built per run, ProGuard rules for network classes, AndroidManifest INTERNET + cleartext patching
- **Deploy** — Health check via SSH (not runner localhost), backend config resolved by absolute path
- **Timezones** — Server set to Asia/Jakarta, WIB-conversion fixes for date handling

### Test Coverage

- **Backend** — +41 new tests (OCR mock, AI Advisor stream, households success, budgets upsert, export xlsx, multi-month range)
- **Mobile** — +59 new tests (AiAdvisorScreen, provider, network, service layers)

### Docs

- Billing cycle feature doc with architecture, API spec, and Flutter implementation
- README sync with cycle overview, budget overview, non-budget expenses, home cycle label

---

For detailed commit history, see [GitHub](https://github.com/filla/wealthtrack/commits/main).
