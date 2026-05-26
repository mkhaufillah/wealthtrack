# Database Schema — WealthTrack

## Configuration (mandatory)

Enable these PRAGMAs on every connection:

```sql
PRAGMA journal_mode = WAL;          -- concurrent reads + writes
PRAGMA foreign_keys = ON;           -- enforce FK constraints
PRAGMA busy_timeout = 5000;         -- wait 5s before giving up on lock
```

## Table: `users`

```sql
CREATE TABLE users (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    username    TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,      -- bcrypt hash
    role        TEXT NOT NULL DEFAULT 'user',  -- 'user' | 'admin'
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
```

Seed data:
- `filla` — Filla
- `nahda` — Nahda

## Table: `categories`

```sql
CREATE TABLE categories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    type        TEXT NOT NULL CHECK(type IN ('expense','income')),
    icon        TEXT DEFAULT '',       -- emoji or icon name
    color       TEXT DEFAULT '#6C63FF',
    is_default  INTEGER NOT NULL DEFAULT 0,  -- seeded categories
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE UNIQUE INDEX idx_cat_name_type ON categories(name, type);
```

### Default Categories (seed)

| Type | Name | Icon | Color |
|------|------|------|-------|
| expense | Makan & Minum | 🍽️ | #FF6B6B |
| expense | Transportasi | 🚗 | #4ECDC4 |
| expense | Belanja Bulanan | 🛒 | #45B7D1 |
| expense | Tagihan & Listrik | 💡 | #96CEB4 |
| expense | Kesehatan | 🏥 | #FFEAA7 |
| expense | Hiburan | 🎬 | #DDA0DD |
| expense | Pendidikan | 📚 | #98D8C8 |
| expense | Hadiah & Donasi | 🎁 | #F7DC6F |
| expense | Lainnya | 📦 | #BDC3C7 |
| income | Gaji | 💰 | #2ECC71 |
| income | Bonus | 🎉 | #27AE60 |
| income | Lainnya | 💵 | #7F8C8D |

## Table: `transactions`

```sql
CREATE TABLE transactions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    category_id INTEGER NOT NULL REFERENCES categories(id),
    type        TEXT NOT NULL CHECK(type IN ('expense','income')),
    amount      INTEGER NOT NULL CHECK(amount > 0),   -- in Rupiah (IDR)
    description TEXT NOT NULL DEFAULT '',
    note        TEXT DEFAULT '',
    date        TEXT NOT NULL,                         -- 'YYYY-MM-DD'
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE INDEX idx_txn_user_date ON transactions(user_id, date);
CREATE INDEX idx_txn_category ON transactions(category_id);
CREATE INDEX idx_txn_type ON transactions(type);
```

**amount** disimpan sebagai INTEGER (IDR, in Rupiah, tanpa desimal). Format display dilakukan di Flutter / Hermes output.

## Table: `budgets` (optional, P4)

```sql
CREATE TABLE budgets (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    category_id INTEGER NOT NULL REFERENCES categories(id),
    month       TEXT NOT NULL,         -- 'YYYY-MM'
    amount      INTEGER NOT NULL,      -- budget ceiling in IDR
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(user_id, category_id, month)
);
```

## Table: `sync_log` (for diagnostics)

```sql
CREATE TABLE sync_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    source      TEXT NOT NULL,          -- 'hermes', 'api', 'flutter'
    action      TEXT NOT NULL,          -- 'insert', 'update', 'delete'
    table_name  TEXT NOT NULL,
    record_id   INTEGER,
    status      TEXT NOT NULL DEFAULT 'ok',
    message     TEXT DEFAULT '',
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
```

## Database File

**Location:** `~/.hermes/data/wealthtrack.db`

Or if you prefer a shared location: `~/dev/wealthtrack/data/wealthtrack.db`

> Recommendation: keep it at `~/.hermes/data/wealthtrack.db` so Hermes scripts can access it without path confusion. FastAPI config points to the same path.

## Migration Strategy

No migration framework. Schema is versioned in `init_db.py`.

When schema changes:
1. Write `alter_table.sql` migration in `scripts/migrate_v2.py`
2. Run manually before deploying new backend version
3. Keep backup of `.db` before migration

For MVP: no migrations needed. Schema is designed for P1-P3.
