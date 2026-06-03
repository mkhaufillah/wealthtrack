"""
WealthTrack Test Suite — Pytest Configuration & Fixtures.

How to run:
    cd ~/dev/wealthtrack
    source .venv/bin/activate
    pytest backend/tests/ -v --asyncio-mode=auto

Uses dedicated PostgreSQL test database.
Each test function:
  1. Gets a fresh connection
  2. Tables are truncated and seeded
  3. The connection is yielded to test
  4. Connection is closed after test
"""

import os
from typing import AsyncGenerator

import asyncpg
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from passlib.context import CryptContext

from app.database import get_db, CursorWrapper
from app.main import app
from app.core.security import create_access_token

TEST_DB_URL = os.getenv(
    "WEALTHTRACK_TEST_DATABASE_URL",
    "postgresql://wealthtrack_test:wealthtrack_test123@localhost:5432/wealthtrack_test",
)

PWD_CTX = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ─── Seed data ─────────────────────────────────────────────────

DEFAULT_USERS = [
    (1, "filla", "Filla", PWD_CTX.hash("password123"), "admin", "khaufillahmohammad@gmail.com"),
    (2, "nahda", "Nahda", PWD_CTX.hash("password123"), "user", "nahdanurfitriana3@gmail.com"),
]
DEFAULT_CATEGORIES = [
    (1, "Makanan & Minuman", "expense", "🍽️", 1, 1, "Food & Drinks", "[]"),
    (2, "Transportasi & Bensin", "expense", "🚗", 0, 2, "Transport & Fuel", "[]"),
    (3, "Belanja Harian", "expense", "🛒", 0, 3, "Daily Shopping", "[]"),
    (4, "Hiburan", "expense", "🎬", 0, 4, "Entertainment", "[]"),
    (5, "Tagihan & Cicilan", "expense", "📄", 0, 5, "Bills & Installments", "[]"),
    (6, "Kesehatan", "expense", "🏥", 0, 6, "Health", "[]"),
    (7, "Gaji", "income", "💰", 1, 1, "Salary", "[]"),
    (8, "Freelance", "income", "💻", 0, 2, "Freelance", "[]"),
]
DEFAULT_TRANSACTIONS = [
    (1, "income", 15000000, 7, "Gaji", "Gaji Bulanan", "Gaji Mei"),
    (2, "expense", 50000, 1, "Makanan & Minuman", "Nasi Goreng", "Makan siang"),
    (3, "expense", 75000, 2, "Transportasi & Bensin", "Bensin", "Isi Pertalite"),
    (4, "expense", 200000, 3, "Belanja Harian", "Belanja Bulanan", "Indomaret"),
    (5, "income", 3000000, 8, "Freelance", "Freelance Project", "Web dev"),
]

SCHEMA_SQL = """
DROP TABLE IF EXISTS ai_messages CASCADE;
DROP TABLE IF EXISTS ocr_jobs CASCADE;
DROP TABLE IF EXISTS budgets CASCADE;
DROP TABLE IF EXISTS household_members CASCADE;
DROP TABLE IF EXISTS households CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS email_verifications CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user',
    email TEXT DEFAULT '',
    cycle_start_day INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
CREATE TABLE email_verifications (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    verified INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    icon TEXT DEFAULT '',
    is_default INTEGER DEFAULT 0,
    sort_order INTEGER DEFAULT 0,
    name_en TEXT DEFAULT '',
    keywords TEXT DEFAULT '[]'
);
CREATE TABLE households (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    invite_code TEXT UNIQUE NOT NULL,
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
CREATE TABLE household_members (
    user_id INTEGER NOT NULL REFERENCES users(id),
    household_id INTEGER NOT NULL REFERENCES households(id),
    role TEXT NOT NULL DEFAULT 'member',
    joined_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    PRIMARY KEY (user_id, household_id)
);
CREATE TABLE transactions (
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
CREATE TABLE budgets (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    month TEXT NOT NULL,
    category_id INTEGER NOT NULL,
    category_name TEXT NOT NULL,
    budget_amount INTEGER NOT NULL,
    cycle_on INTEGER NOT NULL DEFAULT 1,
    UNIQUE(user_id, month, category_id)
);
CREATE TABLE ocr_jobs (
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
CREATE TABLE ai_messages (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'complete', 'error', 'error:hidden')),
    model TEXT NOT NULL DEFAULT 'flash',
    parent_message_id INTEGER REFERENCES ai_messages(id),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
"""

TABLES_IN_ORDER = [
    "ai_messages", "ocr_jobs", "budgets",
    "household_members", "households", "transactions",
    "email_verifications", "categories", "users",
]


async def _create_test_db():
    """Create a fresh connection and initialize schema + seed data.
    Returns the connection. Caller must close it.
    """
    conn = await asyncpg.connect(TEST_DB_URL)
    await conn.execute(SCHEMA_SQL)
    # Seed
    for u in DEFAULT_USERS:
        await conn.execute(
            "INSERT INTO users (id, username, display_name, password_hash, role, email) VALUES ($1, $2, $3, $4, $5, $6)",
            *u,
        )
    for cat in DEFAULT_CATEGORIES:
        await conn.execute(
            "INSERT INTO categories (id, name, type, icon, is_default, sort_order, name_en, keywords) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
            *cat,
        )
    for i, t in enumerate(DEFAULT_TRANSACTIONS):
        day_offset = len(DEFAULT_TRANSACTIONS) - i
        await conn.execute(
            "INSERT INTO transactions (id, type, amount, category_id, category_name, description, note, date, user_id, created_at) "
            "VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_DATE - MAKE_INTERVAL(days => $8), 1, NOW())",
            t[0], t[1], t[2], t[3], t[4], t[5], t[6], day_offset,
        )
    await conn.execute(
        "INSERT INTO households (id, name, invite_code, created_by) VALUES (1, 'Home', 'TESTCODE1', 1)"
    )
    for uid in [1, 2]:
        role = 'admin' if uid == 1 else 'member'
        await conn.execute(
            "INSERT INTO household_members (user_id, household_id, role) VALUES ($1, 1, $2)",
            uid, role,
        )
    # Reset sequences to prevent conflicts with auto-generated ids
    for tbl in ["users", "categories", "transactions", "households", "budgets", "email_verifications", "ocr_jobs", "ai_messages"]:
        await conn.execute(f"SELECT setval('{tbl}_id_seq', COALESCE((SELECT MAX(id) FROM {tbl}), 0) + 1, false)")
    return conn


# ─── Fixtures (function-scoped) ───────────────────────────────

@pytest_asyncio.fixture
async def db() -> AsyncGenerator[CursorWrapper, None]:
    """Provide a seeded DB connection wrapped in CursorWrapper."""
    conn = await _create_test_db()
    wrapper = CursorWrapper(conn, None)
    try:
        yield wrapper
    finally:
        await conn.close()


@pytest_asyncio.fixture
async def client(db: CursorWrapper) -> AsyncGenerator[AsyncClient, None]:
    """FastAPI test client with overridden DB dependency."""
    async def override_get_db():
        yield db

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def filla_token(db: CursorWrapper) -> str:
    """JWT token for user filla (admin)."""
    return create_access_token(user_id=1, username="filla", role="admin")


@pytest_asyncio.fixture
async def nahda_token(db: CursorWrapper) -> str:
    """JWT token for user nahda (non-admin)."""
    return create_access_token(user_id=2, username="nahda", role="user")


@pytest_asyncio.fixture
async def fake_token() -> str:
    """JWT with non-existent user ID."""
    return create_access_token(user_id=999, username="ghost")


@pytest_asyncio.fixture
async def empty_token(client: AsyncClient, db: CursorWrapper) -> str:
    """JWT token for a user with no transaction data."""
    from passlib.context import CryptContext
    pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
    pw_hash = pwd_ctx.hash("Test1234!")
    await db.execute(
        "INSERT INTO users (id, username, display_name, password_hash, role, email) VALUES (99, 'emptyuser', 'Empty', $1, 'user', 'empty@example.com')",
        (pw_hash,),
    )
    return create_access_token(user_id=99, username="emptyuser", role="user")
