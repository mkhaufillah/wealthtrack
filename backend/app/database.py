"""
WealthTrack PostgreSQL Database Connection.

Uses asyncpg with a thin wrapper that provides cursor-like interface
for backward compatibility with the existing codebase patterns.
"""

import re
import asyncpg

from app.core.config import settings

pool: asyncpg.Pool | None = None


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
        raise RuntimeError("Database pool not initialized. Call init_pool() first.")
    conn = await pool.acquire()
    try:
        yield CursorWrapper(conn, pool)
    finally:
        await pool.release(conn)


async def get_db_bg() -> CursorWrapper:
    """Create a standalone background connection.

    Unlike get_db() (request-scoped), this returns an unbounded connection
    that the caller must close explicitly via wrapper.close().
    """
    if pool is None:
        raise RuntimeError("Database pool not initialized.")
    conn = await pool.acquire()
    return CursorWrapper(conn, pool)
