# Custom Billing Cycle

**Feature added:** 2026-05-30
**See also:** [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md) · [AI Chat History](13-ai-chat-history.md)

---

## Overview

Allows users to set a custom "cycle start day" (e.g., the 25th) so financial summaries and reports reflect periods like **25 Apr – 24 Mei** instead of the fixed calendar month (1st–last day). The AI Financial Advisor also uses this context for accurate recommendations.

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

| Function | Returns |
|----------|---------|
| `get_cycle_range(today, cycle_start_day)` | `(date_from, date_to)` tuple |

Logic:
- Default `cycle_start_day=1` → standard calendar month
- Custom day N → range from Nth of current/prev month to N-1 of next month
- Handles: month boundaries, December crossover, day clamping (e.g., Feb 30→28/29), year wrap

### Updated Endpoints

All summary endpoints now accept `?use_cycle=true`:

| Endpoint | Without use_cycle | With use_cycle=true |
|----------|-------------------|-------------------|
| `GET /summaries/current-month` | Calendar month | Cycle range |
| `GET /summaries/daily` | Explicit dates or today | Cycle range if no dates |
| `GET /summaries/monthly` | Calendar month | Cycle range |
| `GET /summaries/household` | Explicit dates | Cycle range if no dates |
| `GET /summaries/cycle-info` | — | Returns `{cycle_start_day, date_from, date_to}` |

### Profile Update

`PUT /api/v1/auth/me` now accepts `cycle_start_day` (int, 1–28):

```json
{ "display_name": "...", "cycle_start_day": 25 }
```

### AI Advisor (`POST /api/v1/ai/advise`)

The `_build_context()` function now:
1. Reads user's `cycle_start_day` from DB
2. Uses `get_cycle_range()` to compute d_from/d_to
3. Injects cycle label into system prompt: `"Data Keuangan Periode 25 Apr – 24 Mei 2026:"`

---

## Files Changed

### Backend
| File | Change |
|------|--------|
| `backend/app/migrate_db.py` | Auto-migration for `cycle_start_day` column |
| `backend/app/utils/cycle.py` | **New** — `get_cycle_range()` utility |
| `backend/app/routers/auth.py` | Accept `cycle_start_day` in PUT /me + GET /me |
| `backend/app/schemas/auth.py` | `UpdateProfileIn.cycle_start_day` (Optional[int], ge=1, le=28) |
| `backend/app/routers/summaries.py` | All endpoints: `use_cycle` param, `get_cycle_range()`, `cycle-info` endpoint |
| `backend/app/routers/ai_advisor.py` | `_build_context()` uses cycle range, injects cycle label in prompt |

### Mobile (Flutter)
| File | Change |
|------|--------|
| `lib/features/auth/models/user_model.dart` | +`cycleStartDay` field (default 1) |
| `lib/features/auth/data/auth_repository.dart` | `updateProfile()` accepts optional `cycleStartDay` |
| `lib/features/auth/providers/auth_provider.dart` | Same — propagate `cycleStartDay` |
| `lib/features/profile/ui/profile_screen.dart` | +Billing Cycle section, grid picker (1–28), `_saveCycleDay()` |
| `lib/features/home/providers/dashboard_provider.dart` | Pass `use_cycle=true` to `/current-month` |
| `lib/features/reports/data/report_repository.dart` | Pass `use_cycle=true` to `/monthly` + trend |

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
| Backend (pytest) | **157** | ✅ All pass (7 new cycle tests) |
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
| 1 (default) | Any day | "Mei 2026" |
| 15 | May 28 | "15 Mei – 14 Jun 2026" |
| 25 | May 28 | "25 Mei – 24 Jun 2026" |
| 25 | May 2 | "25 Apr – 24 Mei 2026" |
