# Delete Transaction

**Added:** 2026-05-28 · Commit: `6d575dc`  
**See also:** [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [Edit Transaction](10-edit-transaction.md)

---

## Overview

Users can delete a transaction from the **Transactions** list (not from Home recents). A confirm dialog runs first.

Live copy (`copy_fallback.dart` / `t()`):

- Menu: **Hapus**
- Dialog title: **Hapus transaksi?**
- Actions: **Batal** / **Hapus**
- Snackbar success: **Transaksi kehapus**
- Snackbar fail: **Gagal hapus transaksi**

---

## Architecture

```
TransactionTile (showActions: true)
  ⋮ → Ubah | Ganti pemilik | Hapus
              ▼
        AlertDialog  [Batal] [Hapus]
              ▼
        TransactionListNotifier.delete(id)
          → DELETE /transactions/{id}
          → refresh list
          → SnackBar
```

Home recents use `TransactionTile` with default `showActions: false` (no menu).

---

## Mobile

**Tile:** `lib/features/transactions/ui/widgets/transaction_tile.dart` — `showActions`, `onDelete`, `onTransferOwner`.

**List:** `transaction_list_screen.dart` — `_confirmDelete`.

**Tests:** `mobile/test/features/transaction_list_delete_test.dart` (copy must stay Indonesian; do not revert tests to English).

---

## Backend

`DELETE /api/v1/transactions/{id}` — owner only, `204` or `404`. No extra work for this feature.

API error `detail` may still be English (`Transaction not found`); the APK maps user-visible failures to the snackbars above.
