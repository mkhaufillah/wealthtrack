"""
Migration script: add WealthTrack tables/columns to existing finance.db.
Safe to re-run — checks column existence before ALTER TABLE.
Run ONCE before starting FastAPI server.
"""

import sqlite3
from pathlib import Path
from passlib.context import CryptContext
import secrets
import string

from backend.app.core.config import settings

DB_PATH = settings.DB_PATH
PWD_CTX = CryptContext(schemes=["bcrypt"], deprecated="auto")
DEFAULT_PW_HASH = PWD_CTX.hash("password123")


def run_migration():
    if not Path(DB_PATH).exists():
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

        # Add cycle_start_day to users table (billing cycle support)
        user_cols = [row[1] for row in conn.execute("PRAGMA table_info(users)").fetchall()]
        if 'cycle_start_day' not in user_cols:
            conn.execute(
                "ALTER TABLE users ADD COLUMN cycle_start_day INTEGER NOT NULL DEFAULT 1"
            )
            added.append("cycle_start_day (users)")

        if added:
            print(f"  ✓ added columns: {', '.join(added)}")
        else:
            print("  ✓ no new columns needed (already migrated)")

        # 5. Create budgets table + ensure columns
        conn.execute("""
            CREATE TABLE IF NOT EXISTS budgets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id),
                month TEXT NOT NULL,
                category_id INTEGER NOT NULL,
                category_name TEXT NOT NULL,
                budget_amount INTEGER NOT NULL,
                UNIQUE(user_id, month, category_id)
            );
        """)
        cursor = conn.execute("PRAGMA table_info(budgets)")
        budget_cols = [row[1] for row in cursor.fetchall()]
        budget_added = []
        if 'user_id' not in budget_cols:
            conn.execute("ALTER TABLE budgets ADD COLUMN user_id INTEGER REFERENCES users(id) DEFAULT 1")
            budget_added.append("user_id")
        if 'cycle_on' not in budget_cols:
            conn.execute("ALTER TABLE budgets ADD COLUMN cycle_on INTEGER NOT NULL DEFAULT 1")
            budget_added.append("cycle_on")
        if budget_added:
            print(f"  ✓ budgets added columns: {', '.join(budget_added)}")
        else:
            print("  ✓ budgets table ready")

        # 6. Backfill existing data
        conn.execute("UPDATE transactions SET user_id = 1 WHERE user_id IS NULL")
        conn.execute(
            "UPDATE transactions SET date = substr(created_at, 1, 10) WHERE date IS NULL AND created_at IS NOT NULL"
        )
        print("  ✓ backfilled existing transactions (user_id=1, date from created_at)")

        # 7. Migrate existing budget months: month label now = START month of cycle range
        #    Previously month was END month (e.g. "2026-06" for range May 5 - June 4).
        #    Now month = START month (e.g. "2026-05" for range May 5 - June 4).
        cursor = conn.execute(
            "SELECT id, month FROM budgets WHERE cycle_on > 1"
        )
        budget_rows = cursor.fetchall()
        migrated = 0
        for row in budget_rows:
            bid, old_month = row
            year, mon = map(int, old_month.split('-'))
            # Decrement month by 1 (with year wrap)
            if mon == 1:
                new_month = f"{year - 1}-12"
            else:
                new_month = f"{year}-{mon - 1:02d}"
            conn.execute(
                "UPDATE budgets SET month = ? WHERE id = ?",
                (new_month, bid),
            )
            migrated += 1
        if migrated:
            print(f"  ✓ migrated {migrated} budget(s) to new month schema (cycle_on > 1)")
        else:
            print("  ✓ no budgets to migrate (cycle_on > 1)")

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


def run_household_migration():
    """
    Phase 2: add households + household_members tables.
    Creates a default 'Home' household and assigns existing users to it.
    Safe to re-run (idempotent via IF NOT EXISTS).
    """
    if not Path(DB_PATH).exists():
        print(f"ERROR: Database not found at {DB_PATH}")
        return False

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys=OFF;")

    try:
        # 1. Create households table
        conn.execute("""
            CREATE TABLE IF NOT EXISTS households (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                invite_code TEXT UNIQUE NOT NULL,
                created_by INTEGER NOT NULL REFERENCES users(id),
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            );
        """)
        print("  ✓ households table ready")

        # 2. Create household_members table
        conn.execute("""
            CREATE TABLE IF NOT EXISTS household_members (
                user_id INTEGER NOT NULL REFERENCES users(id),
                household_id INTEGER NOT NULL REFERENCES households(id),
                role TEXT NOT NULL DEFAULT 'member',
                joined_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
                PRIMARY KEY (user_id, household_id)
            );
        """)
        print("  ✓ household_members table ready")

        # 3. Check if there's already a household — skip if yes
        cursor = conn.execute("SELECT COUNT(*) as cnt FROM households")
        if cursor.fetchone()[0] > 0:
            print("  ✓ households already exist, skipping seed")
        else:
            # Generate invite code
            alphabet = string.ascii_uppercase + string.digits
            code = ''.join(secrets.choice(alphabet) for _ in range(8))

            # Create default household (created_by = first user = 1/Filla)
            conn.execute(
                "INSERT INTO households (name, invite_code, created_by) VALUES (?, ?, ?)",
                ("Home", code, 1),
            )
            print("  ✓ default 'Home' household created")

            # Assign existing users (filla=1, nahda=2) to the household
            cursor = conn.execute("SELECT id FROM users ORDER BY id")
            users = [r[0] for r in cursor.fetchall()]
            for uid in users:
                role = "admin" if uid == 1 else "member"
                conn.execute(
                    "INSERT INTO household_members (user_id, household_id, role) VALUES (?, 1, ?)",
                    (uid, role),
                )
            print(f"  ✓ assigned {len(users)} existing users to household")

        # 4. Backfill user transactions — ensure household_id is set
        # (no household_id column on transactions — we filter via user -> household_members join)
        # Verify
        cursor = conn.execute("""
            SELECT COUNT(*) FROM household_members hm
            JOIN households h ON hm.household_id = h.id
        """)
        count = cursor.fetchone()[0]
        print(f"  ✓ verified: {count} member(s) in household")

        conn.commit()
        print("\n✅ Household migration complete!")
        return True

    except Exception as e:
        conn.rollback()
        print(f"❌ Household migration failed: {e}")
        return False
    finally:
        conn.close()


if __name__ == "__main__":
    run_migration()
    run_household_migration()
