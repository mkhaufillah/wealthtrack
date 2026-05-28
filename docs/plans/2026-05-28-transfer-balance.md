# Transfer Balance Between Household Members — Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Allow a household member to transfer money to other members, creating expense transactions for the sender and income transactions for each recipient.

**Architecture:** Backend-only for this phase. A new `POST /api/v1/transactions/transfer` endpoint accepts a sender (authenticated user), a date, and a list of {recipient_id, amount} pairs. Each pair generates 2 transactions: an expense for the sender (category "Kebutuhan Rumah Tangga / Household Needs") and an income for the recipient (category "Penghasilan Rumah Tangga / Household Income"). If the special categories don't exist, they are created on-the-fly.

**Tech Stack:** FastAPI, SQLite (existing), Pydantic (existing schemas), pytest (existing test suite)

---

## Task Breakdown

### Task 1: Add Transfer schemas

**Objective:** Create Pydantic models for the transfer request and response.

**Files:**
- Modify: `backend/app/schemas/transaction.py` (append new models)

**Step 1: Add models**

Append to `backend/app/schemas/transaction.py`:

```python
class TransferItem(BaseModel):
    user_id: int = Field(gt=0, description="Recipient user ID")
    amount: int = Field(gt=0, description="Amount to transfer")


class TransferRequest(BaseModel):
    date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$", description="YYYY-MM-DD")
    transfers: list[TransferItem] = Field(min_length=1, max_length=10)


class TransferResult(BaseModel):
    sender_expense: TransactionOut
    recipient_income: TransactionOut


class TransferResponse(BaseModel):
    transactions: list[TransferResult]
```

**Step 2: Verify no syntax errors**

Run: `cd ~/dev/wealthtrack/backend && python -c "from app.schemas.transaction import TransferRequest, TransferResponse, TransferItem; print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add backend/app/schemas/transaction.py
git commit -m "feat: add transfer balance schemas"
```

---

### Task 2: Write failing tests for transfer endpoint

**Objective:** Write tests for the transfer endpoint before implementing it.

**Files:**
- Modify: `backend/tests/test_transactions.py` (append new test class)

**Step 1: Add test class**

Append to `backend/tests/test_transactions.py`:

```python
class TestTransferBalance:
    async def test_transfer_to_one_member(self, client, filla_token):
        """Transfer from filla to nahda creates 2 transactions."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 3000000}],
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert "transactions" in data
        assert len(data["transactions"]) == 1
        t = data["transactions"][0]
        # Sender expense
        assert t["sender_expense"]["type"] == "expense"
        assert t["sender_expense"]["amount"] == 3000000
        assert t["sender_expense"]["user"]["id"] == 1
        # Recipient income
        assert t["recipient_income"]["type"] == "income"
        assert t["recipient_income"]["amount"] == 3000000
        assert t["recipient_income"]["user"]["id"] == 2

    async def test_transfer_to_multiple_members(self, client, filla_token):
        """Transfer to 2 members creates 4 transactions (2 pairs)."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [
                    {"user_id": 2, "amount": 3000000},
                    {"user_id": 2, "amount": 500000},
                ],
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        assert len(data["transactions"]) == 2
        # Verify amounts
        amounts_expense = [
            t["sender_expense"]["amount"] for t in data["transactions"]
        ]
        assert sorted(amounts_expense) == [500000, 3000000]

    async def test_transfer_requires_auth(self, client):
        """Without auth token, returns 401."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 1000}],
            },
        )
        assert resp.status_code == 401

    async def test_transfer_outside_household_fails(
        self, client, filla_token
    ):
        """Cannot transfer to user outside household."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 999, "amount": 1000}],
            },
        )
        assert resp.status_code == 400

    async def test_transfer_zero_amount(self, client, filla_token):
        """Amount must be > 0 — returns 422."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 0}],
            },
        )
        assert resp.status_code == 422

    async def test_transfer_empty_list(self, client, filla_token):
        """Empty transfers list returns 422."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={"date": "2026-05-28", "transfers": []},
        )
        assert resp.status_code == 422

    async def test_transfer_updates_summary(
        self, client, filla_token
    ):
        """After transfer, sender's expense and recipient's income appear in summaries."""
        # Do transfer
        await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 2000000}],
            },
        )
        # Check filla's summary
        resp = await client.get(
            "/api/v1/summaries/daily?date_from=2026-05-28&date_to=2026-05-28",
            headers={"Authorization": f"Bearer {filla_token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        # Filla's expense should include transfer
        filla_user = [u for u in data["by_user"] if u["display_name"] == "Filla"]
        assert len(filla_user) > 0
        assert filla_user[0]["total_expense"] >= 2000000

        # Check nahda's summary (using nahda_token)
    async def test_transfer_categories_exist(
        self, client, filla_token
    ):
        """Transfer endpoint ensures the special transfer categories exist."""
        resp = await client.post(
            "/api/v1/transactions/transfer",
            headers={"Authorization": f"Bearer {filla_token}"},
            json={
                "date": "2026-05-28",
                "transfers": [{"user_id": 2, "amount": 100000}],
            },
        )
        assert resp.status_code == 201
        data = resp.json()
        t = data["transactions"][0]
        assert t["sender_expense"]["category"]["name"] == "Kebutuhan Rumah Tangga"
        assert t["recipient_income"]["category"]["name"] == "Penghasilan Rumah Tangga"
```

**Step 2: Run tests to verify they fail**

Run: `cd ~/dev/wealthtrack && source .venv/bin/activate && pytest backend/tests/test_transactions.py::TestTransferBalance -v`
Expected: 6 FAILED — "Failed: NOT FOUND" (endpoint doesn't exist yet)

**Step 3: Commit**

```bash
git add backend/tests/test_transactions.py
git commit -m "test: add failing tests for transfer balance endpoint"
```

---

### Task 3: Implement transfer endpoint

**Objective:** Add the `POST /api/v1/transactions/transfer` endpoint to the transactions router.

**Files:**
- Modify: `backend/app/routers/transactions.py`

**Step 1: Add endpoint**

Add to `backend/app/routers/transactions.py` after the existing `router_transfer_owner` endpoint:

```python
@router.post("/transfer", response_model=TransferResponse, status_code=201)
async def transfer_balance(
    req: TransferRequest,
    db: AsyncIterator[Connection] = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Transfer balance to household members.
    Creates expense transactions for sender and income transactions for each recipient.
    """
    user_id = current_user["id"]
    conn = await anext(db)

    # 1. Verify user is in a household
    member = await conn.execute_fetchall(
        "SELECT household_id, role FROM household_members WHERE user_id = ?",
        (user_id,),
    )
    if not member:
        raise HTTPException(status_code=400, detail="Not a member of any household")
    household_id = member[0]["household_id"]
    user_role = member[0]["role"]

    # 2. Verify all recipients are in the same household
    recipient_ids = [t.user_id for t in req.transfers]
    placeholders = ",".join("?" * len(recipient_ids))
    rows = await conn.execute_fetchall(
        f"SELECT user_id FROM household_members WHERE household_id = ? AND user_id IN ({placeholders})",
        (household_id, *recipient_ids),
    )
    valid_ids = {r["user_id"] for r in rows}
    for rid in recipient_ids:
        if rid not in valid_ids:
            raise HTTPException(
                status_code=400,
                detail=f"User {rid} is not a member of your household",
            )

    # 3. Ensure the special transfer categories exist
    #    Expense: "Kebutuhan Rumah Tangga" (type=expense)
    #    Income: "Penghasilan Rumah Tangga" (type=income)
    expense_cat = await conn.execute_fetchall(
        "SELECT id FROM categories WHERE name = ? AND type = ?",
        ("Kebutuhan Rumah Tangga", "expense"),
    )
    if not expense_cat:
        await conn.execute(
            "INSERT INTO categories (name, type, icon, is_default) VALUES (?, ?, ?, ?)",
            ("Kebutuhan Rumah Tangga", "expense", "🏠", 1),
        )
    expense_cat = await conn.execute_fetchall(
        "SELECT id, name, icon FROM categories WHERE name = ? AND type = ?",
        ("Kebutuhan Rumah Tangga", "expense"),
    )

    income_cat = await conn.execute_fetchall(
        "SELECT id, name, icon FROM categories WHERE name = ? AND type = ?",
        ("Penghasilan Rumah Tangga", "income"),
    )
    if not income_cat:
        await conn.execute(
            "INSERT INTO categories (name, type, icon, is_default) VALUES (?, ?, ?, ?)",
            ("Penghasilan Rumah Tangga", "income", "🏠", 1),
        )
    income_cat = await conn.execute_fetchall(
        "SELECT id, name, icon FROM categories WHERE name = ? AND type = ?",
        ("Penghasilan Rumah Tangga", "income"),
    )

    expense_cat_id = expense_cat[0]["id"]
    expense_cat_name = expense_cat[0]["name"]
    expense_cat_icon = expense_cat[0]["icon"]
    income_cat_id = income_cat[0]["id"]
    income_cat_name = income_cat[0]["name"]
    income_cat_icon = income_cat[0]["icon"]

    # 4. Create transactions
    results = []
    for t in req.transfers:
        now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%fZ")

        # Sender expense
        cursor = await conn.execute(
            """INSERT INTO transactions (type, amount, category_id, category_name, description, date, user_id, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                "expense",
                t.amount,
                expense_cat_id,
                expense_cat_name,
                f"Transfer to user {t.user_id}",
                req.date,
                user_id,
                now,
            ),
        )
        expense_id = cursor.lastrowid

        # Recipient income
        cursor = await conn.execute(
            """INSERT INTO transactions (type, amount, category_id, category_name, description, date, user_id, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                "income",
                t.amount,
                income_cat_id,
                income_cat_name,
                f"Transfer from user {user_id}",
                req.date,
                t.user_id,
                now,
            ),
        )
        income_id = cursor.lastrowid

        # Build response objects
        # Fetch the just-inserted rows for proper TransactionOut format
        exp_txn = await conn.execute_fetchall(
            """SELECT t.*, c.name as cat_name, c.icon as cat_icon,
                      u.display_name as user_display_name
               FROM transactions t
               JOIN categories c ON t.category_id = c.id
               JOIN users u ON t.user_id = u.id
               WHERE t.id = ?""",
            (expense_id,),
        )
        inc_txn = await conn.execute_fetchall(
            """SELECT t.*, c.name as cat_name, c.icon as cat_icon,
                      u.display_name as user_display_name
               FROM transactions t
               JOIN categories c ON t.category_id = c.id
               JOIN users u ON t.user_id = u.id
               WHERE t.id = ?""",
            (income_id,),
        )

        results.append({
            "sender_expense": _row_to_txn_out(exp_txn[0]),
            "recipient_income": _row_to_txn_out(inc_txn[0]),
        })

    await conn.commit()
    return {"transactions": results}
```

This needs a helper function `_row_to_txn_out` that converts a sqlite3.Row to TransactionOut. Let me check if one already exists.

Actually, looking at the existing code, the transactions router has a pattern of building TransactionOut objects inline. Let me follow the same pattern but extract a helper to avoid duplication.

Let me check the existing code pattern first.

**Step 2: Add helper function**

Add at the module level in `transactions.py`:

```python
def _row_to_txn_out(row: sqlite3.Row) -> dict:
    """Convert a transaction DB row to TransactionOut-compatible dict."""
    return {
        "id": row["id"],
        "amount": row["amount"],
        "type": row["type"],
        "description": row["description"],
        "note": row["note"] or "",
        "date": row["date"],
        "category": {
            "id": row["category_id"],
            "name": row["cat_name"],
            "icon": row["cat_icon"],
        },
        "user": {
            "id": row["user_id"],
            "display_name": row["user_display_name"],
        },
        "created_at": row["created_at"],
        "updated_at": row.get("created_at", ""),
    }
```

Also add `import sqlite3` at the top if not already there.

**Step 3: Add necessary imports**

Ensure `TransferRequest, TransferResponse, TransferResult` are imported from schemas. And `datetime` is imported.

**Step 4: Run tests to verify they pass**

Run: `cd ~/dev/wealthtrack && source .venv/bin/activate && pytest backend/tests/test_transactions.py::TestTransferBalance -v`
Expected: all tests pass

**Step 5: Run full test suite to check regressions**

Run: `cd ~/dev/wealthtrack && source .venv/bin/activate && pytest backend/tests/ -v`
Expected: all existing tests pass

**Step 6: Commit**

```bash
git add backend/app/routers/transactions.py backend/app/schemas/transaction.py
git commit -m "feat: implement transfer balance between household members"
```

---

### Task 4: Update API documentation

**Objective:** Document the new transfer endpoint in the API spec.

**Files:**
- Modify: `docs/03-backend-api.md` (append new section after transaction endpoints)

**Step 1: Add Transfer Balance section**

Append to `docs/03-backend-api.md` after the transfer-owner section:

```markdown
### POST `/api/v1/transactions/transfer`

Transfer balance to one or more household members. Creates paired expense/income transactions.

```json
// Request
{
  "date": "2026-05-28",
  "transfers": [
    {"user_id": 2, "amount": 3000000},
    {"user_id": 3, "amount": 500000}
  ]
}

// Response 201
{
  "transactions": [
    {
      "sender_expense": { ...full transaction object, type: "expense" },
      "recipient_income": { ...full transaction object, type: "income" }
    }
  ]
}
```

**Validation:**
- Sender must be a member of a household
- All recipients must be in the same household as the sender
- Amount must be > 0
- At least 1 recipient, max 10 recipients
- Categories "Kebutuhan Rumah Tangga" (expense) and "Penghasilan Rumah Tangga" (income) are auto-created if they don't exist
```

**Step 2: Update P4 plan**

Add the transfer feature to `docs/08-p4-plan.md` with status "✅ Done".

**Step 3: Commit**

```bash
git add docs/03-backend-api.md docs/08-p4-plan.md
git commit -m "docs: document transfer balance endpoint"
```

---

### Verification Checklist

- [ ] All tests pass
- [ ] No regressions in existing tests
- [ ] Transfer creates sender expense + recipient income per pair
- [ ] Special categories auto-created
- [ ] Non-household recipient rejected with 400
- [ ] Unauthenticated request returns 401
- [ ] Empty transfers list rejected with 422
- [ ] API doc updated
