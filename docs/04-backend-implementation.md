# Backend Implementation — Step by Step

This doc is designed for an AI agent (Claude Code, Codex, etc.) to execute sequentially.

## Prerequisites

- Python 3.11+ installed
- `uv` installed (preferred over pip)
- VPS running Linux (proven)

## Step 1: Create Python Virtual Environment

```bash
cd ~/dev/wealthtrack
uv venv .venv
source .venv/bin/activate
```

## Step 2: Install Dependencies

Create `backend/requirements.txt`:

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
cd ~/dev/wealthtrack
source .venv/bin/activate
uv pip install -r backend/requirements.txt
```

## Step 3: Create Core Config

`backend/app/core/config.py`

```python
from pydantic_settings import BaseSettings
from pathlib import Path

class Settings(BaseSettings):
    APP_NAME: str = "WealthTrack API"
    VERSION: str = "0.1.0"
    DEBUG: bool = True

    DB_PATH: str = str(Path.home() / ".hermes" / "data" / "wealthtrack.db")
    DB_DIR: str = str(Path.home() / ".hermes" / "data")

    SECRET_KEY: str = "change-me-in-production-use-env"  # TODO: env var
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_DAYS: int = 30

    CORS_ORIGINS: list[str] = ["*"]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()
```

## Step 4: Create Database Layer

`backend/app/database.py`

```python
import aiosqlite
from contextlib import asynccontextmanager
from pathlib import Path

from app.core.config import settings

_db_path: str = settings.DB_PATH

async def get_db():
    """Dependency: yields aiosqlite connection with WAL mode."""
    Path(settings.DB_DIR).mkdir(parents=True, exist_ok=True)
    db = await aiosqlite.connect(_db_path)
    db.row_factory = aiosqlite.Row
    await db.execute("PRAGMA journal_mode=WAL;")
    await db.execute("PRAGMA foreign_keys=ON;")
    await db.execute("PRAGMA busy_timeout=5000;")
    try:
        yield db
    finally:
        await db.close()

async def init_db():
    """Create tables if they don't exist. Run on startup."""
    async with aiosqlite.connect(_db_path) as db:
        await db.executescript("""
            PRAGMA journal_mode=WAL;
            PRAGMA foreign_keys=ON;

            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT 'user',
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
                updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            );

            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL CHECK(type IN ('expense','income')),
                icon TEXT DEFAULT '',
                color TEXT DEFAULT '#6C63FF',
                is_default INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            );

            CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_name_type ON categories(name, type);

            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id),
                category_id INTEGER NOT NULL REFERENCES categories(id),
                type TEXT NOT NULL CHECK(type IN ('expense','income')),
                amount INTEGER NOT NULL CHECK(amount > 0),
                description TEXT NOT NULL DEFAULT '',
                note TEXT DEFAULT '',
                date TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
                updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            );

            CREATE INDEX IF NOT EXISTS idx_txn_user_date ON transactions(user_id, date);
            CREATE INDEX IF NOT EXISTS idx_txn_category ON transactions(category_id);
            CREATE INDEX IF NOT EXISTS idx_txn_type ON transactions(type);

            CREATE TABLE IF NOT EXISTS sync_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT NOT NULL,
                action TEXT NOT NULL,
                table_name TEXT NOT NULL,
                record_id INTEGER,
                status TEXT NOT NULL DEFAULT 'ok',
                message TEXT DEFAULT '',
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            );
        """)
        await db.commit()
```

## Step 5: Security Module

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

## Step 6: Create Pydantic Schemas

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
from datetime import date

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
    color: str
    is_default: bool
```

## Step 7: Create Routers

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
    cursor = await db.execute("SELECT id, username, display_name, role FROM users WHERE id = ?", (current_user["id"],))
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
        cursor = await db.execute("SELECT * FROM categories WHERE type = ? ORDER BY name", (type,))
    else:
        cursor = await db.execute("SELECT * FROM categories ORDER BY type, name")
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
from app.schemas.transaction import TransactionCreate, TransactionUpdate, PaginatedTransactions, TransactionOut, CategoryBrief, UserBrief

router = APIRouter(prefix="/transactions", tags=["transactions"])

def _row_to_out(row, category, user) -> dict:
    return {
        "id": row["id"],
        "amount": row["amount"],
        "type": row["type"],
        "description": row["description"],
        "note": row["note"] or "",
        "date": row["date"],
        "category": {"id": category["id"], "name": category["name"], "icon": category["icon"] or ""},
        "user": {"id": user["id"], "display_name": user["display_name"]},
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
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
    where = ["user_id = ?"]
    params: list = [current_user["id"]]
    if type:
        where.append("t.type = ?")
        params.append(type)
    if category_id:
        where.append("t.category_id = ?")
        params.append(category_id)
    if date_from:
        where.append("t.date >= ?")
        params.append(date_from)
    if date_to:
        where.append("t.date <= ?")
        params.append(date_to)

    order_map = {"date": "t.date ASC", "-date": "t.date DESC", "amount": "t.amount ASC", "-amount": "t.amount DESC"}
    order = order_map.get(sort, "t.date DESC")

    # Count
    cursor = await db.execute(f"SELECT COUNT(*) FROM transactions t WHERE {' AND '.join(where)}", params)
    total = (await cursor.fetchone())[0]

    # Fetch
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
        c = await (await db.execute("SELECT id, name, icon FROM categories WHERE id = ?", (r["category_id"],))).fetchone()
        u = await (await db.execute("SELECT id, display_name FROM users WHERE id = ?", (r["user_id"],))).fetchone()
        data.append(_row_to_out(r, c, u))

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
    cursor = await db.execute("SELECT id FROM categories WHERE id = ?", (data.category_id,))
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Category not found")
    cursor = await db.execute(
        """INSERT INTO transactions (user_id, category_id, type, amount, description, note, date)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (current_user["id"], data.category_id, data.type, data.amount, data.description, data.note, data.date),
    )
    await db.commit()
    new_id = cursor.lastrowid
    cursor = await db.execute("SELECT * FROM transactions WHERE id = ?", (new_id,))
    row = await cursor.fetchone()
    c = await (await db.execute("SELECT id, name, icon FROM categories WHERE id = ?", (row["category_id"],))).fetchone()
    u = {"id": current_user["id"], "display_name": current_user["username"]}
    return _row_to_out(row, c, u)

@router.get("/{txn_id}")
async def get_transaction(
    txn_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute("SELECT * FROM transactions WHERE id = ? AND user_id = ?", (txn_id, current_user["id"]))
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Transaction not found")
    c = await (await db.execute("SELECT id, name, icon FROM categories WHERE id = ?", (row["category_id"],))).fetchone()
    u = {"id": current_user["id"], "display_name": current_user["username"]}
    return _row_to_out(row, c, u)

@router.put("/{txn_id}")
async def update_transaction(
    txn_id: int,
    data: TransactionUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute("SELECT * FROM transactions WHERE id = ? AND user_id = ?", (txn_id, current_user["id"]))
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Transaction not found")
    updates = {}
    for field in ["amount", "description", "note", "category_id", "date"]:
        val = getattr(data, field, None)
        if val is not None:
            updates[field] = val
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")
    set_clause = ", ".join(f"{k} = ?" for k in updates)
    updates["updated_at"] = "2026-05-26T12:00:00.000Z"  # simplified
    await db.execute(
        f"UPDATE transactions SET {set_clause}, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?",
        list(updates.values()) + [txn_id],
    )
    await db.commit()
    cursor = await db.execute("SELECT * FROM transactions WHERE id = ?", (txn_id,))
    row = await cursor.fetchone()
    c = await (await db.execute("SELECT id, name, icon FROM categories WHERE id = ?", (row["category_id"],))).fetchone()
    u = {"id": current_user["id"], "display_name": current_user["username"]}
    return _row_to_out(row, c, u)

@router.delete("/{txn_id}", status_code=204)
async def delete_transaction(
    txn_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute("SELECT id FROM transactions WHERE id = ? AND user_id = ?", (txn_id, current_user["id"]))
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
           WHERE t.user_id = ? AND t.date >= ? AND t.date <= ?
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
           WHERE t.user_id = ? AND t.date >= ? AND t.date <= ? AND t.type = 'expense'
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
        "total_income": income, "total_expense": expense,
        "balance": income - expense, "by_category": categories,
    }
```

## Step 8: Wire Everything in main.py

`backend/app/main.py`

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.database import init_db
from app.routers import auth, categories, transactions, summaries

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield

app = FastAPI(title=settings.APP_NAME, version=settings.VERSION, lifespan=lifespan)

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

## Step 9: Seed Default Data

`backend/app/seed.py` — run this once after init_db.

```python
import aiosqlite
import asyncio
from pathlib import Path
from app.core.security import hash_password
from app.core.config import settings

DEFAULT_CATEGORIES = [
    ("Makan & Minum", "expense", "🍽️", "#FF6B6B"),
    ("Transportasi", "expense", "🚗", "#4ECDC4"),
    ("Belanja Bulanan", "expense", "🛒", "#45B7D1"),
    ("Tagihan & Listrik", "expense", "💡", "#96CEB4"),
    ("Kesehatan", "expense", "🏥", "#FFEAA7"),
    ("Hiburan", "expense", "🎬", "#DDA0DD"),
    ("Pendidikan", "expense", "📚", "#98D8C8"),
    ("Hadiah & Donasi", "expense", "🎁", "#F7DC6F"),
    ("Lainnya", "expense", "📦", "#BDC3C7"),
    ("Gaji", "income", "💰", "#2ECC71"),
    ("Bonus", "income", "🎉", "#27AE60"),
    ("Lainnya", "income", "💵", "#7F8C8D"),
]

async def seed():
    Path(settings.DB_DIR).mkdir(parents=True, exist_ok=True)
    async with aiosqlite.connect(settings.DB_PATH) as db:
        db.row_factory = aiosqlite.Row

        # Seed users
        users = [("filla", "Filla", "password123"), ("nahda", "Nahda", "password123")]
        for u, dn, pw in users:
            existing = await (await db.execute("SELECT id FROM users WHERE username = ?", (u,))).fetchone()
            if not existing:
                pw_hash = hash_password(pw)
                await db.execute("INSERT INTO users (username, display_name, password_hash) VALUES (?, ?, ?)", (u, dn, pw_hash))
                print(f"  Created user: {u}")

        # Seed categories
        for name, typ, icon, color in DEFAULT_CATEGORIES:
            existing = await (await db.execute("SELECT id FROM categories WHERE name = ? AND type = ?", (name, typ))).fetchone()
            if not existing:
                await db.execute("INSERT INTO categories (name, type, icon, color, is_default) VALUES (?, ?, ?, ?, 1)", (name, typ, icon, color))
                print(f"  Created category: {name} ({typ})")

        await db.commit()
        print("Seed complete!")

if __name__ == "__main__":
    asyncio.run(seed())
```

## Step 10: Run Server

`backend/run.sh`

```bash
#!/bin/bash
cd "$(dirname "$0")/.."
source .venv/bin/activate
cd backend
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

```bash
chmod +x backend/run.sh
# Seed data first
cd ~/dev/wealthtrack && uv run python -m backend.app.seed
# Then run server
./backend/run.sh
```

## Step 11: Verify

```bash
# Health check
curl http://localhost:8080/docs  # Should return Swagger UI
curl -X POST "http://localhost:8080/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username": "filla", "password": "password123"}'
# Should return JWT token
```

## Next Steps After Backend Works

1. Update Hermes cron script to use this DB (see `docs/06-hermes-integration.md`)
2. Build Flutter mobile app (see `docs/05-flutter-mobile.md`)
3. Deploy FastAPI as systemd service (see `docs/07-deployment.md`)
