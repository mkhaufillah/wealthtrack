# UI/UX Revamp + Server-Driven Copy, Config, Calc

> **For Hermes:** Phase 0 is closed (APK visual + ID copy). Phase 1 waits for gas. **Copy SoT is Postgres `ui_copy`, not a Python dict and not `copy_fallback.dart`.** Serve via Redis `ui:bootstrap:{locale}` TTL 3600; DB only on miss. Fallback APK map is offline/old-APK only. Widgets never take `Color(0x…)`. Hex lives in `app_theme.dart` (compiled fallback) and bootstrap `theme` (live, from `ui_config`). Product copy and money math do not live in Dart.

**Goal:** Total visual rombak (eye-catching palette, quieter home) **and** move wording, format/config, and business calculations to the backend so copy/formula/theme tweaks ship without an APK.

**Not a goal:** JSON→widget-tree “server-driven UI”. Flutter keeps layout, navigation, OCR camera, JWT storage.

**See also:** [Flutter Mobile](05-flutter-mobile.md) · [Dark Mode](09-dark-mode.md) · [Date Filter & All-Time Balance](19-date-filter-alltime-balance-debt-entry.md) · [Backend API](03-backend-api.md)

**HTML concepts (throwaway):** [`sketches/`](../sketches/README.md). **Locked:** Pastel cozy (`sketches/004-pastel-cozy/`). **Logo locked:** C — ayam + koin topi (`sketches/brand/chosen-c-chicken.png`). Wallet mark rejected as generic. Do not implement APK until Filla says gas.

---

## Why this exists

Today the APK decides:

- English product strings that used to ship in the APK (`All-time balance`, `Debt Tracker`, `Shorten Tenor`) — **live copy is Indonesian** (`Uang kamu`, `Catatan utang`, `Tenor lebih pendek`)
- `Rp` + `id_ID` in `formatCurrency`
- KPR list **hardcodes ~9%** in `_estimateMonthlyPayment`
- Home **chooses** which summary endpoint (cycle vs household vs daily) — that choice is a product rule stuck in `dashboard_provider.dart`

Every caption or rumus change = Play build. Filla wants that loop dead.

Home is also visually stacked: hero + categories + outstanding debt + Teman AI + Catatan utang + recents.

---

## Non-negotiables

1. **APK renders. Server decides** numbers, labels, format, feature flags, theme tokens.
2. **No hex in feature widgets.** `AppColors.accent`, not `Color(0xFFE8A317)`.
3. **Personal all-time saldo** stays the home default (not household mix). Household is an explicit server flag later, not a silent endpoint swap.
4. **Budgets stay cycle-based.** Home all-time does not infect budget actuals.
5. **Catatan utang entrypoints stay** (feature 3 cancelled). Outstanding card still hidden at `total_debt == 0`.
6. **Indonesian default copy.** EN only if bootstrap `locale` says so.
7. **Offline:** cache last bootstrap + last `/home` snapshot. Stale UI > blank UI.
8. First APK after this revamp **is allowed** (new theme + new clients). After that, copy/calc/palette tweaks = backend deploy.

---

## Palette — “Pastel cozy” (locked)

Filla picked sketch `004-pastel-cozy` over Saffron Ink. Friendly household app: peach cream, mint, rose, lilac. Icons in tinted wells. Not a dark forest bank.

### Light

| Token | Hex | Use |
|-------|-----|-----|
| `background` | `#FFF3EE` | Scaffold |
| `surface` | `#FFFFFF` | Cards, sheets, pill nav |
| `ink` | `#4A3A48` | Primary text, icons |
| `muted` | `#9B8794` | Secondary text |
| `line` | `#F3E0D8` | Dividers |
| `accent` | `#F3A6B8` | FAB, selected, links (rose) |
| `expense` | `#E08B7C` | Outflow, outstanding |
| `income` | `#4EAE90` | Inflow, success |
| `warning` | `#E8B86D` | OCR pending, budget warn |
| `heroFill` | `#FFE8DC` | Home hero (peach, not dark slab) |
| `heroOn` | `#4A3A48` | Text on hero |
| `mint` | `#9DD9C0` | Icon wells, coin |
| `lilac` | `#D4C4F0` | Avatar, AI well |
| `butter` | `#F6E3A1` | Tabungan well |

### Dark

| Token | Hex | Use |
|-------|-----|-----|
| `background` | `#2A2430` | Scaffold |
| `surface` | `#3A3242` | Cards |
| `ink` | `#F7EEE8` | Text |
| `muted` | `#C4B4BE` | Secondary |
| `line` | `#4C4354` | Dividers |
| `accent` | `#E9A0B2` | FAB |
| `expense` | `#F0A090` | |
| `income` | `#7ED0B4` | |
| `warning` | `#E8C47A` | |
| `heroFill` | `#463848` | Hero |
| `heroOn` | `#F7EEE8` | |

### Mapping to today’s `AppColors` getters

Keep **the same getter names** so the first visual pass is a theme swap, not a 200-file rename:

| Today | New meaning |
|-------|-------------|
| `background` / `surface` / `textPrimary` / `textSecondary` / `divider` | paper / surface / ink / muted / line |
| `accent` | rose (was navy) |
| `highlight` | expense (was coral) |
| `success` | income mint |
| `warning` | butter/amber |
| `primary` | ink |
| **new** `heroFill` / `heroOn` | peach hero (light), plum hero (dark) |

`chartPalette` rebuilt from rose/mint/lilac/butter (no random Material rainbow).

Contrast: ink on paper and `heroOn` on `heroFill` must stay ≥ 4.5:1. Verify in the theme PR with a short table (light + dark).

Hex **only** in:

- `mobile/lib/core/theme/app_theme.dart` (compiled fallback)
- bootstrap JSON `theme.light` / `theme.dark` (overrides fallback at runtime)

---

## UX target (not a new IA)

Keep 5 tabs: Dashboard, Transactions, Budgets, Reports, Profile.

### Home (Dashboard)

```
┌─────────────────────────────────────┐
│  [Uang kamu]     Filla  ▾   │  copy from server
│  Rp8.743.144                        │  amount_display from server
│  Pemasukan Rp…    Pengeluaran Rp…   │  display strings, not client math
└─────────────────────────────────────┘
  Simpanan     Dana darurat           │  existing all-time category tiles
  Utang jalan (if > 0)           │  unchanged entry rules
  Teman AI                          │
  Catatan utang                     │  stays
  Transaksi terbaru                   │
```

Hero is the **only** 32px number. Everything else is 14–16px. Saffron hairline under the amount, not a full-bleed rainbow.

### Transactions

Filter bar already has type / category / **date**. Visual pass: one sticky bar, saffron when a filter is on, empty state copy from server (`transactions.empty_filtered`).

### Debt / KPR

No local amortization. List rows use API fields only (`monthly_payment`, `current_month_payment`). Delete extra payment UI stays.

---

## Server contracts

Prefix: `/api/v1`. JWT as today. No MCP change in v1.

### `GET /ui/bootstrap`

**Public** (no JWT). Login chrome is copy too — it cannot wait for a token. Rate-limit by IP. Cached by client (memory + SecureStorage). `ETag` / `Cache-Control: max-age=300`.

**Source of truth: database, not Python.**

| Table | Role |
|-------|------|
| `ui_copy` | Every product string: `t()` keys. PK `(key, locale)`. |
| `ui_config` | Non-copy bootstrap: `format`, `theme.light`, `theme.dark`, `flags` as JSONB rows. |

Seed on startup from `backend/app/core/ui_seed.py` with `INSERT … ON CONFLICT DO NOTHING` so live edits are never overwritten. Changing a string in prod = `UPDATE ui_copy`, not a code deploy.

Do **not** keep a parallel SoT in `ui_copy.py` dicts.

**Redis cache (required for Phase 1).** `GET /ui/bootstrap` must not hit Postgres on every request.

1. `GET` → `GET ui:bootstrap:{locale}` (JSON payload).
2. Miss → read `ui_copy` + `ui_config` once → `SETEX ui:bootstrap:{locale} 3600 <json>`.
3. TTL **1 hour** is the invalidate. After expiry the next request hits DB again and refills Redis.
4. No in-process cache. Redis is the only server cache so multiple workers share one copy.

Live `UPDATE ui_copy` can take up to 1 hour to show. Phase 1 does **not** `DEL` on write. Optional later: `DEL ui:bootstrap:*` after an admin edit.

Client still caches (memory + SecureStorage) with `ETag` / `Cache-Control: max-age=300`. That is the APK layer; Redis is the DB shield.

APK `copy_fallback.dart` stays as last-resort if the key is missing in the payload (typo, old APK, empty cache). It is not the live catalog.

Auth/OCR FastAPI `detail=` English strings are **not** this table in Phase 1. Those stay mapped in `api_client.dart`. Phase 1 = every `t()` key.

```sql
CREATE TABLE IF NOT EXISTS ui_copy (
    key        TEXT NOT NULL,
    locale     TEXT NOT NULL DEFAULT 'id-ID',
    value      TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (key, locale)
);

CREATE TABLE IF NOT EXISTS ui_config (
    key        TEXT PRIMARY KEY,
    value      JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Seed `locale = id-ID` with the current `copyFallback` map (~250 keys). `Email` / `Username` labels stay English in the value, matching the live APK.

```json
{
  "locale": "id-ID",
  "format": {
    "currency": "IDR",
    "currency_prefix": "Rp",
    "group_sep": ".",
    "decimal_sep": ","
  },
  "theme": {
    "light": { "background": "#F6F1E8", "surface": "#FFFBF5", "ink": "#14221B", "muted": "#6B6456", "line": "#E4D9C8", "accent": "#E8A317", "expense": "#E23D28", "income": "#1F8A5B", "warning": "#D97706", "heroFill": "#14221B", "heroOn": "#FFFBF5" },
    "dark":  { "background": "#0E1411", "surface": "#1A2320", "ink": "#F3EDE3", "muted": "#A39B8C", "line": "#2C3833", "accent": "#F0B429", "expense": "#FF6B57", "income": "#3DDC97", "warning": "#FBBF24", "heroFill": "#1A2320", "heroOn": "#F3EDE3" }
  },
  "copy": {
    "home.hero_title": "Uang kamu",
    "home.income": "Pemasukan",
    "home.expense": "Pengeluaran",
    "nav.dashboard": "Beranda",
    "nav.transactions": "Transaksi",
    "nav.budgets": "Anggaran",
    "nav.reports": "Laporan",
    "nav.profile": "Profil",
    "transactions.filter_date": "Tanggal",
    "transactions.filter_date_specific": "Tanggal tertentu",
    "transactions.filter_date_range": "Rentang tanggal",
    "common.clear": "Hapus filter",
    "debt.tracker": "Catatan utang",
    "debt.outstanding": "Utang jalan",
  },
  "flags": {
    "home_all_time": true
  }
}
```

Missing keys → Flutter fallback map in `lib/core/ui/copy_fallback.dart` (ID). **Do not** scatter `'Uang kamu'` in widgets — use `t('home.hero_title')`.

### `GET /home`

One round-trip for Dashboard. Server runs personal all-time summary (same rule as `GET /summaries/daily` with no dates).

```json
{
  "hero": {
    "title_key": "home.hero_title",
    "amount": 8743144,
    "amount_display": "Rp8.743.144",
    "income": 1200000,
    "income_display": "Rp1.200.000",
    "expense": 800000,
    "expense_display": "Rp800.000"
  },
  "pots": {
    "savings_display": "Rp…",
    "emergency_display": "Rp…"
  },
  "debt_summary": {
    "visible": true,
    "total": 500000000,
    "total_display": "Rp500.000.000",
    "title_key": "debt.outstanding"
  },
  "recent": [ { "id": 1, "description": "VPS", "amount_display": "−Rp273.996", "type": "expense" } ]
}
```

Client **must not** compute `income - expense`. It may format only if `*_display` is absent (old server) using bootstrap `format`.

### Later (same pattern, not v1)

- `GET /kpr/simulations` already returns numbers — **delete** Dart `_estimateMonthlyPayment`.
- Extra-payment preview already server.
- Transaction list can grow `amount_display` when convenient; not a blocker for home.

### What stays in the APK

go_router, MainShell, forms, OCR, SecureStorage, Riverpod wiring, widget structure, system strings that are Material (`showDatePicker` localizations via `locale` from bootstrap).

---

## Flutter architecture after revamp

```
login → GET /ui/bootstrap → UiConfigNotifier (copy, format, theme overlay)
     → GET /home         → HomeNotifier (already-formatted cards)
     → widgets read AppColors (synced from theme overlay) + t(copyKey)
```

New modules (do not dump into `dashboard_provider.dart`):

| Path | Role |
|------|------|
| `lib/core/ui/ui_config.dart` | State + parse bootstrap |
| `lib/core/ui/copy.dart` | `t(key)` with fallback |
| `lib/core/ui/money.dart` | format using bootstrap; fallback `formatCurrency` |
| `lib/core/theme/app_theme.dart` | Saffron Ink fallback + `AppColors.applyRemote(map)` |
| `lib/features/home/providers/home_provider.dart` | replaces dashboard summary fetches |

`dashboard_provider.dart` either becomes a thin alias or is deleted once home uses `/home`.

---

## Backend architecture

| Path | Role |
|------|------|
| `backend/app/core/ui_seed.py` | Seed rows only (`ON CONFLICT DO NOTHING`). Not the live catalog. |
| `backend/app/services/ui_bootstrap_service.py` | Redis `ui:bootstrap:{locale}` TTL 3600; DB on miss; assemble payload |
| `backend/app/services/home_service.py` | assemble `/home` from SummaryService + debt summary + recent txns |
| `backend/app/routers/ui.py` | `/ui/bootstrap` (public), `/home` (JWT) |
| `backend/tests/test_ui_bootstrap.py` | keys present, hex shape, values match DB not hardcoded dict |
| `backend/tests/test_home.py` | personal all-time, not household; display strings present |

`get_daily_summary` with no dates remains the personal all-time engine (already done). `/home` calls it; does not invent a third formula.

Register router in `main.py`. Auth: same JWT.

---

## Phased plan

### Phase 0 — Token swap (APK)

**Objective:** Saffron Ink live with **zero** API dependency.

- Rewrite light/dark `Color(0x…)` in `app_theme.dart` only.
- Add `heroFill` / `heroOn`.
- Restyle `BalanceCard` as peach hero (`heroFill`). Label from `t('home.hero_title')` → **Uang kamu**.
- Update `MainShell` labels only after copy pack exists (Phase 1). Until then English nav can stay **or** hardcode ID in fallback file — prefer `copy_fallback.dart` even in Phase 0.
- Tests: `balance_card_test` (label + finds amount). Screenshot not required.

**Files:** `app_theme.dart`, `balance_card.dart`, `app_scaffold.dart` (if nav colors), tests.

### Phase 1 — Bootstrap (API + client)

> **Status:** Implemented (backend + client). Copy lives in Postgres `ui_copy`/`ui_config`, served via Redis `ui:bootstrap:{locale}` TTL 3600, public endpoint, client overlay via `AppColors.applyRemote`, `t()`, `MoneyFormat`. `GET /home` added (personal all-time with `_display` strings).

**Copy lives in Postgres.** No Python dict as SoT.

**TDD backend first**

1. `test_ui_bootstrap.py`: 200 without JWT; payload has `copy`, `format`, `theme.light.accent`; `copy['home.hero_title'] == 'Uang kamu'` from DB; second request does not query `ui_copy` (Redis hit); after TTL/flush, next request refills from DB.
2. Schema `ui_copy` + `ui_config` in `database.py`. Seed from `ui_seed.py` (`ON CONFLICT DO NOTHING`).
3. Router: Redis first (`SETEX` 3600). No in-process cache.
4. Flutter: fetch on cold start (before login), persist, `AppColors.applyRemote`, `t(key)` overlays fallback.
5. Login screen uses bootstrap copy when cache exists.

**Files:** `database.py`, `core/ui_seed.py`, `services/ui_bootstrap_service.py`, `routers/ui.py`, `lib/core/ui/*`, `app.dart` startup.

### Phase 2 — `GET /home`

**TDD**

- Filla vs Nahda amounts differ (reuse marker idea from `test_daily_no_dates_all_time_personal_not_household`).
- `amount_display` starts with `Rp`.
- Household sum is **not** what Filla sees.

Flutter `HomeNotifier.load` → `/home` only (plus OCR pending as today). Remove `/summaries/daily` and `/summaries/all-time-category-balance` from home if `/home` includes pots.

### Phase 3 — Home layout polish

Spacing tokens (`xs=4 … xl=32`) used consistently on home. Drop competing 32px type. Outstanding + Teman AI + Catatan utang stay, visually secondary.

Do **not** merge Catatan utang into outstanding (cancelled).

### Phase 4 — Kill client math

- Delete `_estimateMonthlyPayment` / `annualRate = 0.09` in `kpr_list_screen.dart`. Use API.
- `formatCurrency` becomes wrapper around bootstrap format.
- Extra payment cards already API snapshots — leave.

### Phase 5 — Copy pack rest

Transactions, budgets, profile, KPR dialogs. One file server-side. Grep mobile for `const Text('` and migrate product strings. Leave Material chrome.

### Phase 6 — Transactions / Budgets / Reports visual pass

Same palette, no new endpoints unless a screen still computes.

---

## TDD / verification

Backend (from `backend/`, test DB never prod):

```bash
python -m pytest tests/test_ui_bootstrap.py tests/test_home.py tests/test_summaries.py::TestDailySummary -v --tb=short
```

Mobile (CI):

```bash
flutter test test/widgets/balance_card_test.dart test/features/home_screen_test.dart
```

Manual: light + dark, Filla vs Nahda login, cycle budgets unchanged.

---

## Files (expected)

**Create**

- `backend/app/routers/ui.py`
- `backend/app/services/home_service.py`
- `backend/app/services/ui_bootstrap_service.py`
- `backend/app/core/ui_seed.py`
- `backend/tests/test_ui_bootstrap.py`
- `backend/tests/test_home.py`
- `mobile/lib/core/ui/ui_config.dart`
- `mobile/lib/core/ui/copy.dart`
- `mobile/lib/core/ui/money.dart`
- `mobile/lib/core/ui/copy_fallback.dart`

**Modify**

- `backend/app/main.py` (include router)
- `backend/app/database.py` (`ui_copy`, `ui_config` + seed call)
- `mobile/lib/core/theme/app_theme.dart`
- `mobile/lib/features/home/ui/widgets/balance_card.dart`
- `mobile/lib/features/home/ui/home_screen.dart`
- `mobile/lib/features/home/providers/dashboard_provider.dart` (or replace)
- `mobile/lib/shared/widgets/app_scaffold.dart`
- `mobile/lib/features/debt/kpr/ui/kpr_list_screen.dart` (Phase 4)
- `mobile/lib/shared/utils/currency_formatter.dart`
- `mobile/lib/app.dart`
- `docs/03-backend-api.md`, `docs/05-flutter-mobile.md`, `docs/09-dark-mode.md`
- `CHANGELOG.md`

**Do not**

- Redesign OCR capture flow in v1
- Remove `/debt` hub
- Put JWT or secrets in bootstrap
- Server-driven widget trees

---

## Risks

1. **Theme flash** — apply cached bootstrap before first frame; fetch in background.
2. **Old APK + new `/home`** — keep `/summaries/daily` forever; `/home` is additive.
3. **Copy key typos** — fallback map must contain every key the APK references; test: every `t(` key ∈ fallback ∪ 404 log.
4. **Saffron on navy leftovers** — Phase 0 must restyle FAB/nav or accent-on-navy will clash.
5. **Deploy** — `/home` is backend; palette fallback is APK. Ship Phase 0+1 together so production isn’t navy APK talking saffron JSON.

---

## Open questions (defaults if Filla silent)

| Q | Default |
|---|---------|
| Hero language | ID (`Uang kamu`) |
| Hero on light mode | Dark slab (`heroFill`) |
| Household toggle on home | Not in v1 |
| Remote theme override | Yes, bootstrap can recolor without APK after Phase 1 |

Stop until Filla says implement. Suggested first build: **Phase 0 + Phase 1** in one APK, then Phase 2 backend+client.
