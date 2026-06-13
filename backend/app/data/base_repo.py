"""
Base repository class for WealthTrack data access.

All repositories follow the same pattern:
- Inject a CursorWrapper (from app.database)
- Methods are async, return dicts or lists of dicts
- No business logic — just SQL queries
"""

from app.database import CursorWrapper


class BaseRepository:
    """Base class for all data repositories.

    Provides a consistent interface for DB access.
    Subclasses implement domain-specific query methods.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db
