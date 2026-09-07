# Admin Category CRUD

**Feature added:** 2026-05-30 · Commits: `3dedc7b` (backend), `2d71d74` (Flutter)
**See also:** [Project Overview](01-project-overview.md) · [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [OCR Scanner](16-ocr-scanner.md)

---

## Overview

Admin-only category management — create/update income and expense categories. One Indonesian `name`. Icon = Hugeicons key (`strokeRounded…`) from the in-app picker. `keywords` stay in the DB for classification.

**No DELETE** — categories already used on transactions/budgets are not removed.

Default categories (`is_default=1`) cannot be edited. Seed names (as shown in the app): Gaji, Makanan & Minuman, Lainnya, Transfer, Tabungan & Investasi, Penarikan Tabungan & Investasi, Hasil Investasi, Dana Darurat.

See also [Hugeicons + ID-only categories](21-category-hugeicons-id-only.md).

---

## Architecture

```
[Flutter Admin Screen] ──POST/PUT──▶ [FastAPI /categories] ──▶ [PostgreSQL categories]
                                          │                           │
                                          ▼                           ▼
                                     [Hermes cron] ◄──── reads keywords from DB
                                     classify_transaction()
```

---

## Database Changes

`categories` columns:

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | TEXT | required | Display name (Indonesian) |
| `icon` | TEXT | `strokeRoundedInvoice01` | Hugeicons key, e.g. `strokeRoundedServingFood` |
| `keywords` | TEXT | `'[]'` | JSON array of classification keywords |

`name_en` **dropped**. Legacy emoji migrates to Hugeicons keys at startup (`database.py`).

---

## API Changes

### POST `/api/v1/categories` (admin only)

Create a new category.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Indonesian name (unique per type) |
| `type` | string | required | `"expense"` or `"income"` |
| `icon` | string | invoice fallback | Hugeicons key `strokeRounded…` |
| `keywords` | array | `[]` | Classification keywords |
| `sort_order` | int | `0` | Display order |

**Errors:** 403 (non-admin), 409 (duplicate name+type), 422 (validation)

### PUT `/api/v1/categories/{id}` (admin only)

Update an existing category. Cannot edit default categories (`is_default=1`).

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | New name (duplicate-checked) |
| `icon` | string | Hugeicons key |
| `keywords` | array | Keywords |
| `sort_order` | int | Sort order |

**Errors:** 403 (non-admin or is_default), 404, 409 (duplicate on rename)

### GET `/api/v1/categories` (updated)

Response: `id`, `name`, `type`, `icon`, `is_default`, `keywords`. No `name_en`.

---

## Hermes Skill Changes

- **Removed** hardcoded `EXPENSE_KEYWORDS` / `INCOME_KEYWORDS` dicts (finance_db.py)
- **New** `load_keywords_from_db()` — reads category→keywords mapping from `categories` table
- **Updated** `classify_transaction()` — uses DB-backed keywords, falls back to "Lainnya"
- **Updated** `get_category_id()` — no longer auto-creates categories on unknown name; falls back to "Lainnya" ID

---

## Flutter Changes

### Display name

UI shows `name` only (Indonesian). There is no `name_en` on the API or in Flutter models.

### Category management screen

- **Route:** `/categories/manage`
- **Access:** Profile, admin only. Title **Kelola kategori**. Save **Simpan**, create **Tambah**.
- **List:** grouped by type, `CategoryGlyph` + `name`
- **Add/edit:** one name field, Hugeicons dropdown+search, keywords, sort order
- **Defaults** locked. Seed names: Gaji, Makanan & Minuman, Lainnya, Transfer, Tabungan & Investasi, Dana Darurat, Penarikan Tabungan & Investasi, Hasil Investasi.

### Category Provider
- `CategoryManagementNotifier` — loads, creates, updates via API
- Error handling via state.error

---

## Files Changed

| File | Change |
|------|--------|
| `backend/app/migrate_db.py` | Added columns + backfill |
| `backend/app/schemas/category.py` | Added `CategoryCreate`, `CategoryUpdate`; updated `CategoryOut` |
| `backend/app/routers/categories.py` | Added `POST` + `PUT` endpoints, `_format_category()` helper |
| `backend/tests/test_categories.py` | 14 new tests |
| `mobile/lib/features/categories/providers/category_provider.dart` | **NEW** — state management |
| `mobile/lib/features/categories/ui/category_management_screen.dart` | **NEW** — admin screen |
| `mobile/lib/features/transactions/ui/widgets/category_picker.dart` | Added `nameEn` field |
| `mobile/lib/features/transactions/ui/add_transaction_screen.dart` | Parse `name_en` from API |
| `mobile/lib/features/profile/ui/profile_screen.dart` | Nav entry for admin |
| `mobile/lib/app.dart` | Route + import |
| `~/.hermes/.../finance_db.py` | Keywords from DB, no auto-create |
| `backend/app/routers/budgets.py` | Added `category_name_en` to all responses + budget exhausted message |
| `backend/app/routers/summaries.py` | Added `category_name_en` to monthly/household summaries |
| `backend/app/routers/transactions.py` | Added `name_en` to transaction category object |
| `backend/app/schemas/budget.py` | Added `category_name_en` field to `BudgetResponse`, `BudgetSummaryItem` |
| `backend/app/schemas/transaction.py` | Added `name_en` to transaction category response |
| `mobile/lib/features/budgets/models/budget_model.dart` | Added `categoryNameEn` |
| `mobile/lib/features/budgets/ui/budgets_screen.dart` | Shows `categoryNameEn`, budget exhausted label |
| `mobile/lib/features/home/ui/home_screen.dart` | Added savings & emergency widget |
| `mobile/lib/features/reports/models/report_model.dart` | Added `categoryNameEn` |
| `mobile/lib/features/reports/ui/reports_screen.dart` | Displays `categoryNameEn` |
| `mobile/lib/features/reports/ui/widgets/charts_section.dart` | Uses `categoryNameEn` for labels |
| `mobile/lib/features/transactions/models/transaction_model.dart` | Added `nameEn` field |
| `mobile/lib/features/transactions/ui/widgets/transaction_tile.dart` | Shows `nameEn` |
| `mobile/lib/shared/utils/category_translator.dart` | `translateCategory()` removed |
