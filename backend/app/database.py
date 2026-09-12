"""
WealthTrack PostgreSQL Database Connection.

Uses asyncpg with a thin wrapper that provides cursor-like interface
for backward compatibility with the existing codebase patterns.
"""

import asyncio
from contextlib import asynccontextmanager

import asyncpg

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
    locale TEXT NOT NULL DEFAULT 'id-ID',
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
    keywords TEXT DEFAULT '[]',
    copy_key TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    amount INTEGER NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    category_name TEXT DEFAULT '',
    description TEXT DEFAULT '',
    source TEXT DEFAULT 'manual',
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
    cycle_on INTEGER NOT NULL DEFAULT 1,
    vault_blob TEXT DEFAULT '',
    amount_ord BIGINT,
    category_trace TEXT DEFAULT '',
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
    status TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'completed', 'failed')),
    transaction_id INTEGER REFERENCES transactions(id),
    error TEXT,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_status ON ocr_jobs(user_id, status);

CREATE TABLE IF NOT EXISTS bank_inbox (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    package TEXT NOT NULL,
    bank TEXT,
    posted_at TEXT NOT NULL DEFAULT '',
    txn_type TEXT,
    parsed INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'confirmed', 'rejected')),
    fingerprint TEXT NOT NULL,
    transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    UNIQUE(user_id, fingerprint)
);

ALTER TABLE bank_inbox DROP CONSTRAINT IF EXISTS bank_inbox_transaction_id_fkey;
ALTER TABLE bank_inbox ADD CONSTRAINT bank_inbox_transaction_id_fkey
    FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bank_inbox_user_status ON bank_inbox(user_id, status);

DROP TABLE IF EXISTS bank_category_rules CASCADE;

CREATE TABLE IF NOT EXISTS ai_messages (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    status TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'complete', 'error', 'error:hidden')),
    model TEXT NOT NULL DEFAULT 'flash',
    parent_message_id INTEGER REFERENCES ai_messages(id),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_ai_messages_user ON ai_messages(user_id, created_at);

CREATE TABLE IF NOT EXISTS ai_chat_summaries (
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    covered_through_id INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_type_date ON transactions(user_id, type, COALESCE(date, LEFT(created_at, 10)));
CREATE INDEX IF NOT EXISTS idx_transactions_user_cat_date ON transactions(user_id, category_id, COALESCE(date, LEFT(created_at, 10)) DESC);
CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_created ON ocr_jobs(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS kpr_simulations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    tenor_months INTEGER NOT NULL DEFAULT 120,
    interest_type TEXT NOT NULL DEFAULT 'fixed' CHECK(interest_type IN ('fixed', 'floating', 'graduated', 'mix')),
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
    rate_type TEXT NOT NULL DEFAULT 'fixed' CHECK(rate_type IN ('fixed', 'floating')),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_rate_periods_sim ON kpr_rate_periods(simulation_id);

CREATE TABLE IF NOT EXISTS kpr_monthly_schedules (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    month_number INTEGER NOT NULL,
    rate_type TEXT NOT NULL,
    vault_blob TEXT DEFAULT '',
    amount_ord BIGINT,
    UNIQUE(simulation_id, month_number)
);

CREATE INDEX IF NOT EXISTS idx_kpr_schedules_sim ON kpr_monthly_schedules(simulation_id);

-- Household debt support
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS household_id INTEGER REFERENCES households(id);
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_month INTEGER NOT NULL DEFAULT 1;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_year INTEGER NOT NULL DEFAULT 2026;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS due_date INTEGER DEFAULT NULL;
CREATE INDEX IF NOT EXISTS idx_kpr_simulations_household ON kpr_simulations(household_id);

CREATE TABLE IF NOT EXISTS kpr_extra_payments (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    apply_month INTEGER NOT NULL,
    reduction_type TEXT NOT NULL DEFAULT 'tenor' CHECK(reduction_type IN ('tenor', 'installment')),
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_extra_payments_sim ON kpr_extra_payments(simulation_id);

CREATE TABLE IF NOT EXISTS credit_cards (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    billing_date INTEGER NOT NULL DEFAULT 1,
    due_date INTEGER NOT NULL DEFAULT 15,
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
    transaction_date TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_cc_transactions_card ON credit_card_transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_cc_transactions_date ON credit_card_transactions(transaction_date DESC);

CREATE TABLE IF NOT EXISTS credit_card_installments (
    id SERIAL PRIMARY KEY,
    card_id INTEGER NOT NULL REFERENCES credit_cards(id) ON DELETE CASCADE,
    total_months INTEGER NOT NULL,
    remaining_months INTEGER NOT NULL,
    start_month TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_cc_installments_card ON credit_card_installments(card_id);

CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    key_hash TEXT NOT NULL UNIQUE,
    scopes TEXT[] NOT NULL DEFAULT ARRAY['mcp:read'],
    is_active INTEGER NOT NULL DEFAULT 1,
    last_used_at TEXT,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_api_keys_user ON api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON api_keys(key_hash);

CREATE TABLE IF NOT EXISTS ui_copy (
    key TEXT NOT NULL,
    locale TEXT NOT NULL DEFAULT 'id-ID',
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (key, locale)
);

CREATE TABLE IF NOT EXISTS ui_config (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"""


ICON_EMOJI_MAP = [
    (("🍽️", "🍽", "🍔", "🍜", "🍱"), "strokeRoundedServingFood"),
    (("🚗", "🛵"), "strokeRoundedCar01"),
    (("⛽", "⛽️"), "strokeRoundedFuelStation"),
    (("🛒", "🛍️"), "strokeRoundedShoppingBag01"),
    (("💡", "⚡"), "strokeRoundedHome01"),
    (("🏥", "💊"), "strokeRoundedMedicineBottle01"),
    (("🎓",), "strokeRoundedSchool"),
    (("🎮",), "strokeRoundedGameController01"),
    (("💰", "💵"), "strokeRoundedMoneyBag01"),
    (("🏦",), "strokeRoundedBank"),
    (("📱",), "strokeRoundedSmartPhone01"),
    (("🏠",), "strokeRoundedHouse01"),
    (("👕",), "strokeRoundedClothes"),
    (("🎁",), "strokeRoundedGift"),
    (("✈️", "✈"), "strokeRoundedAirplane01"),
    (("🐶", "🐱"), "strokeRoundedFishFood"),
    (("🎬",), "strokeRoundedTv01"),
    (("📄",), "strokeRoundedInvoice01"),
    (("💻",), "strokeRoundedLaptop"),
    (("🔄",), "strokeRoundedExchange01"),
]


async def _migrate_category_icons(conn):
    """Map leftover emoji icons to Hugeicons keys; drop name_en."""
    try:
        for emojis, key in ICON_EMOJI_MAP:
            placeholders = ", ".join(f"${i+1}" for i in range(len(emojis)))
            await conn.execute(
                f"UPDATE categories SET icon = ${len(emojis)+1} WHERE icon IN ({placeholders})",
                *emojis,
                key,
            )
        await conn.execute(
            """UPDATE categories SET icon = 'strokeRoundedInvoice01'
               WHERE icon IS NULL OR icon = '' OR icon NOT LIKE 'strokeRounded%'"""
        )
        name_icons = {
            "Dana Darurat": "strokeRoundedPiggyBank",
            "Kebutuhan Pribadi": "strokeRoundedUser",
            "Protein, Buah, dan Sayuran": "strokeRoundedServingFood",
            "Hobi & Belajar": "strokeRoundedSchool",
            "Kebutuhan Rumah": "strokeRoundedHouse01",
            "Tagihan & Cicilan": "strokeRoundedInvoice01",
            "Pendidikan": "strokeRoundedSchool",
            "Kebutuhan Bayi/Anak": "strokeRoundedGift",
            "Lainnya": "strokeRoundedSparkles",
            "Freelance": "strokeRoundedLaptop",
            "Hasil Investasi": "strokeRoundedMoneyBag01",
            "Penarikan Tabungan & Investasi": "strokeRoundedWallet01",
        }
        for name, key in name_icons.items():
            await conn.execute(
                "UPDATE categories SET icon = $1 WHERE name = $2 AND icon = 'strokeRoundedInvoice01'",
                key,
                name,
            )
        await conn.execute(
            """UPDATE transactions SET description = replace(description, 'Transfer to ', 'Transfer ke ')
               WHERE description LIKE 'Transfer to %'"""
        )
        await conn.execute(
            """UPDATE transactions SET description = replace(description, 'Transfer from ', 'Transfer dari ')
               WHERE description LIKE 'Transfer from %'"""
        )
    except Exception as e:
        print(f"Schema init warning (non-fatal): {e}")
    try:
        await conn.execute("ALTER TABLE categories DROP COLUMN IF EXISTS name_en")
    except Exception as e:
        print(f"Schema init warning (non-fatal): {e}")


async def _migrate_i18n(conn) -> None:
    """Add locale + copy_key columns (existing DBs). Needs table owner."""
    try:
        await conn.execute(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL DEFAULT 'id-ID'"
        )
    except Exception as e:
        print(f"CRITICAL: cannot add users.locale ({e}). GET /auth/me will 500.")
    try:
        await conn.execute(
            "ALTER TABLE categories ADD COLUMN IF NOT EXISTS copy_key TEXT DEFAULT ''"
        )
    except Exception as e:
        print(f"CRITICAL: cannot add categories.copy_key ({e}).")


async def _assign_category_copy_keys(conn) -> None:
    from app.core.i18n import CATEGORY_COPY_KEYS

    for (name, type_), key in CATEGORY_COPY_KEYS.items():
        await conn.execute(
            """UPDATE categories SET copy_key = $1
               WHERE name = $2 AND type = $3
                 AND (copy_key IS NULL OR copy_key = '')""",
            key,
            name,
            type_,
        )
    await conn.execute(
        """UPDATE categories SET copy_key = 'cat.n.custom.' || id::text
           WHERE copy_key IS NULL OR copy_key = ''"""
    )


async def _migrate_vault(conn) -> None:
    stmts = [
        "ALTER TABLE households ADD COLUMN IF NOT EXISTS vault_sealed INTEGER NOT NULL DEFAULT 0",
        """CREATE TABLE IF NOT EXISTS household_key_wraps (
            household_id INTEGER NOT NULL REFERENCES households(id) ON DELETE CASCADE,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            wrapped_dek TEXT NOT NULL,
            kdf_salt TEXT NOT NULL DEFAULT '',
            kdf_params TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (household_id, user_id)
        )""",
        """CREATE TABLE IF NOT EXISTS household_vault_pubkeys (
            user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            household_id INTEGER NOT NULL REFERENCES households(id) ON DELETE CASCADE,
            public_key TEXT NOT NULL
        )""",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS category_trace TEXT DEFAULT ''",
        "ALTER TABLE budgets ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE budgets ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE budgets ADD COLUMN IF NOT EXISTS category_trace TEXT DEFAULT ''",
        "ALTER TABLE bank_inbox ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE bank_inbox ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE credit_card_transactions ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE credit_card_transactions ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE credit_card_installments ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE credit_card_installments ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE kpr_extra_payments ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE kpr_extra_payments ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE kpr_monthly_schedules ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE kpr_monthly_schedules ADD COLUMN IF NOT EXISTS amount_ord BIGINT",
        "ALTER TABLE kpr_rate_periods ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE ai_messages ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE ai_chat_summaries ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE ocr_jobs ADD COLUMN IF NOT EXISTS vault_blob TEXT DEFAULT ''",
        "ALTER TABLE budgets DROP COLUMN IF EXISTS budget_amount",
        "ALTER TABLE budgets DROP COLUMN IF EXISTS category_name",
        "ALTER TABLE kpr_simulations DROP COLUMN IF EXISTS property_price",
        "ALTER TABLE kpr_simulations DROP COLUMN IF EXISTS down_payment",
        "ALTER TABLE kpr_simulations DROP COLUMN IF EXISTS total_loan",
        "ALTER TABLE kpr_simulations DROP COLUMN IF EXISTS base_interest_rate",
        "ALTER TABLE kpr_simulations DROP COLUMN IF EXISTS graduated_increment",
        "ALTER TABLE kpr_simulations DROP COLUMN IF EXISTS graduated_every_months",
        "ALTER TABLE kpr_rate_periods DROP COLUMN IF EXISTS interest_rate",
        "ALTER TABLE kpr_monthly_schedules DROP COLUMN IF EXISTS payment",
        "ALTER TABLE kpr_monthly_schedules DROP COLUMN IF EXISTS principal",
        "ALTER TABLE kpr_monthly_schedules DROP COLUMN IF EXISTS interest",
        "ALTER TABLE kpr_monthly_schedules DROP COLUMN IF EXISTS remaining_balance",
        "ALTER TABLE kpr_monthly_schedules DROP COLUMN IF EXISTS interest_rate",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS amount",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS old_remaining_balance",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS new_remaining_balance",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS old_remaining_months",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS new_remaining_months",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS old_installment",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS new_installment",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS total_interest_saved",
        "ALTER TABLE credit_cards DROP COLUMN IF EXISTS credit_limit",
        "ALTER TABLE credit_cards DROP COLUMN IF EXISTS card_number_last4",
        "ALTER TABLE credit_cards DROP COLUMN IF EXISTS name",
        "ALTER TABLE credit_card_transactions DROP COLUMN IF EXISTS description",
        "ALTER TABLE credit_card_transactions DROP COLUMN IF EXISTS amount",
        "ALTER TABLE credit_card_installments DROP COLUMN IF EXISTS description",
        "ALTER TABLE credit_card_installments DROP COLUMN IF EXISTS total_amount",
        "ALTER TABLE credit_card_installments DROP COLUMN IF EXISTS monthly_amount",
        "ALTER TABLE ai_messages DROP COLUMN IF EXISTS content",
        "ALTER TABLE ai_chat_summaries DROP COLUMN IF EXISTS summary",
        "ALTER TABLE bank_inbox DROP COLUMN IF EXISTS title",
        "ALTER TABLE bank_inbox DROP COLUMN IF EXISTS text",
        "ALTER TABLE bank_inbox DROP COLUMN IF EXISTS amount",
        "ALTER TABLE bank_inbox DROP COLUMN IF EXISTS merchant",
        "ALTER TABLE ocr_jobs DROP COLUMN IF EXISTS image_filename",
        "ALTER TABLE ocr_jobs DROP COLUMN IF EXISTS raw_text",
        "ALTER TABLE ocr_jobs DROP COLUMN IF EXISTS vault_blob",
        "ALTER TABLE kpr_simulations DROP COLUMN IF EXISTS name",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS original_end_date",
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS new_end_date",
        "ALTER TABLE transactions DROP COLUMN IF EXISTS category_id",
        "ALTER TABLE budgets DROP CONSTRAINT IF EXISTS budgets_user_id_month_category_id_key",
        "ALTER TABLE budgets DROP COLUMN IF EXISTS category_id",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_budgets_user_month_trace ON budgets(user_id, month, category_trace)",
        "ALTER TABLE credit_card_transactions DROP COLUMN IF EXISTS category_id",
        "ALTER TABLE credit_card_transactions DROP COLUMN IF EXISTS installment_id",
        "ALTER TABLE credit_card_transactions DROP COLUMN IF EXISTS is_installment",
    ]
    for sql in stmts:
        try:
            await conn.execute(sql)
        except Exception as e:
            print(f"CRITICAL vault migrate failed (need table owner): {e}")


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
    await _migrate_category_icons(conn)
    await _migrate_i18n(conn)
    await _migrate_vault(conn)
    from app.core.ui_seed import seed_ui
    try:
        await seed_ui(conn)
        await _assign_category_copy_keys(conn)
        await conn.execute("DELETE FROM ui_copy WHERE key LIKE 'bank.rules%'")
    except Exception as e:
        print(f"UI seed warning (non-fatal): {e}")



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
