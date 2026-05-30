# Changelog

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
