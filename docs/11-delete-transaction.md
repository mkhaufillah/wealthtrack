# Hapus Transaksi

**Fitur ditambahkan:** 2026-05-28 · Commit: `6d575dc`
**Lihat juga:** [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [Edit Transaksi](10-edit-transaction.md)

---

## Gambaran Umum

Memungkinkan user menghapus transaksi dari layar daftar transaksi. Fitur ini memakai dialog konfirmasi sebelum menghapus supaya data nggak hilang kena tekan salah.

Hapus cuma tersedia di **halaman Transaksi** (bukan di transaksi terbaru di layar Home) biar layar Home tetap bersih dan nggak ramai.

---

## Arsitektur

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

## Implementasi Mobile

### TransactionTile — flag `showActions`

**File:** `lib/features/transactions/ui/widgets/transaction_tile.dart`

Tile sekarang mendukung flag `showActions` (default `false`). Kalau `true`, sebuah `PopupMenuButton` dirender dengan opsi Edit, Change Owner, dan Delete.

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

**Item menu popup** dirender secara kondisional:
- **Edit** — selalu tampil kalau `showActions == true`
- **Change Owner** — cuma tampil kalau `onTransferOwner` disediakan
- **Delete** — cuma tampil kalau `onDelete` disediakan

### Layar Home — tanpa aksi

**File:** `lib/features/home/ui/widgets/recent_transactions.dart`

```dart
TransactionTile(transaction: transactions[i])
// → showActions defaults to false → no popup menu
```

### Layar daftar transaksi — dengan aksi

**File:** `lib/features/transactions/ui/transaction_list_screen.dart`

```dart
TransactionTile(
  transaction: txn,
  showActions: true,
  onTransferOwner: () => _showChangeOwnerSheet(...),
  onDelete: () => _confirmDelete(txn.id, txn.description),
),
```

### Dialog konfirmasi hapus

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

Alur:
1. User tap ⋮ → "Hapus"
2. Dialog konfirmasi muncul
3. "Batal" → dialog ditutup, nggak ada yang terjadi
4. "Hapus" → panggil provider → API → refresh daftar → umpan balik snackbar
5. Penanganan error: snackbar menampilkan "Gagal menghapus transaksi" kalau gagal

---

## Backend

**File:** `backend/app/routers/transactions.py`

Endpoint `DELETE /api/v1/transactions/{id}` sudah diimplementasikan sejak awal:

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

- Cuma **pemilik** transaksi yang bisa hapus
- Mengembalikan `204 No Content` kalau sukses
- Mengembalikan `404` kalau transaksi nggak ditemukan atau bukan milik user

Tidak perlu perubahan backend untuk fitur ini.

---

## Cakupan Test

| Layer | Test | File |
|-------|-------|------|
| Backend (API) | Endpoint delete teruji | `backend/tests/test_transactions.py` |
| Mobile (widget) | 7 test — visibilitas menu, alur dialog, batal | `mobile/test/features/transaction_list_delete_test.dart` |

---

## File yang Diubah

| File | Perubahan |
|------|-----------|
| `lib/features/transactions/ui/widgets/transaction_tile.dart` | +param `showActions`, `onDelete`; render popup menu kondisional |
| `lib/features/transactions/ui/transaction_list_screen.dart` | +method `_confirmDelete()`, +`showActions: true`, +`onDelete` |
| `mobile/test/features/transaction_list_delete_test.dart` | **Baru** — 7 widget test untuk alur hapus |
