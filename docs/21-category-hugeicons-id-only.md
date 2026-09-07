# Categories: Hugeicons keys in DB + Indonesian name only

> **For Hermes:** Implement after Filla says **gas**. TDD backend first. Widgets use `AppColors` only. Do not change **Catatan utang** / feature 3.

**Goal:** (1) `categories.icon` stores a Hugeicons key, not an emoji. (2) Category management has a Hugeicons picker. (3) Drop `name_en` — one name, Indonesian.

**Architecture:** Icon key = `strokeRounded…` (hugeicons 1.1.7 const name). Backend stores it as-is. Flutter resolves via a curated catalog (not 4000 icons). Legacy emoji migrates once at startup. `name_en` is dropped from schema + API.

**See also:** [Admin Category CRUD](17-admin-category-crud.md) · [Flutter Mobile](05-flutter-mobile.md)

---

## Before

| Piece | State |
|-------|--------|
| `categories.icon` | Emoji (`🍽️`, `🚗`) |
| Render | FE `CategoryGlyph` mapped emoji → Hugeicons |
| `categories.name_en` | Column + API + Flutter model |
| Name UI | Mixed: some tiles used `name`; manage/filter/charts preferred `name_en` |
| Special lookups | `summary_service` / reports used `name_en == 'Savings & Investment'` |

---

## Decisions

1. **DB value** = Hugeicons key, e.g. `strokeRoundedServingFood`.
2. **Curated catalog** in Flutter. Unknown keys → `strokeRoundedInvoice01`.
3. **`name` only.** Drop `name_en`. API does not send `name_en` / `category_name_en`. Flutter drops `nameEn`.
4. **Savings / emergency lookups** use Indonesian `name` (not hardcoded ids):
   - `Tabungan & Investasi`
   - `Penarikan Tabungan & Investasi`
   - `Dana Darurat`
5. Default categories stay locked (`is_default`). Their icons still migrate to Hugeicons keys.
6. **Ship backend + APK together.** Old APKs lose `name_en` (fall back to `name`) and unknown icon strings.

### YAGNI

- Do not expose 4000 Hugeicons in the picker.
- No server-driven icon catalog in v1.
- Keep `keywords`. No DELETE category.

---

## 1. Backend

Startup, idempotent (see `database.py`): emoji → `strokeRounded…`, then `ALTER TABLE categories DROP COLUMN IF EXISTS name_en`.

Validate `icon`: prefix `strokeRounded`, max ~64 chars; empty → `strokeRoundedInvoice01`.

Strip `name_en` from schemas/services. Savings lookups use Indonesian `name IN (...)`.

**Tests:** `tests/test_categories.py` — no `name_en` in GET; POST `icon=strokeRoundedCar01`; non-admin 403.

---

## 2. Flutter

`category_icons.dart` — map + `kCategoryIconCatalog` with short ID labels (Makan, Mobil, Bensin, …). Identifiers must exist in hugeicons 1.1.7.

Manage screen: one name field, dropdown+search picker, `t()` copy (`Kelola kategori`, **Simpan**, **Tambah**). Tiles use `CategoryGlyph` + `name`.

Tests assert Indonesian copy — do not revert to English to make tests pass.

---

## 3. Docs

Keep this file and [17] in **English**. Quoted UI strings stay Indonesian as in the app.

---

## Verify

- pytest categories + transactions + budgets + summaries
- CI APK: real Hugeicons members + ID copy tests
- Prod: `icon LIKE 'strokeRounded%'` and no `name_en` column
