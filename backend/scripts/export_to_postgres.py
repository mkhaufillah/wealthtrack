"""Export SQLite data to PostgreSQL-compatible SQL dump.

Usage:
    cd ~/dev/wealthtrack
    source .venv/bin/activate
    python backend/scripts/export_to_postgres.py

Output: ~/dev/wealthtrack/postgres_migration.sql

This file has NO SQLite dependency — pure PostgreSQL SQL.
Can be run on any PostgreSQL server to recreate the data.
"""

import sqlite3
from pathlib import Path

DB_PATH = Path.home() / ".keuangan" / "finance.db"
OUTPUT = Path.home() / "dev" / "wealthtrack" / "postgres_migration.sql"

# ── PostgreSQL schema definitions ────────────────────────────────────

PG_SCHEMA = """
-- WealthTrack PostgreSQL Schema
-- Auto-generated from SQLite. Safe to re-run (uses IF NOT EXISTS).

BEGIN;

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user',
    email TEXT DEFAULT '',
    cycle_start_day INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE TABLE IF NOT EXISTS email_verifications (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    verified INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    icon TEXT DEFAULT '',
    is_default INTEGER DEFAULT 0,
    sort_order INTEGER DEFAULT 0,
    name_en TEXT DEFAULT '',
    keywords TEXT DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    amount INTEGER NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    category_name TEXT DEFAULT '',
    description TEXT DEFAULT '',
    source TEXT DEFAULT 'manual',
    image_path TEXT DEFAULT '',
    created_at TEXT DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    user_id INTEGER REFERENCES users(id),
    date TEXT,
    note TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS households (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    invite_code TEXT UNIQUE NOT NULL,
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE TABLE IF NOT EXISTS household_members (
    user_id INTEGER NOT NULL REFERENCES users(id),
    household_id INTEGER NOT NULL REFERENCES households(id),
    role TEXT NOT NULL DEFAULT 'member',
    joined_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    PRIMARY KEY (user_id, household_id)
);

CREATE TABLE IF NOT EXISTS budgets (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    month TEXT NOT NULL,
    category_id INTEGER NOT NULL,
    category_name TEXT NOT NULL,
    budget_amount INTEGER NOT NULL,
    cycle_on INTEGER NOT NULL DEFAULT 1,
    UNIQUE(user_id, month, category_id)
);

CREATE TABLE IF NOT EXISTS ocr_jobs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    image_filename TEXT,
    status TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'completed', 'failed')),
    transaction_id INTEGER REFERENCES transactions(id),
    error TEXT,
    raw_text TEXT,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    completed_at TEXT
);

CREATE TABLE IF NOT EXISTS ai_messages (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'complete', 'error', 'error:hidden')),
    model TEXT NOT NULL DEFAULT 'flash',
    parent_message_id INTEGER REFERENCES ai_messages(id),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(COALESCE(date, LEFT(created_at::text, 10)));
CREATE INDEX IF NOT EXISTS idx_budgets_user_month ON budgets(user_id, month);
CREATE INDEX IF NOT EXISTS idx_household_members_user ON household_members(user_id);
CREATE INDEX IF NOT EXISTS idx_household_members_household ON household_members(household_id);
CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_status ON ocr_jobs(user_id, status);
CREATE INDEX IF NOT EXISTS idx_ai_messages_user ON ai_messages(user_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email != '';

COMMIT;
"""


def quote(val):
    """Quote a value for SQL insertion. None → NULL."""
    if val is None:
        return "NULL"
    if isinstance(val, int):
        return str(val)
    if isinstance(val, float):
        # All amounts should be whole numbers
        return str(int(val))
    # Escape single quotes by doubling
    escaped = str(val).replace("'", "''")
    return f"'{escaped}'"


def table_columns(conn, table_name):
    """Get column names for a SQLite table."""
    cursor = conn.execute(f"PRAGMA table_info({table_name})")
    return [row[1] for row in cursor.fetchall() if row[1] != "sqlite_sequence"]


def export_table(conn, table_name):
    """Generate INSERT statements for all rows in a table."""
    cols = table_columns(conn, table_name)
    col_list = ", ".join(cols)
    placeholders = ", ".join(f"${i+1}" for i in range(len(cols)))

    cursor = conn.execute(f"SELECT * FROM {table_name}")
    rows = cursor.fetchall()

    if not rows:
        return ""

    lines = []
    for row in rows:
        values = ", ".join(quote(row[i]) for i in range(len(cols)))
        lines.append(f"    ({values})")

    return (
        f"INSERT INTO {table_name} ({col_list}) VALUES\n"
        + ",\n".join(lines)
        + ";\n"
    )


def main():
    if not DB_PATH.exists():
        print(f"ERROR: SQLite DB not found at {DB_PATH}")
        return False

    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row

    tables = [
        "users",
        "email_verifications",
        "categories",
        "transactions",
        "households",
        "household_members",
        "budgets",
        "ocr_jobs",
        "ai_messages",
    ]

    with open(OUTPUT, "w") as f:
        f.write("-- WealthTrack PostgreSQL Migration Dump\n")
        f.write(f"-- Generated: convert sqlite to postgres\n")
        f.write("-- Safe to re-run on a fresh database.\n\n")

        f.write(PG_SCHEMA)
        f.write("\n")

        for table in tables:
            print(f"  Exporting {table}...")
            sql = export_table(conn, table)
            if sql:
                f.write(f"-- Table: {table}\n")
                f.write(sql)
                f.write("\n")

        # Reset SERIAL sequences to max id
        f.write("-- Reset sequences to current max values\n")
        for table in tables:
            f.write(
                f"SELECT setval(pg_get_serial_sequence('{table}', 'id'), "
                f"COALESCE((SELECT MAX(id) FROM {table}), 0) + 1, false);\n"
            )

    conn.close()
    print(f"\n✅ Migration SQL written to: {OUTPUT}")
    print(f"   Run: psql -U wealthtrack -d wealthtrack -f {OUTPUT}")
    return True


if __name__ == "__main__":
    main()
