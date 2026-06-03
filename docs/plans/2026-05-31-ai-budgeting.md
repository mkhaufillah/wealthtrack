# AI Budgeting Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build AI-powered budgeting features: budget suggestions from historical data, one-tap apply on mobile, smart budget insights in AI Advisor, and budget health forecasting.

**Architecture:** Backend (FastAPI) — new `/budgets/suggestions` endpoint + projection logic. Flutter — suggestion review bottom sheet with accept/decline per category. AI Advisor — enhanced prompt with budget health and projected overrun analysis.

**Tech Stack:** Python/FastAPI, Flutter/Dart, PostgreSQL (existing), same structure as existing budget features.

---

## A — Budget Suggestions API

### Task A1: Add `BudgetSuggestion` schema

**Objective:** Create Pydantic response model for budget suggestions.

**Files:**
- Modify: `backend/app/schemas/budget.py`

**Step 1: Add new models**

Add after `UnbudgetedExpense`:

```python
class BudgetSuggestion(BaseModel):
    category_id: int
    category_name: str
    category_name_en: str = ''
    category_icon: str
    suggested_amount: int
    historical_avg: int
    historical_max: int
    months_analyzed: int
    has_budget: bool = False  # True if user already has a budget for this category this cycle
    existing_amount: int = 0


class BudgetSuggestionResponse(BaseModel):
    items: list[BudgetSuggestion]
    total_suggested: int = 0
    total_income: int = 0
    warning: str = ''  # non-empty if suggestions exceed income
```

**Step 2: Run test to verify imports work**

Run: `cd ~/dev/wealthtrack/backend && python -c "from app.schemas.budget import BudgetSuggestion, BudgetSuggestionResponse; print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
cd ~/dev/wealthtrack && git add backend/app/schemas/budget.py && git commit -m "feat(budget): add BudgetSuggestion schemas"
```

### Task A2: Create `_get_historical_spending` helper

**Objective:** Write a function that queries average spending per category over the last N cycles.

**Files:**
- Create: `backend/app/utils/budget_ai.py`

**Step 1: Create `budget_ai.py`**

```python
"""AI-powered budget utilities: historical analysis, suggestions, projections."""
from datetime import date, datetime, timedelta, timezone
from typing import Optional
from app.utils.cycle import get_cycle_range_for_month


async def get_historical_spending(
    db,
    user_id: int,
    cycle_start_day: int = 1,
    num_cycles: int = 3,
) -> list[dict]:
    """Analyze avg/max spending per expense category over last N cycles.

    Returns list of dicts with: category_id, category_name, category_name_en,
    category_icon, avg_amount, max_amount, months_analyzed.
    Only categories with at least one transaction in the period are included.
    """
    today = date.today()
    cycles = []
    # Build a list of (month_param, d_from, d_to) for the last N cycles
    for i in range(num_cycles):
        # Go back i months from current
        y = today.year
        m = today.month - i
        while m < 1:
            m += 12
            y -= 1
        month_str = f"{y:04d}-{m:02d}"
        d_from, d_to = get_cycle_range_for_month(month_str, cycle_start_day)
        cycles.append((d_from.isoformat(), d_to.isoformat()))

    # For each category, sum up spending across all cycles
    placeholders = ",".join("?" * (2 * num_cycles))
    # Build OR conditions per cycle
    conditions = " OR ".join(
        f"(COALESCE(t.date, substr(t.created_at,1,10)) >= ? AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?)"
        for _ in range(num_cycles)
    )
    params = []
    for d_from, d_to in cycles:
        params.extend([d_from, d_to])

    cursor = await db.execute(
        f"""SELECT t.category_id,
                   c.name AS category_name,
                   c.name_en AS category_name_en,
                   c.icon AS category_icon,
                   CAST(COALESCE(AVG(t.amount), 0) AS INTEGER) AS avg_amount,
                   CAST(COALESCE(MAX(t.amount), 0) AS INTEGER) AS max_amount,
                   COUNT(DISTINCT strftime('%Y-%m', COALESCE(t.date, substr(t.created_at,1,10)))) AS months_with_data
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.user_id = ?
              AND t.type = 'expense'
              AND ({conditions})
            GROUP BY t.category_id
            ORDER BY avg_amount DESC""",
        (user_id, *params),
    )
    rows = await cursor.fetchall()
    return [
        {
            "category_id": r["category_id"],
            "category_name": r["category_name"] or f"Cat#{r['category_id']}",
            "category_name_en": r["category_name_en"] or "",
            "category_icon": r["category_icon"] or "📦",
            "avg_amount": r["avg_amount"],
            "max_amount": r["max_amount"],
            "months_analyzed": r["months_with_data"],
        }
        for r in rows
    ]


async def get_projection(
    db,
    user_id: int,
    cycle_start_day: int,
    d_from: str,
    d_to: str,
) -> dict:
    """Calculate mid-cycle budget projections.

    Returns dict with:
    - days_elapsed: number of days into the cycle
    - total_days: total days in cycle
    - cycle_progress_pct: percentage of cycle completed
    - categories: list per budget with projected_end_amount
    """
    from datetime import date

    d_from_date = date.fromisoformat(d_from)
    d_to_date = date.fromisoformat(d_to)
    total_days = (d_to_date - d_from_date).days or 1
    today = date.today()
    days_elapsed = max(1, (today - d_from_date).days)
    progress_pct = round(days_elapsed / total_days * 100, 1)

    # Get budgets with actual spending for this cycle
    cursor = await db.execute(
        """SELECT b.category_id, b.category_name, b.budget_amount,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS actual
           FROM budgets b
           LEFT JOIN transactions t ON t.category_id = b.category_id
               AND t.user_id = b.user_id
               AND COALESCE(t.date, substr(t.created_at,1,10)) BETWEEN ? AND ?
           WHERE b.month = ? AND b.user_id = ?
           GROUP BY b.category_id""",
        (d_from, d_to, d_from_date.strftime("%Y-%m"), user_id),
    )
    rows = await cursor.fetchall()

    categories = []
    for r in rows:
        actual = r["actual"]
        budget = r["budget_amount"]
        pct = round(actual / budget * 100, 1) if budget > 0 else 0.0
        remaining = budget - actual
        # Project: (actual / days_elapsed) * total_days
        daily_rate = actual / days_elapsed if days_elapsed > 0 else 0
        projected_end = int(daily_rate * total_days)
        projected_remaining = budget - projected_end
        is_over_projected = projected_remaining < 0

        if pct >= 100:
            health = "exhausted"
        elif projected_remaining < 0:
            health = "at_risk"
        elif pct >= 70:
            health = "warning"
        else:
            health = "healthy"

        categories.append({
            "category_id": r["category_id"],
            "category_name": r["category_name"],
            "budget_amount": budget,
            "actual_spent": actual,
            "percentage": pct,
            "remaining": remaining,
            "daily_rate": int(daily_rate),
            "projected_end": projected_end,
            "projected_remaining": projected_remaining,
            "health": health,
        })

    return {
        "days_elapsed": days_elapsed,
        "total_days": total_days,
        "cycle_progress_pct": progress_pct,
        "categories": categories,
    }
```

**Step 2: Verify no syntax errors**

Run: `cd ~/dev/wealthtrack/backend && python -c "from app.utils.budget_ai import get_historical_spending, get_projection; print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
cd ~/dev/wealthtrack && git add backend/app/utils/budget_ai.py && git commit -m "feat(budget): add historical spending and projection utils"
```

### Task A3: Add `GET /budgets/suggestions` endpoint

**Objective:** Create the suggestions endpoint that uses `get_historical_spending` and returns suggested budget amounts.

**Files:**
- Modify: `backend/app/routers/budgets.py`
- Test: `backend/tests/test_budget_suggestions.py` (new)

**Step 1: Add the endpoint to `budgets.py`**

At the end of the file (before any existing trailing code), add:

```python
@router.get("/suggestions", response_model=BudgetSuggestionResponse)
async def budget_suggestions(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    num_cycles: int = Query(3, ge=1, le=12),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Analyze historical spending and suggest budget amounts per category."""
    # Get user's cycle setting
    cursor = await db.execute(
        "SELECT cycle_start_day FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user_row = await cursor.fetchone()
    cycle_start_day = user_row["cycle_start_day"] if user_row else 1

    # Get historical data
    from app.utils.budget_ai import get_historical_spending
    history = await get_historical_spending(
        db,
        current_user["id"],
        cycle_start_day=cycle_start_day,
        num_cycles=num_cycles,
    )

    if not history:
        return BudgetSuggestionResponse(items=[])

    # Get existing budgets for this month
    cursor = await db.execute(
        "SELECT category_id, budget_amount FROM budgets WHERE month = ? AND user_id = ?",
        (month, current_user["id"]),
    )
    existing = {}
    async for r in cursor:
        existing[r["category_id"]] = r["budget_amount"]

    # Build suggestions
    items = []
    for h in history:
        cat_id = h["category_id"]
        # Suggested amount: use avg, but round up to nearest 10k
        raw = h["avg_amount"]
        suggested = ((raw + 9999) // 10000) * 10000
        if suggested < 10000:
            suggested = 10000  # minimum Rp10k

        items.append(BudgetSuggestion(
            category_id=cat_id,
            category_name=h["category_name"],
            category_name_en=h["category_name_en"],
            category_icon=h["category_icon"],
            suggested_amount=suggested,
            historical_avg=h["avg_amount"],
            historical_max=h["max_amount"],
            months_analyzed=h["months_analyzed"],
            has_budget=cat_id in existing,
            existing_amount=existing.get(cat_id, 0),
        ))

    total_suggested = sum(i.suggested_amount for i in items if not i.has_budget)

    # Also fetch total income for comparison
    from app.utils.cycle import get_cycle_range_for_month
    d_from, d_to = get_cycle_range_for_month(month, cycle_start_day)
    cursor = await db.execute(
        """SELECT COALESCE(SUM(amount), 0) FROM transactions
           WHERE user_id = ? AND type = 'income'
             AND COALESCE(date, substr(created_at,1,10)) BETWEEN ? AND ?""",
        (current_user["id"], d_from.isoformat(), d_to.isoformat()),
    )
    row = await cursor.fetchone()
    total_income = row[0] if row else 0

    warning = ""
    if total_income > 0 and total_suggested > total_income:
        warning = f"Suggested budgets (Rp{total_suggested:,}) exceed income (Rp{total_income:,}). Consider reducing."

    return BudgetSuggestionResponse(
        items=items,
        total_suggested=total_suggested,
        total_income=total_income,
        warning=warning,
    )
```

Don't forget to add the import for `BudgetSuggestion, BudgetSuggestionResponse` at the top of the file.

Update the existing import line:
```python
from app.schemas.budget import BudgetCreate, BudgetResponse, BudgetSummaryItem, BudgetSummaryResponse, UnbudgetedExpense, BudgetSuggestion, BudgetSuggestionResponse
```

**Step 2: Write test file `tests/test_budget_suggestions.py`**

```python
"""Tests for GET /budgets/suggestions endpoint."""

from httpx import AsyncClient


class TestBudgetSuggestions:
    async def test_requires_auth(self, client: AsyncClient):
        resp = await client.get("/api/v1/budgets/suggestions?month=2026-05")
        assert resp.status_code == 401

    async def test_empty_when_no_data(self, client: AsyncClient, empty_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-05",
            headers={"Authorization": f"Bearer {empty_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["items"] == []

    async def test_returns_suggestions(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data
        if data["items"]:
            item = data["items"][0]
            assert "category_id" in item
            assert "suggested_amount" in item
            assert item["suggested_amount"] > 0

    async def test_invalid_month_format(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-5",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422

    async def test_num_cycles_param(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/suggestions?month=2026-05&num_cycles=6",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data
```

Also add an `empty_token` fixture to `tests/conftest.py`:

```python
@pytest.fixture
async def empty_token(client: AsyncClient):
    """A user with no transaction data."""
    resp = await client.post(
        "/api/v1/auth/register",
        json={"username": "emptyuser", "display_name": "Empty", "password": "Test1234!"},
    )
    data = resp.json()
    return data["access_token"]
```

**Step 3: Run tests**

Run: `cd ~/dev/wealthtrack/backend && python -m pytest tests/test_budget_suggestions.py -v`
Expected: all 6 tests pass

**Step 4: Commit**

```bash
cd ~/dev/wealthtrack && git add backend/app/routers/budgets.py backend/app/schemas/budget.py backend/app/utils/budget_ai.py backend/tests/test_budget_suggestions.py backend/tests/conftest.py && git commit -m "feat(budget): add GET /budgets/suggestions endpoint"
```

---

## B — Flutter Suggestion Review UI

### Task B1: Add suggestion model and repository method

**Objective:** Add `BudgetSuggestion` model and fetch method to the mobile codebase.

**Files:**
- Modify: `mobile/lib/features/budgets/models/budget_model.dart`
- Modify: `mobile/lib/features/budgets/data/budget_repository.dart`

**Step 1: Add `BudgetSuggestion` model to `budget_model.dart`**

```dart
class BudgetSuggestion {
  final int categoryId;
  final String categoryName;
  final String categoryNameEn;
  final String categoryIcon;
  final int suggestedAmount;
  final int historicalAvg;
  final int historicalMax;
  final int monthsAnalyzed;
  final bool hasBudget;
  final int existingAmount;
  final bool accepted;  // UI state: user toggled accept

  BudgetSuggestion({
    required this.categoryId,
    required this.categoryName,
    required this.categoryNameEn,
    required this.categoryIcon,
    required this.suggestedAmount,
    required this.historicalAvg,
    required this.historicalMax,
    required this.monthsAnalyzed,
    this.hasBudget = false,
    this.existingAmount = 0,
    this.accepted = false,
  });

  BudgetSuggestion copyWith({bool? accepted}) =>
      BudgetSuggestion(
        categoryId: categoryId,
        categoryName: categoryName,
        categoryNameEn: categoryNameEn,
        categoryIcon: categoryIcon,
        suggestedAmount: suggestedAmount,
        historicalAvg: historicalAvg,
        historicalMax: historicalMax,
        monthsAnalyzed: monthsAnalyzed,
        hasBudget: hasBudget,
        existingAmount: existingAmount,
        accepted: accepted ?? this.accepted,
      );

  factory BudgetSuggestion.fromJson(Map<String, dynamic> json) =>
      BudgetSuggestion(
        categoryId: json['category_id'] as int,
        categoryName: json['category_name'] as String? ?? '',
        categoryNameEn: json['category_name_en'] as String? ?? '',
        categoryIcon: json['category_icon'] as String? ?? '📦',
        suggestedAmount: json['suggested_amount'] as int,
        historicalAvg: json['historical_avg'] as int,
        historicalMax: json['historical_max'] as int,
        monthsAnalyzed: json['months_analyzed'] as int,
        hasBudget: json['has_budget'] as bool? ?? false,
        existingAmount: json['existing_amount'] as int? ?? 0,
      );
}

class BudgetSuggestionResponse {
  final List<BudgetSuggestion> items;
  final int totalSuggested;
  final int totalIncome;
  final String warning;
  BudgetSuggestionResponse(this.items, this.totalSuggested, this.totalIncome, this.warning);

  factory BudgetSuggestionResponse.fromJson(Map<String, dynamic> json) =>
      BudgetSuggestionResponse(
        (json['items'] as List).map((e) => BudgetSuggestion.fromJson(e as Map<String, dynamic>)).toList(),
        json['total_suggested'] as int? ?? 0,
        json['total_income'] as int? ?? 0,
        json['warning'] as String? ?? '',
      );
}
```

**Step 2: Add repository method to `budget_repository.dart`**

```dart
Future<BudgetSuggestionResponse> getSuggestions(String month, {int numCycles = 3}) async {
  final res = await _client.get('/budgets/suggestions', queryParams: {
    'month': month,
    'num_cycles': numCycles.toString(),
  });
  return BudgetSuggestionResponse.fromJson(res.data as Map<String, dynamic>);
}
```

**Step 3: Run existing tests to ensure nothing broken**

Run: `cd ~/dev/wealthtrack/mobile && flutter test test/features/budgets_screen_test.dart`
Expected: tests pass

**Step 4: Commit**

```bash
cd ~/dev/wealthtrack && git add mobile/lib/features/budgets/models/budget_model.dart mobile/lib/features/budgets/data/budget_repository.dart && git commit -m "feat(budget): add suggestion model and repository"
```

### Task B2: Create suggestion provider

**Objective:** Create a Riverpod provider for budget suggestion data and apply logic.

**Files:**
- Create: `mobile/lib/features/budgets/providers/budget_suggestion_provider.dart`

**Step 1: Create provider**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/budget_repository.dart';

class BudgetSuggestionState {
  final bool isLoading;
  final String? error;
  final BudgetSuggestionResponse? response;
  final int numAccepted;
  final bool isApplying;

  const BudgetSuggestionState({
    this.isLoading = false,
    this.error,
    this.response,
    this.numAccepted = 0,
    this.isApplying = false,
  });

  BudgetSuggestionState copyWith({
    bool? isLoading,
    String? error,
    BudgetSuggestionResponse? response,
    int? numAccepted,
    bool? isApplying,
  }) => BudgetSuggestionState(
    isLoading: isLoading ?? this.isLoading,
    error: error ?? this.error,
    response: response ?? this.response,
    numAccepted: numAccepted ?? this.numAccepted,
    isApplying: isApplying ?? this.isApplying,
  );
}

class BudgetSuggestionNotifier extends StateNotifier<BudgetSuggestionState> {
  final BudgetRepository _repo;
  String? _currentMonth;

  BudgetSuggestionNotifier(this._repo) : super(const BudgetSuggestionState());

  Future<void> load(String month, {int numCycles = 3}) async {
    _currentMonth = month;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _repo.getSuggestions(month, numCycles: numCycles);
      state = state.copyWith(isLoading: false, response: response);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void toggleAccept(int categoryId) {
    final resp = state.response;
    if (resp == null) return;
    final updated = resp.items.map((item) {
      if (item.categoryId == categoryId) {
        return item.copyWith(accepted: !item.accepted);
      }
      return item;
    }).toList();
    final accepted = updated.where((i) => i.accepted).length;
    state = state.copyWith(
      response: BudgetSuggestionResponse(updated, resp.totalSuggested, resp.totalIncome, resp.warning),
      numAccepted: accepted,
    );
  }

  void toggleSelectAll(bool selectAll) {
    final resp = state.response;
    if (resp == null) return;
    final updated = resp.items.map((item) {
      if (!item.hasBudget) {
        return item.copyWith(accepted: selectAll);
      }
      return item;  // don't toggle existing budgets
    }).toList();
    final accepted = updated.where((i) => i.accepted).length;
    state = state.copyWith(
      response: BudgetSuggestionResponse(updated, resp.totalSuggested, resp.totalIncome, resp.warning),
      numAccepted: accepted,
    );
  }

  Future<bool> applySelected(String month) async {
    final resp = state.response;
    if (resp == null) return false;
    state = state.copyWith(isApplying: true);
    try {
      final selected = resp.items.where((i) => i.accepted && !i.hasBudget).toList();
      for (final item in selected) {
        await _repo.create({
          'month': month,
          'category_id': item.categoryId,
          'amount': item.suggestedAmount,
        });
      }
      state = state.copyWith(isApplying: false);
      return true;
    } catch (e) {
      state = state.copyWith(isApplying: false, error: e.toString());
      return false;
    }
  }
}

final budgetSuggestionProvider = StateNotifierProvider<BudgetSuggestionNotifier, BudgetSuggestionState>((ref) {
  final api = ref.watch(apiClientProvider);
  return BudgetSuggestionNotifier(BudgetRepository(api));
});
```

**Step 2: Verify compilation**

Run: `cd ~/dev/wealthtrack/mobile && flutter analyze lib/features/budgets/providers/budget_suggestion_provider.dart`
Expected: No issues

**Step 3: Commit**

```bash
cd ~/dev/wealthtrack && git add mobile/lib/features/budgets/providers/budget_suggestion_provider.dart && git commit -m "feat(budget): add budget suggestion provider"
```

### Task B3: Build suggestion review bottom sheet

**Objective:** Create the UI that shows budget suggestions with accept/decline toggles.

**Files:**
- Create: `mobile/lib/features/budgets/ui/budget_suggestion_sheet.dart`

**Step 1: Create the bottom sheet widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../providers/budget_suggestion_provider.dart';
import '../models/budget_model.dart';

class BudgetSuggestionSheet extends ConsumerStatefulWidget {
  final String month;
  const BudgetSuggestionSheet({super.key, required this.month});

  @override
  ConsumerState<BudgetSuggestionSheet> createState() => _BudgetSuggestionSheetState();
}

class _BudgetSuggestionSheetState extends ConsumerState<BudgetSuggestionSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(budgetSuggestionProvider.notifier).load(widget.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(budgetSuggestionProvider);
    final notifier = ref.read(budgetSuggestionProvider.notifier);
    final resp = state.response;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text('AI Budget Suggestions',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (state.isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (state.error != null)
              Expanded(child: Center(
                child: Text(state.error!, style: TextStyle(color: AppColors.highlight)),
              ))
            else if (resp == null || resp.items.isEmpty)
              Expanded(child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 48, color: AppColors.textSecondary.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    Text('No suggestions available',
                        style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('Add more transactions to get AI-powered budget suggestions.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ))
            else ...[
              // Warning if over income
              if (resp.warning.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(child: Text(resp.warning,
                          style: TextStyle(fontSize: 12, color: AppColors.warning))),
                    ],
                  ),
                ),
              // Summary bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('${state.numAccepted} of ${resp.items.where((i) => !i.hasBudget).length} selected',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => notifier.toggleSelectAll(true),
                      child: const Text('Select All', style: TextStyle(fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () => notifier.toggleSelectAll(false),
                      child: const Text('Clear', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
              // List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: resp.items.length,
                  itemBuilder: (_, i) => _buildSuggestionCard(resp.items[i], notifier),
                ),
              ),
              // Apply button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: state.isApplying || state.numAccepted == 0
                          ? null
                          : () async {
                              final ok = await notifier.applySelected(widget.month);
                              if (ok && mounted) Navigator.pop(context);
                            },
                      child: state.isApplying
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text('Apply ${state.numAccepted} Budget${state.numAccepted != 1 ? 's' : ''}'),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(BudgetSuggestion item, BudgetSuggestionNotifier notifier) {
    final isAccepted = item.accepted;
    final isExisting = item.hasBudget;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isExisting ? AppColors.divider.withOpacity(0.3) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isAccepted ? AppColors.success.withOpacity(0.5) : AppColors.divider,
          width: isAccepted ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isExisting ? null : () => notifier.toggleAccept(item.categoryId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(item.categoryIcon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.categoryNameEn.isNotEmpty ? item.categoryNameEn : item.categoryName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text('Avg ${formatCurrency(item.historicalAvg)}/mo (${item.monthsAnalyzed}mo)',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (isExisting)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Existing', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                    )
                  else
                    Checkbox(
                      value: isAccepted,
                      onChanged: (_) => notifier.toggleAccept(item.categoryId),
                      activeColor: AppColors.success,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Suggested:',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text(formatCurrency(item.suggestedAmount),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 2: Verify compilation**

Run: `cd ~/dev/wealthtrack/mobile && flutter analyze lib/features/budgets/ui/budget_suggestion_sheet.dart`
Expected: No issues (may have minor import warnings if formatCurrency is not imported — ensure `currency_formatter.dart` has the function)

**Step 3: Commit**

```bash
cd ~/dev/wealthtrack && git add mobile/lib/features/budgets/ui/budget_suggestion_sheet.dart && git commit -m "feat(budget): add suggestion review bottom sheet"
```

### Task B4: Wire suggestion button into budgets screen

**Objective:** Add a "AI Suggestions" button to the budget screen's empty state and FAB area.

**Files:**
- Modify: `mobile/lib/features/budgets/ui/budgets_screen.dart`

**Step 1: Add import and button**

Add import:
```dart
import 'budget_suggestion_sheet.dart';
```

Add "AI Suggestions" button. In `_buildEmptyState`, add a button after the text:
```dart
const SizedBox(height: 16),
FilledButton.icon(
  onPressed: () => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => BudgetSuggestionSheet(month: _monthParam),
  ),
  icon: const Icon(Icons.auto_awesome, size: 18),
  label: const Text('AI Suggestions'),
),
```

Also add a floating "AI" button alongside the existing FAB. Change the FAB to a column:
```dart
floatingActionButton: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    FloatingActionButton.small(
      heroTag: 'ai_suggestions',
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => BudgetSuggestionSheet(month: _monthParam),
      ),
      backgroundColor: AppColors.accent,
      child: const Icon(Icons.auto_awesome, size: 20),
    ),
    const SizedBox(height: 12),
    FloatingActionButton(
      heroTag: 'add_budget',
      onPressed: () => _showAddBudgetSheet(),
      child: const Icon(Icons.add),
    ),
  ],
),
```

**Step 2: Run Flutter analyze**

Run: `cd ~/dev/wealthtrack/mobile && flutter analyze lib/features/budgets/`
Expected: No issues

**Step 3: Run existing tests**

Run: `cd ~/dev/wealthtrack/mobile && flutter test test/features/budgets_screen_test.dart`
Expected: Tests pass

**Step 4: Commit**

```bash
cd ~/dev/wealthtrack && git add mobile/lib/features/budgets/ui/budgets_screen.dart && git commit -m "feat(budget): wire AI suggestions button into budgets screen"
```

---

## C — AI Advisor: Smart Budget Insights

### Task C1: Add budget health + projection context to AI Advisor

**Objective:** Enhance the AI Advisor prompt to include budget health status, projection data, and auto-generated insights.

**Files:**
- Modify: `backend/app/routers/ai_advisor.py`

**Step 1: Add projection data to `_build_context`**

In the `_build_context` function, after the existing budget section (line ~316), add:

```python
# ── Budget health & projection ──
from app.utils.budget_ai import get_projection
projection = await get_projection(
    db, user_id, cycle_start_day, d_from, d_to
)
proj_lines = []
for cat in projection["categories"]:
    icon = {
        "healthy": "✅", "warning": "⚠️", "at_risk": "🔴", "exhausted": "❌"
    }.get(cat["health"], "❓")
    label = {
        "healthy": "Aman", "warning": "Hati-hati", "at_risk": "Berisiko", "exhausted": "Habis"
    }.get(cat["health"], "")
    proj_lines.append(
        f"• {cat['category_name']}: Rp{cat['actual_spent']:,} / Rp{cat['budget_amount']:,} "
        f"({cat['percentage']:.0f}%) {icon} {label}"
    )
    if cat["health"] in ("at_risk", "warning") and cat["projected_end"] > cat["budget_amount"]:
        proj_lines.append(
            f"  ↳ Proyeksi akhir siklus: Rp{cat['projected_end']:,} "
            f"(kelebihan Rp{cat['projected_remaining'] * -1:,})"
        )

# Build the health context block
health_context_lines = [
    f"**Kesehatan Anggaran:** (Hari ke-{projection['days_elapsed']} dari {projection['total_days']} hari — {projection['cycle_progress_pct']:.0f}% siklus)",
]
health_context_lines.extend(proj_lines) if proj_lines else health_context_lines.append("Tidak ada data anggaran.")
health_context = "\n".join(health_context_lines)
```

**Step 2: Pass health_context into the prompt**

Update the `SYSTEM_PROMPT` to include `{health_context}` variable.

In the template, after the existing `{budgets}` section, add:
```
**Kesehatan Anggaran & Proyeksi:**
{health_context}
```

In the `_build_messages` or wherever the prompt template is formatted, add `health_context=health_context` to the format arguments.

**Step 3: Update the analysis guidelines in SYSTEM_PROMPT**

In the "CARA MENGANALISIS" section, enhance point 1:
```
1. **Kesehatan Anggaran** — Bandingkan realisasi vs anggaran per kategori. Kategori mana yang over budget? Mana yang masih aman? Hitung sisa anggaran. Gunakan data proyeksi untuk memperingatkan jika tren pengeluaran saat ini akan menyebabkan over budget sebelum akhir siklus.
```

**Step 4: Run tests**

Run: `cd ~/dev/wealthtrack/backend && python -m pytest tests/test_ai_advisor.py -v`
Expected: All passed (the test mocks may need minor updates if they assert exact prompt content)

**Step 5: Commit**

```bash
cd ~/dev/wealthtrack && git add backend/app/routers/ai_advisor.py && git commit -m "feat(ai-advisor): add budget health projection context"
```

---

## D — Budget Health Forecasting

### Task D1: Add `GET /budgets/health` endpoint

**Objective:** Create an endpoint that returns budget health forecast data — usable by both the Flutter app and AI Advisor.

**Files:**
- Modify: `backend/app/routers/budgets.py`
- Modify: `backend/app/schemas/budget.py`

**Step 1: Add health schema to `budget.py`**

```python
class BudgetHealthItem(BaseModel):
    category_id: int
    category_name: str
    category_name_en: str = ''
    category_icon: str
    budget_amount: int
    actual_spent: int
    percentage: float
    remaining: int
    daily_rate: int
    projected_end: int
    projected_remaining: int
    health: str  # "healthy" | "warning" | "at_risk" | "exhausted"

class BudgetHealthResponse(BaseModel):
    days_elapsed: int
    total_days: int
    cycle_progress_pct: float
    categories: list[BudgetHealthItem]
```

**Step 2: Add endpoint to `budgets.py`**

```python
@router.get("/health", response_model=BudgetHealthResponse)
async def budget_health(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get budget health forecast — projected end-of-cycle spending vs budget."""
    cursor = await db.execute(
        "SELECT cycle_start_day FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user_row = await cursor.fetchone()
    cycle_start_day = user_row["cycle_start_day"] if user_row else 1

    from app.utils.cycle import get_cycle_range_for_month
    d_from, d_to = get_cycle_range_for_month(month, cycle_start_day)

    from app.utils.budget_ai import get_projection
    return await get_projection(
        db, current_user["id"], cycle_start_day,
        d_from.isoformat(), d_to.isoformat(),
    )
```

**Step 3: Add tests `tests/test_budget_health.py`**

```python
"""Tests for GET /budgets/health endpoint."""
from httpx import AsyncClient

class TestBudgetHealth:
    async def test_requires_auth(self, client: AsyncClient):
        resp = await client.get("/api/v1/budgets/health?month=2026-05")
        assert resp.status_code == 401

    async def test_returns_projections(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/health?month=2026-05",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "days_elapsed" in data
        assert "total_days" in data
        assert "categories" in data

    async def test_invalid_month_format(self, client: AsyncClient, filla_token: str):
        resp = await client.get(
            "/api/v1/budgets/health?month=2026-5",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 422
```

**Step 4: Run all budget tests**

Run: `cd ~/dev/wealthtrack/backend && python -m pytest tests/test_budget_health.py tests/test_budget_suggestions.py tests/test_budgets.py -v`
Expected: All pass

**Step 5: Run full backend test suite**

Run: `cd ~/dev/wealthtrack/backend && python -m pytest -v`
Expected: 175 + new tests all pass

**Step 6: Commit**

```bash
cd ~/dev/wealthtrack && git add backend/app/routers/budgets.py backend/app/schemas/budget.py backend/app/utils/budget_ai.py backend/tests/test_budget_health.py backend/tests/test_budget_suggestions.py && git commit -m "feat(budget): add budget health forecasting endpoint"
```

---

## E — Documentation & Integration

### Task E1: Update docs

**Objective:** Sync documentation with new features.

**Files:**
- Modify: `docs/03-backend-api.md`
- Modify: `docs/05-flutter-mobile.md`
- Modify: `CHANGELOG.md`

**Step 1: Update `docs/03-backend-api.md` — add suggestions and health endpoints**

Add section after existing budget API docs:
```
### `GET /budgets/suggestions`

Analyze historical spending and suggest budget amounts.

**Parameters:**
- `month` (required, `YYYY-MM`) — target month
- `num_cycles` (optional, default 3, max 12) — cycles of history to analyze

**Response:**
```json
{
  "items": [{
    "category_id": 1,
    "category_name": "Makanan & Minuman",
    "category_name_en": "Food & Drinks",
    "category_icon": "🍔",
    "suggested_amount": 1500000,
    "historical_avg": 1420000,
    "historical_max": 1850000,
    "months_analyzed": 3,
    "has_budget": true,
    "existing_amount": 1200000
  }],
  "total_suggested": 5000000,
  "total_income": 8000000,
  "warning": ""
}
```

### `GET /budgets/health`

Get budget health forecast with projected end-of-cycle spending.

**Parameters:**
- `month` (required, `YYYY-MM`) — target month

**Response:**
```json
{
  "days_elapsed": 6,
  "total_days": 30,
  "cycle_progress_pct": 20.0,
  "categories": [{
    "category_id": 1,
    "category_name": "Makanan & Minuman",
    "budget_amount": 1500000,
    "actual_spent": 450000,
    "percentage": 30.0,
    "remaining": 1050000,
    "daily_rate": 75000,
    "projected_end": 2250000,
    "projected_remaining": -750000,
    "health": "at_risk"
  }]
}
```

Health categories:
- `healthy` — under 70% spent or well within projected budget
- `warning` — 70-99% spent or projected to exceed budget
- `at_risk` — projected to exceed budget significantly
- `exhausted` — budget fully consumed
```

**Step 2: Update `CHANGELOG.md`**

Add v0.4.0 entry:
```markdown
## v0.4.0 — AI Budgeting (2026-05-31)

### Features
- **Budget Suggestions API** — `GET /budgets/suggestions` analyzes last 3-12 cycles of spending and recommends budget amounts per category based on historical average.
- **Forecast API** — `GET /budgets/health` returns mid-cycle projections: per-category daily rate, projected end-of-cycle total, and health status (healthy/warning/at_risk/exhausted).
- **Flutter: AI Suggestions sheet** — Bottom sheet showing suggested budgets per category with accept/decline toggle, \"Select All\" / \"Apply N budgets\" button.
- **AI Advisor: Budget Health** — Advisor prompt enhanced with budget health context: days elapsed, cycle progress %, per-category health status, and projected overrun alerts.

### API Changes
- New `GET /api/v1/budgets/suggestions?month=&num_cycles=`
- New `GET /api/v1/budgets/health?month=`

### Dependencies
- No new dependencies (all pure Python + existing stack)
```

**Step 3: Commit**

```bash
cd ~/dev/wealthtrack && git add docs/03-backend-api.md CHANGELOG.md && git commit -m "docs: add AI budgeting API and changelog"
```

### Task E2: Deploy and verify

**Objective:** Deploy to production and run health check.

**Step 1: Deploy**

```bash
cd ~/dev/wealthtrack && git push && sudo systemctl restart wealthtrack && sleep 2 && curl -s http://127.0.0.1:8080/api/v1/health
```
Expected: `{"status": "ok", "database": "connected"}`

**Step 2: Verify suggestions endpoint**

```bash
curl -s -H "Authorization: Bearer $(curl -s -X POST http://127.0.0.1:8080/api/v1/auth/login -H 'Content-Type: application/json' -d '{"username":"filla","password":"..."}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')" "http://127.0.0.1:8080/api/v1/budgets/suggestions?month=2026-05" | python3 -m json.tool
```
Expected: 200 with items array

**Step 3: Verify health endpoint**

```bash
curl -s -H "Authorization: Bearer $(same token)" "http://127.0.0.1:8080/api/v1/budgets/health?month=2026-05" | python3 -m json.tool
```
Expected: 200 with projection data

---

## Summary

| Phase | Tasks | Est. Time |
|-------|-------|-----------|
| A | ✅ Suggestions API (schema + util + endpoint + tests) | ~2h |
| B | ✅ Flutter suggestion UI (model + provider + sheet + wiring) | ~2h |
| C | ✅ AI Advisor health context (projection + prompt update) | ~1h |
| D | ✅ Health forecast endpoint (schema + endpoint + tests) | ~1h |
| E | ✅ Docs + deploy | ~30m |
| **Total** | **14 tasks** ✅ **Completed** | **~6.5h** |
