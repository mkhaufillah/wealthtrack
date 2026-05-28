# Transfer Balance

**Feature added:** 2026-05-28 · Commit: `8a8ace8`
**See also:** [Backend API](03-backend-api.md) · [Database Schema](02-database-schema.md) · [Hermes Integration](06-hermes-integration.md) · [P4 Plan](08-p4-plan.md)

---

## Overview

Allows a household member to transfer money to other members, creating an expense for the sender and an income for each recipient — all recorded under the **"Transfer"** category with icon 🔄. Each transfer pair is atomic: sender expense + recipient income are committed together in a single request.

Supports 1–10 recipients per call, enabling batch transfers (e.g. splitting an allowance across multiple members).

---

## Architecture

```
POST /api/v1/transactions/transfer
  │
  ├── Validate sender is in a household
  ├── Validate all recipients are in the same household
  ├── Auto-create "Transfer" (expense) + "Transfer" (income) categories if missing
  │
  ├── For each {user_id, amount}:
  │   ├── INSERT expense  (sender's user_id,  type=expense,  cat="Transfer")
  │   └── INSERT income   (recipient's user_id, type=income,   cat="Transfer")
  │
  └── Commit all → return TransferResponse
```

**Key design choices:**
- Both sender and recipient transactions use the same category name `"Transfer"`, differentiated by `type` (expense/income)
- Categories are auto-created on first use — no manual seed migration needed
- All transfers are wrapped in a single DB transaction (commit once at the end)

---

## Backend

### Schemas

**File:** `backend/app/schemas/transaction.py`

| Model | Fields |
|-------|--------|
| `TransferItem` | `user_id: int`, `amount: int` (gt=0) |
| `TransferRequest` | `date: str` (YYYY-MM-DD), `transfers: list[TransferItem]` (1–10) |
| `TransferResult` | `sender_expense: TransactionOut`, `recipient_income: TransactionOut` |
| `TransferResponse` | `transactions: list[TransferResult]` |

### Endpoint

**`POST /api/v1/transactions/transfer`** — `backend/app/routers/transactions.py`

```python
@router.post("/transfer", response_model=TransferResponse, status_code=201)
async def transfer_balance(
    req: TransferRequest,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
```

**Flow:**
1. Verify sender belongs to a household (from `household_members`)
2. Verify **all** recipient `user_id`s are in the same household
3. Auto-create `"Transfer"` (expense) and `"Transfer"` (income) categories if they don't exist
4. For each transfer item:
   - Insert expense for sender (`"Transfer to user {recipient_id}"`)
   - Insert income for recipient (`"Transfer from user {sender_id}"`)
5. Commit & return all transaction pairs

**Validation:**
- Sender must be a household member → `400`
- Recipient must be in the same household → `400`
- Amount must be > 0 (Pydantic `Field(gt=0)`) → `422`
- Empty transfers list → `422`
- More than 10 recipients → `422`
- No auth token → `401`

### Category Auto-Creation

```python
# Expense side
cursor = await db.execute(
    "SELECT id, name, icon FROM categories WHERE name = ? AND type = ?",
    ("Transfer", "expense"),
)
if not expense_cat:
    await db.execute(
        "INSERT INTO categories (name, type, icon, is_default) VALUES (?, ?, ?, ?)",
        ("Transfer", "expense", "🔄", 1),
    )

# Income side — same name, different type
cursor = await db.execute(
    "SELECT id, name, icon FROM categories WHERE name = ? AND type = ?",
    ("Transfer", "income"),
)
```

---

## Hermes Skill Integration

### finance_db.py — Seed Categories

**File:** `~/.hermes/skills/productivity/financial-tracker/scripts/finance_db.py`

"Transfer" was added to both `INCOME_CATEGORIES` and `EXPENSE_CATEGORIES` seed lists so the Hermes cron recognizes them:

```python
INCOME_CATEGORIES = [
    ...
    ("Transfer", "income", "🔄", 0, 6),
]

EXPENSE_CATEGORIES = [
    ...
    ("Transfer", "expense", "🔄", 0, 11),
]
```

### finance_db.py — Keyword Classification

Keywords added to `EXPENSE_KEYWORDS` and `INCOME_KEYWORDS` so transactions added via the Hermes CLI (`python finance_db.py add ...`) auto-classify as "Transfer":

```python
EXPENSE_KEYWORDS = {
    ...
    "Transfer": ["transfer ke", "transfer untuk"],
}

INCOME_KEYWORDS = {
    ...
    "Transfer": ["transfer dari"],
    ...
}
```

**Resolution order:** Existing categories are checked first — a description like "transfer gaji bulan ini" still correctly classifies as "Gaji" because `INCOME_KEYWORDS["Gaji"]` is checked before `INCOME_KEYWORDS["Transfer"]`.

### household_report.py — Icon Mapping

**File:** `~/.hermes/scripts/household_report.py`

Added icon mapping so "Transfer" displays with 🔄 in the daily WhatsApp report:

```python
elif "Transfer" in cat:
    cat_icon = "🔄"
```

---

## Flutter

### category_translator.dart

**File:** `mobile/lib/shared/utils/category_translator.dart`

```dart
'Transfer': 'Transfer',
```

Same name in both languages (short enough to not need translation).

---

## Budgets

Budget tracking works with any category — no code changes needed. Users can create a budget entry for the "Transfer" (expense) category via `POST /api/v1/budgets` to cap monthly transfers. The `/api/v1/budgets/summary` endpoint correctly reports actual vs budgeted amounts for Transfer spending.

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Recipient is the sender | Allowed — creates expense & income for same user (no guard; treat as wallet-to-wallet entry) |
| Transfer to non-existent user | `400` — caught by household membership check |
| Multiple transfers to same recipient | Each becomes a separate transaction pair (no merge) |
| Category deleted between calls | Re-created on next transfer — `is_default=1` prevents deletion from regular UI |
| Sender has no household | `400` — "Not a member of any household" |
| Amount exceeds sender's expense balance | No check — WealthTrack is not a double-entry ledger; transactions are records, not balances |

---

## Test Coverage

| Layer | Tests | File |
|-------|-------|------|
| Backend (API) | 8 tests — single, multi, auth, outside household, zero amount, empty list, category names, summary update | `backend/tests/test_transactions.py::TestTransferBalance` |

---

## Files Changed

| File | Change |
|------|--------|
| `backend/app/schemas/transaction.py` | +4 new Pydantic models: `TransferItem`, `TransferRequest`, `TransferResult`, `TransferResponse` |
| `backend/app/routers/transactions.py` | +`POST /transfer` endpoint with category auto-creation |
| `backend/tests/test_transactions.py` | +8 tests in `TestTransferBalance` class |
| `docs/03-backend-api.md` | +API documentation for transfer endpoint |
| `docs/08-p4-plan.md` | Marked transfer feature as ✅ Done |
| `mobile/lib/shared/utils/category_translator.dart` | +`'Transfer': 'Transfer'` mapping |

### Outside repo (Hermes skill/script)

| File | Change |
|------|--------|
| `finance_db.py` | +"Transfer" in `INCOME_CATEGORIES`, `EXPENSE_CATEGORIES`, `EXPENSE_KEYWORDS`, `INCOME_KEYWORDS` |
| `household_report.py` | +icon mapping `"Transfer" → "🔄"` |
