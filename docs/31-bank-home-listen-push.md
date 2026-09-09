# 31 — Home draft, listen-app picker, action notifications

**Status:** Implemented on `main`.

**See also:** [29](29-bank-notif-inbox.md) · [30](30-bank-rules-internal-ios.md)

Docs/README English. UI copy Bahasa via `t()`.

## Goal

1. Top **pending** bank draft on **Home** — Catat / Abaikan / Hapus without opening Dari bank.
2. User picks **which installed apps** to listen to (not a hardcoded 16).
3. When a listened app posts a notification, WealthTrack posts its **own** notification: new draft, with actions Catat / Abaikan / Hapus.

Also: paste-block top spacing; rules FAB contrast (ink on pastel).

## Listen list

- Android launcher apps via `ACTION_MAIN` + `CATEGORY_LAUNCHER` (no `QUERY_ALL_PACKAGES`).
- Selection stored in `SharedPreferences` `bank_capture` / `listen_packages`.
- Default if unset: the 16 packages from doc 29.
- Listener skips WealthTrack’s own package (no loop).

Server ingest **accepts any package**. Known Play IDs still map to slugs; unknown → last dotted segment as slug.

## Push actions

Notification channel `wt_bank`. Actions start `MainActivity` with extras (`confirm` / `reject` / `delete` + payload). Flutter flushes the queue then applies the action (Catat uses suggested/default category — no picker on a shade notification).

Android 13+: `POST_NOTIFICATIONS`.

## Home

`GET /bank-inbox` — first `pending` item. Same three actions as inbox. Catat still opens the category dialog.

## Copy

`home.bank_draft`, `bank.listen_apps`, `bank.listen_save`, `bank.listen_search`.
