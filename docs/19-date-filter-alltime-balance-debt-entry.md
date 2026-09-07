# Transactions Date Filter and All-Time Home Balance

> **For Hermes:** Implement after Filla says go. TDD for provider/API wiring. Widgets use `AppColors` only — no `Color(0x…)` in screens.

**Goal:** (1) Filter the transactions list by a date range or a single day. (2) Home balance is all-time (every transaction), not the billing cycle.

**Cancelled:** Feature 3 (clickable outstanding debt / remove **Catatan utang** entrypoints). Home **Catatan utang** card and Profile menu stay. Outstanding card stays display-only and hidden when `total_debt == 0`.

**Architecture:** Backend already has `date_from`/`date_to` on `GET /transactions`. Home saldo uses personal `GET /summaries/daily` with no dates (all-time, current user only — not household).

**Tech Stack:** FastAPI (unchanged contracts), Flutter Riverpod, `showDatePicker` / `showDateRangePicker`, `AppColors` tokens.

**See also:** [Custom Billing Cycle](14-custom-billing-cycle.md) · [Delete Transaction](11-delete-transaction.md) · [Flutter Mobile](05-flutter-mobile.md)

---

## Current context

| Need | Today |
|------|--------|
| Date filter on Transactions | API + `TransactionRepository.list(dateFrom:, dateTo:)` exist. `TransactionListNotifier` never sends them. UI has type/category/sort/search chips only. |
| Home total saldo | `DashboardNotifier.load` calls `/summaries/current-month?use_cycle=true` — **cycle-bounded**. Savings/emergency already hit `/summaries/all-time-category-balance`. MCP `get_current_balance` is household all-time via `/summaries/household` with no dates. |
| Debt entry | Home: `_buildDebtSummaryCard` (not tappable) **and** `_buildDebtCard` → `/debt`. Profile: **Catatan utang** → `/debt`. Route `/debt` (`DebtHomeScreen`) stays. |

---

## 1. Transactions date filter

**No new API.** `GET /api/v1/transactions` already accepts `date_from` / `date_to` (`YYYY-MM-DD`). Tests in `backend/tests/test_transactions.py`.

### Modes

- **Off** — no date params (current behavior).
- **Single day** — `date_from == date_to == picked day`.
- **Range** — `date_from` / `date_to` inclusive. If user picks one day in the range picker, treat as single day.

Clear chip resets both to null.

### Files

- Modify: `mobile/lib/features/transactions/providers/transaction_provider.dart`
  - State: `String? dateFrom`, `String? dateTo`
  - `copyWith` cannot use `??` for clearing. Add `clearDateFilter()` that rebuilds state with both null, `page: 1`, then `load()`.
  - `setDateFilter({required String from, required String to})` then `load()`.
  - Pass `dateFrom`/`dateTo` in `load()` and `loadNextPage()`.
- Modify: `mobile/lib/features/transactions/ui/transaction_list_screen.dart`
  - Add `ActionChip` next to Categories (same chip style, `AppColors.accent` when active).
  - On tap: bottom sheet with three actions using `AppColors` only: **Specific date**, **Date range**, **Clear** (if active).
  - Specific → `showDatePicker`. Range → `showDateRangePicker`. Format `yyyy-MM-dd` for API; chip label `dd MMM` or `dd MMM – dd MMM`.
- Test: `mobile/test/features/transactions/` — if a notifier test exists, add date-filter cases. If not, add focused notifier tests with `MockApiClient` asserting query params. Do not invent a widget-test harness.

### YAGNI

- No calendar heatmap.
- No backend change unless household list (`/transactions/household`) is what the screen uses — it uses `/transactions` (personal). Confirm in `TransactionRepository.list`.
- Do not hardcode hex; pickers use Material theme already wired to `AppTheme`.

---

## 2. Home all-time total balance

**Problem:** `BalanceCard` shows cycle income/expense/balance. Filla wants the headline saldo = sum of **all** household transactions, no date window.

**Source of truth (already exists):** `GET /api/v1/summaries/household` with **no** `date_from`/`date_to` → `SummaryService.get_household_summary` all-time (same as MCP `get_current_balance`).

### Approach

- `DashboardNotifier.load`: keep fetching recent txns from `/transactions?per_page=5`.
- Replace `/summaries/current-month?use_cycle=true` with `/summaries/household` (no dates) for `totalIncome`, `totalExpense`, `balance`.
- Stop sending `dateFrom`/`dateTo` into `BalanceCard` as a cycle range. Hero title: **Uang kamu**; subtitle **Rekap pribadi, dari awal sampai sekarang**. Income/expense labels: **Pemasukan** / **Pengeluaran**.
- `BalanceCard` uses `t('home.hero_title')` — not `'All-time balance'` / `'Monthly Balance'`.
- Refresh path (`homeRefreshProvider`, pull-to-refresh) stays; still `load(force: true)`.

### Do not

- Do not remove billing cycle from **Budgets** (`use_cycle` there is correct).
- Do not add a second balance card (YAGNI). One card, all-time numbers.
- Do not call MCP from Flutter.

### Tests

- Update `mobile/test/features/home_screen_test.dart` / dashboard tests if they mock `/summaries/current-month` — point mocks at `/summaries/household`.
- Backend: no new tests unless household-without-dates is untested (it was fixed for MCP; reuse existing summary tests).

---

## 3. Clickable outstanding debt — CANCELLED

Do **not** implement. Leave `_buildDebtSummaryCard` display-only and gated on `total_debt > 0`. Keep `_buildDebtCard` on home and Profile **Catatan utang**. Route `/debt` unchanged.

---

## Files likely to change

- `mobile/lib/features/transactions/providers/transaction_provider.dart`
- `mobile/lib/features/transactions/ui/transaction_list_screen.dart`
- `mobile/lib/features/home/providers/dashboard_provider.dart`
- `mobile/lib/features/home/ui/widgets/balance_card.dart`
- Matching tests under `mobile/test/features/`
- `docs/01-project-overview.md` (link this doc)
- `CHANGELOG.md` Unreleased

Do **not** touch `home_screen.dart` debt widgets or `profile_screen.dart` menu except if dashboard load lives only in the provider (home still displays `state.balance`).

`home_screen.dart` only changes if BalanceCard args change. Live label is `t('home.hero_title')` (**Uang kamu**).

No new tables, no new routes, no MCP tools, no deploy from the agent unless asked.

---

## Implementation order

1. Date filter state + repo wiring + chip/sheet (TDD notifier).
2. Dashboard all-time household summary + BalanceCard label.
3. Docs/changelog.

Colors: `AppColors.*` only in widgets. Hex stays in `app_theme.dart`.

---

## Risks / open questions

1. **All-time vs cycle on home:** Income/expense on the card become all-time too (same payload). Budgets stay on cycle.
2. **Household vs personal:** All-time saldo uses household summary to match MCP.
3. Flutter SDK may be missing on this VPS; CI `build-apk.yml` is the real test run.

Stop until Filla says implement.
