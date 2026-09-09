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
- Default if unset: intersection of the 16 packages from doc 29 **and apps actually installed**. Uninstalled defaults are skipped (no listen, no checkbox).
- Listener skips WealthTrack’s own package (no loop).

Android 13+: inbox boot requests `POST_NOTIFICATIONS`. Channel `wt_bank` uses the app icon (not a system info glyph). Action icons must be a real drawable — `0` failed silently.

## Rules

Bank dropdown = listened packages (labels from launcher), plus “any”.

Dari bank overflow (three-dot, 12px horizontal padding): App yang didengar, Aturan kategori.

Rules FAB matches Home/Transaksi (`AppColors.accent` + `onAccent`).

Listen checkboxes: accent fill + onAccent check + ink border.

Server ingest **accepts any package**. Known Play IDs still map to slugs; unknown → last dotted segment as slug.

## Push actions

Notification channel `wt_bank`. Actions are **broadcasts**, not activities: Catat / Abaikan / Hapus dismiss the shade notification and hit the API in the background. The app does not open.

Catat from the shade uses category **Lainnya** (expense). Token + base URL + Lainnya id are written to `bank_capture` prefs on login (`setSession`); cleared on logout.

Notifications with **no amount** (`Rp`/`IDR` or grouped thousands) are dropped — ads.

Android 13+: `POST_NOTIFICATIONS`.

## Home

`GET /bank-inbox` — first `pending` item. Same three actions as inbox. Catat still opens the category dialog.

## Copy

`home.bank_draft`, `bank.listen_apps`, `bank.listen_save`, `bank.listen_search`.
