import aiosqlite
import sqlite3

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


async def get_db_bg() -> aiosqlite.Connection:
    """Create a standalone async DB connection for background tasks.

    Unlike get_db() (which is request-scoped and auto-closes),
    this returns an unbounded connection that the caller must close explicitly.
    """
    db = await aiosqlite.connect(settings.DB_PATH)
    db.row_factory = aiosqlite.Row
    await db.execute("PRAGMA journal_mode=WAL")
    await db.execute("PRAGMA foreign_keys=ON")
    return db
