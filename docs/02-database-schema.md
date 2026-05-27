# Database Schema — WealthTrack

**See also:** [Project Overview](01-project-overview.md) · [Backend API](03-backend-api.md) · [Backend Implementation](04-backend-implementation.md) · [P4 Plan](08-p4-plan.md)



## Database File

**Path:** `~/.keuangan/finance.db` (existing database, 24KB, 27 transactions)

> Uses the existing database from the `financial-tracker` skill. All existing data remains safe.
> Cron and `financial-tracker` skill remain fully compatible — no changes needed.

## Configuration

```sql
PRAGMA journal_mode = WAL;          -- concurrent reads + writes
PRAGMA foreign_keys = ON;           -- enforce FK constraints
PRAGMA busy_timeout = 5000;         -- wait 5s before giving up on lock
```

## Existing Tables (untouched)

### `categories` — unchanged

```sql
CREATE TABLE IF NOT EXISTS categories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    type        TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    icon        TEXT DEFAULT '',
    is_default  INTEGER DEFAULT 0,
    sort_order  INTEGER DEFAULT 0
);
```

15 categories seeded: 5 income + 10 expense (from `finance_db.py`).

### `budgets` — unchanged

```sql
CREATE TABLE IF NOT EXISTS budgets (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    month         TEXT NOT NULL,
    category_id   INTEGER,
    category_name TEXT,
    budget_amount REAL NOT NULL,
    UNIQUE(month, category_name),
    FOREIGN KEY (category_id) REFERENCES categories(id)
);
```

## New Table (added by WealthTrack)

### `users`

```sql
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT NOT NULL UNIQUE,
    display_name  TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'user',
    created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
```

Seed data:
| id | username | display_name |
|----|----------|-------------|
| 1 | filla | Filla |
| 2 | nahda | Nahda |

## Modified Table — `transactions`

### Existing columns (untouched, for backward compatibility)

```sql
CREATE TABLE IF NOT EXISTS transactions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    type          TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    amount        REAL NOT NULL,
    category_id   INTEGER,
    category_name TEXT,
    description   TEXT,
    source        TEXT DEFAULT 'manual',
    image_path    TEXT,
    created_at    TEXT DEFAULT (datetime('now', 'localtime')),
    -- NEW columns added via ALTER TABLE:
    -- user_id      INTEGER REFERENCES users(id),
    -- date         TEXT,
    -- note         TEXT DEFAULT ''
);
```

### New columns (added via migration, not CREATE TABLE)

```sql
ALTER TABLE transactions ADD COLUMN user_id INTEGER REFERENCES users(id);
ALTER TABLE transactions ADD COLUMN date TEXT;
ALTER TABLE transactions ADD COLUMN note TEXT DEFAULT '';
```

**Backward compatibility:**
- Old transactions: `user_id = NULL`, `date = NULL`, `note = ''`
- Script `finance_db.py` can still INSERT because it uses explicit column names (not `INSERT *`)
- FastAPI can read all data, old + new
- Cron keeps running without changes

## Migration Script

Run once after WealthTrack deployment. Safe to run multiple times (checks column existence).

```python
import sqlite3
import os

DB_PATH = os.path.expanduser("~/.keuangan/finance.db")

def migrate():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys=OFF;")  # allow ALTER during migration

    # 1. Create users table
    conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'user',
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
        );
    """)

    # 2. Seed default users
    users = [
        (1, 'filla', 'Filla', '$2b$12$LJ3m4ys3Lk0TSwHCpNqrPOkODhBIjs5y7Kwe5mCpMOABsERy7aEJa', 'admin'),
        (2, 'nahda', 'Nahda', '$2b$12$LJ3m4ys3Lk0TSwHCpNqrPOkODhBIjs5y7Kwe5mCpMOABsERy7aEJa', 'user'),
    ]
    for uid, uname, dname, pw_hash, role in users:
        conn.execute(
            "INSERT OR IGNORE INTO users (id, username, display_name, password_hash, role) VALUES (?, ?, ?, ?, ?)",
            (uid, uname, dname, pw_hash, role)
        )

    # 3. Add new columns to transactions (safe: checks existence first)
    cursor = conn.execute("PRAGMA table_info(transactions)")
    existing_cols = [row[1] for row in cursor.fetchall()]

    if 'user_id' not in existing_cols:
        conn.execute("ALTER TABLE transactions ADD COLUMN user_id INTEGER REFERENCES users(id)")
    if 'date' not in existing_cols:
        conn.execute("ALTER TABLE transactions ADD COLUMN date TEXT")
    if 'note' not in existing_cols:
        conn.execute("ALTER TABLE transactions ADD COLUMN note TEXT DEFAULT ''")

    # 4. Backfill: set user_id = 1 (filla) for old transactions
    conn.execute("UPDATE transactions SET user_id = 1 WHERE user_id IS NULL")

    # 5. Backfill: set date = created_at for old transactions that have NULL date
    conn.execute("UPDATE transactions SET date = substr(created_at, 1, 10) WHERE date IS NULL AND created_at IS NOT NULL")

    conn.commit()
    conn.close()
    print("Migration complete.")

if __name__ == "__main__":
    migrate()
```

## Schema Diagram (after migration)

```
┌──────────────┐       ┌───────────────────────────────────┐       ┌──────────────┐
│    users     │       │           transactions            │       │  categories  │
├──────────────┤       ├───────────────────────────────────┤       ├──────────────┤
│ id (PK)      │◄──────│ user_id (FK)                      │       │ id (PK)      │
│ username     │       │ id (PK)                           │◄──────│ category_id  │
│ display_name │       │ type                              │       │ name         │
│ password_hash│       │ amount     (REAL, in Rupiah)      │       │ type         │
│ role         │       │ category_id (FK → categories)     │       │ icon         │
│ created_at   │       │ category_name (denormalized)      │       │ is_default   │
└──────────────┘       │ description                       │       │ sort_order   │
                       │ source       ('manual','api',etc) │       └──────────────┘
                       │ image_path   (invoice photo)      │
                       │ user_id      (NEW)                │       ┌──────────────┐
                       │ date         (NEW: YYYY-MM-DD)    │       │   budgets    │
                       │ note         (NEW: optional)      │       ├──────────────┤
                       │ created_at   (timestamp)          │       │ id (PK)      │
                       └───────────────────────────────────┘       │ month        │
                                                                   │ category_id  │
                                                                   │ category_name│
                                                                   │ budget_amount│
                                                                   └──────────────┘
```

## Amount Format

All amounts stored as REAL (float, integer in IDR) — compatible with `finance_db.py`.
No decimals. Display formatting is done in Flutter / Hermes output.

## Backup

Due to this single file: backup = copy file.

```bash
cp ~/.keuangan/finance.db ~/wealthtrack-backups/finance-$(date +%Y%m%d).db
```
