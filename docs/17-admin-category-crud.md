# Admin Category CRUD

**Feature added:** 2026-05-30 · Commits: `3dedc7b` (backend), `2d71d74` (Flutter)
**See also:** [Project Overview](01-project-overview.md) · [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [OCR Scanner](16-ocr-scanner.md)

---

## Overview

Admin-only category management — create and edit expense/income categories. Categories are no longer hardcoded; admin can add new categories with English names and keyword mappings through the Flutter UI. Hermes cron skill reads keywords from the database instead of hardcoded dicts.

**No DELETE** — categories referenced by transactions/budgets cannot be safely removed.

Default categories (is_default=1) also cannot be edited or deleted. This includes: Gaji, Makanan & Minuman, Lainnya (expense & income), Transfer (expense & income), Tabungan & Investasi (expense & income), Penarikan Tabungan & Investasi, Hasil Investasi, and Dana Darurat (expense & income).

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

Two new columns on `categories` table:

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `name_en` | TEXT | `''` | English display name for Flutter UI |
| `keywords` | TEXT | `'[]'` | JSON array of keywords for Hermes classification |

Migration is in `migrate_db.py` (safe to re-run) — backfills all existing categories with English names and keyword arrays from the original hardcoded maps.

---

## API Changes

### POST `/api/v1/categories` (admin only)

Create a new category.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Indonesian name (unique per type) |
| `name_en` | string | `""` | English display name |
| `type` | string | required | `"expense"` or `"income"` |
| `icon` | string | `""` | Emoji icon |
| `keywords` | array | `[]` | Keywords for Hermes classification |
| `sort_order` | int | `0` | Display order |

**Errors:** 403 (non-admin), 409 (duplicate name+type), 422 (validation)

### PUT `/api/v1/categories/{id}` (admin only)

Update an existing category. Cannot edit default categories (`is_default=1`).

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | New name (checked for duplicates) |
| `name_en` | string | New English name |
| `icon` | string | New emoji |
| `keywords` | array | New keyword list |
| `sort_order` | int | New display order |

**Errors:** 403 (non-admin or is_default), 404, 409 (duplicate on rename)

### GET `/api/v1/categories` (updated)

Now returns `name_en` and `keywords` in every response.

---

## Hermes Skill Changes

- **Removed** hardcoded `EXPENSE_KEYWORDS` / `INCOME_KEYWORDS` dicts (finance_db.py)
- **New** `load_keywords_from_db()` — reads category→keywords mapping from `categories` table
- **Updated** `classify_transaction()` — uses DB-backed keywords, falls back to "Lainnya"
- **Updated** `get_category_id()` — no longer auto-creates categories on unknown name; falls back to "Lainnya" ID

---

## Flutter Changes

### name_en Propagation (v0.3.1)

`name_en` now flows through the entire system from `categories` DB → API responses → Flutter UI.

| Consumer | API Field | Flutter Display |
|----------|-----------|-----------------|
| Transaction tiles | `category.name_en` | Primary name, fallback to `category.name` |
| Budget list | `category_name_en` | Primary name, fallback to `category_name` |
| Budget summary | `category_name_en` | Primary name, fallback to `category_name` |
| Reports breakdown | `category_name_en` | Primary name, fallback to `category_name` |
| Charts (pie/bar) | `category_name_en` | Chart labels |
| Category picker | `name_en` | Dropdown label, fallback to `name` |

**`category_translator.dart` simplified** — `translateCategory()` removed. Flutter no longer does client-side translation; `name_en` comes from the server. The fallback mechanism is:

```dart
categoryNameEn.isNotEmpty ? categoryNameEn : categoryName
```

### CategoryChip (category_picker.dart)
- Added `nameEn` field
- Label prefers `nameEn` if available, falls back to `name` (not `translateCategory(name)` since that function was removed)

### Category Management Screen
- **Route:** `/categories/manage`
- **Access:** menu entry in Profile screen, visible only for `role == 'admin'`
- **List:** grouped by type (expense / income), shows icon + name_en + name
- **Add:** FAB → bottom sheet form: name, name_en, type, icon, keywords, sort_order
- **Edit:** tap non-default category → same form pre-filled
- **Default categories** are locked (lock icon) — cannot be edited. The is_default flag is set server-side for system-critical categories (Gaji, Makanan & Minuman, Lainnya, Transfer, Tabungan & Investasi, Dana Darurat, Penarikan Tabungan & Investasi, Hasil Investasi).

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
