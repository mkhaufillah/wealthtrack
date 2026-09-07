# Edit Transaction

**Added:** 2026-05-27 · Commit: `bffe0ec`  
**See also:** [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)

---

## Overview

Users can edit amount, type (pengeluaran/pemasukan), category, description, note, and **date** from the transaction list.

Edit reuses `AddTransactionScreen` (no separate screen).

---

## Architecture

```
TransactionTile ⋮ → Ubah
  context.push('/transactions/add', extra: transaction)
        ▼
AddTransactionScreen(editTransaction: state.extra)
  title: "Ubah catatan"     button: "Simpan perubahan"
  _save() → notifier.update() → PUT /transactions/{id}
```

Create mode (no extra): title **Catatan baru**, primary button **Simpan**, snackbar **Tercatat**.  
Edit mode: title **Ubah catatan**, button **Simpan perubahan**, snackbar **Sudah diubah**.

---

## Why `state.extra`

The row is already in memory (`TransactionListNotifier`). Passing `extra` avoids a refetch by id.

```dart
context.push('/transactions/add', extra: transaction);

GoRoute(
  path: '/transactions/add',
  builder: (_, state) => AddTransactionScreen(
    editTransaction: state.extra is TransactionModel
        ? state.extra as TransactionModel
        : null,
  ),
);
```

`editTransaction == null` → create; otherwise edit.

---

## Prefill

**File:** `lib/features/transactions/ui/add_transaction_screen.dart`

| Field | Source |
|-------|--------|
| Amount | `txn.amount` |
| Description | `txn.description` |
| Note | `txn.note` |
| Type | `txn.type == 'expense'` |
| Category | `txn.category.id` |
| Date | `DateTime.tryParse(txn.date)` |

Categories load from the API first (same as create). Changing type swaps the category list.

---

## Provider

**File:** `lib/features/transactions/providers/transaction_provider.dart`

`update(id, data)` → `PUT` → refresh list → `true`/`false`.

---

## Backend

`PUT /transactions/{txn_id}` already accepts `amount`, `description`, `note`, `category_id`, `date`. No extra backend work.

---

## Create vs edit (live copy)

| | Create | Edit |
|--|--------|------|
| AppBar | Catatan baru | Ubah catatan |
| Button | Simpan | Simpan perubahan |
| Snackbar | Tercatat | Sudah diubah |
| API | POST | PUT |
| Prefill | No | Yes |

---

## Files

| File | Change |
|------|--------|
| `transaction_provider.dart` | `update(id, data)` |
| `add_transaction_screen.dart` | `editTransaction`, prefill, mode-aware copy |
| `app.dart` | route `state.extra` |
| `transaction_tile.dart` | popup **Ubah** |
