"""
Migration script: add WealthTrack tables/columns to existing finance.db.
Safe to re-run — checks column existence before ALTER TABLE.
Run ONCE before starting FastAPI server.
"""

import sqlite3
import os
from pathlib import Path
from passlib.context import CryptContext

DB_PATH = os.path.expanduser("~/.keuangan/finance.db")
PWD_CTX = CryptContext(schemes=["bcrypt"], deprecated="auto")
DEFAULT_PW_HASH = PWD_CTX.hash("password123")


def run_migration():
    if not os.path.exists(DB_PATH):
        print(f"ERROR: Database not found at {DB_PATH}")
        print("Run the existing finance_db.py init first:")
        print("  python3 ~/.hermes/skills/productivity/financial-tracker/scripts/finance_db.py init")
        return False

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys=OFF;")

    try:
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
        print("  ✓ users table ready")

        # 2. Seed default users
        users_data = [
            (1, 'filla', 'Filla', DEFAULT_PW_HASH, 'admin'),
            (2, 'nahda', 'Nahda', DEFAULT_PW_HASH, 'user'),
        ]
        for uid, uname, dname, pw_hash, role in users_data:
            conn.execute(
                "INSERT OR IGNORE INTO users (id, username, display_name, password_hash, role) VALUES (?, ?, ?, ?, ?)",
                (uid, uname, dname, pw_hash, role),
            )
        print("  ✓ default users seeded (filla, nahda)")

        # 3. Add new columns to transactions
        cursor = conn.execute("PRAGMA table_info(transactions)")
        existing_cols = [row[1] for row in cursor.fetchall()]

        added = []
        if 'user_id' not in existing_cols:
            conn.execute("ALTER TABLE transactions ADD COLUMN user_id INTEGER REFERENCES users(id)")
            added.append("user_id")
        if 'date' not in existing_cols:
            conn.execute("ALTER TABLE transactions ADD COLUMN date TEXT")
            added.append("date")
        if 'note' not in existing_cols:
            conn.execute("ALTER TABLE transactions ADD COLUMN note TEXT DEFAULT ''")
            added.append("note")

        if added:
            print(f"  ✓ added columns: {', '.join(added)}")
        else:
            print("  ✓ no new columns needed (already migrated)")

        # 4. Backfill existing data
        conn.execute("UPDATE transactions SET user_id = 1 WHERE user_id IS NULL")
        conn.execute(
            "UPDATE transactions SET date = substr(created_at, 1, 10) WHERE date IS NULL AND created_at IS NOT NULL"
        )
        print("  ✓ backfilled existing transactions (user_id=1, date from created_at)")

        conn.commit()
        print(f"\n✅ Migration complete! DB: {DB_PATH}")
        print("   Users: filla (password123), nahda (password123)")
        print("   Change passwords via API after first login!")
        return True

    except Exception as e:
        conn.rollback()
        print(f"❌ Migration failed: {e}")
        return False
    finally:
        conn.close()


if __name__ == "__main__":
    run_migration()
