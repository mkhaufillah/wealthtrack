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

`backend/requirements.txt`

```
fastapi==0.115.6
uvicorn[standard]==0.34.0
aiosqlite==0.20.0
pydantic==2.10.4
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.19
pydantic-settings==2.7.1
```

Install:

```bash
source .venv/bin/activate
uv pip install -r backend/requirements.txt
```

## Step 3: Database Path & Config

**DB tetap di `~/.keuangan/finance.db`** — jangan bikin baru.

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

    SECRET_KEY: str = "change-me-in-production-use-env"  # TODO: env var
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_DAYS: int = 30

    CORS_ORIGINS: list[str] = ["*"]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()
```

## Step 4: Migration Script (Run ONCE)

Sebelum mulai FastAPI, jalankan migrasi untuk menambah kolom baru ke DB existing.
Script ini **aman dijalankan ulang** — ngecek keberadaan kolom sebelum ALTER TABLE.

`backend/app/migrate_db.py`

```python
"""
Migration script: add new columns to existing finance.db.
Safe to re-run — checks column existence before ALTER TABLE.
Run ONCE before starting FastAPI server.
"""

import sqlite3
import os
from pathlib import Path
from app.core.config import settings

def run_migration():
    db_path = settings.DB_PATH
    print(f"Migrating: {db_path}")

    if not os.path.exists(db_path):
        print(f"ERROR: Database not found at {db_path}")
        print("Run the existing finance_db.py init first, or seed data manually.")
        return

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys=OFF;")

    # 1. Create users table if not exists
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

    # 2. Seed default users (password default: "password123")
    # Hash dihasilkan dari passlib.hash bcrypt — ganti dengan hash real setelah deploy
    import hashlib
    # Placeholder hash — ganti via API nanti
    dummy_hash = "$2b$12$LJ3m4ys3Lk0TSwHCpNqrPOkODhBIjs5y7Kwe5mCpMOABsERy7aEJa"
    users_data = [
        (1, 'filla', 'Filla', dummy_hash, 'admin'),
        (2, 'nahda', 'Nahda', dummy_hash, 'user'),
    ]
    for uid, uname, dname, pw_hash, role in users_data:
        conn.execute(
            "INSERT OR IGNORE INTO users (id, username, display_name, password_hash, role) VALUES (?, ?, ?, ?, ?)",
            (uid, uname, dname, pw_hash, role)
        )

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

    # 4. Backfill existing data
    conn.execute("UPDATE transactions SET user_id = 1 WHERE user_id IS NULL")
    conn.execute(
        "UPDATE transactions SET date = substr(created_at, 1, 10) WHERE date IS NULL AND created_at IS NOT NULL"
    )

    conn.commit()
    conn.close()

    print(f"Migration complete. Added columns: {added if added else 'none needed'}")
    print(f"Users seeded: filla (admin), nahda (user) — password default: password123")
    print("IMPORTANT: Change password via API after first login!")

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
from app.schemas.transaction import TransactionCreate, TransactionUpdate, PaginatedTransactions

router = APIRouter(prefix="/transactions", tags=["transactions"])

def _format_txn(row, cat_name="", cat_icon="", username=""):
    return {
        "id": row["id"],
        "amount": int(row["amount"]),
        "type": row["type"],
        "description": row["description"] or "",
        "note": row["note"] or "",
        "date": row["date"] or row["created_at"][:10],
        "category": {
            "id": row["category_id"],
            "name": cat_name or row["category_name"] or "",
            "icon": cat_icon or "",
        },
        "user": {
            "id": row.get("user_id") or 1,
            "display_name": username or ("Filla" if row.get("user_id") == 2 else "Filla"),
        },
        "created_at": row["created_at"],
        "updated_at": row.get("updated_at", row["created_at"]),
    }

@router.get("")
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
        f"""SELECT t.* FROM transactions t
            WHERE {' AND '.join(where)}
            ORDER BY {order}
            LIMIT ? OFFSET ?""",
        params + [per_page, offset],
    )
    rows = await cursor.fetchall()

    data = []
    for r in rows:
        c = await (await db.execute(
            "SELECT id, name, icon FROM categories WHERE id = ?", (r["category_id"],)
        )).fetchone()
        if c:
            data.append(_format_txn(r, c["name"], c["icon"]))
        else:
            data.append(_format_txn(r, r.get("category_name", "")))

    return PaginatedTransactions(
        data=data,
        meta={
            "page": page, "per_page": per_page,
            "total": total, "total_pages": max(1, (total + per_page - 1) // per_page),
        },
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

> `--host 127.0.0.1` — hanya localhost, tidak exposed ke public.
> Nginx akan reverse proxy ke port ini.

## Step 12: Verify

```bash
# Health check (from VPS)
curl http://127.0.0.1:8080/docs

# Test login
curl -X POST "http://127.0.0.1:8080/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username": "filla", "password": "password123"}'

# Test list categories (should show 15 existing categories)
TOKEN="<token_dari_login>"
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8080/api/v1/categories"

# Test list transactions (should show 27 existing transactions)
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8080/api/v1/transactions"

# Test add transaction
curl -X POST "http://127.0.0.1:8080/api/v1/transactions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"expense","category_id":1,"amount":25000,"description":"Test dari API","note":"","date":"2026-05-26"}'

# Test daily summary
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8080/api/v1/summaries/daily"
```

## Next Steps After Backend Works

1. Setup nginx reverse proxy (see `docs/07-deployment.md`)
2. Update Hermes cron (see `docs/06-hermes-integration.md`)
3. Build Flutter mobile app (see `docs/05-flutter-mobile.md`)
