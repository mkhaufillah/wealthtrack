# Clean Code Refactor — WealthTrack

> **Branch:** `refactor/clean-code`
> **Target:** PR ke `main`

**Goal:** Pisahkan business logic dari router ke service layer (backend) dan replace semua hardcoded color ke AppColors (Flutter). Zero behavioral change — semua test harus tetap passing.

**Prinsip:**
- Router cuma handle HTTP (validasi, routing, response formatting)
- Service handle business logic (pure Python, gak depend on FastAPI)
- Data layer handle DB queries
- Flutter: every color goes through `AppColors.*` — no bare `Colors.white`, no `Color(0x...)`

---

## Phase 1 — Backend: Infrastructure + Service Layer

### Task 1.1: Create base service pattern & data layer

**Objective:** Buat `backend/app/services/base.py` sebagai base class untuk semua service, dan `backend/app/data/` untuk repository layer.

**Files:**
- Create: `backend/app/data/__init__.py`
- Create: `backend/app/data/base_repo.py`
- Create: `backend/app/services/__init__.py`

**Pattern:**
```python
# data/base_repo.py
from app.database import CursorWrapper

class BaseRepository:
    def __init__(self, db: CursorWrapper):
        self.db = db

# services/base.py
class BaseService:
    """Marker class for services — pure business logic, no FastAPI dependency."""
    pass
```

### Task 1.2: Extract KPR service

**Objective:** Pindahin logic KPR dari `routers/kpr.py` ke `services/kpr_service.py`.

**Files:**
- Create: `backend/app/services/kpr_service.py`
- Modify: `backend/app/routers/kpr.py` (thin HTTP layer only)

**KPR service covers:**
- `create_simulation()` — insert + schedule generation
- `list_simulations()` — household-aware query
- `get_simulation()` — detail + summary
- `update_simulation()` — metadata update
- `delete_simulation()` — cascade delete
- `preview_extra_payment()` — validate + engine call
- `create_extra_payment()` — insert + schedule regenerate
- `list_extra_payments()` — query existing
- `delete_extra_payment()` — delete + restore schedule
- Ownership/household verification helpers

### Task 1.3: Extract Credit Cards service

**Objective:** Pindahin logic CC dari `routers/credit_cards.py` ke `services/credit_card_service.py`.

**Files:**
- Create: `backend/app/services/credit_card_service.py`
- Modify: `backend/app/routers/credit_cards.py`

### Task 1.4: Extract Transaction service

**Objective:** Pindahin logic transaksi dari `routers/transactions.py` ke `services/transaction_service.py`.

**Files:**
- Create: `backend/app/services/transaction_service.py`
- Modify: `backend/app/routers/transactions.py`

### Task 1.5: Extract Budget service

**Objective:** Pindahin logic budget dari `routers/budgets.py` ke `services/budget_service.py`.

**Files:**
- Create: `backend/app/services/budget_service.py`
- Modify: `backend/app/routers/budgets.py`

### Task 1.6: Extract Summary/Household Debt service

**Objective:** Pindahin logic summary & debt dari `routers/summaries.py` ke `services/summary_service.py`.

**Files:**
- Create: `backend/app/services/summary_service.py`
- Modify: `backend/app/routers/summaries.py`

### Task 1.7: Extract AI Advisor service

**Objective:** Pindahin logic AI advisor dari `routers/ai_advisor.py` ke `services/ai_advisor_service.py`.

**Files:**
- Create: `backend/app/services/ai_advisor_service.py`
- Modify: `backend/app/routers/ai_advisor.py`

### Task 1.8: Extract remaining services (OCR, Auth, Households, Categories, Exports)

**Objective:** Pindahin logic dari router kecil ke service masing-masing.

**Files:**
- Create: `backend/app/services/ocr_service.py`
- Create: `backend/app/services/auth_service.py`
- Create: `backend/app/services/household_service.py`
- Create: `backend/app/services/category_service.py`
- Create: `backend/app/services/export_service.py`
- Modify: masing-masing router file

### Task 1.9: Verify backend tests pass

**Objective:** Jalankan backend test suite — engine tests harus 7/7 passing, API tests (kalau ada DB) juga passing.

---

## Phase 2 — Flutter: Theme Compliance

### Task 2.1: Extract chart color constants

**Objective:** Pindahin chart color palette dan avatar color logic ke AppColors biar gak duplikasi.

**Files:**
- Modify: `mobile/lib/core/theme/app_theme.dart`
- Modify: `mobile/lib/features/reports/ui/reports_screen.dart`
- Modify: `mobile/lib/features/reports/widgets/charts_section.dart`

### Task 2.2: Fix hardcoded Color() in shimmer & AI advisor

**Objective:** Ganti `Color(0xFFEEEEEE)` di shimmer dan `Color(0x...)` di AI advisor code block dengan AppColors.

**Files:**
- Modify: `mobile/lib/shared/widgets/shimmer_loading.dart`
- Modify: `mobile/lib/features/ai/ui/ai_advisor_screen.dart`

### Task 2.3: Replace Colors.white with AppColors in all screens

**Objective:** Ganti semua `Colors.white`, `Colors.white70`, `Colors.white60`, `Colors.white38`, `Colors.black87`, `Colors.black54` dengan AppColors yang sesuai.

**Screens to fix (~40+ occurrences):**
- `add_transaction_screen.dart` (7×)
- `transaction_list_screen.dart` (10×)
- `transfer_screen.dart` (8×)
- `credit_card_detail_screen.dart` (5×)
- `credit_card_list_screen.dart` (1×)
- `credit_card_form_screen.dart` (1×)
- `add_installment_screen.dart` (1×)
- `kpr_list_screen.dart` (1×)
- `kpr_form_screen.dart` (1×)
- `kpr_extra_payment_screen.dart` (3×)
- `kpr_detail_screen.dart` (1×)
- `home_screen.dart` (1×)
- `login_screen.dart` (1×)
- `register_screen.dart` (2×)
- `profile_screen.dart` (10×)
- `shimmer_loading.dart` (1×)
- `ai_advisor_screen.dart` (2×)

### Task 2.4: Fix semantic Colors.red references

**Objective:** Ganti `Colors.red`, `Colors.redAccent`, `Colors.red.shade*` dengan AppColors semantic alias.

**Files:**
- Modify: `mobile/lib/features/transactions/ui/transfer_screen.dart`
- Modify: `mobile/lib/features/profile/ui/profile_screen.dart`

### Task 2.5: Verify Flutter analysis passes

**Objective:** `flutter analyze` harus clean.

---

## Phase 3 — Finalize

### Task 3.1: Verify no behavioral regression

**Objective:** Spot-check key flows:
- KPR create + extra payment
- Transaction CRUD
- Credit card management
- AI advisor
- Dashboard & reports

### Task 3.2: Push branch & create PR

**Objective:** Push `refactor/clean-code` ke origin, buka PR ke `main`.
