# 29 — Bank notification inbox (Android capture)

**Status:** v1 implemented (Android listener + inbox API + confirm/reject)

## Goal

Stop typing every bank spend. Capture **push notifications** from the
user's own bank apps on Android, turn them into **drafts**, and let Filla
confirm before they become transactions.

No bank password. No internet-banking scrape. No SMS (`READ_SMS` is a
Play-restricted permission). No auto-save.

## Why this, not open banking

Indonesia has no consumer open-banking aggregator for household apps.
SNAP / BRIAPI statement APIs are for licensed PJP. Brick/Brankas are B2B.
The legal, durable signal is the notification the bank already posts on
the phone.

## v1 scope

- Android `NotificationListenerService` filters the user allow-list in
  `bank_parser.py` / `BankNotificationListener.kt` (BCA, Livin, BRImo,
  Jago, Superbank/`id.co.bankfama.android`, Krom/`com.krom.android`,
  BTN, SeaBank, Bibit, Stockbit, LinkAja, Flip, OVO, GoPay, DANA,
  ShopeePay). Unknown packages are ignored.
- Queue on device if the app is dead; drain on next launch.
- `POST /bank-inbox` with raw `{package, title, text, posted_at}`.
  Server parses amount / type / merchant / bank, dedupes by fingerprint.
- Inbox UI: pending drafts → **Catat** (creates a transaction) or
  **Abaikan**. Unparsed drafts stay visible with raw text.
- Copy is server-driven (`bank.*` keys). Docs/README stay English.

Out of v1: email mutasi, CSV import, iOS, auto-category rules, pairing
Jago→BCA internal transfers.

## API

- `POST /api/v1/bank-inbox` JWT — ingest one notification.
- `GET /api/v1/bank-inbox?status=pending` — list + `pending_count`.
- `POST /api/v1/bank-inbox/{id}/confirm` — `{category_id?}` → transaction.
- `POST /api/v1/bank-inbox/{id}/reject` — mark rejected.

Parser SoT: `backend/app/services/bank_parser.py` (pytest, no Flutter).

## Privacy / Play

Notification access is a restricted permission. Disclose in-app: we only
read allow-listed bank packages, never harvest other apps, never send
raw notifications anywhere except the user's own WealthTrack account.
Data is drafts until the user confirms.

## Verification

- Backend: `pytest tests/test_bank_parser.py tests/test_bank_inbox.py`
- APK CI: inbox widget test + copy seed sync
- Device: enable notification access → pay with QRIS on one bank → draft
  appears → Catat → shows in transaksi
