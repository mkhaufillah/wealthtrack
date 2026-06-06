# Debt Tracker — Full Implementation Plan

> **For Hermes:** Use subagent-driven-development to implement this plan task-by-task.

**Goal:** Build debt tracker with comprehensive KPR (mortgage) calculator and credit card tracker.

**Architecture:** Backend (FastAPI + asyncpg) handles all business logic, calculations, and persistence. Mobile (Flutter + Riverpod) provides UI with clean feature folders following existing patterns. New DB tables use `SCHEMA_SQL` in `database.py` for auto-migration.

**Tech Stack:** Python/FastAPI, asyncpg, Pydantic v2, Flutter 3.44, Riverpod 2.x, GoRouter, Dio

---

## Task List

---

### PHASE 0: Infrastructure & Performance

---

### Task 0.1: Auto DB Backup Script

**Objective:** Create pg_dump backup script + install cronjob for daily automated PostgreSQL backup.

**Files:**
- Create: `backend/scripts/pg_backup.sh`
- Create: `.github/BACKUP.md` (brief runbook)

**Step 1: Create backup script**

Write `backend/scripts/pg_backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/home/hermes/backups/wealthtrack}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DB_URL="${WEALTHTRACK_DATABASE_URL:-postgresql://wealthtrack:***@localhost:5432/wealthtrack}"

mkdir -p "$BACKUP_DIR"

# Extract connection parts from URL
DB_USER=$(echo "$DB_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')
DB_PASS=$(echo "$DB_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
DB_HOST=$(echo "$DB_URL" | sed -n 's|.*@\([^:]*\):.*|\1|p')
DB_PORT=$(echo "$DB_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
DB_NAME=$(echo "$DB_URL" | sed -n 's|.*/\([^?]*\)|\1|p')

export PGPASSWORD="$DB_PASS"
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  --format=custom \
  --compress=9 \
  --file="$BACKUP_DIR/wealthtrack_$TIMESTAMP.dump" \
  2>&1

# Remove backups older than RETENTION_DAYS
find "$BACKUP_DIR" -name "wealthtrack_*.dump" -mtime +$RETENTION_DAYS -delete

echo "✅ Backup completed: $BACKUP_DIR/wealthtrack_$TIMESTAMP.dump"
```

**Step 2: Make executable + test**

Run: `chmod +x backend/scripts/pg_backup.sh`

**Step 3: Install cronjob**

```bash
(crontab -l 2>/dev/null; echo "0 3 * * * /home/hermes/dev/wealthtrack/backend/scripts/pg_backup.sh >> /home/hermes/backups/wealthtrack/cron.log 2>&1") | crontab -
```

**Step 4: Create runbook**

Write `docs/BACKUP.md` with restore instructions:
```bash
# Restore from backup:
pg_restore --format=custom --dbname=postgresql://wealthtrack:***@localhost:5432/wealthtrack \
  /home/hermes/backups/wealthtrack/wealthtrack_20260606_030000.dump
```

**Step 5: Verify**

Run: `crontab -l | grep pg_backup` — should show the cron entry
Run: `bash backend/scripts/pg_backup.sh` — should create `.dump` file

---

### Task 0.2: DB Query Optimization — Missing Indexes

**Objective:** Add missing indexes to common query patterns identified in transaction, household, and budget queries.

**Files:**
- Modify: `backend/app/database.py` (add CREATE INDEX statements to SCHEMA_SQL)

**Indexes to add (insert before final `"""` in SCHEMA_SQL):**

```sql
-- For summaries grouped by type per user
CREATE INDEX IF NOT EXISTS idx_transactions_user_type_date ON transactions(user_id, type, COALESCE(date, LEFT(created_at, 10)));

-- For category filter in transaction listing
CREATE INDEX IF NOT EXISTS idx_transactions_user_cat_date ON transactions(user_id, category_id, COALESCE(date, LEFT(created_at, 10)) DESC);

-- For OCR jobs listing by user
CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_created ON ocr_jobs(user_id, created_at DESC);
```

---

### PHASE 1: KPR (Mortgage) Calculator

---

### Task 1.1: Backend — KPR Database Tables

**Objective:** Create KPR simulation tables in SCHEMA_SQL.

**Files:**
- Modify: `backend/app/database.py`

**Tables to add (append to SCHEMA_SQL):**

```sql
CREATE TABLE IF NOT EXISTS kpr_simulations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    name TEXT NOT NULL DEFAULT 'KPR Simulation',
    property_price INTEGER NOT NULL DEFAULT 0,
    down_payment INTEGER NOT NULL DEFAULT 0,
    total_loan INTEGER NOT NULL DEFAULT 0,
    tenor_months INTEGER NOT NULL DEFAULT 120,
    interest_type TEXT NOT NULL DEFAULT 'fixed' CHECK(interest_type IN ('fixed', 'floating', 'graduated', 'mix')),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_simulations_user ON kpr_simulations(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS kpr_rate_periods (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    period_start INTEGER NOT NULL,
    period_end INTEGER NOT NULL,
    interest_rate NUMERIC(6,4) NOT NULL,
    rate_type TEXT NOT NULL DEFAULT 'fixed' CHECK(rate_type IN ('fixed', 'floating')),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_rate_periods_sim ON kpr_rate_periods(simulation_id);

CREATE TABLE IF NOT EXISTS kpr_monthly_schedules (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    month_number INTEGER NOT NULL,
    payment INTEGER NOT NULL,
    principal INTEGER NOT NULL,
    interest INTEGER NOT NULL,
    remaining_balance INTEGER NOT NULL,
    rate_type TEXT NOT NULL,
    interest_rate NUMERIC(6,4) NOT NULL,
    UNIQUE(simulation_id, month_number)
);

CREATE INDEX IF NOT EXISTS idx_kpr_schedules_sim ON kpr_monthly_schedules(simulation_id);
```

---

### Task 1.2: Backend — KPR Calculation Engine

**Objective:** Build the core KPR mortgage calculation engine supporting fixed, floating, graduated, and mixed rate types.

**Files:**
- Create: `backend/app/services/kpr_engine.py`

**Formulas:**

- **Monthly payment (fixed):** `M = P × (r × (1+r)^n) / ((1+r)^n - 1)`
  where P = loan principal, r = monthly interest rate (annual/12), n = total months
- **Floating/graduated/mix:** Same formula per period, rate changes at defined intervals

**Engine output per month:** payment, principal, interest, remaining_balance, rate_type, interest_rate

```python
"""KPR (Mortgage) Calculation Engine.

Supports:
- Fixed rate (suku bunga tetap)
- Floating rate (suku bunga mengambang)
- Graduated rate (suku bunga berjenjang)
- Mix (kombinasi fixed + floating + graduated)
"""

from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional


@dataclass
class MonthlySchedule:
    month_number: int
    payment: int
    principal: int
    interest: int
    remaining_balance: int
    rate_type: str
    interest_rate: float


@dataclass
class RatePeriod:
    period_start: int
    period_end: int
    interest_rate: float
    rate_type: str = "fixed"


def _decimal(value: float) -> Decimal:
    return Decimal(str(value))


def _annual_to_monthly(annual_rate: float) -> Decimal:
    return _decimal(annual_rate) / Decimal('12')


def _calculate_payment(
    principal: Decimal,
    monthly_rate: Decimal,
    remaining_months: int,
) -> Decimal:
    if monthly_rate == 0:
        return principal / Decimal(str(remaining_months))
    one_plus_r = Decimal('1') + monthly_rate
    numerator = principal * monthly_rate * (one_plus_r ** remaining_months)
    denominator = (one_plus_r ** remaining_months) - Decimal('1')
    return numerator / denominator


def calculate_kpr(
    total_loan: int,
    tenor_months: int,
    rate_periods: Optional[list[RatePeriod]] = None,
    interest_type: str = "fixed",
    base_interest_rate: float = 0.075,
    graduated_increment: float = 0.005,
    graduated_every_months: int = 12,
) -> list[MonthlySchedule]:
    """Calculate full KPR amortization schedule."""
    remaining = _decimal(total_loan)
    schedule: list[MonthlySchedule] = []

    for month in range(1, tenor_months + 1):
        current_rate: float = base_interest_rate
        current_rate_type: str = interest_type

        if interest_type == "mix" and rate_periods:
            for rp in rate_periods:
                if rp.period_start <= month <= rp.period_end:
                    current_rate = rp.interest_rate
                    current_rate_type = rp.rate_type
                    break
        elif interest_type == "graduated":
            periods_passed = (month - 1) // graduated_every_months
            current_rate = base_interest_rate + (graduated_increment * periods_passed)
            current_rate_type = "graduated"

        monthly_rate = _annual_to_monthly(current_rate)
        remaining_months = tenor_months - month + 1
        payment = _calculate_payment(remaining, monthly_rate, remaining_months)

        interest_amount = (remaining * monthly_rate).to_integral_value(rounding=ROUND_HALF_UP)
        principal_amount = (payment - interest_amount).to_integral_value(rounding=ROUND_HALF_UP)
        payment_amount = principal_amount + interest_amount

        schedule.append(MonthlySchedule(
            month_number=month,
            payment=int(payment_amount),
            principal=int(principal_amount),
            interest=int(interest_amount),
            remaining_balance=int(remaining - principal_amount),
            rate_type=current_rate_type,
            interest_rate=current_rate,
        ))
        remaining -= principal_amount

    return schedule


def simulate_summary(schedule: list[MonthlySchedule]) -> dict:
    if not schedule:
        return {}
    return {
        "total_payment": sum(s.payment for s in schedule),
        "total_interest": sum(s.interest for s in schedule),
        "monthly_payment": schedule[0].payment if schedule else 0,
        "total_months": len(schedule),
    }
```

---

### Task 1.3: Backend — KPR API Endpoints

**Objective:** Create REST API endpoints for KPR simulation CRUD + calculation + schedule.

**Files:**
- Create: `backend/app/schemas/kpr.py`
- Create: `backend/app/routers/kpr.py`
- Modify: `backend/app/main.py` (register router)

**Step 1: Create KPR schemas** (`backend/app/schemas/kpr.py`)

```python
from pydantic import BaseModel, Field
from typing import Optional


class RatePeriodIn(BaseModel):
    period_start: int = Field(ge=1)
    period_end: int = Field(ge=1)
    interest_rate: float = Field(ge=0, le=1)
    rate_type: str = "fixed"


class KPRSimulationCreate(BaseModel):
    name: str = "KPR Simulation"
    property_price: int = Field(ge=0)
    down_payment: int = Field(ge=0, default=0)
    tenor_months: int = Field(ge=12, le=360)
    interest_type: str = "fixed"
    base_interest_rate: float = 0.075
    graduated_increment: float = 0.005
    graduated_every_months: int = 12
    rate_periods: list[RatePeriodIn] = []


class KPRSimulationUpdate(BaseModel):
    name: Optional[str] = None
    property_price: Optional[int] = None
    down_payment: Optional[int] = None
    tenor_months: Optional[int] = None


class KPRScheduleItemOut(BaseModel):
    month_number: int
    payment: int
    principal: int
    interest: int
    remaining_balance: int
    rate_type: str
    interest_rate: float


class KPRSimulationOut(BaseModel):
    id: int
    user_id: int
    name: str
    property_price: int
    down_payment: int
    total_loan: int
    tenor_months: int
    interest_type: str
    created_at: str


class KPRSimulationDetailOut(KPRSimulationOut):
    schedule: list[KPRScheduleItemOut]
    summary: dict
```

**Step 2: Create KPR router** (`backend/app/routers/kpr.py`)

Endpoints:
```
POST   /kpr/simulations              — Create simulation + calculate schedule
GET    /kpr/simulations               — List user's simulations
GET    /kpr/simulations/{id}          — Get simulation detail + full schedule
PUT    /kpr/simulations/{id}          — Update simulation metadata
DELETE /kpr/simulations/{id}          — Delete simulation + cascade schedules
GET    /kpr/simulations/{id}/schedule?month=X  — Get single month breakdown
```

**Step 3: Register in main.py**

Add import: `from app.routers import kpr`
Add router: `app.include_router(kpr.router, prefix="/api/v1")`

---

### Task 1.4: Backend — KPR Tests

**Objective:** Write pytest tests for the KPR calculation engine and API.

**Files:**
- Create: `backend/tests/test_kpr.py`

**Test cases for engine:**
- Fixed rate: verify payment matches known amortization values
- Floating rate: rate change mid-tenor, verify recalculate
- Graduated rate: rate increments at correct intervals
- Mix: multiple rate periods applied correctly
- Zero interest edge case
- Large loan (billions) — verify no overflow

**Test cases for API:**
- Create simulation → 201 + schedule returned
- List simulations → returns list
- Get by id → returns detail with schedule
- Delete → 204, subsequent GET → 404

---

### Task 1.5: Mobile — KPR Models & Provider

**Objective:** Create KPR data models and Riverpod provider.

**Files:**
- Create: `mobile/lib/features/debt/models/kpr_model.dart`
- Create: `mobile/lib/features/debt/kpr/providers/kpr_provider.dart`

**Step 1: KPR Model** (`mobile/lib/features/debt/models/kpr_model.dart`)

```dart
class KPRSimulation {
  final int id;
  final String name;
  final int propertyPrice;
  final int downPayment;
  final int totalLoan;
  final int tenorMonths;
  final String interestType;
  final String createdAt;
  final List<KPRScheduleItem>? schedule;

  KPRSimulation({...});
  factory KPRSimulation.fromJson(Map<String, dynamic> json) => ...;
}

class KPRScheduleItem {
  final int monthNumber;
  final int payment;
  final int principal;
  final int interest;
  final int remainingBalance;
  final String rateType;
  final double interestRate;

  KPRScheduleItem({...});
  factory KPRScheduleItem.fromJson(Map<String, dynamic> json) => ...;
}
```

**Step 2: KPR Provider** (`mobile/lib/features/debt/kpr/providers/kpr_provider.dart`)

Riverpod StateNotifier with:
- `loadAll()` — fetch simulations list
- `loadDetail(id)` — fetch single with schedule
- `create(data)` — POST → return result
- `delete(id)` — DELETE → refresh list
- `calculate()` — for create preview before save

---

### Task 1.6: Mobile — KPR Screens

**Objective:** Create Flutter UI for KPR calculator and schedule view.

**Files:**
- Create: `mobile/lib/features/debt/kpr/ui/kpr_list_screen.dart`
- Create: `mobile/lib/features/debt/kpr/ui/kpr_form_screen.dart`
- Create: `mobile/lib/features/debt/kpr/ui/kpr_detail_screen.dart`

**Step 1: KPR List Screen**
- Card list showing saved simulations
- Each card: property name/price, monthly payment, total interest
- FAB to create new
- Swipe to delete

**Step 2: KPR Form Screen**
- Property price input (IDR formatted)
- Down payment input (auto-calculate total_loan)
- Tenor selector (years: 5/10/15/20/25/30)
- Interest type: dropdown (fixed/floating/graduated/mix)
- Rate input fields (based on type):
  - Fixed: single rate %
  - Floating: rate % (base)
  - Graduated: base rate %, increment %, every N months
  - Mix: list of period rows (from month, to month, rate %, type)
- Calculate button → show summary before save
- Save button → creates simulation

**Step 3: KPR Detail Screen**
- Header: property price, loan amount, monthly payment
- Quick summary cards: total interest, total payment, remaining
- Year-by-year collapsible schedule table
  - Each year row: year, total payment, total interest
  - Expand: shows 12 months with month, payment, principal, interest, balance
- Current month highlighted
- Scrollable for full tenure

---

### PHASE 2: Credit Card Tracker

---

### Task 2.1: Backend — Credit Card DB Tables

**Objective:** Create credit card, transaction, and installment tables.

**Files:**
- Modify: `backend/app/database.py`

**Tables to add to SCHEMA_SQL:**

```sql
CREATE TABLE IF NOT EXISTS credit_cards (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    card_number_last4 TEXT DEFAULT '',
    billing_date INTEGER NOT NULL DEFAULT 1,
    due_date INTEGER NOT NULL DEFAULT 15,
    credit_limit INTEGER DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_credit_cards_user ON credit_cards(user_id);

CREATE TABLE IF NOT EXISTS credit_card_transactions (
    id SERIAL PRIMARY KEY,
    card_id INTEGER NOT NULL REFERENCES credit_cards(id) ON DELETE CASCADE,
    description TEXT NOT NULL DEFAULT '',
    amount INTEGER NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    transaction_date TEXT NOT NULL,
    is_installment INTEGER NOT NULL DEFAULT 0,
    installment_id INTEGER REFERENCES credit_card_installments(id),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_cc_transactions_card ON credit_card_transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_cc_transactions_date ON credit_card_transactions(transaction_date DESC);

CREATE TABLE IF NOT EXISTS credit_card_installments (
    id SERIAL PRIMARY KEY,
    card_id INTEGER NOT NULL REFERENCES credit_cards(id) ON DELETE CASCADE,
    description TEXT NOT NULL DEFAULT '',
    total_amount INTEGER NOT NULL,
    monthly_amount INTEGER NOT NULL,
    total_months INTEGER NOT NULL,
    remaining_months INTEGER NOT NULL,
    start_month TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_cc_installments_card ON credit_card_installments(card_id);
```

---

### Task 2.2: Backend — Credit Card API Endpoints

**Objective:** Create REST API for credit card management.

**Files:**
- Create: `backend/app/schemas/credit_card.py`
- Create: `backend/app/routers/credit_cards.py`
- Modify: `backend/app/main.py`

**Step 1: Create schemas** (`backend/app/schemas/credit_card.py`)

```python
from pydantic import BaseModel, Field
from typing import Optional


class CreditCardCreate(BaseModel):
    name: str = Field(min_length=1)
    card_number_last4: str = ""
    billing_date: int = Field(1, ge=1, le=31)
    due_date: int = Field(15, ge=1, le=31)
    credit_limit: int = 0


class CreditCardUpdate(BaseModel):
    name: Optional[str] = None
    billing_date: Optional[int] = None
    due_date: Optional[int] = None
    credit_limit: Optional[int] = None


class CreditCardOut(BaseModel):
    id: int
    user_id: int
    name: str
    card_number_last4: str
    billing_date: int
    due_date: int
    credit_limit: int
    created_at: str


class CreditCardTransactionCreate(BaseModel):
    description: str = ""
    amount: int = Field(ge=0)
    category_id: Optional[int] = None
    transaction_date: str
    is_installment: bool = False
    installment_id: Optional[int] = None


class CreditCardTransactionOut(BaseModel):
    id: int
    card_id: int
    description: str
    amount: int
    category_id: Optional[int]
    transaction_date: str
    is_installment: bool
    installment_id: Optional[int]
    created_at: str


class CreditCardInstallmentCreate(BaseModel):
    description: str = ""
    total_amount: int = Field(ge=0)
    monthly_amount: int = Field(ge=0)
    total_months: int = Field(ge=1)
    remaining_months: int = Field(ge=1)
    start_month: str  # YYYY-MM


class CreditCardInstallmentOut(BaseModel):
    id: int
    card_id: int
    description: str
    total_amount: int
    monthly_amount: int
    total_months: int
    remaining_months: int
    start_month: str
    created_at: str


class NextMonthProjection(BaseModel):
    total_installments: int = 0
    total_new_transactions: int = 0
    total_expected: int = 0
    per_card: list[dict] = []
```

**Step 2: Create credit card router** (`backend/app/routers/credit_cards.py`)

```
POST   /credit-cards                    — Create card
GET    /credit-cards                    — List cards
GET    /credit-cards/{id}               — Get card detail
PUT    /credit-cards/{id}               — Update card
DELETE /credit-cards/{id}               — Delete card (+ cascade)

POST   /credit-cards/{id}/transactions               — Add transaction
GET    /credit-cards/{id}/transactions                — List transactions
DELETE /credit-cards/{id}/transactions/{txn_id}       — Delete transaction

POST   /credit-cards/{id}/installments                — Add installment
GET    /credit-cards/{id}/installments                — List installments
PUT    /credit-cards/{id}/installments/{inst_id}      — Update (decrement remaining)
DELETE /credit-cards/{id}/installments/{inst_id}      — Delete installment

GET    /credit-cards/next-month-projection            — Expected next month amounts
```

**Step 3: Register in main.py**

Add import: `from app.routers import credit_cards`
Add router: `app.include_router(credit_cards.router, prefix="/api/v1")`

---

### Task 2.3: Backend — Credit Card Tests

**Objective:** Write pytest tests for credit card API.

**Files:**
- Create: `backend/tests/test_credit_cards.py`

**Test cases:**
- Create card → 201
- List cards → returns list
- Add transaction → 201
- Add installment → 201
- Next month projection includes active installments
- Delete card cascades to transactions + installments

---

### Task 2.4: Mobile — Credit Card Models & Providers

**Objective:** Create credit card data models and Riverpod provider.

**Files:**
- Create: `mobile/lib/features/debt/models/credit_card_model.dart`
- Create: `mobile/lib/features/debt/credit_card/providers/credit_card_provider.dart`

**Step 1: Models**

```dart
class CreditCard {
  final int id;
  final String name;
  final String cardNumberLast4;
  final int billingDate;
  final int dueDate;
  final int creditLimit;
  final String createdAt;

  CreditCard({...});
  factory CreditCard.fromJson(Map<String, dynamic> json) => ...;
}

class CCTransaction {
  final int id;
  final int cardId;
  final String description;
  final int amount;
  final int? categoryId;
  final String transactionDate;
  final bool isInstallment;
  final int? installmentId;

  CCTransaction({...});
  factory CCTransaction.fromJson(Map<String, dynamic> json) => ...;
}

class CCInstallment {
  final int id;
  final int cardId;
  final String description;
  final int totalAmount;
  final int monthlyAmount;
  final int totalMonths;
  final int remainingMonths;
  final String startMonth;

  CCInstallment({...});
  factory CCInstallment.fromJson(Map<String, dynamic> json) => ...;
}
```

**Step 2: Provider**

Riverpod StateNotifier with:
- `loadCards()` — fetch card list
- `loadCardDetail(id)` — card + transactions + installments
- `createCard(data)`, `deleteCard(id)`
- `addTransaction(cardId, data)`
- `addInstallment(cardId, data)`
- `deleteInstallment(cardId, instId)`
- `loadNextMonthProjection()`

---

### Task 2.5: Mobile — Credit Card Screens

**Objective:** Create Flutter UI for credit card management.

**Files:**
- Create: `mobile/lib/features/debt/credit_card/ui/credit_card_list_screen.dart`
- Create: `mobile/lib/features/debt/credit_card/ui/credit_card_form_screen.dart`
- Create: `mobile/lib/features/debt/credit_card/ui/credit_card_detail_screen.dart`
- Create: `mobile/lib/features/debt/credit_card/ui/add_installment_screen.dart`

**Step 1: Credit Card List Screen**
- Card list showing each card with masked number, limit, next due date
- Total summary at top: total limit, total outstanding installments
- Swipe to delete card
- FAB to add new card

**Step 2: Credit Card Form Screen**
- Card name (e.g. "BCA Visa Platinum")
- Last 4 digits optional
- Billing date dropdown (1-31)
- Due date dropdown (1-31)
- Credit limit input

**Step 3: Credit Card Detail Screen**
- Tab/segment: Transactions | Installments
- **Transactions tab:**
  - List of transactions with date, description, amount, category
  - Flag for installment-linked transactions
  - FAB to add new transaction
- **Installments tab:**
  - Progress cards per installment (description, X/Y months remaining, monthly amount)
  - Swipe to mark month complete (decrement remaining)
  - Tap to see installment detail
  - FAB to add new installment

**Step 4: Add Installment Screen**
- Description
- Total amount
- Monthly amount (auto-fill if total/total_months)
- Total months
- Start month (YYYY-MM picker)

---

### PHASE 3: Navigation Integration

---

### Task 3.1: Navigation — Routes & Bottom Nav

**Objective:** Wire debt tracker screens into GoRouter and app navigation.

**Files:**
- Modify: `mobile/lib/app.dart`

**New routes to add:**
```
/debt                        → DebtHomeScreen (tabs: KPR | Credit Cards)
/debt/kpr                    → KPRListScreen
/debt/kpr/new                → KPRFormScreen
/debt/kpr/{id}               → KPRDetailScreen
/debt/credit-cards           → CreditCardListScreen
/debt/credit-cards/new       → CreditCardFormScreen
/debt/credit-cards/{id}      → CreditCardDetailScreen
/debt/credit-cards/{id}/installments/new → AddInstallmentScreen
```

**Navigation structure:**

Add a "Debt" tab to the bottom navigation bar (`BottomNavigationBarItem` with icon). The tab order becomes:

1. Home
2. Transactions
3. Debt ← NEW
4. Budget
5. Reports
6. AI Advisor

In the bottom nav shell (`app.dart`), add the new route branch for `/debt` with its nested routes.

---

### Task 3.2: Mobile — Debt Home Screen

**Objective:** Create the debt home screen with tabs for KPR and Credit Cards.

**File:**
- Create: `mobile/lib/features/debt/ui/debt_home_screen.dart`

Simple screen with two primary action cards:
- **KPR** → icon + "Mortgage Calculator" → navigate to KPR list
- **Credit Cards** → icon + "Credit Cards" → navigate to CC list

Plus quick summary cards at top if data exists.

---

## Summary (Estimation)

| Phase | Tasks | Files | Est. Time |
|-------|-------|-------|-----------|
| 0.1 DB Backup | 5 | 2 | 15 min |
| 0.2 Indexes | 1 | 1 | 10 min |
| 1.1 KPR Tables | 1 | 1 | 10 min |
| 1.2 KPR Engine | 1 | 1 | 25 min |
| 1.3 KPR API | 3 | 3 | 25 min |
| 1.4 KPR Tests | 1 | 1 | 20 min |
| 1.5 KPR Models/Provider | 2 | 2 | 20 min |
| 1.6 KPR Screens | 3 | 3 | 45 min |
| 2.1 CC Tables | 1 | 1 | 10 min |
| 2.2 CC API | 3 | 3 | 30 min |
| 2.3 CC Tests | 1 | 1 | 20 min |
| 2.4 CC Models/Provider | 2 | 2 | 20 min |
| 2.5 CC Screens | 4 | 4 | 50 min |
| 3.1 Navigation | 1 | 1 | 15 min |
| 3.2 Debt Home | 1 | 1 | 15 min |
| **Total** | **30** | **27** | **~5h** |
