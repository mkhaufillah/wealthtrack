# Backend Implementation — Step by Step

This doc is designed for an AI agent (Claude Code, Codex, etc.) to execute sequentially.

## Prerequisites

- Python 3.11+ installed
- `uv` installed (preferred over pip)
- VPS running Linux (proven)
- Existing DB at `~/.keuangan/finance.db` with 27 transactions

## Step 1: Create Python Virtual Environment

```bash
cd ~/dev/wealthtrack
uv venv .venv
source .venv/bin/activate
```

## Step 2: Install Dependencies

`backend/requirements.txt` — Using loose `>=` constraints (check actual file for current versions).

```
fastapi>=0.115.0
uvicorn[standard]>=0.34.0
aiosqlite>=0.20.0
pydantic>=2.10.0
python-jose[cryptography]>=3.3.0
passlib[bcrypt]>=1.7.4
python-multipart>=0.0.19
pydantic-settings>=2.7.0
slowapi>=0.1.9
bcrypt==4.0.1
pytest>=8.0.0
pytest-asyncio>=0.24.0
httpx>=0.28.0
```

Install:

```bash
source .venv/bin/activate
uv pip install -r backend/requirements.txt
```

## Step 3: Database Path & Config

**DB stays at `~/.keuangan/finance.db`** — do not create a new one.

`backend/app/core/config.py`

```python
from pydantic_settings import BaseSettings
from pathlib import Path

class Settings(BaseSettings):
    APP_NAME: str = "WealthTrack API"
    VERSION: str = "0.1.0"
    DEBUG: bool = True

    # === PAKAI DB YANG SUDAH ADA ===
    DB_PATH: str = str(Path.home() / ".keuangan" / "finance.db")

    SECRET_KEY: str = "change-me-in-production-use-env"  # override via .env
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_DAYS: int = 30

    # JSON string — parsed via cors_origins_list property
    CORS_ORIGINS: str = (
        '["http://localhost:8080", "http://127.0.0.1:8080", "https://wealthtrack.filla.id"]'
    )

    @property
    def cors_origins_list(self) -> list[str]:
        import json
        return json.loads(self.CORS_ORIGINS)

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

settings = Settings()
```

## Step 4: Migration Script (Run ONCE)

Before starting FastAPI, run the migration to add new columns to the existing DB.
This script is **safe to re-run** — it checks column existence before ALTER TABLE.

`backend/app/migrate_db.py`

```python
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

        # 2. Seed default users (password default: "password123")
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

        # 3. Add new columns to transactions (safe: checks existence)
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
```

Run migration:

```bash
cd ~/dev/wealthtrack
source .venv/bin/activate
uv run python -m backend.app.migrate_db
```

## Step 5: Database Layer

`backend/app/database.py`

```python
import aiosqlite
import sqlite3
from contextlib import asynccontextmanager
from pathlib import Path

from app.core.config import settings

async def get_db():
    """Dependency: yields aiosqlite connection with WAL mode."""
    db = await aiosqlite.connect(settings.DB_PATH)
    db.row_factory = aiosqlite.Row
    await db.execute("PRAGMA journal_mode=WAL;")
    await db.execute("PRAGMA foreign_keys=ON;")
    await db.execute("PRAGMA busy_timeout=5000;")
    try:
        yield db
    finally:
        await db.close()

def get_sync_db():
    """Synchronous connection for migration / seed scripts."""
    conn = sqlite3.connect(settings.DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA foreign_keys=ON;")
    return conn
```

## Step 6: Security Module

`backend/app/core/security.py`

```python
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer()

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

def create_access_token(user_id: int, username: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=settings.ACCESS_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": str(user_id),
        "username": username,
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> dict:
    """Dependency: returns user dict from token."""
    payload = decode_token(credentials.credentials)
    return {"id": int(payload["sub"]), "username": payload["username"]}
```

## Step 7: Create Pydantic Schemas

`backend/app/schemas/user.py`

```python
from pydantic import BaseModel, Field

class UserRegister(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    display_name: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=6, max_length=128)

class UserLogin(BaseModel):
    username: str
    password: str

class UserOut(BaseModel):
    id: int
    username: str
    display_name: str
    role: str
    created_at: str

class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
```

`backend/app/schemas/transaction.py`

```python
from pydantic import BaseModel, Field
from typing import Optional

class TransactionCreate(BaseModel):
    type: str = Field(pattern="^(expense|income)$")
    category_id: int
    amount: int = Field(gt=0)
    description: str = Field(default="", max_length=255)
    note: str = Field(default="", max_length=500)
    date: str  # YYYY-MM-DD

class TransactionUpdate(BaseModel):
    amount: Optional[int] = Field(default=None, gt=0)
    description: Optional[str] = None
    note: Optional[str] = None
    category_id: Optional[int] = None
    date: Optional[str] = None

class CategoryBrief(BaseModel):
    id: int
    name: str
    icon: str

class UserBrief(BaseModel):
    id: int
    display_name: str

class TransactionOut(BaseModel):
    id: int
    amount: int
    type: str
    description: str
    note: str
    date: str
    category: CategoryBrief
    user: UserBrief
    created_at: str
    updated_at: str

class PaginationMeta(BaseModel):
    page: int
    per_page: int
    total: int
    total_pages: int

class PaginatedTransactions(BaseModel):
    data: list[TransactionOut]
    meta: PaginationMeta
```

`backend/app/schemas/category.py`

```python
from pydantic import BaseModel

class CategoryOut(BaseModel):
    id: int
    name: str
    type: str
    icon: str
    is_default: bool
```

## Step 8: Create Routers

`backend/app/routers/auth.py`

```python
from fastapi import APIRouter, Depends, HTTPException, status
import aiosqlite

from app.database import get_db
from app.core.security import hash_password, verify_password, create_access_token, get_current_user
from app.schemas.user import UserRegister, UserLogin, UserOut, TokenOut
from app.core.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/register", status_code=201)
async def register(data: UserRegister, db: aiosqlite.Connection = Depends(get_db)):
    cursor = await db.execute("SELECT id FROM users WHERE username = ?", (data.username,))
    if await cursor.fetchone():
        raise HTTPException(status_code=409, detail="Username already exists")
    pw_hash = hash_password(data.password)
    cursor = await db.execute(
        "INSERT INTO users (username, display_name, password_hash) VALUES (?, ?, ?)",
        (data.username, data.display_name, pw_hash),
    )
    await db.commit()
    return {"id": cursor.lastrowid, "username": data.username, "display_name": data.display_name}

@router.post("/login")
async def login(data: UserLogin, db: aiosqlite.Connection = Depends(get_db)):
    cursor = await db.execute("SELECT * FROM users WHERE username = ?", (data.username,))
    user = await cursor.fetchone()
    if not user or not verify_password(data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    token = create_access_token(user["id"], user["username"])
    return TokenOut(
        access_token=token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_DAYS * 86400,
    )

@router.get("/me")
async def me(current_user: dict = Depends(get_current_user), db: aiosqlite.Connection = Depends(get_db)):
    cursor = await db.execute(
        "SELECT id, username, display_name, role, created_at FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user = await cursor.fetchone()
    return dict(user)
```

`backend/app/routers/categories.py`

```python
from fastapi import APIRouter, Depends, Query
import aiosqlite
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user

router = APIRouter(prefix="/categories", tags=["categories"])

@router.get("")
async def list_categories(
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    if type:
        cursor = await db.execute(
            "SELECT * FROM categories WHERE type = ? ORDER BY sort_order", (type,)
        )
    else:
        cursor = await db.execute("SELECT * FROM categories ORDER BY type, sort_order")
    rows = await cursor.fetchall()
    return [dict(r) for r in rows]
```

`backend/app/routers/transactions.py`

```python
from fastapi import APIRouter, Depends, HTTPException, Query
import aiosqlite
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user
from app.schemas.transaction import TransactionCreate, TransactionUpdate, PaginatedTransactions, PaginationMeta

router = APIRouter(prefix="/transactions", tags=["transactions"])


def _format_txn(row, cat_name="", cat_icon="", display_name=""):
    # sqlite3.Row doesn't support .get() — convert to dict for safe access
    r = dict(row)
    return {
        "id": r["id"],
        "amount": int(r["amount"]),
        "type": r["type"],
        "description": r.get("description", "") or "",
        "note": r.get("note", "") or "",
        "date": r.get("date") or r["created_at"][:10],
        "category": {
            "id": r["category_id"],
            "name": cat_name or r.get("category_name", "") or "",
            "icon": cat_icon or "",
        },
        "user": {
            "id": r.get("user_id", 1) or 1,
            "display_name": display_name or r.get("user_display_name", ""),
        },
        "created_at": r["created_at"],
        "updated_at": r.get("updated_at", r["created_at"]),
    }

@router.get("", response_model=PaginatedTransactions)
async def list_transactions(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    category_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sort: str = Query("-date", pattern="^(date|-date|amount|-amount)$"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    where = ["t.user_id = ?"]
    params: list = [current_user["id"]]
    if type:
        where.append("t.type = ?")
        params.append(type)
    if category_id:
        where.append("t.category_id = ?")
        params.append(category_id)
    if date_from:
        where.append("COALESCE(t.date, substr(t.created_at,1,10)) >= ?")
        params.append(date_from)
    if date_to:
        where.append("COALESCE(t.date, substr(t.created_at,1,10)) <= ?")
        params.append(date_to)

    order_map = {
        "date": "COALESCE(t.date, substr(t.created_at,1,10)) ASC",
        "-date": "COALESCE(t.date, substr(t.created_at,1,10)) DESC",
        "amount": "t.amount ASC",
        "-amount": "t.amount DESC",
    }
    order = order_map.get(sort, "COALESCE(t.date, substr(t.created_at,1,10)) DESC")

    cursor = await db.execute(
        f"SELECT COUNT(*) FROM transactions t WHERE {' AND '.join(where)}", params
    )
    total = (await cursor.fetchone())[0]

    offset = (page - 1) * per_page
    cursor = await db.execute(
        f"""SELECT t.id, t.type, t.amount, t.category_id, t.category_name,
                   t.description, t.note, t.date, t.user_id, t.created_at,
                   c.name AS cat_name, c.icon AS cat_icon,
                   u.display_name AS user_display_name
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            LEFT JOIN users u ON t.user_id = u.id
            WHERE {' AND '.join(where)}
            ORDER BY {order}
            LIMIT ? OFFSET ?""",
        params + [per_page, offset],
    )
    rows = await cursor.fetchall()

    data = [_format_txn(r, r["cat_name"] or "", r["cat_icon"] or "") for r in rows]

    return PaginatedTransactions(
        data=data,
        meta=PaginationMeta(
            page=page,
            per_page=per_page,
            total=total,
            total_pages=max(1, (total + per_page - 1) // per_page),
        ),
    )

@router.post("", status_code=201)
async def create_transaction(
    data: TransactionCreate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute("SELECT id, name FROM categories WHERE id = ?", (data.category_id,))
    cat = await cursor.fetchone()
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")

    cursor = await db.execute(
        """INSERT INTO transactions (user_id, category_id, category_name, type, amount, description, note, date)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (current_user["id"], data.category_id, cat["name"], data.type, data.amount, data.description, data.note, data.date),
    )
    await db.commit()
    new_id = cursor.lastrowid
    cursor = await db.execute("SELECT * FROM transactions WHERE id = ?", (new_id,))
    row = await cursor.fetchone()
    return _format_txn(row, cat["name"], "", current_user["username"])

@router.get("/{txn_id}")
async def get_transaction(
    txn_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT * FROM transactions WHERE id = ? AND user_id = ?", (txn_id, current_user["id"])
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Transaction not found")
    c = await (await db.execute(
        "SELECT id, name, icon FROM categories WHERE id = ?", (row["category_id"],)
    )).fetchone()
    return _format_txn(row, c["name"] if c else "", "", current_user["username"])

@router.put("/{txn_id}")
async def update_transaction(
    txn_id: int,
    data: TransactionUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT id FROM transactions WHERE id = ? AND user_id = ?", (txn_id, current_user["id"])
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Transaction not found")

    updates = {}
    for field in ["amount", "description", "note", "category_id", "date"]:
        val = getattr(data, field, None)
        if val is not None:
            if field == "category_id":
                c = await (await db.execute(
                    "SELECT name FROM categories WHERE id = ?", (val,)
                )).fetchone()
                if not c:
                    raise HTTPException(status_code=404, detail="Category not found")
                updates["category_id"] = val
                updates["category_name"] = c["name"]
            else:
                updates[field] = val
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = ?" for k in updates)
    await db.execute(
        f"UPDATE transactions SET {set_clause} WHERE id = ?",
        list(updates.values()) + [txn_id],
    )
    await db.commit()

    cursor = await db.execute("SELECT * FROM transactions WHERE id = ?", (txn_id,))
    row = await cursor.fetchone()
    c = await (await db.execute(
        "SELECT id, name, icon FROM categories WHERE id = ?", (row["category_id"],)
    )).fetchone()
    return _format_txn(row, c["name"] if c else "", "", current_user["username"])

@router.delete("/{txn_id}", status_code=204)
async def delete_transaction(
    txn_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT id FROM transactions WHERE id = ? AND user_id = ?", (txn_id, current_user["id"])
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Transaction not found")
    await db.execute("DELETE FROM transactions WHERE id = ?", (txn_id,))
    await db.commit()
```

### GET /transactions/household — List household transactions

```python
@router.get("/household", response_model=PaginatedTransactions)
async def list_household_transactions(
    page: int = Query(1, ge=1),
    per_page: int = Query(100, ge=1, le=200),
    type: Optional[str] = Query(None, pattern="^(expense|income)$"),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sort: str = Query("-date", pattern="^(date|-date|amount|-amount)$"),
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    # Get user's household
    cursor = await db.execute(
        "SELECT household_id FROM household_members WHERE user_id = ?",
        (current_user["id"],),
    )
    hm = await cursor.fetchone()
    if not hm:
        raise HTTPException(status_code=404, detail="Not a member of any household")
    household_id = hm["household_id"]

    where = ["hm2.household_id = ?"]
    params: list = [household_id]
    if type:
        where.append("t.type = ?")
        params.append(type)
    if date_from:
        where.append("COALESCE(t.date, substr(t.created_at,1,10)) >= ?")
        params.append(date_from)
    if date_to:
        where.append("COALESCE(t.date, substr(t.created_at,1,10)) <= ?")
        params.append(date_to)

    # Sort
    sort_col = "t.date" if "date" in sort else "t.amount"
    sort_dir = "DESC" if sort.startswith("-") else "ASC"

    # Count
    cursor = await db.execute(
        f"SELECT COUNT(*) FROM transactions t "
        f"JOIN household_members hm2 ON hm2.user_id = t.user_id "
        f"WHERE {' AND '.join(where)}", params
    )
    total = (await cursor.fetchone())[0]
    total_pages = max(1, (total + per_page - 1) // per_page)

    # Fetch
    offset = (page - 1) * per_page
    cursor = await db.execute(
        f"SELECT t.*, u.display_name as user_display_name, "
        f"c.name as category_name, c.icon as category_icon "
        f"FROM transactions t "
        f"JOIN household_members hm2 ON hm2.user_id = t.user_id "
        f"JOIN users u ON t.user_id = u.id "
        f"LEFT JOIN categories c ON t.category_id = c.id "
        f"WHERE {' AND '.join(where)} "
        f"ORDER BY {sort_col} {sort_dir} LIMIT ? OFFSET ?",
        params + [per_page, offset],
    )
    rows = await cursor.fetchall()

    return {
        "data": [_format_txn(r) for r in rows],
        "meta": {"page": page, "per_page": per_page, "total": total, "total_pages": total_pages},
    }
```

`backend/app/routers/summaries.py`

```python
from fastapi import APIRouter, Depends, Query
import aiosqlite
from datetime import date
from typing import Optional

from app.database import get_db
from app.core.security import get_current_user

router = APIRouter(prefix="/summaries", tags=["summaries"])

@router.get("/daily")
async def daily_summary(
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    today = date.today().isoformat()
    d_from = date_from or today
    d_to = date_to or today

    cursor = await db.execute(
        """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
           FROM transactions t
           WHERE t.user_id = ? AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           GROUP BY t.type""",
        (current_user["id"], d_from, d_to),
    )
    rows = await cursor.fetchall()
    income = 0
    expense = 0
    for r in rows:
        if r["type"] == "income":
            income = r["total"]
        else:
            expense = r["total"]

    cursor = await db.execute(
        """SELECT c.id, c.name, c.icon, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t JOIN categories c ON t.category_id = c.id
           WHERE t.user_id = ? AND COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
             AND t.type = 'expense'
           GROUP BY c.id ORDER BY total DESC""",
        (current_user["id"], d_from, d_to),
    )
    by_cat = await cursor.fetchall()
    categories = []
    for r in by_cat:
        pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
        categories.append({
            "category_id": r["id"], "category_name": r["name"],
            "icon": r["icon"] or "", "total": r["total"],
            "count": r["count"], "percentage": pct,
        })

    return {
        "date_from": d_from, "date_to": d_to,
        "total_income": int(income), "total_expense": int(expense),
        "balance": int(income - expense), "by_category": categories,
    }


@router.get("/household")
async def household_summary(
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Household-wide summary across ALL users. Requires authentication."""
    today = date.today().isoformat()
    d_from = date_from or today
    d_to = date_to or today

    # Combined totals (all users)
    cursor = await db.execute(
        """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
           FROM transactions t
           WHERE COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           GROUP BY t.type""",
        (d_from, d_to),
    )
    rows = await cursor.fetchall()
    income = 0
    expense = 0
    for r in rows:
        if r["type"] == "income":
            income = r["total"]
        else:
            expense = r["total"]

    # By category (all users)
    cursor = await db.execute(
        """SELECT c.id, c.name, c.icon, SUM(t.amount) as total, COUNT(*) as count
           FROM transactions t JOIN categories c ON t.category_id = c.id
           WHERE COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
             AND t.type = 'expense'
           GROUP BY c.id ORDER BY total DESC""",
        (d_from, d_to),
    )
    by_cat = await cursor.fetchall()
    categories = []
    for r in by_cat:
        pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
        categories.append({
            "category_id": r["id"], "category_name": r["name"],
            "icon": r["icon"] or "", "total": r["total"],
            "count": r["count"], "percentage": pct,
        })

    # By user
    cursor = await db.execute(
        """SELECT t.user_id, u.display_name,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) as total_expense,
                  COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) as total_income
           FROM transactions t JOIN users u ON t.user_id = u.id
           WHERE COALESCE(t.date, substr(t.created_at,1,10)) >= ?
             AND COALESCE(t.date, substr(t.created_at,1,10)) <= ?
           GROUP BY t.user_id ORDER BY total_expense DESC""",
        (d_from, d_to),
    )
    by_user = await cursor.fetchall()
    users = [{
        "user_id": r["user_id"], "display_name": r["display_name"],
        "total_expense": int(r["total_expense"]), "total_income": int(r["total_income"]),
    } for r in by_user]

    return {
        "date_from": d_from, "date_to": d_to,
        "total_income": int(income), "total_expense": int(expense),
        "balance": int(income - expense),
        "by_category": categories, "by_user": users,
    }
```

## Step 9: Wire Everything in main.py

`backend/app/main.py`

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import auth, categories, transactions, summaries

app = FastAPI(title=settings.APP_NAME, version=settings.VERSION)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/v1")
app.include_router(categories.router, prefix="/api/v1")
app.include_router(transactions.router, prefix="/api/v1")
app.include_router(summaries.router, prefix="/api/v1")
```

## Step 10: Run Migration First!

```bash
cd ~/dev/wealthtrack
source .venv/bin/activate
uv run python -m backend.app.migrate_db
```

Expected output:
```
Migrating: /home/filla/.keuangan/finance.db
Migration complete. Added columns: ['user_id', 'date', 'note']
Users seeded: filla (admin), nahda (user) — password default: password123
```

## Step 11: Run Server

`backend/run.sh`

```bash
#!/bin/bash
cd "$(dirname "$0")/.."
source .venv/bin/activate
cd backend
uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload
```

```bash
chmod +x backend/run.sh
./backend/run.sh
```

> `--host 127.0.0.1` — localhost only, not exposed to the public.
> Nginx will reverse-proxy to this port.

## Step 12: Verify

```bash
# Health check (from VPS)
curl http://127.0.0.1:8080/docs

# Test login
curl -X POST "http://127.0.0.1:8080/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username": "filla", "password": "password123"}'

# Test list categories (should show 15 existing categories)
TOKEN="<token_from_login>"
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8080/api/v1/categories"

# Test list transactions (should show 27 existing transactions)
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8080/api/v1/transactions"

# Test add transaction
curl -X POST "http://127.0.0.1:8080/api/v1/transactions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"expense","category_id":1,"amount":25000,"description":"Test from API","note":"","date":"2026-05-26"}'

# Test daily summary
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8080/api/v1/summaries/daily"
```

## Security & Hardening

### JWT Secret Key

The app reads `SECRET_KEY` from `backend/.env`. If the file doesn't exist, it uses a hardcoded default (`change-me-in-production-use-env`) and logs a warning.

**Generate a key on first deploy:**
```bash
cd ~/dev/wealthtrack
python3 -c "import secrets
f=open('backend/.env','w')
f.write(f'SECRET_KEY={secrets.token_hex(32)}\nDEBUG=True\nACCESS_TOKEN_EXPIRE_DAYS=30\n')
f.close()"
```

The `.env` file is in `.gitignore`. A `.env.example` is checked into the repo as a template.

### Global Error Handler

`backend/app/main.py` registers a catch-all exception handler for 500 errors:

```python
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={
            "detail": {
                "code": "INTERNAL_ERROR",
                "message": "An unexpected error occurred",
            }
        },
    )
```

This ensures unexpected crashes return a consistent JSON response instead of raw tracebacks. FastAPI's built-in `HTTPException` handling is not affected — 400/401/404/409 errors still return their specific messages.

### Rate Limiting (Auth)

Login and register endpoints are rate-limited using `slowapi` to prevent brute-force attacks:

- **POST /auth/register** — 5 requests/minute per IP
- **POST /auth/login** — 10 requests/minute per IP

Configured in `app/core/limiter.py` and wired in `app/main.py` via `SlowAPIMiddleware`. Returns `429 Too Many Requests` when exceeded.

### Health Check

A **GET /api/v1/health** endpoint is available for monitoring / load balancer probes:

```python
@router.get("/health")
async def health_check(db):
    # Returns {"status": "ok", "database": "connected"}
    # or {"status": "degraded", "database": "unreachable"}
```

The endpoint pings the SQLite database and reports connectivity status. No authentication required — designed for external monitoring tools.

### CORS

CORS origins are restricted by default to localhost and `https://wealthtrack.filla.id`. Override via `CORS_ORIGINS` env var:

```bash
CORS_ORIGINS='["https://app.domain.com"]'
```

Parsed from a JSON string in `config.py` via the `cors_origins_list` property.

### SQL Best Practices

All queries use **specific column names** instead of `SELECT *`:
- Only fetch columns that are actually used in the response
- Reduces memory overhead and prevents accidental data leakage
- Makes query intent explicit (e.g., login only fetches `id, username, password_hash`)

## Next Steps After Backend Works

1. Setup nginx reverse proxy (see `docs/07-deployment.md`)
2. Update Hermes cron (see `docs/06-hermes-integration.md`)
3. Build Flutter mobile app (see `docs/05-flutter-mobile.md`)
