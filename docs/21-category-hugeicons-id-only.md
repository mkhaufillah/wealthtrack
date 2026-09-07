# Kategori: ikon Hugeicons di DB + nama Indonesia only

> **For Hermes:** Implement setelah Filla bilang **gas**. TDD backend dulu. Widget hanya `AppColors`. Jangan sentuh Debt Tracker / fitur 3.

**Goal:** (1) `categories.icon` simpan key Hugeicons, bukan emoji. (2) Halaman kelola kategori punya icon picker Hugeicons. (3) Hapus `name_en` — satu nama, bahasa Indonesia.

**Architecture:** Key ikon = string `strokeRounded…` (nama const hugeicons 1.1.7). Backend simpan apa adanya. Flutter resolve lewat katalog curated (bukan 4000 ikon). Emoji lama di-migrate sekali di startup. `name_en` di-drop dari schema + API.

**Tech Stack:** PostgreSQL (`ALTER` di `database.py` startup), FastAPI schemas/services, Flutter `CategoryGlyph` + picker grid.

**See also:** [Admin Category CRUD](17-admin-category-crud.md) · [Flutter Mobile](05-flutter-mobile.md)

---

## Sekarang

| Hal | Kondisi |
|-----|---------|
| `categories.icon` | Emoji (`🍽️`, `🚗`) |
| Render | FE `CategoryGlyph` switch emoji → Hugeicons |
| `categories.name_en` | Masih kolom + field API + model Flutter |
| UI nama | Campur: tile/picker sudah `name`; kelola kategori + filter list + chart masih `name_en` dulu |
| Lookup khusus | `summary_service` + laporan pakai `name_en == 'Savings & Investment'` dll. |

---

## Keputusan

1. **Value DB** = key Hugeicons, contoh `strokeRoundedServingFood`. Bukan path JSON, bukan emoji.
2. **Katalog curated** di Flutter (~30 ikon finansial). Picker hanya ini. Key di luar katalog → fallback `strokeRoundedInvoice01`.
3. **`name` saja.** Drop kolom `name_en`. API tidak kirim `name_en` / `category_name_en`. Flutter hapus `nameEn` / `categoryNameEn`.
4. **Lookup tabungan/darurat** ganti ke `name` ID (bukan id hardcode — nama bisa custom, tapi default seed tetap):
   - `Tabungan & Investasi`
   - `Penarikan Tabungan & Investasi`
   - `Dana Darurat`
5. Default categories tetap tidak bisa diedit (`is_default`). Ikon default tetap di-migrate ke key Hugeicons.
6. APK lama: `name_en` hilang → fallback ke `name` (ID). Ikon jadi string non-emoji → glyph lama (kalau masih emoji-switch) jatuh ke invoice sampai update APK. **Satu ship backend+APK.**

### YAGNI

- Jangan expose 4000 Hugeicons di picker.
- Jangan server-driven icon catalog v1 (APK punya map).
- Jangan hapus `keywords`.
- Jangan DELETE kategori.
- Jangan ganti `transactions.category_name` snapshot (sudah ID).

---

## 1. Backend — schema + migrate

**Modify:** `backend/app/database.py` (setelah `CREATE TABLE IF NOT EXISTS categories`)

Startup, idempotent:

```sql
-- icon: emoji → key Hugeicons (hanya jika value masih emoji / belum strokeRounded)
UPDATE categories SET icon = 'strokeRoundedServingFood' WHERE icon IN ('🍽️','🍽','🍔','🍜','🍱');
UPDATE categories SET icon = 'strokeRoundedCar01' WHERE icon IN ('🚗','🛵');
UPDATE categories SET icon = 'strokeRoundedFuelStation' WHERE icon IN ('⛽','⛽️');
UPDATE categories SET icon = 'strokeRoundedShoppingBag01' WHERE icon IN ('🛒','🛍️');
UPDATE categories SET icon = 'strokeRoundedHome01' WHERE icon IN ('💡','⚡');
UPDATE categories SET icon = 'strokeRoundedMedicineBottle01' WHERE icon IN ('🏥','💊');
UPDATE categories SET icon = 'strokeRoundedSchool' WHERE icon = '🎓';
UPDATE categories SET icon = 'strokeRoundedGameController01' WHERE icon = '🎮';
UPDATE categories SET icon = 'strokeRoundedMoneyBag01' WHERE icon IN ('💰','💵');
UPDATE categories SET icon = 'strokeRoundedBank' WHERE icon = '🏦';
UPDATE categories SET icon = 'strokeRoundedSmartPhone01' WHERE icon = '📱';
UPDATE categories SET icon = 'strokeRoundedHouse01' WHERE icon = '🏠';
UPDATE categories SET icon = 'strokeRoundedClothes' WHERE icon = '👕';
UPDATE categories SET icon = 'strokeRoundedGift' WHERE icon = '🎁';
UPDATE categories SET icon = 'strokeRoundedAirplane01' WHERE icon IN ('✈️','✈');
UPDATE categories SET icon = 'strokeRoundedFishFood' WHERE icon IN ('🐶','🐱');
UPDATE categories SET icon = 'strokeRoundedTv01' WHERE icon = '🎬';
UPDATE categories SET icon = 'strokeRoundedInvoice01' WHERE icon = '📄';
UPDATE categories SET icon = 'strokeRoundedLaptop' WHERE icon = '💻';
UPDATE categories SET icon = 'strokeRoundedInvoice01'
  WHERE icon IS NULL OR icon = '' OR icon NOT LIKE 'strokeRounded%';

ALTER TABLE categories DROP COLUMN IF EXISTS name_en;
```

Validasi create/update: `icon` string, prefix `strokeRounded`, max ~64 char. Kosong → `strokeRoundedInvoice01`.

**Modify:** `backend/app/schemas/category.py` — buang `name_en`.
**Modify:** `backend/app/schemas/transaction.py` — category object tanpa `name_en`.
**Modify:** `backend/app/schemas/budget.py` — buang semua `category_name_en`.
**Modify:** `category_service.py`, `transaction_service.py`, `summary_service.py`, `budget_ai.py`, routers — SELECT/INSERT tanpa `name_en`.

**Lookup:** `summary_service.get_all_time_category_balance` pakai `name IN (...)` Indonesia, bukan `name_en`.

**Test dulu:** `backend/tests/test_categories.py`
- GET tidak punya `name_en`
- POST tanpa `name_en`, `icon` = `strokeRoundedCar01`
- GET icon bukan emoji
- non-admin 403 tetap

Lalu sesuaikan fixture `DEFAULT_CATEGORIES` di `backend/tests/conftest.py` (kolom `name_en` hilang, icon = key).

Run: `python -m pytest tests/test_categories.py tests/test_budgets.py tests/test_transactions.py -v --tb=short` dari `backend/`.

---

## 2. Flutter — resolve + picker

**Create:** `mobile/lib/core/ui/category_icons.dart`

- Map `String` → `List<List<dynamic>>` (hanya const yang **ada** di hugeicons 1.1.7 — cek `stroke_rounded.dart`, jangan ulangi bug `Petrol`/`Education`).
- List `kCategoryIconCatalog` untuk picker (label ID pendek: Makan, Mobil, Bensin, Belanja, Rumah, Kesehatan, Sekolah, Game, Uang, Bank, HP, Baju, Kado, Pesawat, TV, Struk, Laptop, …).
- `hugeIconFor(String key)` → catalog atau `Invoice01`.

**Modify:** `category_glyph.dart` — input = key DB, bukan emoji. Tetap well pastel + `AppColors`.

**Modify:** `category_management_screen.dart`
- Satu field nama (ID). Hapus Name (English) + Icon (emoji).
- Icon picker: grid Hugeicons dari katalog, selected pakai `AppColors.accent` / `onAccent`.
- Tile: `CategoryGlyph(icon: cat['icon'])` + `cat['name']` only. Copy form ID (`t()`).
- FAB sudah accent+onAccent.

**Modify:** hapus `nameEn` / `categoryNameEn` dari:
- `transaction_model.dart`, `add_transaction_screen.dart`, `category_picker.dart`
- `transaction_list_screen.dart` (filter: nama ID + `CategoryGlyph`, bukan emoji)
- `budget_model.dart`, `budgets_screen.dart`, `budget_suggestion_sheet.dart`
- `report_model.dart`, `reports_screen.dart` (savings match pakai `categoryName` ID)
- `charts_section.dart` — label `name` + glyph, bukan `'${emoji} ${nameEn}'`

**Test:** sesuaikan fixture icon (`🍜` → `strokeRoundedServingFood`) dan assert tanpa `Food & Drinks` / `name_en`. Tes picker: tap ikon katalog ter-select.

CI: `flutter test` hanya di `build-apk.yml`.

---

## 3. Docs

Update `docs/17-admin-category-crud.md` (ID): icon = key Hugeicons, tidak ada `name_en`.
Jangan rewrite 01–18 penuh di PR ini.

---

## File touch list

Backend: `database.py`, `schemas/category.py`, `schemas/transaction.py`, `schemas/budget.py`, `services/category_service.py`, `services/transaction_service.py`, `services/summary_service.py`, `utils/budget_ai.py`, `tests/conftest.py`, `tests/test_categories.py` (+ tes lain yang assert `name_en`).

Mobile: `category_icons.dart` (baru), `category_glyph.dart`, `category_management_screen.dart`, models/screens di atas, tes budgets/reports/add_transaction/tile.

---

## Verifikasi

- pytest kategori + transaksi + budget + summary hijau.
- CI APK: compile (tidak ada member Hugeicons fiktif) + tes copy ID.
- Prod migrate: setelah deploy backend, `icon LIKE 'strokeRounded%'` dan kolom `name_en` hilang.
- Kelola kategori: picker grid, simpan, list transaksi/anggaran/laporan tampil ikon yang sama.
