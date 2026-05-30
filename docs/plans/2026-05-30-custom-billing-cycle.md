# Custom Billing Cycle Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Allow users to set a custom "cycle start day" (e.g., 25th) so the financial period runs from day N of month M to day N-1 of month M+1, instead of the fixed calendar month (1st–last day).

**Architecture:**
- Store `cycle_start_day` (INTEGER, 1-28) in `users` table, default 1
- Backend utility function to compute cycle date range from any date
- All summary endpoints switch from calendar-month to cycle-aware range
- Flutter profile screen: add cycle start day picker (1–28)
- Cron household script: read user's cycle from DB

**Tech Stack:** FastAPI (backend), aiosqlite, Flutter + Riverpod (mobile)

---

## Task 1: Add `cycle_start_day` column to users table

**Objective:** Persist the user's chosen cycle start day (1–28).

**Files:**
- Modify: `backend/app/migrate_db.py` — add `cycle_start_day` column migration
- Test: `backend/tests/test_auth.py` — verify column exists

**Step 1: Write failing test**

Add to `test_auth.py`:

```python
async def test_user_has_cycle_start_day(self, client: AsyncClient, filla_token: str):
    resp = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {filla_token}"})
    assert resp.status_code == 200
    assert "cycle_start_day" in resp.json()
    assert resp.json()["cycle_start_day"] == 1  # default
```

**Step 2: Run test**

Run: `pytest backend/tests/test_auth.py::TestAuth::test_user_has_cycle_start_day -v`
Expected: FAIL — "cycle_start_day" not in response

**Step 3: Add migration**

In `migrate_db.py`, add to the migration section:

```python
if "cycle_start_day" not in existing_cols:
    conn.execute(
        "ALTER TABLE users ADD COLUMN cycle_start_day INTEGER NOT NULL DEFAULT 1"
    )
    added.append("cycle_start_day")
```

Also add `cycle_start_day` to the `/me` endpoint SELECT query in `auth.py`:

```python
cursor = await db.execute(
    "SELECT id, username, display_name, role, created_at, COALESCE(cycle_start_day, 1) as cycle_start_day FROM users WHERE id = ?",
    (current_user["id"],),
)
```

**Step 4: Run test**

Run: `pytest backend/tests/test_auth.py::TestAuth::test_user_has_cycle_start_day -v`
Expected: PASS

**Step 5: Commit**

```bash
git add backend/app/migrate_db.py backend/app/routers/auth.py backend/tests/test_auth.py
git commit -m "feat(db): add cycle_start_day column to users table"
```

---

## Task 2: Create cycle utility + update profile endpoint

**Objective:** Build a shared date-range utility and allow updating `cycle_start_day` via API.

**Files:**
- Create: `backend/app/utils/cycle.py` — cycle date range helpers
- Modify: `backend/app/routers/auth.py` — add `cycle_start_day` to update profile
- Modify: `backend/app/schemas/auth.py` — add `cycle_start_day` to schema
- Test: `backend/tests/test_auth.py`

**Step 1: Write failing test**

```python
async def test_update_cycle_start_day(self, client: AsyncClient, filla_token: str):
    resp = await client.put(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"cycle_start_day": 25},
    )
    assert resp.status_code == 200
    assert resp.json()["cycle_start_day"] == 25
```

**Step 2: Run test**

Run: `pytest backend/tests/test_auth.py::TestAuth::test_update_cycle_start_day -v`
Expected: FAIL — "cycle_start_day" unknown field

**Step 3: Create cycle utility**

```python
# backend/app/utils/cycle.py
from datetime import date, timedelta
from typing import Tuple


def get_cycle_range(today: date, cycle_start_day: int = 1) -> Tuple[date, date]:
    """Return (start_date, end_date) for the current billing cycle.

    If cycle_start_day == 1: standard calendar month.
    If cycle_start_day == 25: cycle runs from 25th of prev month to 24th of this month.
    """
    if cycle_start_day == 1:
        # Standard calendar month
        start = date(today.year, today.month, 1)
        # Last day of month
        if today.month == 12:
            end = date(today.year, 12, 31)
        else:
            end = date(today.year, today.month + 1, 1) - timedelta(days=1)
        return start, end

    # Custom cycle start day
    # If today >= cycle_start_day: cycle_start = this month's cycle_start_day
    # Else: cycle_start = last month's cycle_start_day
    if today.day >= cycle_start_day:
        try:
            start = date(today.year, today.month, cycle_start_day)
        except ValueError:
            # cycle_start_day > days in month, use last day
            if today.month == 12:
                start = date(today.year, 12, 31)
            else:
                start = date(today.year, today.month + 1, 1) - timedelta(days=1)
    else:
        # Go back one month
        if today.month == 1:
            prev_month = date(today.year - 1, 12, 1)
        else:
            prev_month = date(today.year, today.month - 1, 1)
        try:
            start = date(prev_month.year, prev_month.month, cycle_start_day)
        except ValueError:
            if prev_month.month == 12:
                start = date(prev_month.year, 12, 31)
            else:
                start = date(prev_month.year, prev_month.month + 1, 1) - timedelta(days=1)

    # End = start + ~1 month (day before next cycle start)
    if start.month == 12:
        end_candidate = date(start.year + 1, 1, cycle_start_day) - timedelta(days=1)
    else:
        try:
            end_candidate = date(start.year, start.month + 1, cycle_start_day) - timedelta(days=1)
        except ValueError:
            if start.month + 1 > 12:
                end_candidate = date(start.year + 1, 1, cycle_start_day) - timedelta(days=1)
            else:
                end_candidate = date(start.year, start.month + 1, 1) - timedelta(days=1)

    return start, end_candidate
```

**Step 4: Update auth schema**

In `backend/app/schemas/auth.py`, add to `UpdateProfileIn`:

```python
cycle_start_day: Optional[int] = Field(default=None, ge=1, le=28)
```

**Step 5: Update `/me` PUT endpoint**

In `backend/app/routers/auth.py`:

```python
@router.put("/me")
async def update_profile(...):
    # ... existing code ...
    if data.cycle_start_day is not None:
        await db.execute(
            "UPDATE users SET cycle_start_day = ? WHERE id = ?",
            (data.cycle_start_day, current_user["id"]),
        )
    # ... rest ...
```

Also update the SELECT in GET /me and PUT /me response to include `cycle_start_day`.

**Step 6: Run tests**

Run: `pytest backend/tests/test_auth.py -v`
Expected: all tests PASS

**Step 7: Commit**

```bash
git add backend/app/utils/cycle.py backend/app/routers/auth.py backend/app/schemas/auth.py backend/tests/test_auth.py
git commit -m "feat(api): add cycle utility + cycle_start_day update endpoint"
```

---

## Task 3: Update summary endpoints to use cycle-aware dates

**Objective:** All summary endpoints use `get_cycle_range()` instead of calendar month.

**Files:**
- Modify: `backend/app/routers/summaries.py`

**Step 1: Write failing tests**

Add to `test_summaries.py`:

```python
@pytest.fixture
async def test_user_with_cycle(client: AsyncClient, filla_token: str):
    """Set filla's cycle_start_day to 25 and create a transaction on day 26."""
    await client.put(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"cycle_start_day": 25},
    )
    # Create a transaction dated 26th of current month (should be in cycle)
    today = date.today()
    day_26 = date(today.year, today.month, min(26, today.day))
    await client.post(
        "/api/v1/transactions",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={
            "type": "income", "category_id": 1, "amount": 100000,
            "description": "Cycle test", "date": day_26.isoformat(),
        },
    )
    # Also create one on day 2 (should be in PREVIOUS cycle)
    day_2 = date(today.year, today.month, 2)
    await client.post(
        "/api/v1/transactions",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={
            "type": "expense", "category_id": 6, "amount": 50000,
            "description": "Prev cycle test", "date": day_2.isoformat(),
        },
    )

async def test_current_month_uses_cycle_start_day(self, client: AsyncClient, filla_token: str, test_user_with_cycle):
    """With cycle_start_day=25, summaries should use 25th-to-24th range."""
    resp = await client.get(
        "/api/v1/summaries/current-month",
        headers={"Authorization": f"Bearer {filla_token}"},
    )
    data = resp.json()
    # Transaction on day 26 should be included, day 2 excluded
    assert data["total_income"] >= 100000  # day 26 income
    assert data["total_expense"] == 0       # day 2 expense excluded

async def test_monthly_accepts_cycle_param(self, client: AsyncClient, filla_token: str):
    """monthly endpoint should honor cycle_start_day when use_cycle=true."""
    resp = await client.get(
        "/api/v1/summaries/monthly?use_cycle=true",
        headers={"Authorization": f"Bearer {filla_token}"},
    )
    assert resp.status_code == 200
```

**Step 2: Add helper to get user's cycle_start_day**

In `summaries.py`, add a helper:

```python
async def _get_cycle_start_day(db: aiosqlite.Connection, user_id: int) -> int:
    cursor = await db.execute(
        "SELECT COALESCE(cycle_start_day, 1) as cycle_start_day FROM users WHERE id = ?",
        (user_id,),
    )
    row = await cursor.fetchone()
    return row["cycle_start_day"] if row else 1
```

**Step 3: Modify `_single_month`**

Replace the hardcoded d_from/d_to with cycle-aware logic:

```python
async def _single_month(m: str, today: date, db: aiosqlite.Connection, current_user: dict,
                         use_cycle: bool = False) -> dict:
    if use_cycle:
        cycle_start = await _get_cycle_start_day(db, current_user["id"])
        d_from, d_to = get_cycle_range(today, cycle_start)
        # Convert to strings
        d_from_str = d_from.isoformat()
        d_to_str = d_to.isoformat()
    else:
        d_from = f"{m}-01"
        if m == today.strftime("%Y-%m"):
            d_to = today.isoformat()
        else:
            import calendar
            y, mo = map(int, m.split("-"))
            d_to = f"{m}-{calendar.monthrange(y, mo)[1]}"
        d_from_str = d_from
        d_to_str = d_to

    # Use d_from_str, d_to_str in all queries instead of hardcoded d_from/d_to
    ...
```

**Step 4: Update `current-month` endpoint to use cycle**

```python
@router.get("/current-month")
async def current_month_summary(
    use_cycle: bool = Query(False, description="Use user's billing cycle instead of calendar month"),
    ...
):
    cycle_start = await _get_cycle_start_day(db, current_user["id"])
    if use_cycle:
        d_from, d_to = get_cycle_range(today, cycle_start)
        m = f"{d_from.year}-{d_from.month:02d}"
        return await _single_month(m, today, db, current_user, use_cycle=True)
    return await _single_month(m, today, db, current_user)
```

Also update `daily` and `household` endpoints similarly.

**Step 5: Add cycle endpoints**

```python
@router.get("/cycle-info")
async def cycle_info(
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Return the current cycle date range."""
    cycle_start = await _get_cycle_start_day(db, current_user["id"])
    d_from, d_to = get_cycle_range(date.today(), cycle_start)
    return {
        "cycle_start_day": cycle_start,
        "date_from": d_from.isoformat(),
        "date_to": d_to.isoformat(),
    }
```

**Step 6: Run tests**

Run: `pytest backend/tests/ -v`
Expected: all tests PASS

**Step 7: Commit**

```bash
git add backend/app/routers/summaries.py
git commit -m "feat(api): summary endpoints support billing cycle"
```

---

## Task 4: Update daily/household endpoints for cycle support

**Objective:** Extend cycle-aware range to `/daily` and `/household` endpoints.

**Files:**
- Modify: `backend/app/routers/summaries.py`

**Step 1: Write failing test**

```python
async def test_daily_summary_with_cycle(self, client: AsyncClient, filla_token: str):
    resp = await client.get(
        "/api/v1/summaries/daily?use_cycle=true",
        headers={"Authorization": f"Bearer {filla_token}"},
    )
    assert resp.status_code == 200
```

**Step 2: Modify `/daily` endpoint**

Add `use_cycle` query param. When true, compute date_from/date_to from cycle range:

```python
@router.get("/daily")
async def daily_summary(
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    use_cycle: bool = Query(False),
    ...
):
    if use_cycle and not date_from and not date_to:
        cycle_start = await _get_cycle_start_day(db, current_user["id"])
        d_from, d_to = get_cycle_range(today, cycle_start)
        date_from = d_from.isoformat()
        date_to = d_to.isoformat()
    ...
```

**Step 3: Modify `/household` endpoint**

Same pattern — add `use_cycle` param.

**Step 4: Run tests**

Run: `pytest backend/tests/ -v`
Expected: all tests PASS

**Step 5: Commit**

```bash
git add backend/app/routers/summaries.py
git commit -m "feat(api): daily/household summaries support billing cycle"
```

---

## Task 5: Flutter — add cycle_start_day setting to profile

**Objective:** User can set their cycle start day in Profile → Settings.

**Files:**
- Modify: `mobile/lib/features/profile/ui/profile_screen.dart`

**Step 1: Add cycle start day picker UI**

In the profile screen, add a section:

```dart
// Cycle Settings
const SizedBox(height: 24),
const Text('Billing Cycle',
  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
const SizedBox(height: 8),
Card(
  elevation: 0,
  color: AppColors.surface,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  child: ListTile(
    title: const Text('Cycle Start Day'),
    subtitle: Text('Day ${_cycleStartDay} of each month'),
    trailing: const Icon(Icons.edit_calendar, size: 18),
    onTap: _pickCycleDay,
  ),
),
```

**Step 2: Implement picker**

```dart
Future<void> _pickCycleDay() async {
  final picked = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Cycle Start Day'),
      content: SizedBox(
        width: 300,
        height: 400,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
          ),
          itemCount: 28,
          itemBuilder: (ctx, i) {
            final day = i + 1;
            final isSelected = day == _cycleStartDay;
            return GestureDetector(
              onTap: () => Navigator.pop(ctx, day),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : null,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.divider,
                  ),
                ),
                child: Center(
                  child: Text('$day',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : null,
                      color: isSelected ? Colors.white : null,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  if (picked != null) {
    setState(() => _cycleStartDay = picked);
    _saveCycleDay(picked);
  }
}
```

**Step 3: Add API call to save**

```dart
Future<void> _saveCycleDay(int day) async {
  try {
    final api = ref.read(apiClientProvider);
    await api.put('/auth/me', data: {'cycle_start_day': day});
  } catch (_) {}
}
```

**Step 4: Load existing value on init**

In `initState`, load from `/auth/me`:

```dart
Future<void> _loadProfile() async {
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/auth/me');
    setState(() {
      _cycleStartDay = res.data['cycle_start_day'] ?? 1;
    });
  } catch (_) {}
}
```

**Step 5: Commit**

```bash
git add mobile/lib/features/profile/ui/profile_screen.dart
git commit -m "feat(ui): add cycle start day picker to profile"
```

---

## Task 6: Flutter — update providers to pass `use_cycle`

**Objective:** Dashboard and report providers send `use_cycle=true` to API.

**Files:**
- Modify: `mobile/lib/features/home/providers/dashboard_provider.dart`
- Modify: `mobile/lib/features/reports/providers/report_provider.dart`
- Modify: `mobile/lib/features/reports/data/report_repository.dart`

**Step 1: Update dashboard provider**

```dart
Future<void> load() async {
  state = state.copyWith(isLoading: true, error: null);
  try {
    final summaryRes = await _api.get('/summaries/current-month', queryParams: {'use_cycle': 'true'});
    // ... rest unchanged
  } catch (e) { ... }
}
```

**Step 2: Update report repository**

In `report_repository.dart`:

```dart
Future<MonthlyReport> getMonthlyReport(String month) async {
  final res = await _client.get('/summaries/monthly', queryParams: {
    'month': month,
    'use_cycle': 'true',
  });
  return MonthlyReport.fromJson(res.data);
}
```

**Step 3: Commit**

```bash
git add mobile/lib/features/home/providers/dashboard_provider.dart mobile/lib/features/reports/data/report_repository.dart
git commit -m "feat(client): pass use_cycle to summary endpoints"
```

---

## Task 7: Update cron household report to use cycle

**Objective:** `household_report.py` script reads each user's cycle_start_day and uses cycle-aware range.

**Files:**
- Modify: `~/.hermes/skills/productivity/financial-tracker/scripts/household_report.py`

**Step 1: Read cycle_start_day per user**

```python
# When loading users, also get their cycle_start_day
c.execute("SELECT id, username, display_name, COALESCE(cycle_start_day, 1) as cycle_start_day FROM users")
users = c.fetchall()
for u in users:
    # Compute cycle range for each user individually
    cycle_start = u["cycle_start_day"]
    if cycle_start > 1:
        # Calculate cycle-based date_from/date_to
        from datetime import date, timedelta
        today = date.today()
        if today.day >= cycle_start:
            d_from = date(today.year, today.month, cycle_start)
        else:
            if today.month == 1:
                d_from = date(today.year - 1, 12, cycle_start)
            else:
                d_from = date(today.year, today.month - 1, cycle_start)
        # ... use d_from, d_to in queries
```

**Step 2: Commit**

```bash
git add ~/.hermes/skills/productivity/financial-tracker/scripts/household_report.py
git commit -m "feat(cron): household report uses user's billing cycle"
```

---

## Task 8: Tests — backend summary with cycle

**Objective:** Ensure all summary endpoints work with cycle-enabled mode.

**Files:**
- Modify: `backend/tests/test_summaries.py`
- Modify: `backend/tests/test_transactions.py`

**Step 1: Add comprehensive cycle tests**

```python
class TestCycleAwareSummaries:
    async def test_cycle_range_25th(self, ...):
        """Verify get_cycle_range returns correct dates for cycle_start_day=25."""

    async def test_cycle_range_1st(self, ...):
        """Default cycle_start_day=1 behaves like calendar month."""

    async def test_current_month_with_cycle(self, ...):
        """Verify transactions outside cycle are excluded."""

    async def test_daily_with_cycle(self, ...):
        """Daily summary respects cycle range."""

    async def test_household_with_cycle(self, ...):
        """Household summary respects cycle range."""
```

**Step 2: Run tests**

Run: `pytest backend/tests/ -v`
Expected: all tests PASS (150+)

**Step 3: Commit**

```bash
git add backend/tests/test_summaries.py backend/tests/test_transactions.py
git commit -m "test: add cycle-aware summary tests"
```

---

## Task 9: Update mobile tests

**Objective:** Ensure Flutter tests still pass with `use_cycle` param.

**Files:**
- Modify: `mobile/test/` — update mock API responses

**Step 1:** Search for mocked summary endpoints and add `use_cycle` where needed.

```bash
grep -rn "summaries/current-month\|summaries/monthly\|summaries/daily\|summaries/household" mobile/test/
```

**Step 2:** Update mocks to accept `use_cycle=true` query param.

**Step 3:** Run Flutter tests (CI will verify).

---

## Task 10: Update docs

**Objective:** Document the new billing cycle feature.

**Files:**
- Create: `docs/10-custom-billing-cycle.md`
- Update: `docs/` — cross-reference

**Step 1: Create feature doc**

Create `docs/10-custom-billing-cycle.md` with architecture diagram, file changes, and before/after comparison.

**Step 2: Update README** if feature is significant.

**Step 3: Commit**

```bash
git add docs/10-custom-billing-cycle.md
git commit -m "docs: add custom billing cycle documentation"
```

---

## Task 11: AI Advisor — inject cycle context for accurate recommendations

**Objective:** AI Financial Advisor (`/api/v1/ai/advise`) must use the user's billing cycle when querying financial data, so recommendations reflect the correct period — not calendar month.

**Why:** Without this, user sets cycle_start_day=25 but AI still reads Jan 1–31 instead of Jan 25–Feb 24. All balance, income, expense, category breakdown, and trend data are wrong.

**Files:**
- Modify: `backend/app/routers/ai_advisor.py`

**Changes needed in `_build_context()`:**

```python
# Step 1: Read user's cycle_start_day from DB
cursor = await db.execute(
    "SELECT COALESCE(cycle_start_day, 1) as cycle_start_day FROM users WHERE id = ?",
    (user_id,),
)
row = await cursor.fetchone()
cycle_start_day = row["cycle_start_day"] if row else 1

# Step 2: Use get_cycle_range instead of calendar month
from app.utils.cycle import get_cycle_range
now = datetime.now(timezone(timedelta(hours=7)))
d_from_date, d_to_date = get_cycle_range(now.date(), cycle_start_day)
d_from = d_from_date.isoformat()
d_to = d_to_date.isoformat()

# Step 3: Update month_display to reflect cycle range
month_display = f"{d_from_date.strftime('%d %b')} – {d_to_date.strftime('%d %b %Y')}"
```

**Detail file:**
| Location | Before | After |
|----------|--------|-------|
| `d_from` (line 88) | `f"{month}-01"` | `d_from_date.isoformat()` from `get_cycle_range()` |
| `d_to` (line 89) | `f"{month}-31"` | `d_to_date.isoformat()` from `get_cycle_range()` |
| `month` variable | `now.strftime("%Y-%m")` | Still used for budgets, but budgets query uses `d_from`/`d_to` |
| `month_display` (line 87) | `now.strftime("%B %Y")` | `f"{d_from_date.strftime('%d %b')} – {d_to_date.strftime('%d %b %Y')}"` |
| Trend (lines 122-144) | Calendar months | Keep as-is — trend can stay monthly for long-range view |

**System prompt update:** `{month}` now resolves to cycle label (e.g., `"25 Apr – 24 Mei 2026"`) — no separate cycle line needed.

**Step 4: Run tests**

```bash
pytest backend/tests/ -v
# 157 tests pass (7 new cycle tests)
```

**Step 5: Commit**

Combined with Flutter + cron changes:

```bash
git commit -m "feat(cycle): flutter profile picker, use_cycle providers, cron cycle, ai advisor cycle"
```

**Actual diff summary:**
- `d_from`/`d_to` → `get_cycle_range()` with cycle_start_day from DB
- `month` variable removed → budgets use `d_from_date.strftime("%Y-%m")`
- `month_display` → cycle label string
- Context dict → added `cycle_label` key
- SYSTEM_PROMPT unchanged — `{month}` already renders cycle label
- Trend 6 bulan tetap pakai calendar month (long-range trending)
