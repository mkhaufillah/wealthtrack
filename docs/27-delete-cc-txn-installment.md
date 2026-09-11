# Delete credit-card transactions and installments

**See also:** [Backend API](03-backend-api.md)

## 1. Problem

Card delete exists (swipe + dialog). Rows on the **Transaksi** and **Cicilan** tabs cannot be removed. Backend already has:

- `DELETE /credit-cards/{card_id}/transactions/{txn_id}`
- `DELETE /credit-cards/{card_id}/installments/{inst_id}`

Flutter `deleteInstallment` exists; **no UI**. No `deleteTransaction` on the provider.

## 2. Behaviour

- Swipe end-to-start (same as card list) + confirm dialog.
- Copy: **Hapus transaksi?** / **Hapus cicilan?** · **Batal** / **Hapus** · snackbar **Transaksi kehapus** / **Cicilan kehapus**.
- Deleting an installment deletes the plan only. Charge rows are a separate table and were never linked.
- Refresh card detail + next-month projection.

## 3. Files

- `credit_card_service.py` — null/delete linked txns before installment delete
- `credit_card_provider.dart` — `deleteTransaction`; projection after installment delete
- `credit_card_detail_screen.dart` — Dismissible + dialog
- `copy_fallback.dart` — keys
- Provider tests

No new endpoints.
