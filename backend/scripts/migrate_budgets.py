"""
Migration: Fix budgets table UNIQUE constraint to include user_id.

Run this once: python3 migrate_budgets.py

Old: UNIQUE(month, category_name)
New: UNIQUE(month, category_id, user_id)

This allows each user to have their own budget per category per month.
"""
import sqlite3
import sys
from pathlib import Path


def migrate(db_path: str):
    db = Path(db_path).expanduser().resolve()
    if not db.exists():
        print(f"❌ Database not found: {db}")
        sys.exit(1)

    conn = sqlite3.connect(str(db))
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Check current schema
    c.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='budgets'")
    current = c.fetchone()
    if not current:
        print("❌ budgets table not found")
        sys.exit(1)

    print(f"Current schema:\n{current['sql']}\n")

    # Verify old constraint exists
    if "UNIQUE(month, category_name)" not in current["sql"]:
        print("✅ Schema already migrated or different — skipping")
        conn.close()
        return

    # Create new table with correct constraint
    c.execute("""
        CREATE TABLE budgets_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            month TEXT NOT NULL,
            category_id INTEGER,
            category_name TEXT,
            budget_amount REAL NOT NULL,
            user_id INTEGER REFERENCES users(id) DEFAULT 1,
            UNIQUE(month, category_id, user_id),
            FOREIGN KEY (category_id) REFERENCES categories(id)
        )
    """)

    # Copy existing data
    c.execute("""
        INSERT INTO budgets_new (id, month, category_id, category_name, budget_amount, user_id)
        SELECT id, month, category_id, category_name, budget_amount, user_id FROM budgets
    """)
    count = c.rowcount
    print(f"📋 Copied {count} rows")

    # Swap tables
    c.execute("DROP TABLE budgets")
    c.execute("ALTER TABLE budgets_new RENAME TO budgets")
    conn.commit()

    # Verify
    c.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='budgets'")
    new_schema = c.fetchone()["sql"]
    print(f"New schema:\n{new_schema}")
    print("✅ Migration complete")
    conn.close()


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "~/.keuangan/finance.db"
    migrate(path)
