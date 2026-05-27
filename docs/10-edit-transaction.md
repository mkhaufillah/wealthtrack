# Edit Transaction

**Feature added:** 2026-05-27 · Commit: `bffe0ec`
**See also:** [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)

---

## Overview

Allows users to edit any field of an existing transaction — amount, type (expense/income), category, description, note, and **date** — from the transaction list screen.

The edit flow reuses the existing `AddTransactionScreen` in edit mode rather than building a separate screen. This keeps UI consistent and reduces duplication.

---

## Architecture

```
┌─ Transaction List ─────────────────────┐
│                                        │
│  TransactionTile                       │
│    │                                   │
│    ├── ⋮ → Edit                        │
│    │      context.push('/transactions  │
│    │        /add', extra: transaction)  │
│    │                                   │
│    └── ⋮ → Change Owner (existing)     │
│                                        │
└──────────────────┬────────────────────┘
                   │
                   ▼
┌─ GoRouter ─────────────────────────────┐
│                                        │
│  /transactions/add                     │
│    builder: (_, state) →               │
│      AddTransactionScreen(             │
│        editTransaction: state.extra    │
│      )                                 │
│                                        │
└──────────────────┬────────────────────┘
                   │
                   ▼
┌─ AddTransactionScreen ────────────────┐
│                                        │
│  if editTransaction != null:           │
│    ├─ Title: "Edit Transaction"        │
│    ├─ Prefill all fields               │
│    ├─ Button: "Update"                 │
│    └─ _save() → notifier.update()     │
│                                        │
│  else:                                 │
│    ├─ Title: "Add Transaction"         │
│    ├─ Blank form                       │
│    ├─ Button: "Save"                   │
│    └─ _save() → notifier.create()     │
│                                        │
└──────────────────┬────────────────────┘
                   │
                   ▼
┌─ Provider → Repository ───────────────┐
│                                        │
│  TransactionListNotifier.update(       │
│    id, data                            │
│  ) → _repo.update(id, data)            │
│    → _client.put('/transactions/$id')  │
│    → refresh list                      │
│    → return success/fail               │
│                                        │
└────────────────────────────────────────┘
```

---

## Route Design

**Why `state.extra` instead of path params?**

Since the transaction data is already loaded in memory (in `TransactionListNotifier`), fetching it again from the API via `id` would be wasteful. Using GoRouter's `extra` parameter avoids an extra network call.

```dart
// Navigation (from tile popup menu)
context.push('/transactions/add', extra: transaction);

// Route builder (in app.dart)
GoRoute(
  path: '/transactions/add',
  builder: (_, state) => AddTransactionScreen(
    editTransaction: state.extra is TransactionModel
        ? state.extra as TransactionModel
        : null,
  ),
);
```

The screen infers mode from the presence of `editTransaction`:
- `null` → create mode
- `TransactionModel` → edit mode

---

## Prefill Logic

**File:** `lib/features/transactions/ui/add_transaction_screen.dart`

When `widget.editTransaction != null`, `_prefillFields()` is called from `initState`:

| Field | Prefill Source |
|-------|---------------|
| Amount | `txn.amount.toString()` |
| Description | `txn.description` |
| Note | `txn.note` |
| Type (expense/income) | `txn.type == 'expense'` |
| Category | `txn.category.id` |
| Date | `DateTime.tryParse(txn.date)` |

Categories are loaded from the API first (shared with create mode), so the
selected category's ID is guaranteed to exist in the picker. If the transaction
type changed (e.g., editing an income to become expense), the category picker
switches to the correct category list.

---

## Provider Method

**File:** `lib/features/transactions/providers/transaction_provider.dart`

```dart
Future<bool> update(int id, Map<String, dynamic> data) async {
  try {
    await _repo.update(id, data);
    await load(refresh: true);  // refresh list after update
    return true;
  } catch (e) {
    state = state.copyWith(error: e.toString());
    return false;
  }
}
```

The `update` method:
1. Sends a PUT request via `TransactionRepository.update()`
2. Refreshes the transaction list (so changes appear immediately)
3. Returns `true` on success, `false` on failure

---

## Backend

The backend already supported editing the `date` field via `PUT /transactions/{txn_id}`:

```python
# routers/transactions.py — update_transaction()
updates = {}
for field in ["amount", "description", "note", "category_id", "date"]:
    val = getattr(data, field, None)
    if val is not None:
        updates[field] = val
```

No backend changes were needed — the endpoint dynamically builds a `SET` clause from whichever fields are provided, so `date` was always available.

---

## Edit vs Create: Visual Differences

| Aspect | Create Mode | Edit Mode |
|--------|------------|-----------|
| AppBar title | "Add Transaction" | "Edit Transaction" |
| Button label | "Save" | "Update" |
| Snackbar | "Transaction recorded" | "Transaction updated" |
| API method | POST | PUT |
| Provider method | `create()` | `update()` |
| Pre-filled | No | Yes, all fields |

---

## Files Changed

| File | Change |
|------|--------|
| `lib/features/transactions/providers/transaction_provider.dart` | +`update(id, data)` method |
| `lib/features/transactions/ui/add_transaction_screen.dart` | +`editTransaction` param, prefill logic, mode-aware title/button/save |
| `lib/app.dart` | +route builder passes `state.extra` as `editTransaction`, +import `TransactionModel` |
| `lib/features/transactions/ui/widgets/transaction_tile.dart` | +"Edit" popup menu item, +GoRouter push with extra |

No backend changes.
