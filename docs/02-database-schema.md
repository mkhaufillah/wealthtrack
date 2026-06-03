# Database Schema — WealthTrack

**See also:** [Project Overview](01-project-overview.md) · [Backend API](03-backend-api.md) · [Backend Implementation](04-backend-implementation.md) · [P4 Plan](08-p4-plan.md)

> ⚠️ **v0.5.0+** App now runs on **PostgreSQL** via asyncpg pool.
> Legacy SQLite (`~/.keuangan/finance.db`) preserved as backup only.
> This doc documents the current PostgreSQL schema.

## Database

| Item | Value |
|------|-------|
| Engine | PostgreSQL 16 |
| Connection | asyncpg pool (`DATABASE_URL` env var) |
| Pool | min 2, max 10 connections |
| Legacy backup | `~/.keuangan/finance.db` (SQLite, read-only) |

## Configuration

No PRAGMA needed — PostgreSQL uses its own config via `postgresql.conf`.

Key settings applied by the driver:
- `application_name=wealthtrack`
- `statement_cache_size=100`

## Tables

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

### `budgets` — updated (user_id, category_id, UNIQUE constraint)

```sql
CREATE TABLE IF NOT EXISTS budgets (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id       INTEGER NOT NULL REFERENCES users(id),
    month         TEXT NOT NULL,
    category_id   INTEGER,
    category_name TEXT,
    budget_amount REAL NOT NULL,
    UNIQUE(user_id, month, category_id),
    FOREIGN KEY (category_id) REFERENCES categories(id)
);
```

### Transfer Categories

Two special categories are auto-created for the transfer balance feature:

| id | name | type | icon | is_default | sort_order |
|----|------|------|------|-----------|------------|
| 16 | Transfer | expense | 🔄 | 0 | 100 |
| 17 | Transfer | income | 🔄 | 0 | 100 |

These are used by `POST /api/v1/transactions/transfer` to create paired expense (sender) and income (recipient) transactions. They are auto-created by the backend if they don't already exist.

## New Table (added by WealthTrack)

### `users`

```sql
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT NOT NULL UNIQUE,
    display_name  TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'user',
    email         TEXT DEFAULT '',
    cycle_start_day INTEGER NOT NULL DEFAULT 1,
    created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
```

Partial unique index on email (ignores empty strings):
```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email != '';
```

Seed data:
| id | username | display_name | email |
|----|----------|-------------|-------|
| 1 | filla | Filla | khaufillahmohammad@gmail.com |
| 2 | nahda | Nahda | nahdanurfitriana3@gmail.com |

### `email_verifications`

```sql
CREATE TABLE IF NOT EXISTS email_verifications (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    email      TEXT NOT NULL,
    code       TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    verified   INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
```

Used for registration OTP flow. OTPs expire after 10 minutes. Each email can have multiple entries (latest one is checked).

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

## Migration (PostgreSQL)

The database is created from scratch via:

```bash
cd ~/dev/wealthtrack
python backend/scripts/export_to_postgres.py   # reads SQLite, writes postgres_migration.sql
PGPASSWORD=wealthtrack123 psql -U wealthtrack -d wealthtrack -h localhost -f postgres_migration.sql
```

For **new VPS deployment** (no SQLite available):

```sql
-- Run the schema section from postgres_migration.sql
-- Then restore from a pg_dump backup
```

## Legacy migration (original SQLite → WealthTrack)

The old `backend/app/migrate_db.py` was kept for reference but no longer needed at runtime. It handled:

- Creating users, budgets, households, ocr_jobs, ai_messages tables
- Adding columns to existing SQLite transactions table
- Seeding default users and categories
- Backfilling English names and keywords
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
                       │ created_at   (timestamp)          │       │ user_id (FK)  │──► users
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
