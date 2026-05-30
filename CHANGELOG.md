# Changelog

## v0.3.3 — OCR Performance Optimization (2026-05-31)

### Performance
- **Model swap** — OCR vision model changed from `kimi-k2.6` to `minimax-m2.7`. Rate limit increased from 1,150 → 3,400 per 5 hours (3×). Model is lighter and faster for receipt parsing.
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
