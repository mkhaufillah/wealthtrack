# Custom Billing Cycle

**Feature added:** 2026-05-30
**See also:** [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md) · [AI Chat History](13-ai-chat-history.md)

---

## Overview

Allows users to set a custom "cycle start day" (e.g., the 25th) so financial summaries and reports reflect periods like **25 Apr – 24 May** instead of the fixed calendar month (1st–last day). The AI Financial Advisor also uses this context for accurate recommendations.

Default is `1` (standard calendar month). Valid range: 1–28.

---

## Architecture

```
[Profile Screen]──set cycle_start_day──▶[PUT /auth/me]
                                              │
                                              ▼
                                          [users table]
                                     cycle_start_day INTEGER
                                              │
            ┌─────────────────────────────────┤
            ▼                                 ▼
   [get_cycle_range()]               [Flutter providers]
   (backend cycle utility)            pass ?use_cycle=true
            │                                 │
            ▼                                 ▼
   [Summary Endpoints]               [Dashboard / Reports]
   current-month, daily,             show cycle-aware data
   monthly, household,
   cycle-info, ai/advise
```

---

## Database

**Table:** `users`
**Column:** `cycle_start_day INTEGER NOT NULL DEFAULT 1`

Migration auto-applied via `migrate_db.py`:

```python
if "cycle_start_day" not in existing_cols:
    conn.execute("ALTER TABLE users ADD COLUMN cycle_start_day INTEGER NOT NULL DEFAULT 1")
```

---

## Backend

### Cycle Utility (`backend/app/utils/cycle.py`)

| Function | Returns | Description |
|----------|---------|-------------|
| `get_cycle_range(today, cycle_start_day)` | `(date_from, date_to)` | Cycle containing today's date |
| `get_cycle_range_for_month(month, cycle_on)` | `(date_from, date_to)` | Budget period for a given month label |

**`get_cycle_range_for_month` logic:**
- `cycle_on=1` → calendar month (1st to last day)
- `cycle_on=N` → runs from **Nth of this month** to **(N-1)th of next month**
  - Example: month `"2026-05"`, `cycle_on=3` → **3 May – 2 Jun**

**Key design choice:** Budget month label = **start month** of the cycle range.
This keeps the month label consistent when you change `cycle_on` on an existing budget.
Changing from D1→D28 always means the range shifts forward, never backward.

### Updated Endpoints

All summary endpoints now accept `?use_cycle=true`:

| Endpoint | Without use_cycle | With use_cycle=true |
|----------|-------------------|-------------------|
| `GET /summaries/current-month` | Calendar month | Cycle range. Accepts `?ref_date=YYYY-MM-DD` to override server date. |
| `GET /summaries/daily` | Explicit dates or today | Cycle range if no dates |
| `GET /summaries/monthly` | Calendar month | Cycle range |
| `GET /summaries/household` | Explicit dates | Cycle range if no dates |
| `GET /summaries/cycle-info` | — | Returns `{cycle_start_day, date_from, date_to}` |
| `GET /budgets/summary` | Calendar month dates | Cycle-aware actuals with `?use_cycle=true`. Returns `{"items","uncategorized_expenses"}` — each budget uses own `cycle_on`. `uncategorized_expenses` shows spending outside budget. |

### Profile Update

`PUT /api/v1/auth/me` now accepts `cycle_start_day` (int, 1–28):

```json
{ "display_name": "...", "cycle_start_day": 25 }
```

### AI Advisor (`POST /api/v1/ai/advise`)

The `_build_context()` function now:
1. Reads user's `cycle_start_day` from DB
2. Uses `get_cycle_range()` to compute d_from/d_to
3. Injects cycle label into system prompt: `"Financial Data for the Period 25 Apr – 24 May 2026:"`

---

## Files Changed

### Backend
| File | Change |
|------|--------|
| `backend/app/migrate_db.py` | Auto-migration for `cycle_start_day` column + budget month migration (section #7 decrement removed 2026-05-30 — was non-idempotent, ran every deploy) |
| `backend/app/utils/cycle.py` | **New** — `get_cycle_range()` + `get_cycle_range_for_month()` utilities |
| `backend/app/routers/auth.py` | Accept `cycle_start_day` in PUT /me + GET /me |
| `backend/app/schemas/auth.py` | `UpdateProfileIn.cycle_start_day` (Optional[int], ge=1, le=28) |
| `backend/app/routers/summaries.py` | All endpoints: `use_cycle` param, `get_cycle_range()`, `cycle-info` endpoint |
| `backend/app/routers/ai_advisor.py` | `_build_context()` uses cycle range, injects cycle label in prompt |
| `backend/app/routers/budgets.py` | `/summary` — cycle-aware with `?use_cycle=true`. Each budget uses its own `cycle_on`. Response: `{"items","uncategorized_expenses"}` showing spending outside budget. |
| `backend/app/routers/transactions.py` | Transfer description: "Transfer to/from" instead of "Transfer to/from" for English consistency. |
| `backend/app/core/config.py` | Env file resolved by absolute path, not relative CWD |

### Mobile (Flutter)
| File | Change |
|------|--------|
| `lib/features/auth/models/user_model.dart` | +`cycleStartDay` field (default 1) |
| `lib/features/auth/data/auth_repository.dart` | `updateProfile()` accepts optional `cycleStartDay` |
| `lib/features/auth/providers/auth_provider.dart` | Same — propagate `cycleStartDay` |
| `lib/features/profile/ui/profile_screen.dart` | +Billing Cycle section, grid picker (1–28), `_saveCycleDay()`, dark mode fix |
| `lib/features/home/providers/dashboard_provider.dart` | Pass `use_cycle=true` + `ref_date=DateTime.now()` to `/current-month`. Store `dateFrom`/`dateTo` from response. |
| `lib/features/home/ui/widgets/balance_card.dart` | Accept `cycleLabel`, show cycle range (e.g. "25 May – 24 Jun") instead of "Monthly Balance". |
| `lib/features/home/ui/home_screen.dart` | Format `dateFrom`/`dateTo` into cycle label + pass to BalanceCard. |
| `lib/features/reports/data/report_repository.dart` | Pass `use_cycle=true` to `/monthly` + trend |
| `lib/features/reports/ui/reports_screen.dart` | Compute cycle range locally, cycle label, `_maxMonth()` for start-month logic |
| `lib/features/budgets/data/budget_repository.dart` | Pass `use_cycle=true` to `/summary`. Return `BudgetSummaryResult` with `items` + `uncategorizedExpenses`. Accept `d_from_override`/`d_to_override` for non-budget expense scope. |
| `lib/features/budgets/ui/budgets_screen.dart` | Compute cycle range locally, date range badge, `_maxMonth()` start-month logic. +"Outside Budget" section for non-budget expenses. Budget overview compares `totalBudget > totalIncome`. |
| `lib/features/budgets/providers/budget_provider.dart` | Preserve date range for balance fetch across create/delete. Store `uncategorizedExpenses` + `totalIncome` from monthly summary. |
| `lib/shared/utils/date_formatter.dart` | +`getCycleRangeForMonth()` — mirror backend |

### Cron
| File | Change |
|------|--------|
| `~/.hermes/scripts/household_report.py` | Read Filla's `cycle_start_day`, compute cycle range, display cycle label |

### Tests
| File | Change |
|------|--------|
| `backend/tests/test_summaries.py` | +`TestCycleAwareSummaries` (7 tests) |
| `mobile/test/helpers/mocks.dart` | MockAuthRepository sync signature |

---

## Test Results

| Suite | Count | Status |
|-------|-------|--------|
| Backend (pytest) | **162** | ✅ All pass |
| Flutter (flutter test) | **237** | ✅ All pass |

---

## Usage

1. Tap **Profile** → scroll to **Billing Cycle** section
2. Tap **Cycle Start Day: Day N**
3. Pick a day from the grid (1–28)
4. Dashboard, Reports, and AI Advisor immediately reflect the new cycle

### Cycle Label Examples

| cycle_start_day | Today (May 28) | Period Display |
|----------------|----------------|----------------|
| 1 (default) | Any day | "May 2026" |
| 15 | May 28 | "15 May – 14 Jun 2026" |
| 25 | May 28 | "25 May – 24 Jun 2026" |
| 25 | May 2 | "25 Apr – 24 May 2026" |

---

## Budget Month Design Decision

**Budget month = start month of the cycle range.** This was changed from "end month" to fix an inconsistency where editing a budget's cycle_on would drastically change the date range.

**Before (end month):**
```
month="2026-06", cycle_on=3 → range 3 Apr – 2 May   [prev month → this month]
month="2026-06", cycle_on=1 → range 1 Jun – 30 Jun  [calendar month]
```
Changing cycle_on from 3→1 shifted the range from Apr–May to just June (inconsistent).

**After (start month):**
```
month="2026-05", cycle_on=3 → range 3 May – 2 Jun   [this month → next month]
month="2026-05", cycle_on=1 → range 1 May – 31 May  [calendar month]
```
Changing cycle_on from 3→1 keeps May as the budget month (consistent).