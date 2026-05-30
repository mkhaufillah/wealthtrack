# Changelog

## v0.3.1 — Category English Names & Home Widget (2026-05-30)

### Features
- **English Category Names (`category_name_en`)** — All endpoints (transactions, budgets, reports, summaries) now return `category_name_en`/`name_en` from the DB. Flutter UI uses `name_en` as primary display, falls back to Indonesian `category_name`.
- **Home Savings & Emergency Widget** — Dashboard now shows Savings & Investment and Emergency Funds balances from `/summaries/all-time-category-balance` endpoint.
- **Budget Exhausted Message** — Overspent budget categories show an "exhausted" label when percentage ≥ 100%.
- **Lainnya Locked** — "Lainnya" category cannot be edited or deleted via admin CRUD.

### Fixes
- **category_translator.dart** — `translateCategory()` removed; category translation is now server-side via `name_en`. Flutter simply displays the field from the API response.
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
