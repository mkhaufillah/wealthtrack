# Delete Transaction

**Feature added:** 2026-05-28 · Commit: `6d575dc`
**See also:** [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [Edit Transaction](10-edit-transaction.md)

---

## Overview

Allows users to delete a transaction from the transaction list screen. The feature uses a confirmation dialog before deletion to prevent accidental data loss.

Delete is only available on the **Transactions page** (not on the Home screen recent transactions) to keep the home screen clean and uncluttered.

---

## Architecture

```
┌─ Transaction List ───────────────────────┐
│                                          │
│  TransactionTile (showActions: true)     │
│    │                                     │
│    ├── ⋮ → Edit    (navigates to edit)   │
│    ├── ⋮ → Change Owner                  │
│    └── ⋮ → Delete                        │
│              │                           │
│              ▼                           │
│  ┌─ Confirmation Dialog ───────┐         │
│  │                             │         │
│  │  "Delete \"Lunch\"?         │         │
│  │   This cannot be undone.   │         │
│  │                             │         │
│  │    [Cancel]    [Delete]     │         │
│  └──────────┬──────────────────┘         │
│             │                            │
│        ┌────┴────┐                       │
│     Cancel     Confirm                   │
│     (close)      │                       │
│                  ▼                       │
│     TransactionListNotifier.delete(id)   │
│       → _repo.delete(id)                 │
│       → _client.delete('/transactions')  │
│       → refresh list                     │
│       → snackbar: "Transaction deleted"  │
│                                          │
└──────────────────────────────────────────┘
```

---

## Mobile Implementation

### TransactionTile — `showActions` flag

**File:** `lib/features/transactions/ui/widgets/transaction_tile.dart`

The tile now supports a `showActions` flag (default `false`). When `true`, a `PopupMenuButton` is rendered with Edit, Change Owner, and Delete options.

```dart
class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback? onTransferOwner;
  final VoidCallback? onDelete;
  final bool showActions;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTransferOwner,
    this.onDelete,
    this.showActions = false,  // ← default: no popup menu
  });
```

**Popup menu items** are conditionally rendered:
- **Edit** — always shown when `showActions == true`
- **Change Owner** — only shown if `onTransferOwner` is provided
- **Delete** — only shown if `onDelete` is provided

### Home screen — no actions

**File:** `lib/features/home/ui/widgets/recent_transactions.dart`

```dart
TransactionTile(transaction: transactions[i])
// → showActions defaults to false → no popup menu
```

### Transaction list screen — with actions

**File:** `lib/features/transactions/ui/transaction_list_screen.dart`

```dart
TransactionTile(
  transaction: txn,
  showActions: true,
  onTransferOwner: () => _showChangeOwnerSheet(...),
  onDelete: () => _confirmDelete(txn.id, txn.description),
),
```

### Delete confirmation dialog

```dart
Future<void> _confirmDelete(int txnId, String description) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Transaction'),
      content: Text(
        'Delete "${description.isEmpty ? 'this transaction' : description}"? '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: AppColors.highlight)),
        ),
      ],
    ),
  );

  if (confirmed == true && mounted) {
    final success = await ref.read(transactionListProvider.notifier).delete(txnId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Transaction deleted' : 'Failed to delete transaction')),
      );
    }
  }
}
```

Flow:
1. User taps ⋮ → "Delete"
2. Confirmation dialog appears
3. "Cancel" → dialog closes, nothing happens
4. "Delete" → calls provider → API → refreshes list → snackbar feedback
5. Error handling: snackbar shows "Failed to delete transaction" on failure

---

## Backend

**File:** `backend/app/routers/transactions.py`

The `DELETE /api/v1/transactions/{id}` endpoint was already implemented:

```python
@router.delete("/{txn_id}", status_code=204)
async def delete_transaction(
    txn_id: int,
    db: asyncpg.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT id FROM transactions WHERE id = ? AND user_id = ?",
        (txn_id, current_user["id"]),
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Transaction not found")
    await db.execute("DELETE FROM transactions WHERE id = ?", (txn_id,))
    await db.commit()
```

- Only the transaction **owner** can delete
- Returns `204 No Content` on success
- Returns `404` if transaction not found or not owned by user

No backend changes were needed for this feature.

---

## Test Coverage

| Layer | Tests | File |
|-------|-------|------|
| Backend (API) | Delete endpoint tested | `backend/tests/test_transactions.py` |
| Mobile (widget) | 7 tests — menu visibility, dialog flow, cancel | `mobile/test/features/transaction_list_delete_test.dart` |

---

## Files Changed

| File | Change |
|------|--------|
| `lib/features/transactions/ui/widgets/transaction_tile.dart` | +`showActions`, `onDelete` params; conditional popup menu render |
| `lib/features/transactions/ui/transaction_list_screen.dart` | +`_confirmDelete()` method, +`showActions: true`, +`onDelete` |
| `mobile/test/features/transaction_list_delete_test.dart` | **New** — 7 widget tests for delete flow |
