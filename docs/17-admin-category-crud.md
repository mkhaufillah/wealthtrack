# Admin Category CRUD

**Feature added:** 2026-05-30 · Commits: `3dedc7b` (backend), `2d71d74` (Flutter)
**See also:** [Project Overview](01-project-overview.md) · [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [OCR Scanner](16-ocr-scanner.md)

---

## Overview

Admin-only category management — create and edit expense/income categories. Categories are no longer hardcoded; admin can add new categories with English names and keyword mappings through the Flutter UI. Hermes cron skill reads keywords from the database instead of hardcoded dicts.

**No DELETE** — categories referenced by transactions/budgets cannot be safely removed.

---

## Architecture

```
[Flutter Admin Screen] ──POST/PUT──▶ [FastAPI /categories] ──▶ [SQLite categories]
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

### CategoryChip (category_picker.dart)
- Added `nameEn` field
- Label prefers `nameEn` if available, falls back to `translateCategory(name)`

### Category Management Screen
- **Route:** `/categories/manage`
- **Access:** menu entry in Profile screen, visible only for `role == 'admin'`
- **List:** grouped by type (expense / income), shows icon + name_en + name
- **Add:** FAB → bottom sheet form: name, name_en, type, icon, keywords, sort_order
- **Edit:** tap non-default category → same form pre-filled
- **Default categories** are locked (lock icon) — cannot be edited

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
