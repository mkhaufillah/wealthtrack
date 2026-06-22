# Clean Code Refactor — WealthTrack

> **Branch:** `refactor/clean-code`
> **Target:** PR to `main`

**Goal:** Separate business logic from the router to the service layer (backend) and replace all hardcoded colors with AppColors (Flutter). Zero behavioral change — all tests must remain passing.

**Principles:**
- Router only handles HTTP (validation, routing, response formatting)
- Service handles business logic (pure Python, no dependency on FastAPI)
- Data layer handles DB queries
- Flutter: every color goes through `AppColors.*` — no bare `Colors.white`, no `Color(0x...)`

---

## Phase 1 — Backend: Infrastructure + Service Layer

### Task 1.1: Create base service pattern & data layer

**Objective:** Create `backend/app/services/base.py` as the base class for all services, and `backend/app/data/` for the repository layer.

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

**Objective:** Move KPR logic from `routers/kpr.py` to `services/kpr_service.py`.

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

**Objective:** Move CC logic from `routers/credit_cards.py` to `services/credit_card_service.py`.

**Files:**
- Create: `backend/app/services/credit_card_service.py`
- Modify: `backend/app/routers/credit_cards.py`

### Task 1.4: Extract Transaction service

**Objective:** Move transaction logic from `routers/transactions.py` to `services/transaction_service.py`.

**Files:**
- Create: `backend/app/services/transaction_service.py`
- Modify: `backend/app/routers/transactions.py`

### Task 1.5: Extract Budget service

**Objective:** Move budget logic from `routers/budgets.py` to `services/budget_service.py`.

**Files:**
- Create: `backend/app/services/budget_service.py`
- Modify: `backend/app/routers/budgets.py`

### Task 1.6: Extract Summary/Household Debt service

**Objective:** Move summary & debt logic from `routers/summaries.py` to `services/summary_service.py`.

**Files:**
- Create: `backend/app/services/summary_service.py`
- Modify: `backend/app/routers/summaries.py`

### Task 1.7: Extract AI Advisor service

**Objective:** Move AI advisor logic from `routers/ai_advisor.py` to `services/ai_advisor_service.py`.

**Files:**
- Create: `backend/app/services/ai_advisor_service.py`
- Modify: `backend/app/routers/ai_advisor.py`

### Task 1.8: Extract remaining services (OCR, Auth, Households, Categories, Exports)

**Objective:** Move logic from smaller routers to their respective services.

**Files:**
- Create: `backend/app/services/ocr_service.py`
- Create: `backend/app/services/auth_service.py`
- Create: `backend/app/services/household_service.py`
- Create: `backend/app/services/category_service.py`
- Create: `backend/app/services/export_service.py`
- Modify: respective router files

### Task 1.9: Verify backend tests pass

**Objective:** Run the backend test suite — engine tests must be 7/7 passing, API tests (if there is a DB) must also pass.

---

## Phase 2 — Flutter: Theme Compliance

### Task 2.1: Extract chart color constants

**Objective:** Move the chart color palette and avatar color logic to AppColors to avoid duplication.

**Files:**
- Modify: `mobile/lib/core/theme/app_theme.dart`
- Modify: `mobile/lib/features/reports/ui/reports_screen.dart`
- Modify: `mobile/lib/features/reports/widgets/charts_section.dart`

### Task 2.2: Fix hardcoded Color() in shimmer & AI advisor

**Objective:** Replace `Color(0xFFEEEEEE)` in shimmer and `Color(0x...)` in the AI advisor code block with AppColors.

**Files:**
- Modify: `mobile/lib/shared/widgets/shimmer_loading.dart`
- Modify: `mobile/lib/features/ai/ui/ai_advisor_screen.dart`

### Task 2.3: Replace Colors.white with AppColors in all screens

**Objective:** Replace all `Colors.white`, `Colors.white70`, `Colors.white60`, `Colors.white38`, `Colors.black87`, `Colors.black54` with the appropriate AppColors.

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

**Objective:** Replace `Colors.red`, `Colors.redAccent`, `Colors.red.shade*` with AppColors semantic aliases.

**Files:**
- Modify: `mobile/lib/features/transactions/ui/transfer_screen.dart`
- Modify: `mobile/lib/features/profile/ui/profile_screen.dart`

### Task 2.5: Verify Flutter analysis passes

**Objective:** `flutter analyze` must be clean.

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

**Objective:** Push `refactor/clean-code` to origin, open a PR to `main`.