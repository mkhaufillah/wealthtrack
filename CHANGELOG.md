# Changelog

## v0.7.2 — Dockerization & GitHub-Hosted Runners (2026-06-21)

### Infrastructure & Deployment
- **Dockerized Backend:** Replaced native `systemd` deployment with a containerized deployment (`python:3.11-slim` Docker image).
- **GitHub-Hosted Runners:** Migrated CI/CD workflows (`build-apk.yml`, `deploy-backend.yml`) from self-hosted runners to GitHub-hosted ephemeral `ubuntu-latest` runners.
- **SSH Deployment:** Deploys are now executed via `appleboy/ssh-action` to build and restart the Docker container on the VPS.
- **Network Host:** Docker container uses `--network host` to maintain seamless connectivity to local PostgreSQL and Redis instances on the VPS.
- **Removed Self-Hosted Runner:** Cleaned up documentation and dependencies related to the outdated self-hosted runner.

---
## v0.7.0 — Extra Payment KPR + Household Debt (2026-06-09)

### Extra Payment KPR

**Two reduction options for extra payments:**
- **Option A — Reduce Installment:** Keep same tenor, lower monthly payment when principal is reduced
- **Option B — Reduce Tenor:** Keep same installment, shorter loan period, save more total interest
- Preview comparison: See both options side-by-side before committing
- Penalty rate support (% of extra payment, configurable)
- Multiple extra payments can stack — each recalculates the amortization schedule
- Delete extra payment: Regenerates original schedule, re-applies remaining extras

**Engine (`kpr_engine.py`):**
- `apply_extra_payment()` — core function supporting both reduction types
- `preview_extra_payment()` — returns comparison of both options without DB write
- `_build_schedule_from()` — generates amortization schedule from a given starting point
- `ExtraPaymentResult` / `ExtraPaymentComparison` dataclasses

**New DB table: `kpr_extra_payments`**
- Stores amount, penalty, reduction type, before/after balance, savings info

**API endpoints:**
- `POST /kpr/simulations/{id}/extra-payments/preview` — preview comparison
- `POST /kpr/simulations/{id}/extra-payments` — commit extra payment
- `GET /kpr/simulations/{id}/extra-payments` — list history
- `DELETE /kpr/simulations/{id}/extra-payments/{eid}` — delete and restore

**Mobile (Flutter):**
- New `KPRExtraPaymentScreen` — 3-step flow: form → preview comparison → confirm
- Extra payment history section in KPR detail screen
- Extra button in KPR detail app bar
- `ExtraPaymentRecord`, `ExtraPaymentPreview`, `ExtraPaymentOption` models

### Household Debt — Family-wide Debt Visibility

**All debt types (KPR + Credit Cards) can now be shared:**
- `household_id` column added to `kpr_simulations` and `credit_cards` tables
- Debt with `household_id` set is visible to all household members
- Debt without `household_id` stays private

**API changes:**
- `GET /summaries/debt/household` — aggregated debt across all household members
- KPR CREATE/LIST/DELETE now support household scope
- Credit Card CREATE/LIST/DELETE now support household scope
- `_get_simulation_for_user()` and `_get_card_for_user()` household-aware
- Personal debt summary still works as before

**Mobile (Flutter) changes:**
- Home screen: "Outstanding Household Debt" title with member breakdown
- KPR/CC list screens: Owner badge (`🏠 Anggota`) for shared debts
- KPR/CC form screens: "Share with household" toggle

### Database Fixes
- Persist `base_interest_rate`, `graduated_increment`, `graduated_every_months` in `kpr_simulations` (schedule regeneration now uses correct parameters)
- Added missing columns to CREATE TABLE: `due_date`, `start_month`, `start_year`, `base_interest_rate`, `graduated_increment`, `graduated_every_months`
- `apply_month` now has upper bound validation (max 600 months)
- `ExtraPaymentOut` response now returns real `created_at` from DB
- Extra payment delete correctly re-fetches from DB for fresh data

### CI Polish & Bugfixes

- **Missing `import pytest`** (`test_summaries.py`) — caused `NameError` when running tests; function-scoped fixtures became inaccessible.
- **`const Divider(color: AppColors.divider)`** (`home_screen.dart:308`) — `AppColors.divider` is a getter, not a compile-time constant; removed `const`.
- **Telegram notification exit code 35** — curl to Telegram API occasionally failed with SSL error (exit 35), which blocked subsequent CI steps (`Setup Python`, `Run tests`) and marked successful builds as failed. Fixed by appending `|| true` to all notification curl commands + added `--connect-timeout 10`.
- **`kpr_extra_payments` table not dropped between tests** (`conftest.py`) — `DROP TABLE IF EXISTS kpr_extra_payments CASCADE` was missing from `SCHEMA_SQL`, causing extra payments to leak across test functions and making `test_list_extra_payments`, `test_delete_extra_payment`, and `test_delete_restores_schedule` fail.
- **Missing `household_id` / `display_order` in credit card list query** (`credit_cards.py`) — the `SELECT` for `GET /credit-cards` omitted `cc.household_id` and `cc.display_order`, so household-scoped listing always returned empty for other household members.

### Test Counts

- **Backend:** 313 tests (58 routes, ~5.4 tests/route)
- **Flutter:** 290 tests
- **Total:** 603 tests

---

## v0.7.1 — Extra Payment UX Polish + Household Debt Context + Penalty Cleanup (2026-06-10)

### UX Polish

**Thousand separator on amount inputs** — Konsisten pake `_formatIdrDisplay` (format "Rp 50.000" pake dots):
- Extra payment amount field
- Add transaction credit card amount field
- On focus: raw digits aja — on unfocus: formatting diterapkan
- Parsing pake `replaceAll(RegExp(r'[^\d]'), '')` — works with any formatting

**Date format extra payment card:**
- "Recalculation of installment amount and new tenor starts from **May 2026 — Dec 2040**"
- Kedua tanggal pake month name (bukan "2040-12")

**Member tag — "Anggota" → "Member" & posisi:**
- KPR list: Member tag dipindah ke baris sendiri di bawah tenor, gak tumpang tindih sama Interest Badge
- CC list: "Anggota" → "Member" (posisi aman karena gak ada badge lain)

### Penalty Cleanup — Bersih Total

- `penalty_rate` dan `penalty_amount` dihapus dari semua layer:
  - DB: `DROP COLUMN` dari `kpr_extra_payments`
  - Backend: schemas, engine, router — parameter & perhitungan dihapus
  - Mobile: model, provider, screen — semua referensi dibersihkan
  - Docs: semua dokumentasi penalty dihapus

### AI Advisor — Debt Context Enriched

- **Household-aware:** Query KPR & CC sekarang include household members pake pola `WHERE user_id = ? OR household_id IN (SELECT ...)` — sama kaya router
- **Per-owner breakdown:** Tiap KPR/CC disebutin siapa pemiliknya
- **Interest type:** Fixed/Floating/Graduated/Mix per KPR
- **Extra payment count:** Disebutin jumlah extra payment yang udah dilakukan
- Contoh output:
  ```
  • KPR: Rp350.000.000 (2 simulasi)
      Filla: 1 simulasi (Fixed)
      Nahda: 1 simulasi (Floating)
      *2 extra payment telah dilakukan
  ```

### CI Fixes

- **onFocusChange → FocusNode:** Flutter `stable-3.44.1` (versi CI) gak punya parameter `onFocusChange` di `TextFormField`. Diganti pake `FocusNode` + listener di `initState`.

### Tests

- **New:** `test_apply_month_after_tenor_months` — extra payment dengan `apply_month` melebihi `tenor_months` ditolak (400)
- **New:** `test_apply_month_backwards` — extra payment dengan `apply_month` sebelum extra payment sebelumnya ditolak (400)
- **Total:** 313 backend tests passing

---

## v0.6.2 — Test Coverage + Hotfixes (2026-06-09)

### Test Coverage — Debt Tracker

#### Backend — 6 missing endpoint tests added
| File | Tests Added | Total Lines |
|------|-------------|-------------|
| `test_kpr.py` | `TestKprApiUpdate` (6 tests), `TestKprApiSchedule` (5 tests) | 590 |
| `test_credit_cards.py` | `TestUpdateCreditCard` (5), `TestDeleteTransaction` (3), `TestListInstallments` (3), `TestDeleteInstallment` (3) | 667 |

All 18 KPR + CC routes now have coverage. KPR engine fully covered (6 tests). CC transactions, installments, and projection covered.

#### Mobile — 4 new test files (59 tests)
| File | Tests |
|------|-------|
| `test/features/debt/models/kpr_model_test.dart` | 8 (fromJson/toJson, edge cases) |
| `test/features/debt/models/credit_card_model_test.dart` | 14 (fromJson, null safety) |
| `test/features/debt/providers/kpr_provider_test.dart` | 16 (loadAll, loadDetail, create, delete, clear) |
| `test/features/debt/providers/credit_card_provider_test.dart` | 21 (CRUD, transactions, installments, projection) |

### Bugs Fixed

- **`copyWith` null-coalescing bug** (`mobile/lib/features/debt/kpr/providers/kpr_provider.dart`, `mobile/lib/features/debt/credit_card/providers/credit_card_provider.dart`): `copyWith(error: null)` dan `copyWith(selectedSimulation: null)` tidak berfungsi karena `??` (null-coalescing) operator mengembalikan nilai lama saat parameter null. Semua state class sekarang punya `clearError`/`clearSelection` flags.
- **`loadCardDetail` silent error swallowing** (`mobile/lib/features/debt/credit_card/providers/credit_card_provider.dart`): Semua error di-silent catch — caller seperti `addTransaction`/`addInstallment` tidak tahu bahwa refresh detail gagal. Sekarang `rethrow` setelah clear selection.
- **Detail screen crash saat card dihapus** (`mobile/lib/features/debt/credit_card/ui/credit_card_detail_screen.dart`): Listener `homeRefreshProvider` wrap `loadCardDetail` dengan try-catch (card mungkin sudah dihapus).

- **White screen / stuck loading after APK update** (`mobile/lib/features/auth/providers/auth_provider.dart`): `getToken()` dari `flutter_secure_storage` dipanggil di luar try-catch. Pas update APK, secure storage bisa throw (encryption key mismatch) → Future reject → `_initialized` tetap false → loading spinner forever. Fix: pindah `getToken()` ke dalam try-catch + `.catchError()` safety net di `app.dart`.
- **"Something went wrong" setelah delete credit card/KPR terakhir** (`mobile/lib/features/debt/credit_card/providers/credit_card_provider.dart`): `deleteCard()` trigger `homeRefreshProvider` → listener di detail screen panggil `loadCardDetail(cardId)` (card sudah dihapus → 404) → `state.error` diset. List screen lihat `state.error != null && cards.isEmpty` → error display. Fix: clearError di delete, silent catch 404 di loadCardDetail.
- **Sama untuk KPR provider** — tambah `error: null` di `delete()`.
- **White screen setelah update APK** — Safety net `.catchError()` di `app.dart` agar loading screen selalu release meskipun ada unexpected error.

### CI

- `flutter clean` ditambahkan sebelum `flutter build apk --release` untuk mencegah stale artifact issues.

---

## v0.6.1 — Bug Fix Batch: 12 Fixes for Debt Tracker & Polish (2026-06-08)

### Fixes

#### KPR Engine
- **Rate period auto-extend** — Last rate period sekarang auto-extend ke full tenor. Sebelumnya default `toMonth: 120`, month 121+ pake `base_interest_rate` salah.
- **KPR outstanding value** — Ambil `remaining_balance` dari prev month (sebelum bayar cicilan bulan ini). Month 1 → `total_loan`.
- **`totalInterest=0`** — Response sekarang include computed fields (`total_interest`, `monthly_payment`, dll) secara eksplisit.
- **CROSS JOIN LATERAL syntax** — WHERE clause dipindah setelah semua JOINs (PostgreSQL strict requirement).
- **`due_date` duplicate arg** — Fix double pass di KPR create response.

#### Credit Card
- **CC value tidak muncul** — Sekarang include transaksi non-cicilan (current month) + sisa cicilan aktif.
- **Installment progress 0/12** — `remaining_months` dihitung dinamis dari `start_month`, bukan dari kolom DB statis.
- **CC debt summary** — Filter transaksi by current month (`EXTRACT(YEAR/MONTH FROM transaction_date::date)`).
- **EXTRACT on TEXT columns** — Tambah `::date` cast untuk kolom `transaction_date` (TEXT).

#### Home Screen
- **Spacing konsisten 8px** antar semua widget home (CategoriesCard, DebtSummaryCard, AI, dll).
- **Auto refresh home** — `homeRefreshProvider.state++` di trigger di semua mutation (add/delete KPR, add installment, add transaction).
- **Next month projection refresh** — Listener on back to detail card via `homeRefreshProvider`.

#### UI
- **Divider opacity** — `Divider(color: AppColors.divider)`.
- **Import path** — Fix 3 file import path missing `features/` prefix.
- **Route flattening** — Debt routes di-flatten ke top-level agar `push()`/`pop()` kompatibel dengan GoRouter.
- **Start month date picker** — Ganti text field dengan `showDatePicker` (month-year).
- **Mark complete dihapus** — `remaining_months` auto-calculated. Tidak ada manual mark complete.
- **KPR `due_date`** — Kolom INTEGER 1-31. Outstanding: if today >= due_date → exclude bulan ini.

### Test Fixes
- Test assertions updated untuk dynamic `remaining_months`, `due_date`, dan `EXTRACT` cast.

---

## v0.6.0 — Debt Tracker: KPR Calculator & Credit Card Management (2026-06-07)

### Features

#### KPR (Mortgage) Calculator
- **Full amortization engine** (`backend/app/services/kpr_engine.py`) — Mendukung 4 interest types: fixed, floating, graduated, mix.
- **Rate periods** — Multiple rate periods per simulation. Masing-masing dengan start/end month, rate, dan type.
- **Auto-extend** — Last rate period auto-extend ke full tenor.
- **Schedule generation** — Full amortization schedule per month (payment, principal, interest, remaining balance).
- **API CRUD** — Create, list, detail (with full schedule), update, delete.
- **Flutter UI:**
  - **Form screen** — Input property price, down payment (auto loan), tenor, interest type + periods.
  - **Detail screen** — Collapsible year-by-year schedule, summary cards (monthly payment, total interest, total payment).
  - **List screen** — Swipe to delete, card list with key metrics.
- **`due_date` support** — Tanggal jatuh tempo (1-31) mempengaruhi perhitungan outstanding bulan ini.
- **Dynamic `remaining_months`** — Auto-dihitung dari `start_month` vs current date.

#### Credit Card Management
- **Full CRUD** — Cards, transactions, installments.
- **Transactions** — Non-installment transaction per card with date & amount.
- **Installments** — Auto-calculated remaining months from `start_month`.
- **Next month projection** — Aggregates non-installment transactions + active installments.
- **Debt summary** — CC debt = transaksi non-cicilan bulan ini + sisa cicilan (monthly_amount × remaining_months).
- **Flutter UI:**
  - **List screen** — Summary header, card list with credit limit, billing/due dates, swipe to delete.
  - **Detail screen** — Tabs for transactions & installments, projection summary.
  - **Form screen** — Add card with name, last 4 digits, credit limit, billing/due dates.
  - **Add installment screen** — Description, amount, total months, start month.
- **Refresh on mutation** — `homeRefreshProvider` trigger di semua add/delete.

#### Home Screen Debt Widget
- **Total debt summary** — Aggregates KPR outstanding + CC debt.
- **AI Advisor debt context** — Debt summary dimasukkan ke konteks AI advisor untuk saran yang lebih relevan.
- **Debt Home Screen** — Entry point dari home & profile, routing ke KPR & CC sections.

#### Android Home Screen Widget
- **Quick add transaction** — Buka add transaction screen langsung dari widget.
- **Quick scan receipt** — Buka scan (OCR) langsung dari widget.
- **Native Kotlin implementation** — AppWidgetProvider dengan configuration activity.
- **Pending intent navigation** — Method channel ke Flutter untuk handle tap actions.

### Infrastructure
- **Auto DB backup script** (`backend/scripts/pg_backup.sh`) — pg_dump custom format, 7-day retention.
- **Missing indexes** — 3 indexes untuk optimasi query (transactions user+type+date, user+cat+date, OCR jobs user+created).
- **Docs relocation** — Plan docs dipindah dari `.hermes/plans/` ke `docs/plans/` untuk konsistensi.

### Test Coverage
- **Backend** — 361 lines test untuk KPR engine + API di `test_kpr.py`.
- **Backend** — 392 lines test untuk CC creation, transactions, installments, projection di `test_credit_cards.py`.
- **conftest.py** — Updated dengan schema untuk semua tabel debt tracker.

---

## v0.5.4 — Full Code Audit – 20 Fixes, 2 Cancelled, CI Green (2026-06-06)

### Root Cause Analysis
A comprehensive audit of the entire codebase found **29 findings** across Security, Backend Code Quality, Mobile, and Docs. **20 fixed**, **2 cancelled** (low-value refactors), **0 outstanding bugs**.

### Security Fixes

- **S3 – SQL injection via Meilisearch IDs** (`backend/app/routers/transactions.py`): Replaced unsafe string formatting with parameterized queries `$1::int[]` — Meilisearch IDs are user-facing, could have been used for injection.
- **S4 – SECRET_KEY loaded at module level** (`backend/app/core/config.py`): Reloaded from env vars at every access instead of once at import. Global `settings` object now defers SECRET_KEY read until first access.
- **S6 – CORS wildcard** (`backend/app/main.py`): Changed `["*"]` to `["https://wealthtrack.filla.id", "http://localhost:8080", "null"]`. Also restricted `Access-Control-Allow-Methods` and `Access-Control-Allow-Headers`.
- **S2 – Atomic rate limiter** (`backend/app/core/rate_limiter.py`): Implemented Lua script for Redis INCR + EXPIRE to prevent race conditions under concurrent requests.

### Backend Code Quality

- **CQ1 – Silent pass in error handling** (`backend/app/routers/*.py`, 4 files): Replaced bare `except: pass` with proper logging via `logger.exception()` across export, AI, and OCR routers.
- **CQ3 – Background task lifecycle** (`backend/app/services/ai_advisor.py`): Added `asyncio.Task` tracking — tasks are cancelled on app shutdown to prevent orphaned DB writes.
- **CQ5 – Atomic transaction boundaries** (`backend/app/routers/transactions.py`): Wrapped multi-statement operations (transfer balance, delete transaction chain) in explicit `BEGIN/COMMIT/ROLLBACK` via asyncpg transactions.

### Mobile Fixes

- **C1 – SSE stream memory leak** (`mobile/lib/core/network/api_client.dart`): Added `CancelToken` parameter to `streamPost()`. Stream controller `onCancel` now aborts the underlying HTTP request. Leak could cause unbounded memory growth on AI Advisor screen.
- **H1 – Network vs expired token ambiguity** (`mobile/lib/features/auth/providers/auth_provider.dart`): `checkAuth()` now distinguishes between network errors (retry) and token expiry (session expired).
- **C2 – e.toString() → handleError()** (`mobile/lib/features/*/providers/*.dart`, 3 files): Replaced raw `e.toString()` with centralized `handleError()` for consistent error messages.
- **M9 – Budget repo silent try/catch** (`mobile/lib/features/budgets/data/budget_repository.dart`): Caught exceptions now propagate instead of returning defaults silently.
- **L2 – Hardcoded strings** (`mobile/lib/*.dart`): Moved UI strings to centralized constants.
- **L8 – Null safety in BudgetModel** (`mobile/lib/features/budgets/models/budget_model.dart`): Fixed nullable `budgetId` causing runtime cast failures.
- **M5 – setState after dispose** (`mobile/lib/features/*/screens/*.dart`): Added `mounted` checks before `setState` in async callbacks.

### Mock & Test Fixes

- **Mocks update** (`mobile/test/helpers/mocks.dart`): `MockApiClient.streamPost` now accepts `CancelToken? cancelToken` parameter matching the real implementation.
- **BudgetSuggestion test** (`mobile/test/features/budget_suggestion_provider_test.dart`): Added missing second constructor argument `MockApiClient()`.
- **OCR test assertion** (`backend/tests/test_new_endpoints.py`): Fixed case mismatch in assertion — `"already have an OCR job"` → `"already have an ocr job"`.
- **T1 – New endpoint tests** (`backend/tests/test_new_endpoints.py`): Added **597 lines, 28 new tests** covering OCR process/save, AI chat, chat messages CRUD, pending count, and concurrent job rejection.

### Infrastructure

- **Cleanup job** (`.github/workflows/deploy-backend.yml`): Added separate `cleanup` job that runs before `test` to remove stale containers eating ports 5433/6380 on self-hosted runner.
- **Test DB password fix** (`.github/workflows/deploy-backend.yml`): `WEALTHTRACK_TEST_DATABASE_URL` was literal `***` — changed to `wealthtrack_test123` (matching service container).
- **REDIS_URL fix** (`.github/workflows/deploy-backend.yml`): Was `redis://localhost:***@v6` — changed to correct `redis://localhost:6380/0`.

### Cancelled (Low-Value Refactors)

- **M1 – AppColors → Riverpod**: Would require ~50-file refactor for dark mode that works fine with existing `Theme.of(context)`.
- **M8 – homeRefreshProvider → ref.invalidate`: ~30-min refactor of a stable pattern; no real bug.

### Stats
- Backend tests: 193 → **221** (+28)
- Mobile tests: ✅ All passing (APK build green)
- CI: Both workflows green ✅
- Audit coverage: Security (4/4), Backend Code Quality (3/3), Mobile (7/7), Docs (6/6), Deployment (4/4), Tests (2/2)

---

## v0.5.3 — CI/CD Migration, Security Hardening & 15 Code Fixes (2026-06-05)

### Infrastructure — Self-Hosted Runner

- **Self-hosted GitHub Actions runner** (`wealthtrack-vps`) — Registered on VPS, installed as systemd service. Replaces SSH-based deployment (port 2222 no longer needed). Runner communicates outbound to GitHub — no inbound ports required.
- **All workflows migrated to self-hosted** — `deploy-backend.yml` (test + deploy) and `build-apk.yml` (Flutter APK) now run entirely on `[self-hosted, linux]`. Pre-installed Android SDK + JDK 17 + Gradle cache for fast builds.
- **NOPASSWD sudo** — SUDO_PASSWORD secret eliminated. `/etc/sudoers.d/wealthtrack` allows `sudo systemctl restart wealthtrack` without password.
- **Workspace cleanup** — `git checkout` with `clean: false` preserves workspace between runs; full cleanup done via `git clean` + `git checkout -- .` in the deploy step.
- **Build artifact cleanup** — APK build auto-removes `build/` and `.dart_tool/` after every run (`always()`).
- **Redis CI port fix** — Changed test Redis from 6379→6380 to avoid conflict with production Redis on self-hosted runner.
- **PEP 668 fix** — Pillow install uses `--break-system-packages` for Python 3.12 compatibility on self-hosted runner.
- **Weekly Docker cleanup** — `docker system prune -f` added to weekly cron for CI service container images.
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
