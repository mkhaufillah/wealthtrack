# Delete Extra Payment Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task. Do not invent a second extra-payment domain — this is KPR / household-debt simulations only.

**Goal:** Let Filla/Nahda delete a mistaken KPR extra payment from the simulation detail screen so the amortization schedule (and remaining extra-payment snapshots) match corrected data.

**Architecture:** Backend `DELETE /kpr/simulations/{id}/extra-payments/{eid}` and Flutter `KPRNotifier.deleteExtraPayment()` already exist. The work is (1) harden delete so remaining extras get recomputed snapshots, (2) wire a confirmation + overflow menu on the extra-payment card, (3) cover the gap with TDD tests. No new table, no new route, no MCP tool.

**Tech Stack:** FastAPI + asyncpg (SQL in `KPRService`), `kpr_engine.apply_extra_payment`, Flutter Riverpod, `go_router`, existing `AlertDialog` delete pattern from transactions.

**See also:** [Backend API](03-backend-api.md) · [Delete Transaction](11-delete-transaction.md) · [Flutter Mobile](05-flutter-mobile.md) · [Extra Payment KPR](plans/2026-06-09-extra-payment-household-debt.md)

---

## Current context (read this first)

This is **not** a greenfield API. As of v0.7.x:

| Layer | Status |
|-------|--------|
| Table `kpr_extra_payments` | Exists (`backend/app/database.py`) |
| Engine `apply_extra_payment` / `preview_extra_payment` | Exists (`backend/app/services/kpr_engine.py`) |
| `KPRService.delete_extra_payment` | Exists — deletes row, rebuilds base schedule, re-applies remaining extras by `apply_month ASC` |
| Router `DELETE .../extra-payments/{extra_payment_id}` | Exists — 204, JWT, `KPRServiceError` → HTTPException |
| Tests `test_delete_extra_payment`, `test_delete_restores_schedule` | Exist (`backend/tests/test_kpr.py`) |
| Flutter `KPRNotifier.deleteExtraPayment` | Exists — DELETE then `loadDetail` + `loadExtraPayments` |
| Flutter UI | **Missing** — `kpr_detail_screen.dart` `_buildExtraPaymentCard` is display-only |
| Flutter provider tests for extra-payment delete | **Missing** |
| Widget tests for KPR detail | None (do not create a new widget-test stack just for this) |

Auth already matches the rest of KPR: owner **or** household member of `sim.household_id` via `get_simulation_for_user`.

`apply_month` on **create** cannot go backwards. **Delete** currently allows any extra on that simulation (including a middle one). Keep that — correcting a wrong early payment is the point.

### Bug to fix while wiring UI

After deleting extra A, remaining extra B is re-applied on a new schedule, but B’s stored snapshot columns (`old_*`, `new_*`, `total_interest_saved`, end dates) are **not** updated. The detail card reads those columns, so the UI would lie after a mid-list delete.

**Required:** when re-applying remaining extras, `UPDATE kpr_extra_payments` with the new `ExtraPaymentResult` fields (same columns `create_extra_payment` writes).

### Out of scope (YAGNI)

- Edit extra payment in place
- Undo / soft-delete
- MCP `delete_extra_payment`
- Credit-card installment delete (already has its own API)
- New DB migration
- Deploy

---

## Architecture (target)

```
┌─ KPR Detail ─────────────────────────────────────┐
│  Extra Payment card                              │
│    ⋮ → Delete                                    │
│         │                                        │
│         ▼                                        │
│  AlertDialog (same pattern as txn delete)        │
│    Cancel / Delete                               │
│         │ confirm                                │
│         ▼                                        │
│  KPRNotifier.deleteExtraPayment(simId, epId)     │
│    → DELETE /kpr/simulations/{id}/extra-payments/{eid}
│         │                                        │
│         ▼                                        │
│  KPRService.delete_extra_payment                 │
│    1. ownership check                            │
│    2. 404 if extra not on this sim               │
│    3. DELETE row                                 │
│    4. calculate_kpr(base)                        │
│    5. re-apply remaining extras in apply_month order
│    6. UPDATE remaining extras' snapshot columns  │
│    7. replace kpr_monthly_schedules              │
│         │                                        │
│         ▼                                        │
│  loadDetail + loadExtraPayments                  │
│  snackbar: Extra payment deleted                 │
└──────────────────────────────────────────────────┘
```

---

## Files likely to change

- Modify: `backend/app/services/kpr_service.py` (`delete_extra_payment`, ~701–823)
- Modify: `backend/tests/test_kpr.py` (new cases next to existing delete tests)
- Modify: `mobile/lib/features/debt/kpr/ui/kpr_detail_screen.dart` (`_buildExtraPaymentCard`)
- Modify: `mobile/test/features/debt/providers/kpr_provider_test.dart`
- Modify: `docs/03-backend-api.md` (DELETE section: remaining snapshots recalculated)
- Modify: `docs/01-project-overview.md` (link this doc)
- Modify: `CHANGELOG.md` (Unreleased)
- Do **not** modify: `kpr.py` router, `kpr_provider.dart` (already correct), schemas, MCP

---

## Step-by-step plan

### Task 1: Failing backend test — remaining extra snapshots refresh

**Objective:** Prove that deleting an earlier extra updates the later extra’s stored installment/tenor snapshots.

**Files:**
- Test: `backend/tests/test_kpr.py` (class that already has `test_delete_extra_payment`)

**Step 1: Write failing test**

Add after `test_delete_restores_schedule`:

```python
    async def test_delete_middle_extra_recomputes_remaining_snapshot(
        self, client, auth_headers, filla_token
    ):
        """Deleting an earlier extra must refresh later extras' snapshot columns."""
        sim_id = await self._create_sim(client, filla_token)

        first = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 50000000, "apply_month": 12, "reduction_type": "tenor"},
            headers=auth_headers,
        )
        assert first.status_code == 201
        first_id = first.json()["id"]

        second = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 25000000, "apply_month": 24, "reduction_type": "tenor"},
            headers=auth_headers,
        )
        assert second.status_code == 201
        stale_interest = second.json()["total_interest_saved"]
        stale_new_months = second.json()["new_remaining_months"]

        resp = await client.delete(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments/{first_id}",
            headers=auth_headers,
        )
        assert resp.status_code == 204

        remaining = await client.get(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            headers=auth_headers,
        )
        assert remaining.status_code == 200
        rows = remaining.json()
        assert len(rows) == 1
        assert rows[0]["apply_month"] == 24
        # Snapshot must change: second extra now sits on the original (pre-first) schedule
        assert rows[0]["total_interest_saved"] != stale_interest or rows[0]["new_remaining_months"] != stale_new_months
        assert rows[0]["old_remaining_months"] > 0
        assert rows[0]["new_remaining_months"] > 0
```

Also add thin 404 / 403 cases if not present:

```python
    async def test_delete_extra_payment_not_found(self, client, auth_headers, filla_token):
        sim_id = await self._create_sim(client, filla_token)
        resp = await client.delete(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments/999999",
            headers=auth_headers,
        )
        assert resp.status_code == 404

    async def test_delete_extra_forbidden_other_user(
        self, client, filla_token, nahda_token
    ):
        sim_id = await self._create_sim(client, filla_token)
        create_resp = await client.post(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments",
            json={"amount": 50000000, "apply_month": 12, "reduction_type": "tenor"},
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        ep_id = create_resp.json()["id"]
        resp = await client.delete(
            f"/api/v1/kpr/simulations/{sim_id}/extra-payments/{ep_id}",
            headers={"Authorization": f"Bearer {nahda_token}"},
        )
        assert resp.status_code == 403
```

Note: if the sim is household-shared, 403 may not fire for Nahda. `_create_sim` today creates a personal sim — keep it that way. If 403 fails because household_id is set, assert `403` or `404` only after reading `_create_sim`; do not weaken ownership.

**Step 2: Run to verify failure**

```bash
cd /home/deploy/apps/wealthtrack/backend
python -m pytest tests/test_kpr.py::TestKPRExtraPayments::test_delete_middle_extra_recomputes_remaining_snapshot -v --tb=short
```

(Adjust class name to the actual class wrapping `test_delete_extra_payment` — read the file; do not invent a new test class.)

Expected: FAIL — remaining extra’s `total_interest_saved` / months unchanged.

Needs `WEALTHTRACK_TEST_DATABASE_URL` (and typically `REDIS_URL`). **Never** point at production.

**Step 3: Minimal implementation**

In `KPRService.delete_extra_payment`, inside the `else` branch that re-applies remaining extras, after `ep_result = apply_extra_payment(...)`:

```python
await db.execute(
    """UPDATE kpr_extra_payments
       SET old_remaining_balance = ?,
           new_remaining_balance = ?,
           old_remaining_months = ?,
           new_remaining_months = ?,
           old_installment = ?,
           new_installment = ?,
           total_interest_saved = ?,
           original_end_date = ?,
           new_end_date = ?
       WHERE simulation_id = ? AND apply_month = ? AND amount = ?""",
    (
        ep_result.old_remaining_balance,
        ep_result.new_remaining_balance,
        ep_result.old_remaining_months,
        ep_result.new_remaining_months,
        ep_result.old_installment,
        ep_result.new_installment,
        ep_result.total_interest_saved,
        ep_result.original_end_date,
        ep_result.new_end_date,
        sim_id,
        ep_dict["apply_month"],
        ep_dict["amount"],
    ),
)
```

Prefer updating by **id**: change the remaining SELECT to include `id`, then `WHERE id = ?`. Do not match on amount+month only.

Reuse the same `ExtraPaymentResult` attribute names `create_extra_payment` already uses (~587–670). Do not invent columns.

Keep the existing `remaining_count == 0` path (write base schedule only).

**Step 4: Run tests**

```bash
python -m pytest tests/test_kpr.py -v --tb=short -k extra_payment
```

Expected: PASS for delete / restore / middle-recompute / 404 / 403.

**Step 5: Commit** (only when Filla asks to commit, or at end of implementation batch)

```bash
git add backend/app/services/kpr_service.py backend/tests/test_kpr.py
git commit -m "fix(kpr): recompute remaining extra-payment snapshots on delete"
```

---

### Task 2: Flutter provider test for `deleteExtraPayment`

**Objective:** Lock the existing notifier method so UI work cannot “fix” it by rewriting the API call.

**Files:**
- Test: `mobile/test/features/debt/providers/kpr_provider_test.dart`
- Do not change `kpr_provider.dart` unless a test proves a bug

**Step 1: Write failing tests** (they fail only if mock paths are unset — write them first anyway)

Inspect `MockApiClient.onDelete` in `mobile/test/helpers/mocks.dart`. Follow the existing `group('delete')` for simulations.

```dart
    group('deleteExtraPayment', () {
      test('calls DELETE extra-payments path then reloads detail and list', () async {
        mockApi.onGet('/kpr/simulations/1', {
          'id': 1,
          'user_id': 1,
          'name': 'Rumah',
          'property_price': 1000000000,
          'down_payment': 200000000,
          'total_loan': 800000000,
          'tenor_months': 120,
          'interest_type': 'fixed',
          'created_at': '2026-06-09T10:00:00Z',
        });
        mockApi.onGet('/kpr/simulations/1/extra-payments', []);
        mockApi.onDelete('/kpr/simulations/1/extra-payments/9');

        final ok = await notifier.deleteExtraPayment(1, 9);

        expect(ok, true);
        expect(notifier.state.extraPayments, isEmpty);
        expect(notifier.state.error, isNull);
      });

      test('returns false and sets error when delete fails', () async {
        // no onDelete mock → client throws / unexpected body
        final ok = await notifier.deleteExtraPayment(1, 9);
        expect(ok, false);
        expect(notifier.state.error, isNotNull);
      });
    });
```

If `MockApiClient` needs GET after DELETE, register those mocks **before** calling delete (the notifier always `loadDetail` + `loadExtraPayments`).

**Step 2: Run**

```bash
cd /home/deploy/apps/wealthtrack/mobile
flutter test test/features/debt/providers/kpr_provider_test.dart
```

Expected: new group PASS. If Flutter SDK is missing on this VPS, record that in the implementation notes and do not fake results.

---

### Task 3: Detail-screen delete UI (copy transaction pattern)

**Objective:** User can delete an extra payment from KPR detail with a confirmation dialog.

**Files:**
- Modify: `mobile/lib/features/debt/kpr/ui/kpr_detail_screen.dart`

`KPRDetailScreen` is already a `ConsumerStatefulWidget` (or equivalent with `ref`) — use the same `showDialog<bool>` as `transaction_list_screen.dart` `_confirmDelete`.

**Step 1: Add confirm helper** on the State class (next to `_buildExtraPaymentCard`):

```dart
  Future<void> _confirmDeleteExtraPayment(ExtraPaymentRecord ep) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Extra Payment'),
        content: Text(
          'Delete extra payment ${formatCurrency(ep.amount)} at month ${ep.applyMonth}? '
          'The schedule will be rebuilt. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final simId = ep.simulationId;
      final success = await ref
          .read(kprProvider.notifier)
          .deleteExtraPayment(simId, ep.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Extra payment deleted' : 'Failed to delete extra payment',
            ),
          ),
        );
      }
    }
  }
```

**Step 2: Overflow menu on the card header Row**

In `_buildExtraPaymentCard`, the header `Row` currently ends with created-at text. Add `PopupMenuButton` after it (same icons/size as `transaction_tile.dart`):

```dart
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 18, color: AppColors.textSecondary),
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmDeleteExtraPayment(ep);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
```

Do **not** add Edit. Do **not** put delete on `KPRExtraPaymentScreen` (that screen is create-only 3-step flow).

Disable the menu while `state.isLoading` if easy (`onSelected` no-op); do not add a new global loading overlay.

**Step 3: Manual check**

- Empty extras: still the info card, no menu
- One extra: menu → cancel → unchanged
- Confirm → list count drops, schedule length restored if it was the only extra
- Two extras, delete the first → remaining card numbers change (backend Task 1)

**Step 4: Commit**

```bash
git add mobile/lib/features/debt/kpr/ui/kpr_detail_screen.dart \
        mobile/test/features/debt/providers/kpr_provider_test.dart
git commit -m "feat(kpr): delete extra payment from simulation detail"
```

---

### Task 4: Docs + changelog (same change set)

**Objective:** Canonical docs match behavior.

**Files:**
- `docs/03-backend-api.md` — under DELETE extra-payments, add: remaining extras are re-applied in `apply_month` order and their snapshot columns are rewritten; 404 extra not on sim; 403 not owner/household.
- `docs/01-project-overview.md` — Related Documents bullet for this file.
- `CHANGELOG.md` — Unreleased: Flutter delete extra payment; backend snapshot recompute on delete.

Do not rewrite `docs/04-backend-implementation.md` unless a sentence there still says snapshots are immutable.

---

## Tests / validation

Backend (from `backend/`):

```bash
python -m pytest tests/test_kpr.py -v --tb=short -k extra_payment
```

Mobile (from `mobile/`, when SDK exists):

```bash
flutter test test/features/debt/providers/kpr_provider_test.dart
```

Do **not** run against production DB. Do **not** deploy (GitHub Actions on `main`).

---

## Risks, tradeoffs, open questions

1. **Household 403:** Nahda can delete extras on a **shared** household sim. That matches create. If Filla wants owner-only delete, say so before implementation — default is household-same-as-create.
2. **Deleting a middle extra** is allowed. Create still forbids going backwards; after a middle delete, a new extra may be applied at a month that was previously “after” the deleted one. That is intended for correction.
3. **No widget test file** for KPR detail today. Provider + backend tests are the contract; adding a full widget harness is out of scope.
4. **`deleteExtraPayment` does not set `isLoading`.** Create/preview does. Optional polish only if the schedule rebuild feels slow; do not block the feature on it.
5. **Confirmation copy** is English to match the rest of KPR extra-payment UI (`Extra Payments`, `Shorten Tenor`). Do not mix ID unless the surrounding screen is already ID.

---

## Implementation order

1. Backend test (middle extra) → service UPDATE → extra_payment tests green  
2. Flutter provider tests  
3. Detail UI + dialog  
4. Docs/changelog  

Stop after the plan until Filla says implement.
