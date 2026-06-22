# Refactor: Layer Separation + Clean Code

> **Branch:** `refactor/layer-separation`
> **Target:** PR into `main`
> **Status:** ✅ Plan — Ready for execution

**Goal:** Separate all business logic from routers to the service layer (backend), and implement full theme + Riverpod consistency (Flutter).

**Principles:**
- Routers only handle HTTP request/response + dependency injection
- Services handle all DB queries, validation, and transformation
- No `cursor.execute` in routers (except for genuinely infrastructure-related ones)
- Flutter: zero hardcoded colors, all using `AppColors`

---

## Phase 1: Backend — Router → Service Extraction

### 1.1 `health.py` — Extract to `HealthService`

**Objective:** Move the DB `SELECT 1` and Redis ping from the router to the service.

**Files:**
- Create: `backend/app/services/health_service.py`
- Modify: `backend/app/routers/health.py`

**Steps:**
1. Create a `HealthService` class with a `check()` method
2. The router simply calls `await service.check(db, redis)`
3. Test: `curl /api/v1/health` still returns 200

---

### 1.2 `ocr.py` — Move models + duplicate validation

**Objective:** Move Pydantic models from `routers/ocr.py` to `schemas/ocr.py`. Remove duplicate validation (content_type, size) from the router — it is already in `OcrService`.

**Files:**
- Create: `backend/app/schemas/ocr.py`
- Modify: `backend/app/routers/ocr.py`

Models to move: `OcrResult`, `OcrAutoSaveResult`, `OcrPendingCount`

---

### 1.3 `ai_advisor.py` — Move helper functions to service

**Objective:** Move `_check_api_key()` and `_check_model_access()` to `ai_advisor_service.py`.

**Files:**
- Modify: `backend/app/services/ai_advisor_service.py`
- Modify: `backend/app/routers/ai_advisor.py`

Check functions become methods in the service or module-level functions that the router imports from the service.

---

### 1.4 `kpr.py` — Move `_convert_sim_row()` to service

**Objective:** Move the response transformation helper to `KPRService` as a static/instance method.

**Files:**
- Modify: `backend/app/services/kpr_service.py`
- Modify: `backend/app/routers/kpr.py`

---

## Phase 2: Flutter — Hardcoded Color → AppColors

### 2.1 AppColors: add missing palette

**Objective:** Add `card`, `chartPalette`, and `avatarColor` helpers.

**Files:**
- Modify: `mobile/lib/core/theme/app_theme.dart`

### 2.2 `profile_screen.dart` — Migrate 4 avatar blocks

**Objective:** Replace `Colors.pink.shade200`, `Colors.blue.shade200`, `Colors.white` → `AppColors`

### 2.3 `reports_screen.dart` — Migrate category→color maps

**Objective:** Replace `Colors.orange/blue/purple/red/teal/indigo` → `AppColors`

### 2.4 `transaction_list_screen.dart` — Migrate `Colors.primaries`

**Objective:** Replace `Colors.primaries[idx].shade` → `AppColors`

### 2.5 `transfer_screen.dart` — Migrate `Colors.primaries`

**Objective:** Same as 2.4

### 2.6 `shimmer_loading.dart` — Fix redundant brightness check

**Objective:** `isDark ? darkSurface : surface` → just `surface` (already brightness-aware)

---

## Testing & Verification

- [ ] Backend engine tests (no DB): `pytest tests/test_kpr.py::TestKprEngine -q`
- [ ] Health endpoint: `curl http://localhost:8080/api/v1/health` → 200
- [ ] Flutter: `flutter analyze` in mobile/ — zero new errors
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