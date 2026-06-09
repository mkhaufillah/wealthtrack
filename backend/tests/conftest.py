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
    "postgresql://wealthtrack_test:***@localhost:5433/wealthtrack_test",
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
DROP TABLE IF EXISTS kpr_extra_payments CASCADE;
DROP TABLE IF EXISTS kpr_monthly_schedules CASCADE;
DROP TABLE IF EXISTS kpr_rate_periods CASCADE;
DROP TABLE IF EXISTS kpr_simulations CASCADE;
DROP TABLE IF EXISTS credit_card_transactions CASCADE;
DROP TABLE IF EXISTS credit_card_installments CASCADE;
DROP TABLE IF EXISTS credit_cards CASCADE;
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
CREATE TABLE kpr_simulations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    name TEXT NOT NULL DEFAULT 'KPR Simulation',
    property_price INTEGER NOT NULL DEFAULT 0,
    down_payment INTEGER NOT NULL DEFAULT 0,
    total_loan INTEGER NOT NULL DEFAULT 0,
    tenor_months INTEGER NOT NULL DEFAULT 120,
    interest_type TEXT NOT NULL DEFAULT 'fixed' CHECK(interest_type IN ('fixed', 'floating', 'graduated', 'mix')),
    base_interest_rate NUMERIC(6,4) NOT NULL DEFAULT 0.075,
    graduated_increment NUMERIC(6,4) NOT NULL DEFAULT 0.005,
    graduated_every_months INTEGER NOT NULL DEFAULT 12,
    start_month INTEGER NOT NULL DEFAULT 1,
    start_year INTEGER NOT NULL DEFAULT 2026,
    due_date INTEGER DEFAULT NULL,
    household_id INTEGER DEFAULT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
CREATE TABLE kpr_rate_periods (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    period_start INTEGER NOT NULL,
    period_end INTEGER NOT NULL,
    interest_rate NUMERIC(6,4) NOT NULL,
    rate_type TEXT NOT NULL DEFAULT 'fixed' CHECK(rate_type IN ('fixed', 'floating')),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
CREATE TABLE kpr_monthly_schedules (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    month_number INTEGER NOT NULL,
    payment INTEGER NOT NULL,
    principal INTEGER NOT NULL,
    interest INTEGER NOT NULL,
    remaining_balance INTEGER NOT NULL,
    rate_type TEXT NOT NULL,
    interest_rate NUMERIC(6,4) NOT NULL,
    UNIQUE(simulation_id, month_number)
);

CREATE TABLE IF NOT EXISTS kpr_extra_payments (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,
    penalty_rate NUMERIC(6,4) NOT NULL DEFAULT 0,
    penalty_amount INTEGER NOT NULL DEFAULT 0,
    apply_month INTEGER NOT NULL,
    reduction_type TEXT NOT NULL DEFAULT 'tenor' CHECK(reduction_type IN ('tenor', 'installment')),
    old_remaining_balance INTEGER NOT NULL,
    new_remaining_balance INTEGER NOT NULL,
    old_remaining_months INTEGER NOT NULL,
    new_remaining_months INTEGER NOT NULL,
    old_installment INTEGER NOT NULL DEFAULT 0,
    new_installment INTEGER NOT NULL DEFAULT 0,
    total_interest_saved INTEGER NOT NULL DEFAULT 0,
    original_end_date TEXT DEFAULT '',
    new_end_date TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE TABLE IF NOT EXISTS credit_cards (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    card_number_last4 TEXT DEFAULT '',
    billing_date INTEGER NOT NULL DEFAULT 1,
    due_date INTEGER NOT NULL DEFAULT 15,
    credit_limit INTEGER DEFAULT 0,
    household_id INTEGER DEFAULT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE TABLE IF NOT EXISTS credit_card_installments (
    id SERIAL PRIMARY KEY,
    card_id INTEGER NOT NULL REFERENCES credit_cards(id) ON DELETE CASCADE,
    description TEXT NOT NULL DEFAULT '',
    total_amount INTEGER NOT NULL,
    monthly_amount INTEGER NOT NULL,
    total_months INTEGER NOT NULL,
    remaining_months INTEGER NOT NULL,
    start_month TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE TABLE IF NOT EXISTS credit_card_transactions (
    id SERIAL PRIMARY KEY,
    card_id INTEGER NOT NULL REFERENCES credit_cards(id) ON DELETE CASCADE,
    description TEXT NOT NULL DEFAULT '',
    amount INTEGER NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    transaction_date TEXT NOT NULL,
    is_installment INTEGER NOT NULL DEFAULT 0,
    installment_id INTEGER REFERENCES credit_card_installments(id),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
"""

TABLES_IN_ORDER = [
    "kpr_extra_payments", "credit_card_transactions", "credit_card_installments", "credit_cards",
    "kpr_monthly_schedules", "kpr_rate_periods", "kpr_simulations",
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
            "VALUES ($1, $2, $3, $4, $5, $6, $7, (CURRENT_DATE - MAKE_INTERVAL(days => $8))::date, 1, NOW())",
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
    for tbl in ["users", "categories", "transactions", "households", "budgets", "email_verifications", "ocr_jobs", "ai_messages", "kpr_simulations", "kpr_rate_periods", "kpr_monthly_schedules", "credit_cards", "credit_card_installments", "credit_card_transactions"]:
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
async def auth_headers(filla_token: str) -> dict:
    """Authorization headers for filla (admin)."""
    return {"Authorization": f"Bearer {filla_token}"}


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
