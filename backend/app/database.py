"""
WealthTrack PostgreSQL Database Connection.

Uses asyncpg with a thin wrapper that provides cursor-like interface
for backward compatibility with the existing codebase patterns.
"""

import re
import asyncio
import asyncpg

from contextlib import asynccontextmanager

from app.core.config import settings

pool: asyncpg.Pool | None = None

# ── Global background task tracking for clean shutdown ──────────────
background_tasks: set[asyncio.Task] = set()


class CursorWrapper:
    """Wraps an asyncpg connection to provide cursor-like interface.

    - ``await db.execute(sql, params)`` → returns ``self`` for chaining
    - ``await cursor.fetchone()`` → returns first row or None
    - ``await cursor.fetchall()`` → returns list of rows
    - ``cursor.lastrowid`` → returns last inserted id (via RETURNING)
    - ``async for row in cursor:`` → iterates over fetched rows
    - ``close()`` → releases connection back to pool

    Automatically converts ``?`` placeholders to ``$1, $2, ...`` and
    appends ``RETURNING id`` to INSERT statements that don't have one.
    """

    def __init__(self, conn: asyncpg.Connection, pool_ref: asyncpg.Pool | None = None):
        self._conn = conn
        self._pool = pool_ref
        self._rows: list[asyncpg.Record] = []
        self._row_index = 0
        self._lastrowid_val: int | None = None

    # ── Cursor-like interface ──────────────────────────────────

    async def execute(self, query: str, *args):
        """Execute query and store result for cursor operations.

        Handles three cases:
        - ``SELECT`` / ``RETURNING`` → store result rows
        - ``INSERT`` without RETURNING → append RETURNING id, store lastrowid
        - Other (UPDATE, DELETE) → execute directly
        """
        # Flatten tuple/list arg
        params = args[0] if args and isinstance(args[0], (list, tuple)) else args

        sql = self._number_params(query, len(params))
        upper = sql.strip().upper()

        self._rows = []
        self._row_index = 0
        self._lastrowid_val = None

        if upper.startswith("INSERT"):
            if "RETURNING" not in upper:
                # Try RETURNING id — falls back to no RETURNING for tables 
                # with composite PK (e.g. household_members)
                try:
                    sql_with_returning = sql.rstrip().rstrip(";") + " RETURNING id"
                    self._lastrowid_val = await self._conn.fetchval(sql_with_returning, *params)
                except asyncpg.UndefinedColumnError:
                    # Column "id" doesn't exist (composite PK), execute normally
                    await self._conn.execute(sql, *params)
            else:
                self._lastrowid_val = await self._conn.fetchval(sql, *params)
        elif upper.startswith("SELECT") or "RETURNING" in upper:
            self._rows = await self._conn.fetch(sql, *params)
        else:
            await self._conn.execute(sql, *params)

        return self

    async def fetchone(self) -> asyncpg.Record | None:
        return self._rows[0] if self._rows else None

    async def fetchall(self) -> list[asyncpg.Record]:
        return self._rows

    @property
    def lastrowid(self) -> int | None:
        return self._lastrowid_val

    # ── Async iteration over results ───────────────────────────

    def __aiter__(self):
        self._row_index = 0
        return self

    async def __anext__(self) -> asyncpg.Record:
        if self._row_index < len(self._rows):
            row = self._rows[self._row_index]
            self._row_index += 1
            return row
        raise StopAsyncIteration

    # ── Placeholder conversion ─────────────────────────────────

    @staticmethod
    def _number_params(query: str, param_count: int) -> str:
        """Replace ``?`` with ``$1, $2, ...``, skipping inside string literals."""
        if "?" not in query:
            return query

        result = []
        in_sq = False  # inside single-quoted string
        in_dq = False  # inside double-quoted string
        counter = 0

        for char in query:
            if char == "'" and not in_dq:
                in_sq = not in_sq
                result.append(char)
            elif char == '"' and not in_sq:
                in_dq = not in_dq
                result.append(char)
            elif char == "?" and not in_sq and not in_dq:
                counter += 1
                if counter <= param_count:
                    result.append(f"${counter}")
                else:
                    result.append("?")
            else:
                result.append(char)

        return "".join(result)

    # ── Close / cleanup ────────────────────────────────────────

    async def commit(self):
        """No-op compatibility — asyncpg auto-commits each statement.
        Preserved for test compatibility."""
        pass

    async def close(self):
        """Release the underlying connection back to the pool."""
        if self._pool is not None:
            await self._pool.release(self._conn)
        else:
            await self._conn.close()

    @asynccontextmanager
    async def transaction(self):
        """Context manager for atomic multi-statement transactions.

        Usage:
            async with db.transaction():
                await db.execute(...)
                await db.execute(...)

        All statements inside the block run in a single PostgreSQL
        transaction — if any fails, all changes are rolled back.
        """
        async with self._conn.transaction():
            yield

    # ── Delegate other attrs to underlying connection ──────────

    def __getattr__(self, name):
        return getattr(self._conn, name)


# ── Pool lifecycle ────────────────────────────────────────────────


async def init_pool():
    global pool
    pool = await asyncpg.create_pool(
        dsn=settings.DATABASE_URL,
        min_size=2,
        max_size=10,
        command_timeout=30,
    )
    # Auto-create schema on first connection (idempotent)
    assert pool is not None
    async with pool.acquire() as conn:
        await _init_schema(conn)


SCHEMA_SQL = """
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

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email != '';

CREATE TABLE IF NOT EXISTS email_verifications (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    verified INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_email_verifications_email ON email_verifications(email);

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

CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(COALESCE(date, LEFT(created_at, 10)));
CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date DESC NULLS LAST);

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

CREATE INDEX IF NOT EXISTS idx_budgets_user_month ON budgets(user_id, month);

CREATE TABLE IF NOT EXISTS households (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
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

CREATE INDEX IF NOT EXISTS idx_household_members_user ON household_members(user_id);
CREATE INDEX IF NOT EXISTS idx_household_members_household ON household_members(household_id);

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

CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_status ON ocr_jobs(user_id, status);

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

CREATE INDEX IF NOT EXISTS idx_ai_messages_user ON ai_messages(user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_transactions_user_type_date ON transactions(user_id, type, COALESCE(date, LEFT(created_at, 10)));
CREATE INDEX IF NOT EXISTS idx_transactions_user_cat_date ON transactions(user_id, category_id, COALESCE(date, LEFT(created_at, 10)) DESC);
CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_created ON ocr_jobs(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS kpr_simulations (
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
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_simulations_user ON kpr_simulations(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS kpr_rate_periods (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    period_start INTEGER NOT NULL,
    period_end INTEGER NOT NULL,
    interest_rate NUMERIC(6,4) NOT NULL,
    rate_type TEXT NOT NULL DEFAULT 'fixed' CHECK(rate_type IN ('fixed', 'floating')),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_rate_periods_sim ON kpr_rate_periods(simulation_id);

CREATE TABLE IF NOT EXISTS kpr_monthly_schedules (
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

CREATE INDEX IF NOT EXISTS idx_kpr_schedules_sim ON kpr_monthly_schedules(simulation_id);

-- Household debt support
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS household_id INTEGER REFERENCES households(id);
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;
-- Legacy column migration (safe on existing)
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS base_interest_rate NUMERIC(6,4) NOT NULL DEFAULT 0.075;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS graduated_increment NUMERIC(6,4) NOT NULL DEFAULT 0.005;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS graduated_every_months INTEGER NOT NULL DEFAULT 12;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_month INTEGER NOT NULL DEFAULT 1;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_year INTEGER NOT NULL DEFAULT 2026;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS due_date INTEGER DEFAULT NULL;
CREATE INDEX IF NOT EXISTS idx_kpr_simulations_household ON kpr_simulations(household_id);

CREATE TABLE IF NOT EXISTS kpr_extra_payments (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,
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

CREATE INDEX IF NOT EXISTS idx_kpr_extra_payments_sim ON kpr_extra_payments(simulation_id);

CREATE TABLE IF NOT EXISTS credit_cards (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    card_number_last4 TEXT DEFAULT '',
    billing_date INTEGER NOT NULL DEFAULT 1,
    due_date INTEGER NOT NULL DEFAULT 15,
    credit_limit INTEGER DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_credit_cards_user ON credit_cards(user_id);

-- Household debt support for CC
ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS household_id INTEGER REFERENCES households(id);
ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_credit_cards_household ON credit_cards(household_id);

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

CREATE INDEX IF NOT EXISTS idx_cc_transactions_card ON credit_card_transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_cc_transactions_date ON credit_card_transactions(transaction_date DESC);

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

CREATE INDEX IF NOT EXISTS idx_cc_installments_card ON credit_card_installments(card_id);
"""


async def _init_schema(conn):
    """Create tables and indexes if they don't exist. Idempotent."""
    # Split by semicolons and execute each statement
    for statement in SCHEMA_SQL.split(';'):
        stmt = statement.strip()
        if stmt and not stmt.startswith('--'):
            try:
                await conn.execute(stmt)
            except Exception as e:
                print(f"Schema init warning (non-fatal): {e}")



async def close_pool():
    global pool
    if pool is not None:
        await pool.close()
        pool = None


async def get_db():
    """Dependency: yields a CursorWrapper (asyncpg connection + cursor compat).

    Each ``await db.execute()`` auto-commits (single-statement transactions).
    For multi-statement atomicity, use ``async with db.transaction():``.
    """
    if pool is None:
        # Return None for test environments (MCP tests don't need real DB)
        yield None
        return
    conn = await pool.acquire()
    try:
        yield CursorWrapper(conn, pool)
    finally:
        await pool.release(conn)


async def get_db_bg():
    """Create a standalone background connection.

    Unlike get_db() (request-scoped), this returns an unbounded connection
    that the caller must close explicitly via wrapper.close().
    """
    if pool is None:
        return None
    conn = await pool.acquire()
    return CursorWrapper(conn, pool)
