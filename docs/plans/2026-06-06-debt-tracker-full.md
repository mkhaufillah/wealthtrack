# Debt Tracker & Notification System — Implementation Plan

> **For Hermes:** Use subagent-driven-development to implement this plan task-by-task.

**Goal:** Build notification system for household transactions, comprehensive debt tracker with KPR (mortgage) calculator and credit card tracker.

**Architecture:** Backend (FastAPI + asyncpg) handles all business logic, calculations, and persistence. Mobile (Flutter + Riverpod) provides UI with clean feature folders following existing patterns. New DB tables use `SCHEMA_SQL` in `database.py` for auto-migration. Notification delivery uses polling (no WebSocket needed for MVP).

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

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/home/hermes/backups/wealthtrack}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DB_URL="${WEALTHTRACK_DATABASE_URL:-postgresql://wealthtrack:***@localhost:5432/wealthtrack}"

mkdir -p "$BACKUP_DIR"

# Extract connection parts from the URL
# Example URL: postgresql://user:password@host:port/dbname
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

**Step 2: Test script**

Run: `chmod +x backend/scripts/pg_backup.sh && bash backend/scripts/pg_backup.sh`  
Expected: Creates dump file in `/home/hermes/backups/wealthtrack/`

**Step 3: Install cronjob**

Add to crontab:
```bash
# Run daily at 03:00 AM
0 3 * * * /home/hermes/dev/wealthtrack/backend/scripts/pg_backup.sh >> /home/hermes/backups/wealthtrack/cron.log 2>&1
```

Install via: `(crontab -l 2>/dev/null; echo "0 3 * * * /home/hermes/dev/wealthtrack/backend/scripts/pg_backup.sh >> /home/hermes/backups/wealthtrack/cron.log 2>&1 ") | crontab -`

**Step 4: Write runbook**

Create `.github/BACKUP.md` with restore instructions.

**Step 5: Verify**

Check: `ls -la /home/hermes/backups/wealthtrack/` — should have a `.dump` file  
Check: `crontab -l | grep pg_backup` — should show the cron entry

---

### Task 0.2: DB Query Optimization — Missing Indexes

**Objective:** Add missing indexes to common query patterns identified in transaction and budget queries.

**Files:**
- Modify: `backend/app/database.py` (add CREATE INDEX statements to SCHEMA_SQL)

**Analysis of current query patterns:**

1. `list_household_transactions` joins: `transactions t JOIN household_members hm2 ON hm2.user_id = t.user_id` — no index on `household_members.user_id` (has PK index only on `(user_id, household_id)` — this is already covered)
2. `list_transactions` filters by `user_id, type, category_id, date` — existing indexes: `idx_transactions_user`, `idx_transactions_user_date`
3. `summaries` aggregates by `user_id, date, type` — needs composite index
4. `budgets` queries by `user_id, month` — existing `idx_budgets_user_month`

**Indexes to add:**

```sql
-- For household transaction listing (JOIN performance)
CREATE INDEX IF NOT EXISTS idx_household_members_user_household ON household_members(user_id, household_id);

-- For summaries grouped by type per user per month
CREATE INDEX IF NOT EXISTS idx_transactions_user_type_date ON transactions(user_id, type, COALESCE(date, LEFT(created_at, 10)));

-- For category filter in transaction listing
CREATE INDEX IF NOT EXISTS idx_transactions_user_cat_date ON transactions(user_id, category_id, COALESCE(date, LEFT(created_at, 10)) DESC);

-- For OCR jobs listing by user
CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_created ON ocr_jobs(user_id, created_at DESC);
```

**Step 1: Add indexes to SCHEMA_SQL in database.py**

Insert the index creation statements before the final `"""` delimiter.

**Step 2: Verify**

Check existing indexes: `psql -U wealthtrack -d wealthtrack -c "\di"`  
Verify new indexes exist after app restart (schema init auto-runs).

---

### PHASE 1: Notification System

---

### Task 1.1: Backend — Notifications Table + Service

**Objective:** Create notifications database table and notification service module.

**Files:**
- Modify: `backend/app/database.py` (add notifications table)
- Create: `backend/app/services/notification_service.py`
- Create: `backend/app/schemas/notification.py`

**Step 1: Add notifications table to SCHEMA_SQL**

```sql
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    type TEXT NOT NULL DEFAULT 'info',
    title TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    data_json TEXT DEFAULT '{}',
    is_read INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications(user_id, created_at DESC);
```

**Step 2: Create notification service**

File: `backend/app/services/notification_service.py`

```python
"""Notification service for WealthTrack.

Handles creating and querying notifications, and triggering
notifications on relevant events (new transaction, etc.).
"""

import json
import logging
from typing import Optional

from app.database import CursorWrapper

logger = logging.getLogger(__name__)

NOTIFICATION_TYPES = {
    "new_transaction": "New Transaction",
    "household_invite": "Household Invite",
    "budget_alert": "Budget Alert",
    "system": "System",
}


async def create_notification(
    db: CursorWrapper,
    user_id: int,
    type: str = "info",
    title: str = "",
    body: str = "",
    data: Optional[dict] = None,
) -> int:
    """Create a notification for a user. Returns notification ID."""
    type_title = NOTIFICATION_TYPES.get(type, type.capitalize())
    if not title:
        title = type_title

    cursor = await db.execute(
        """INSERT INTO notifications (user_id, type, title, body, data_json)
           VALUES (?, ?, ?, ?, ?)""",
        (user_id, type, title, body, json.dumps(data or {})),
    )
    notif_id = cursor.lastrowid
    logger.info("Created notification %s for user %s: %s", notif_id, user_id, title)
    return notif_id


async def notify_household_members(
    db: CursorWrapper,
    household_id: int,
    type: str,
    title: str,
    body: str = "",
    data: Optional[dict] = None,
    exclude_user_id: Optional[int] = None,
) -> list[int]:
    """Notify all members of a household (optionally excluding one user).

    Returns list of notification IDs created.
    """
    cursor = await db.execute(
        "SELECT user_id FROM household_members WHERE household_id = ?",
        (household_id,),
    )
    members = await cursor.fetchall()

    notif_ids = []
    for member in members:
        uid = member["user_id"]
        if exclude_user_id is not None and uid == exclude_user_id:
            continue
        notif_id = await create_notification(db, uid, type, title, body, data)
        notif_ids.append(notif_id)

    return notif_ids


async def get_unread_count(db: CursorWrapper, user_id: int) -> int:
    """Get count of unread notifications for a user."""
    cursor = await db.execute(
        "SELECT COUNT(*) FROM notifications WHERE user_id = ? AND is_read = 0",
        (user_id,),
    )
    row = await cursor.fetchone()
    return row[0] if row else 0


async def get_notifications(
    db: CursorWrapper,
    user_id: int,
    page: int = 1,
    per_page: int = 50,
    unread_only: bool = False,
) -> list[dict]:
    """Get paginated notifications for a user."""
    where = ["user_id = ?"]
    params = [user_id]
    if unread_only:
        where.append("is_read = 0")

    # Count
    cursor = await db.execute(
        f"SELECT COUNT(*) FROM notifications WHERE {' AND '.join(where)}", params
    )
    total = (await cursor.fetchone())[0]

    # Fetch
    offset = (page - 1) * per_page
    cursor = await db.execute(
        f"""SELECT id, type, title, body, data_json, is_read, created_at
            FROM notifications
            WHERE {' AND '.join(where)}
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?""",
        params + [per_page, offset],
    )
    rows = await cursor.fetchall()

    items = []
    for row in rows:
        r = dict(row)
        try:
            r["data"] = json.loads(r.get("data_json", "{}"))
        except (json.JSONDecodeError, TypeError):
            r["data"] = {}
        r.pop("data_json", None)
        items.append(r)

    return {
        "items": items,
        "total": total,
        "page": page,
        "per_page": per_page,
        "total_pages": max(1, (total + per_page - 1) // per_page),
    }


async def mark_as_read(db: CursorWrapper, user_id: int, notification_id: int) -> bool:
    """Mark a single notification as read. Returns True if found."""
    cursor = await db.execute(
        "UPDATE notifications SET is_read = 1 WHERE id = ? AND user_id = ?",
        (notification_id, user_id),
    )
    return cursor.lastrowid is not None


async def mark_all_as_read(db: CursorWrapper, user_id: int) -> int:
    """Mark all notifications as read. Returns count updated."""
    cursor = await db.execute(
        "UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0",
        (user_id,),
    )
    return 0  # asyncpg doesn't return rowcount from execute


async def delete_notification(db: CursorWrapper, user_id: int, notification_id: int) -> bool:
    """Delete a notification. Returns True if found."""
    cursor = await db.execute(
        "DELETE FROM notifications WHERE id = ? AND user_id = ?",
        (notification_id, user_id),
    )
    return True
```

**Step 3: Create notification schemas**

File: `backend/app/schemas/notification.py`

```python
from pydantic import BaseModel, Field
from typing import Optional


class NotificationOut(BaseModel):
    id: int
    type: str
    title: str
    body: str = ""
    data: dict = {}
    is_read: int = 0
    created_at: str


class NotificationListOut(BaseModel):
    items: list[NotificationOut]
    total: int
    page: int
    per_page: int
    total_pages: int


class UnreadCountOut(BaseModel):
    count: int
```

---

### Task 1.2: Backend — Notification API Routes

**Objective:** Create REST API endpoints for notification CRUD + new transaction trigger.

**Files:**
- Create: `backend/app/routers/notifications.py`
- Modify: `backend/app/main.py` (register router)

**Step 1: Create notification router**

```python
import logging

from fastapi import APIRouter, Depends, Query

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.schemas.notification import NotificationOut, NotificationListOut, UnreadCountOut
from app.services.notification_service import (
    get_notifications,
    get_unread_count,
    mark_as_read,
    mark_all_as_read,
    delete_notification,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=NotificationListOut)
async def list_notifications(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
    unread_only: bool = False,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    return await get_notifications(db, current_user["id"], page, per_page, unread_only)


@router.get("/unread-count", response_model=UnreadCountOut)
async def unread_count(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    count = await get_unread_count(db, current_user["id"])
    return {"count": count}


@router.put("/{notification_id}/read", response_model=dict)
async def read_notification(
    notification_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    found = await mark_as_read(db, current_user["id"], notification_id)
    if not found:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Notification not found")
    return {"ok": True}


@router.put("/read-all", response_model=dict)
async def read_all_notifications(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    await mark_all_as_read(db, current_user["id"])
    return {"ok": True}


@router.delete("/{notification_id}", status_code=204)
async def delete_notification_endpoint(
    notification_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    await delete_notification(db, current_user["id"], notification_id)
```

**Step 2: Register router in main.py**

Add import in `backend/app/main.py`:
```python
from app.routers import notifications
```

Add router:
```python
app.include_router(notifications.router, prefix="/api/v1")
```

---

### Task 1.3: Backend — Trigger Notification on New Transaction

**Objective:** When a transaction is created in a household, notify all other household members.

**Files:**
- Modify: `backend/app/routers/transactions.py`
- (uses `notify_household_members` from notification_service)

**Step 1: Add notification call in create_transaction**

In `backend/app/routers/transactions.py`, after the transaction is created and inserted, add:

```python
from app.services.notification_service import notify_household_members

# Inside create_transaction, after successful insert and before the return
try:
    cursor = await db.execute(
        "SELECT household_id FROM household_members WHERE user_id = ?",
        (current_user["id"],),
    )
    hm = await cursor.fetchone()
    if hm:
        await notify_household_members(
            db,
            household_id=hm["household_id"],
            type="new_transaction",
            title="New Transaction",
            body=f"{current_user.get('display_name', 'Someone')} added a {data.type} of {data.amount}",
            data={
                "transaction_id": new_id,
                "amount": data.amount,
                "type": data.type,
                "category_id": data.category_id,
            },
            exclude_user_id=current_user["id"],
        )
except Exception as e:
    logger.warning("Failed to send transaction notification: %s", e)
```

---

### Task 1.4: Mobile — Notification Provider + API

**Objective:** Create Riverpod provider for notifications with polling.

**Files:**
- Create: `mobile/lib/features/notifications/providers/notification_provider.dart`

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';

class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final String createdAt;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    this.data = const {},
    this.isRead = false,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as int,
      type: json['type'] as String? ?? 'info',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
      isRead: (json['is_read'] as int?) == 1,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class NotificationNotifier extends StateNotifier<AsyncValue<List<NotificationItem>>> {
  final ApiClient _client;
  Timer? _pollTimer;

  NotificationNotifier(this._client) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      final res = await _client.get('/notifications', queryParams: {'per_page': '50'});
      final items = (res.data['items'] as List)
          .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  int get unreadCount {
    return state.whenOrNull(data: (items) => items.where((n) => !n.isRead).length) ?? 0;
  }

  Future<void> markAsRead(int id) async {
    try {
      await _client.put('/notifications/$id/read');
      await load();
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    try {
      await _client.put('/notifications/read-all');
      await load();
    } catch (_) {}
  }

  void startPolling() {
    _pollTimer?.cancel();
    load();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

final notificationProvider = StateNotifierProvider<NotificationNotifier, AsyncValue<List<NotificationItem>>>((ref) {
  final client = ref.watch(apiClientProvider);
  return NotificationNotifier(client);
});
```

---

### Task 1.5: Mobile — Notification List Screen + Navigation Badge

**Objective:** Create notification list UI and add badge to navigation.

**Files:**
- Create: `mobile/lib/features/notifications/ui/notification_list_screen.dart`
- Modify: `mobile/lib/app.dart` (add route + notification bell + badge)

**Step 1: Create notification list screen**

A standard consumer widget with ListView of notification items, pull-to-refresh, mark-as-read swipe action.

**Step 2: Add to navigation in app.dart**

- Add notification route to GoRouter
- Add notification bell icon in app bar with unread badge (or in bottom nav as 5th tab)
- Start polling when authenticated

**Routes to add:**
```
/debt          → Debt Screen (placeholder or menu)
/notifications → NotificationListScreen
```

Best approach: Add a bell icon in the AppBar of the main scaffold (app_scaffold.dart or app.dart shell) that shows unread count as a badge.

---

### PHASE 2: Debt Tracker

---

### Task 2.1: Backend — KPR Database Tables

**Objective:** Create KPR simulation tables in SCHEMA_SQL.

**Files:**
- Modify: `backend/app/database.py`

**Tables to add:**

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
    period_start INTEGER NOT NULL,  -- month number (1-based)
    period_end INTEGER NOT NULL,    -- month number (inclusive)
    interest_rate NUMERIC(6,4) NOT NULL,  -- e.g. 0.0750 for 7.5%
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

### Task 2.2: Backend — KPR Calculation Engine

**Objective:** Build the core KPR mortgage calculation engine supporting fixed, floating, graduated, and mixed rate types.

**Files:**
- Create: `backend/app/services/kpr_engine.py`

**Calculation formulas:**

- **Monthly payment (fixed rate):** `M = P × (r × (1+r)^n) / ((1+r)^n - 1)`
  where P = loan principal, r = monthly interest rate (annual/12), n = total months

- **Floating rate:** Same formula, but rate changes at specified periods
- **Graduated rate:** Rate increases by fixed percentage at specified intervals
- **Mix:** Different rates for different time periods (each period uses its own rate)

**Engine output per month:**
- month_number
- payment (total monthly payment — equal for fixed, changes for others)
- principal portion
- interest portion
- remaining_balance
- rate_type applied
- interest_rate applied

**Step 1: Create the engine**

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
    period_start: int   # 1-based month
    period_end: int     # inclusive
    interest_rate: float  # annual rate, e.g. 0.075 for 7.5%
    rate_type: str = "fixed"  # 'fixed' or 'floating'


def _decimal(value: float) -> Decimal:
    return Decimal(str(value))


def _annual_to_monthly(annual_rate: float) -> Decimal:
    """Convert annual interest rate to monthly."""
    return _decimal(annual_rate) / Decimal('12')


def _calculate_payment(
    principal: Decimal,
    monthly_rate: Decimal,
    remaining_months: int,
) -> Decimal:
    """Calculate monthly payment using standard amortization formula."""
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
    base_interest_rate: float = 0.075,  # 7.5% default
    graduated_increment: float = 0.005,  # 0.5% per period for graduated
    graduated_every_months: int = 12,    # every 12 months
) -> list[MonthlySchedule]:
    """Calculate full KPR amortization schedule.

    Args:
        total_loan: Total loan amount (property price - down payment) in IDR
        tenor_months: Loan tenure in months
        rate_periods: For 'mix' type, explicit rate periods
        interest_type: 'fixed', 'floating', 'graduated', or 'mix'
        base_interest_rate: Base annual interest rate
        graduated_increment: Annual rate increment for graduated type
        graduated_every_months: How often rate changes for graduated

    Returns:
        List of MonthlySchedule for each month
    """
    remaining = _decimal(total_loan)
    schedule: list[MonthlySchedule] = []

    for month in range(1, tenor_months + 1):
        # Determine current rate
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

        # Calculate payment for this month
        payment = _calculate_payment(remaining, monthly_rate, remaining_months)

        # Round to integer (IDR)
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


def simulate_rates(
    monthly_schedules: list[MonthlySchedule],
) -> dict:
    """Generate rate simulation summary."""
    if not monthly_schedules:
        return {}

    total_payment = sum(s.payment for s in monthly_schedules)
    total_interest = sum(s.interest for s in monthly_schedules)
    
    return {
        "total_payment": total_payment,
        "total_interest": total_interest,
        "total_months": len(monthly_schedules),
    }
```

---

### Task 2.3: Backend — KPR API Endpoints

**Objective:** Create REST API for KPR simulation CRUD + calculation.

**Files:**
- Create: `backend/app/schemas/kpr.py`
- Create: `backend/app/routers/kpr.py`
- Modify: `backend/app/main.py` (register router)

**Step 1: KPR schemas**

File: `backend/app/schemas/kpr.py`

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
    interest_type: str = "fixed"  # fixed, floating, graduated, mix
    base_interest_rate: float = 0.075
    graduated_increment: float = 0.005
    graduated_every_months: int = 12
    rate_periods: list[RatePeriodIn] = []


class KPRSimulationUpdate(BaseModel):
    name: Optional[str] = None
    property_price: Optional[int] = None
    down_payment: Optional[int] = None
    tenor_months: Optional[int] = None


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
    rate_periods: list[dict] = []


class KPRScheduleItemOut(BaseModel):
    month_number: int
    payment: int
    principal: int
    interest: int
    remaining_balance: int
    rate_type: str
    interest_rate: float


class KPRSimulationResult(BaseModel):
    simulation: KPRSimulationDetailOut
    schedule: list[KPRScheduleItemOut]
    summary: dict
```

**Step 2: KPR router**

File: `backend/app/routers/kpr.py`

```
POST   /kpr/simulations              — Create simulation + calculate
GET    /kpr/simulations               — List user's simulations
GET    /kpr/simulations/{id}          — Get simulation detail + schedule
PUT    /kpr/simulations/{id}          — Update simulation
DELETE /kpr/simulations/{id}          — Delete simulation
GET    /kpr/simulations/{id}/schedule — Get schedule for a month range
```

---

### Task 2.4: Mobile — KPR Screens

**Objective:** Create Flutter UI for KPR calculator and schedule view.

**Files:**
- Create: `mobile/lib/features/debt/models/kpr_model.dart`
- Create: `mobile/lib/features/debt/kpr/providers/kpr_provider.dart`
- Create: `mobile/lib/features/debt/kpr/ui/kpr_screen.dart`
- Create: `mobile/lib/features/debt/kpr/ui/kpr_form_screen.dart`
- Create: `mobile/lib/features/debt/kpr/ui/kpr_schedule_screen.dart`

**Step 1: KPR Model**

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
  final List<KPRRatePeriod> ratePeriods;

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

class KPRRatePeriod {
  final int periodStart;
  final int periodEnd;
  final double interestRate;
  final String rateType;
  
  KPRRatePeriod({...});
  factory KPRRatePeriod.fromJson(Map<String, dynamic> json) => ...;
}
```

**Step 2: KPR Provider**

Riverpod StateNotifier with CRUD operations + calculation call.

**Step 3: KPR Screens**

- **KPR List Screen:** Shows saved simulations with summary cards (property price, monthly payment, total interest)
- **KPR Form Screen:** Input form with fields:
  - Property price, down payment, tenor (years/months)
  - Interest type selector (fixed/floating/graduated/mix)
  - Rate configuration fields (rate %, graduated increment, period configs)
  - "Calculate" button → shows result
- **KPR Schedule Screen:** Table view of monthly schedule
  - Collapsible by year
  - Current month highlighted
  - Summary at top: monthly payment, this month interest, total interest

---

### Task 2.5: Backend — Credit Card Tables

**Objective:** Create credit card tables in SCHEMA_SQL.

**Files:**
- Modify: `backend/app/database.py`

```sql
CREATE TABLE IF NOT EXISTS credit_cards (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    card_number_last4 TEXT DEFAULT '',
    billing_date INTEGER NOT NULL DEFAULT 1,  -- day of month (1-31)
    due_date INTEGER NOT NULL DEFAULT 15,     -- day of month (1-31)
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
    start_month TEXT NOT NULL,  -- YYYY-MM
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_cc_installments_card ON credit_card_installments(card_id);
```

---

### Task 2.6: Backend — Credit Card API Endpoints

**Objective:** Create REST API for credit card management.

**Files:**
- Create: `backend/app/schemas/credit_card.py`
- Create: `backend/app/routers/credit_cards.py`
- Modify: `backend/app/main.py`

**API Endpoints:**

```
# Cards
POST   /credit-cards                    — Create card
GET    /credit-cards                    — List cards
GET    /credit-cards/{id}               — Get card details
PUT    /credit-cards/{id}               — Update card
DELETE /credit-cards/{id}               — Delete card

# Transactions
POST   /credit-cards/{id}/transactions               — Add transaction
GET    /credit-cards/{id}/transactions                — List transactions
DELETE /credit-cards/{id}/transactions/{txn_id}       — Delete transaction

# Installments
POST   /credit-cards/{id}/installments                — Add installment
GET    /credit-cards/{id}/installments                — List installments
PUT    /credit-cards/{id}/installments/{inst_id}      — Update installment
DELETE /credit-cards/{id}/installments/{inst_id}      — Delete installment

# Projections
GET    /credit-cards/next-month-projection            — Expected next month amounts
```

---

### Task 2.7: Mobile — Credit Card Screens

**Objective:** Create Flutter UI for credit card tracker.

**Files:**
- Create: `mobile/lib/features/debt/models/credit_card_model.dart`
- Create: `mobile/lib/features/debt/credit_card/providers/credit_card_provider.dart`
- Create: `mobile/lib/features/debt/credit_card/ui/credit_card_list_screen.dart`
- Create: `mobile/lib/features/debt/credit_card/ui/credit_card_detail_screen.dart`
- Create: `mobile/lib/features/debt/credit_card/ui/add_installment_screen.dart`
- Create: `mobile/lib/features/debt/ui/debt_home_screen.dart`

**Step 1: Models + Providers**

Following same pattern as existing features (transaction_repository, provider).

**Step 2: Screens**

- **Debt Home Screen:** Tab/segment view switching between KPR and Credit Cards
- **Credit Card List:** Cards with balance, limit, upcoming installments
- **Credit Card Detail:** Transactions list + installments list for one card
- **Add Installment Form:** Description, total amount, monthly amount, months, start month

---

### PHASE 3: Integration & Navigation

---

### Task 3.1: Navigation Integration

**Objective:** Wire everything into the app's GoRouter and bottom nav.

**Files:**
- Modify: `mobile/lib/app.dart`

**New routes:**
```
/debt              → DebtHomeScreen (KPR + CC menu)
/debt/kpr          → KPR List Screen
/debt/kpr/new      → KPR Form Screen  
/debt/kpr/{id}     → KPR Schedule Screen
/debt/cards        → Credit Card List
/debt/cards/{id}   → Credit Card Detail
/debt/cards/{id}/installments/new → Add Installment
/notifications     → Notification List Screen
```

**Navigation:**
- Add "Debt" tab or entry in existing navigation (maybe replace or add to bottom nav bar)
- Add notification bell icon in app bar (persistent across pages)

---

### Task 3.2: Backend Tests

**Objective:** Write pytest tests for new endpoints.

**Files:**
- Create: `backend/tests/test_notifications.py`
- Create: `backend/tests/test_kpr.py`
- Create: `backend/tests/test_credit_cards.py`

**Test coverage:**
- Notification CRUD
- KPR calculation edge cases (different rate types)
- Credit card CRUD + installment projections

---

### Task 3.3: Mobile Tests

**Objective:** Write widget/provider tests for new features.

**Files:**
- Create: `mobile/test/features/kpr_provider_test.dart`
- Create: `mobile/test/features/credit_card_provider_test.dart`

---

## Summary (estimation)

| Phase | Tasks | Files | Est. Time |
|-------|-------|-------|-----------|
| 0.1 DB Backup | 5 | 2 | 15 min |
| 0.2 Indexes | 2 | 1 | 10 min |
| 1.1 Notif Table | 4 | 3 | 20 min |
| 1.2 Notif API | 2 | 2 | 15 min |
| 1.3 Transaction trigger | 1 | 1 | 10 min |
| 1.4 Mobile Provider | 1 | 1 | 20 min |
| 1.5 Mobile Screen | 2 | 2 | 30 min |
| 2.1 KPR Tables | 1 | 1 | 10 min |
| 2.2 KPR Engine | 1 | 1 | 30 min |
| 2.3 KPR API | 3 | 3 | 30 min |
| 2.4 KPR Mobile | 5 | 5 | 60 min |
| 2.5 CC Tables | 1 | 1 | 10 min |
| 2.6 CC API | 3 | 3 | 30 min |
| 2.7 CC Mobile | 6 | 6 | 60 min |
| 3.1 Navigation | 1 | 1 | 15 min |
| 3.2 Backend Tests | 3 | 3 | 30 min |
| 3.3 Mobile Tests | 2 | 2 | 30 min |
| **Total** | **43** | **37** | **~6h** |
