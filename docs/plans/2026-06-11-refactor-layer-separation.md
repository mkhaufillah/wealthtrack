# Refactor: Layer Separation + Clean Code

> **Branch:** `refactor/layer-separation`
> **Target:** PR into `main`
> **Status:** ✅ Plan — Ready for execution

**Goal:** Pisahkan semua business logic dari routers ke service layer (backend), dan terapkan full theme + konsistensi Riverpod (Flutter).

**Prinsip:**
- Router cuma pegang HTTP request/response + dependency injection
- Service pegang semua DB queries, validasi, transformasi
- Tidak ada `cursor.execute` di router (kecuali yang genuinely infrastructur)
- Flutter: zero hardcoded colors, semua pake `AppColors`

---

## Phase 1: Backend — Ekstraksi Router → Service

### 1.1 `health.py` — Extract to `HealthService`

**Objective:** Pindahkan DB `SELECT 1` dan Redis ping dari router ke service.

**Files:**
- Create: `backend/app/services/health_service.py`
- Modify: `backend/app/routers/health.py`

**Langkah:**
1. Buat `HealthService` class dengan `check()` method
2. Router tinggal panggil `await service.check(db, redis)`
3. Test: `curl /api/v1/health` tetep return 200

---

### 1.2 `ocr.py` — Pindahkan model + validasi duplikat

**Objective:** Pindahkan Pydantic models dari `routers/ocr.py` ke `schemas/ocr.py`. Hapus validasi duplikat (content_type, size) dari router — sudah ada di `OcrService`.

**Files:**
- Create: `backend/app/schemas/ocr.py`
- Modify: `backend/app/routers/ocr.py`

Models to move: `OcrResult`, `OcrAutoSaveResult`, `OcrPendingCount`

---

### 1.3 `ai_advisor.py` — Pindahkan helper functions ke service

**Objective:** Pindahkan `_check_api_key()` dan `_check_model_access()` ke `ai_advisor_service.py`.

**Files:**
- Modify: `backend/app/services/ai_advisor_service.py`
- Modify: `backend/app/routers/ai_advisor.py`

Check functions jadi method di service atau module-level function yang di-import router dari service.

---

### 1.4 `kpr.py` — Pindahkan `_convert_sim_row()` ke service

**Objective:** Pindahkan response transformation helper ke `KPRService` sebagai static/instance method.

**Files:**
- Modify: `backend/app/services/kpr_service.py`
- Modify: `backend/app/routers/kpr.py`

---

## Phase 2: Flutter — Hardcoded Color → AppColors

### 2.1 AppColors: tambah palette yang kurang

**Objective:** Tambah `card`, `chartPalette`, dan `avatarColor` helper.

**Files:**
- Modify: `mobile/lib/core/theme/app_theme.dart`

### 2.2 `profile_screen.dart` — Migrasi 4 avatar blocks

**Objective:** Ganti `Colors.pink.shade200`, `Colors.blue.shade200`, `Colors.white` → `AppColors`

### 2.3 `reports_screen.dart` — Migrasi category→color maps

**Objective:** Ganti `Colors.orange/blue/purple/red/teal/indigo` → `AppColors`

### 2.4 `transaction_list_screen.dart` — Migrasi `Colors.primaries`

**Objective:** Ganti `Colors.primaries[idx].shade` → `AppColors`

### 2.5 `transfer_screen.dart` — Migrasi `Colors.primaries`

**Objective:** Sama dengan 2.4

### 2.6 `shimmer_loading.dart` — Fix redundant brightness check

**Objective:** `isDark ? darkSurface : surface` → `surface` aja (udah brightness-aware)

---

## Testing & Verification

- [ ] Backend engine tests (no DB): `pytest tests/test_kpr.py::TestKprEngine -q`
- [ ] Health endpoint: `curl http://localhost:8080/api/v1/health` → 200
- [ ] Flutter: `flutter analyze` di mobile/ — zero new errors
- [ ] Flutter: `flutter test` — existing tests pass

## Files Changed (Expected)

**Backend (4 files):**
- Create: `backend/app/services/health_service.py`
- Create: `backend/app/schemas/ocr.py`
- Modify: `backend/app/routers/health.py`
- Modify: `backend/app/routers/ocr.py`
- Modify: `backend/app/routers/ai_advisor.py`
- Modify: `backend/app/services/ai_advisor_service.py`
- Modify: `backend/app/routers/kpr.py`
- Modify: `backend/app/services/kpr_service.py`

**Flutter (6 files):**
- Modify: `mobile/lib/core/theme/app_theme.dart`
- Modify: `mobile/lib/features/profile/ui/profile_screen.dart`
- Modify: `mobile/lib/features/reports/ui/reports_screen.dart`
- Modify: `mobile/lib/features/transactions/ui/transaction_list_screen.dart`
- Modify: `mobile/lib/features/transactions/ui/transfer_screen.dart`
- Modify: `mobile/lib/shared/widgets/shimmer_loading.dart`
