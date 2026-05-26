# Hermes Integration — Cron & Chat Input

## Overview

Hermes connects to WealthTrack in two ways:

1. **Cron job** — Daily finance summary reads from SQLite
2. **Chat input** — User messages via Hermes agent write transactions to SQLite

Both connect **directly to SQLite** (same DB file FastAPI uses).

## Database File Location

```bash
# Both Hermes scripts and FastAPI use the same path:
~/.hermes/data/wealthtrack.db
```

## Step 1: Update Daily Finance Summary Cron

The existing cron runs `daily_finance_report.py`. This script currently reads from the old format. Update it to:

1. Connect to `~/.hermes/data/wealthtrack.db`
2. Read today's transactions
3. Generate the summary in the existing format (numbered list, grouped by user)

### Script: `~/.hermes/scripts/daily_finance_report.py`

```python
#!/usr/bin/env python3
"""Daily finance report — reads from WealthTrack SQLite database."""

import sqlite3
import os
from datetime import date
from pathlib import Path

DB_PATH = os.path.expanduser("~/.hermes/data/wealthtrack.db")

def run():
    today = date.today().isoformat()
    
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    
    # Today's transactions
    cursor = conn.execute("""
        SELECT t.*, c.name as category_name, c.icon as category_icon, 
               u.display_name as user_name
        FROM transactions t
        JOIN categories c ON t.category_id = c.id
        JOIN users u ON t.user_id = u.id
        WHERE t.date = ?
        ORDER BY t.created_at ASC
    """, (today,))
    
    rows = cursor.fetchall()
    
    if not rows:
        today_formatted = date.today().strftime("%A, %d %B %Y")
        print(f"📊 *Laporan Keuangan — {today_formatted}*")
        print()
        print("Belum ada transaksi hari ini.")
        return

    # Group by user
    by_user = {}
    for r in rows:
        name = r["user_name"]
        if name not in by_user:
            by_user[name] = []
        by_user[name].append(r)
    
    today_formatted = date.today().strftime("%A, %d %B %Y")
    print(f"📊 *Laporan Keuangan — {today_formatted}*")
    print()
    
    total_expense = 0
    total_income = 0
    
    for user_name, txns in by_user.items():
        print(f"*{user_name}*")
        for i, t in enumerate(txns, 1):
            icon = t["category_icon"] or ""
            desc = t["description"] or t["category_name"]
            amount = t["amount"]
            formatted = f"Rp{amount:,}".replace(",", ".")
            
            if t["type"] == "expense":
                print(f"{i}. {icon} {desc} — {formatted}")
                total_expense += amount
            else:
                print(f"{i}. {icon} {desc} — *+{formatted}*")
                total_income += amount
        print()
    
    if total_expense > 0:
        print(f"Total pengeluaran: Rp{total_expense:,}".replace(",", "."))
    if total_income > 0:
        print(f"Total pemasukan: Rp{total_income:,}".replace(",", "."))
    balance = total_income - total_expense
    balance_str = f"Rp{balance:,}".replace(",", ".")
    if balance >= 0:
        print(f"Sisa saldo: +{balance_str}")
    else:
        print(f"Sisa saldo: {balance_str}")
    
    conn.close()

if __name__ == "__main__":
    run()
```

### Update Cron Job

```bash
# Update existing cron job to point to new script
# Or recreate it

# First, list current cron jobs
hermes cron list
```

Then update or recreate the "Daily Finance Summary" cron:

```
hermes cron create \
  --name "Daily Finance Summary" \
  --schedule "0 13 * * *" \
  --script "daily_finance_report.py" \
  --no-agent \
  --deliver "whatsapp"
```

> The `no_agent=true` flag makes this run without LLM — the script output goes directly to WhatsApp.

## Step 2: Chat-Based Transaction Input

When the user messages Hermes to record a transaction (e.g., "beli nasi goreng 25rb"), the Hermes agent should:

1. Parse the message for: amount, description, category
2. Write directly to SQLite
3. Confirm to the user

### Create Hermes Skill: `add-transaction`

```markdown
# Add Transaction

## Trigger
User asks to record an expense or income.

## Examples
- "beli nasi goreng 25rb"
- "gaji masuk 15jt"
- "catat: makan siang 50k"
- "add expense bensin 100k transportasi"
- "pengeluaran 75rb buat gojek"

## Steps

1. Parse the message to extract:
   - `type` — "expense" (default) or "income"
   - `amount` — numeric value in Rupiah (handle: "rb" = 000, "jt" = 000000, "k" = 000)
   - `description` — what was purchased
   - `category` — optional, guess from description if not specified
   - `date` — today (default) or parse "kemarin", "tgl 3" dll

2. Write to SQLite

   ```python
   import sqlite3
   from pathlib import Path
   
   db = sqlite3.connect(str(Path.home() / ".hermes" / "data" / "wealthtrack.db"))
   db.execute(
       "INSERT INTO transactions (user_id, category_id, type, amount, description, date) VALUES (?, ?, ?, ?, ?, ?)",
       (1, cat_id, "expense", amount, description, date.isoformat())
   )
   db.commit()
   ```

3. Confirm with formatted response:
   "✅ Dicatat: Nasi Goreng — Rp25.000 (Makan & Minum)"
```

## Step 3: Chat-Based Recap ("rekap", "cek saldo")

When user asks for a recap, the Hermes agent can:

1. Read from SQLite directly
2. Use the existing reporting format (numbered list, simple)

The FastAPI summaries endpoint is available too, but direct SQLite is faster since they're co-located.

## Step 4: Sync Hermes Scripts

Store transaction scripts in `~/.hermes/scripts/`:

```
~/.hermes/scripts/
├── daily_finance_report.py   # Cron: daily summary
├── add_transaction.py        # Called by Hermes agent for chat input
└── get_summary.py            # Called by Hermes agent for recap requests
```

### Helper Script: `add_transaction.py`

```python
#!/usr/bin/env python3
"""Add transaction to WealthTrack from command line args."""

import sqlite3
import sys
import os
from pathlib import Path
from datetime import date

DB_PATH = os.path.expanduser("~/.hermes/data/wealthtrack.db")
FILLA_USER_ID = 1  # filla
NAHDA_USER_ID = 2  # nahda
# Default: user is filla unless specified

def guess_category(db, description: str) -> int:
    """Simple keyword-based category guessing."""
    keywords = {
        "makan": 1, "nasi": 1, "goreng": 1, "bakso": 1, "mie": 1,
        "minum": 1, "kopi": 1, "teh": 1, "jus": 1, "cafe": 1,
        "bensin": 2, "bensin": 2, "bbm": 2, "gojek": 2, "grab": 2,
        "ojol": 2, "taxi": 2, "parkir": 2, "toll": 2, "tol": 2,
        "belanja": 3, "sembako": 3, "pasar": 3, "supermarket": 3,
        "listrik": 4, "pln": 4, "tagihan": 4, "wifi": 4, "pdam": 4,
        "bpjs": 4, "pulsa": 4,
        "obat": 5, "dokter": 5, "rumah sakit": 5, "klinik": 5,
        "nonton": 6, "film": 6, "netflix": 6, "spotify": 6,
        "buku": 7, "kursus": 7, "les": 7, "belajar": 7,
        "hadiah": 8, "kado": 8, "donasi": 8, "sedekah": 8,
    }
    
    desc_lower = description.lower()
    for word, cat_id in keywords.items():
        if word in desc_lower:
            return cat_id
    
    # Default: return "Lainnya" (expense)
    cursor = db.execute("SELECT id FROM categories WHERE name = 'Lainnya' AND type = 'expense'")
    row = cursor.fetchone()
    return row[0] if row else 9  # fallback

def add_transaction(type_: str, amount: int, description: str, 
                    category_id: int = None, user_id: int = FILLA_USER_ID,
                    txn_date: str = None):
    """Insert a transaction into WealthTrack DB."""
    db = sqlite3.connect(DB_PATH)
    
    if category_id is None:
        category_id = guess_category(db, description)
    
    if txn_date is None:
        txn_date = date.today().isoformat()
    
    db.execute(
        """INSERT INTO transactions (user_id, category_id, type, amount, description, date)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (user_id, category_id, type_, amount, description, txn_date),
    )
    db.commit()
    
    # Get category name for response
    cursor = db.execute("SELECT name FROM categories WHERE id = ?", (category_id,))
    cat_name = cursor.fetchone()[0]
    
    db.close()
    return cat_name

if __name__ == "__main__":
    # CLI: python add_transaction.py --type expense --amount 25000 --desc "Nasi Goreng" [--category 1] [--user 1] [--date 2026-05-26]
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--type", default="expense")
    parser.add_argument("--amount", type=int, required=True)
    parser.add_argument("--desc", required=True)
    parser.add_argument("--category", type=int)
    parser.add_argument("--user", type=int, default=FILLA_USER_ID)
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()
    
    cat = add_transaction(args.type, args.amount, args.desc, args.category, args.user, args.date)
    formatted = f"Rp{args.amount:,}".replace(",", ".")
    print(f"✅ Dicatat: {args.desc} — {formatted} ({cat})")
```

## Hermes Agent Prompt for Chat Input

When user messages "beli nasi goreng 25rb", the Hermes agent should:

1. Parse: type=expense, amount=25000, description="Nasi Goreng"
2. Run: `uv run ~/.hermes/scripts/add_transaction.py --amount 25000 --desc "Nasi Goreng"`
3. Respond with confirmation

For recap: run `uv run ~/.hermes/scripts/get_summary.py` instead of querying FastAPI.

## Summary: Hermes ↔ WealthTrack Data Flow

```
User sends "beli nasi goreng 25rb"
        │
        ▼
Hermes agent parses message
        │
        ▼
Hermes calls add_transaction.py → SQLite
        │
        ▼
Hermes confirms to user ✅
        │
        ▼
Next day: cron runs daily_finance_report.py → SQLite → WhatsApp summary
        │
        ▼
Flutter can see same data via FastAPI (or direct SQLite on VPS)
```
