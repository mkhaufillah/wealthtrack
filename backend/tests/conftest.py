"""
WealthTrack Test Suite — Pytest Configuration & Fixtures.

How to run:
    cd ~/dev/wealthtrack
    source .venv/bin/activate
    uv pip install -r backend/requirements.txt   # one-time
    pytest backend/tests/ -v

Does NOT touch the real database (~/.keuangan/finance.db).
Uses a temporary file-based SQLite, seeded fresh per session.
"""

import os
import tempfile
from typing import AsyncGenerator

import sqlite3

import aiosqlite
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from passlib.context import CryptContext

from app.database import get_db
from app.main import app
from app.core.security import create_access_token

# ─── Test database ─────────────────────────────────────────────

PWD_CTX = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Seed data
DEFAULT_USERS = [
    (1, "filla", "Filla", PWD_CTX.hash("password123"), "admin"),
    (2, "nahda", "Nahda", PWD_CTX.hash("password123"), "user"),
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


def create_test_db(db_path: str):
    """Create and seed a test database (synchronous — uses sqlite3)."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA foreign_keys=ON;")

    conn.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'user',
            cycle_start_day INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            icon TEXT DEFAULT '',
            is_default INTEGER DEFAULT 0,
            name_en TEXT DEFAULT '',
            keywords TEXT DEFAULT '[]',
            sort_order INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            category_id INTEGER,
            category_name TEXT DEFAULT '',
            description TEXT DEFAULT '',
            source TEXT DEFAULT '',
            image_path TEXT DEFAULT '',
            created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
            user_id INTEGER REFERENCES users(id),
            date TEXT,
            note TEXT DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS households (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            invite_code TEXT UNIQUE NOT NULL,
            created_by INTEGER NOT NULL REFERENCES users(id),
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
        );
        CREATE TABLE IF NOT EXISTS household_members (
            user_id INTEGER NOT NULL REFERENCES users(id),
            household_id INTEGER NOT NULL REFERENCES households(id),
            role TEXT NOT NULL DEFAULT 'member',
            joined_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
            PRIMARY KEY (user_id, household_id)
        );
        CREATE TABLE IF NOT EXISTS budgets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users(id),
            month TEXT NOT NULL,
            category_id INTEGER NOT NULL,
            category_name TEXT NOT NULL,
            budget_amount INTEGER NOT NULL,
            cycle_on INTEGER NOT NULL DEFAULT 1,
            UNIQUE(user_id, month, category_id)
        );
    """)

    for u in DEFAULT_USERS:
        conn.execute(
            "INSERT OR IGNORE INTO users (id, username, display_name, password_hash, role) VALUES (?, ?, ?, ?, ?)",
            u,
        )
    for cat in DEFAULT_CATEGORIES:
        conn.execute(
            "INSERT OR IGNORE INTO categories (id, name, type, icon, is_default, sort_order, name_en, keywords) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            cat,
        )
    for i, t in enumerate(DEFAULT_TRANSACTIONS):
        day_offset = len(DEFAULT_TRANSACTIONS) - i
        conn.execute(
            "INSERT OR IGNORE INTO transactions (id, type, amount, category_id, category_name, description, note, date, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, date('now', '-' || ? || ' days'), 1, strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
            t + (day_offset,),
        )

    # Seed default household — all existing users are members
    conn.execute(
        "INSERT OR IGNORE INTO households (id, name, invite_code, created_by) VALUES (1, 'Home', 'TESTCODE1', 1)"
    )
    for uid in [1, 2]:
        role = 'admin' if uid == 1 else 'member'
        conn.execute(
            "INSERT OR IGNORE INTO household_members (user_id, household_id, role) VALUES (?, 1, ?)",
            (uid, role),
        )

    conn.commit()
    conn.close()


# ─── Fixtures ──────────────────────────────────────────────────

@pytest.fixture(scope="function")
def test_db_path() -> str:
    """Create temp database file, seed it, yield path, then clean up."""
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    tmp.close()
    create_test_db(tmp.name)
    yield tmp.name
    os.unlink(tmp.name)


@pytest_asyncio.fixture
async def db(test_db_path: str) -> AsyncGenerator[aiosqlite.Connection, None]:
    """Provide a test database connection."""
    conn = await aiosqlite.connect(test_db_path)
    conn.row_factory = aiosqlite.Row
    await conn.execute("PRAGMA journal_mode=WAL;")
    await conn.execute("PRAGMA foreign_keys=ON;")
    try:
        yield conn
    finally:
        await conn.close()


@pytest_asyncio.fixture
async def client(db: aiosqlite.Connection) -> AsyncGenerator[AsyncClient, None]:
    """FastAPI test client with overridden DB dependency."""
    async def override_get_db():
        yield db

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def filla_token(db: aiosqlite.Connection) -> str:
    """JWT token for user filla (admin)."""
    return create_access_token(user_id=1, username="filla", role="admin")


@pytest_asyncio.fixture
async def nahda_token(db: aiosqlite.Connection) -> str:
    """JWT token for user nahda (non-admin)."""
    return create_access_token(user_id=2, username="nahda", role="user")


@pytest_asyncio.fixture
async def fake_token() -> str:
    """JWT with non-existent user ID."""
    return create_access_token(user_id=999, username="ghost")
