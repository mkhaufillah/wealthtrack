# 24 — Phase 4: Server-computed report stats (savings rate + daily avg)

**Status:** ✅ Done — server computes `savings_rate` + `daily_avg_expense` in
`GET /summaries/monthly`; mobile reads them (local formula removed).
**Scope owner:** Filla / Hermes

## Backdrop

Phase 3 closed home to a single round-trip; the audit then removed the KPR
client amortization math (`/kpr/calculate`). The last remaining financial
*formula* in the APK is the monthly report's **savings rate** (and its close
companion, **daily average expense**), computed in
`mobile/lib/features/reports/ui/reports_screen.dart`:

```dart
final savingsExpense = categories.where(c.name == 'Tabungan & Investasi').sum(total);
final savingsIncome = incomeCategories.where(c.name == 'Penarikan Tabungan & Investasi').sum(total);
final adjustedNumerator = (income - expense) + (savingsExpense - savingsIncome);
final savingsRate = income > 0 ? (adjustedNumerator / income * 100) : 0.0;
final dailyAvg = actualDays > 0 ? expense ~/ actualDays : 0;
```

Per the standing rule *"Server: copy/format/flags/colors/formulas"*, these
formulas belong on the server — one source of truth, no APK rebuild needed
when the formula changes.

## Backend

`GET /summaries/monthly` (single-month mode,
`backend/app/services/summary_service.py::_get_single_month`) already returns
`categories` and `income_categories` (with names + totals), plus
`total_income`/`total_expense`. Add two computed fields:

- `savings_rate`: adjusted savings rate formula above, rounded to 1 decimal;
  0 when income <= 0.
- `daily_avg_expense`: `expense // days`, where `days` = `(d_to - d_from)` in
  days (fallback 30 when <= 0), matching the client's cycle-day computation.

These are additive fields; no existing contract breaks. Multi-month
(range/trend) mode stays as-is — the charts only need income/expense/balance.

### Tests

- `backend/tests/test_summaries.py`: extend `test_monthly_specific` (or new
  test) to assert `savings_rate` + `daily_avg_expense` present and sane for
  seeded Filla data (income 15jt, categories include 'Tabungan & Investasi').
- Edge: month with zero income → `savings_rate == 0`.

## Mobile

`mobile/lib/features/reports/models/report_model.dart`:
`MonthlyReport` gains `savingsRate` (double) + `dailyAvgExpense` (int), parsed
from the new fields (default 0 when absent — backward compatible with older
backend).

`reports_screen.dart::_buildExtraStats`:
- Use `report.savingsRate` / `report.dailyAvgExpense` when present.
- Keep the existing local computation as fallback only when the new fields are
  missing (old backend) — or remove it entirely once backend is live
  (preferred: remove, keeping the screen lean; the backend always ships first).

## Non-goals

- Household report stats stay client-presented (percentages are already
  server-computed per category; the savings card is personal monthly only).
- No new copy keys: `report.savings_rate` (`Simpanan`) and `report.daily_avg`
  already exist.

## Ship

Backend pytest green → deploy backend first → then mobile build (APK green).
Update this doc status at the end.