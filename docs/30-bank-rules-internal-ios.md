# 30 — Auto-category rules, own-account transfers, confirm picker, iOS

**Status:** Specified; implementation follows this doc.

**See also:** [29 Bank notif inbox](29-bank-notif-inbox.md) · [03 Backend API](03-backend-api.md)

Docs and README stay English. On-screen copy is Bahasa via `t()` / `ui_copy`.

## Goal

Make bank-draft confirm useful, not noisy:

1. **Auto-category** — `categories.keywords` (Kelola kategori). No second rules table/screen.
2. **Category picker on Catat** — user picks a category before the row becomes a transaction.
3. **iOS** — same inbox API; **no silent notification listener** (Apple does not allow it).

No bank passwords. No IB scrape. Drafts still require confirm except where this doc says a rule only *suggests* a category.

## Non-goals

- Reading other apps’ notifications on iOS.
- Auto-saving transactions without Catat.
- Open banking / Brick / SNAP PJP APIs.
- Changing Debt Tracker.

---

## 1. Auto-category

**Source of truth:** `categories.keywords` (Kelola kategori). No second editor. No `bank_category_rules` table, no `/bank-inbox/rules` API, no Aturan kategori screen.

On GET inbox / shade Catat without `category_id`: first case-insensitive **word-boundary** hit in `"{title} {text} {merchant}"` against keywords of the same txn type. Else **Lainnya**. (`erha` matches `Bayar ke ERHA`, not `berhasil`.)

In-app Catat still uses a picker; `suggested_category_id` is pre-highlighted.

---

## 2. Own-account transfer — dropped

Removed. Inbox actions are **Catat**, **Abaikan**, **Hapus** only. Confirm always writes one draft. `internal` / `pair_id` on confirm are ignored if an old client still sends them.

Existing `source=internal_transfer` rows stay; no new ones.

---

## 3. Category picker on Catat

Catat must not silently use the default category.

Flow:

1. Tap **Catat**.
2. Bottom sheet: categories of the draft’s `type` (`GET /categories?type=`).
3. Pre-select `suggested_category_id` when set.
4. Tap a row → `POST confirm { category_id }`.
5. Cancel sheet → no write.

Unparsed drafts still cannot confirm (existing 400).

Copy: `bank.pick_category`.

---

## 4. iOS

### Constraint

iOS has **no** `NotificationListenerService`. Background reading of other apps’ notifications is not available to App Store (or sideloaded) apps. Do not fake a listener.

### What iOS ships

Same FastAPI inbox. Flutter screens already work if an iOS target exists.

Capture options that are legal and durable:

| Path | Notes |
|------|--------|
| **Paste / share text** | User copies the bank banner or shares it into WealthTrack. `POST /bank-inbox` with `package` chosen from the allow-list (or a dedicated `manual` slug mapped in parser). |
| **Email later** | Out of this slice (doc 29). |

v1 iOS: **Tempel notif** on the inbox screen (also useful on Android when the listener misses a format).

`POST /bank-inbox` body already `{ package, title, text, posted_at }`.

UI: package chips (the 16 allow-list slugs) + text field + **Kirim**. Server parses as today.

Copy: `bank.paste_title`, `bank.paste_hint`, `bank.paste_send`, `bank.ios_hint`.

iOS project: enable `ios` via `flutter create --platforms ios` only when building on a Mac. This VPS cannot produce an IPA. Document that; do not claim an IPA from GitHub-hosted Linux CI.

---

## Implementation order

1. Category picker (confirm already accepts `category_id`).
2. `suggested_category_id` from `categories.keywords`.
3. Paste-text ingest UI (Android + future iOS).

## Tests

- `tests/test_bank_match.py` — keyword match, type filter.
- `tests/test_bank_inbox.py` — confirm with category_id; confirm ignores `internal`/`pair_id`; paste/manual package.
- Widget: Catat opens dialog.

## Copy guardrail

New keys in **both** `copy_fallback.dart` and `ui_seed.py`. No duplicate keys (`tx.deleted` already exists).

## Out of this slice

Email mutasi, CSV, Play Store listing, excluding `internal_transfer` from budget charts (follow-up if reports look noisy).
