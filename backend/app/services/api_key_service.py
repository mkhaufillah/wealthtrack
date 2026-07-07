"""API key service for long-lived MCP authentication.

API keys are scoped (e.g., mcp:read, mcp:write), do not expire, and can be
revoked at any time. The plaintext key is shown only once at creation time.
"""
import secrets
import string
from datetime import datetime, timezone
from typing import Optional

from app.database import CursorWrapper


API_KEY_PREFIX = "wt_mcp_"
API_KEY_LENGTH = 48


class ApiKeyService:
    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    @staticmethod
    def generate_key() -> str:
        """Generate a cryptographically secure API key."""
        suffix = "".join(
            secrets.choice(string.ascii_letters + string.digits)
            for _ in range(API_KEY_LENGTH)
        )
        return f"{API_KEY_PREFIX}{suffix}"

    @staticmethod
    def _hash_key(key: str) -> str:
        """Hash the plaintext key for storage."""
        import bcrypt

        return bcrypt.hashpw(key.encode(), bcrypt.gensalt()).decode()

    @staticmethod
    def verify_key(key: str, key_hash: str) -> bool:
        import bcrypt

        return bcrypt.checkpw(key.encode(), key_hash.encode())

    async def create_key(
        self,
        user_id: int,
        name: str,
        scopes: Optional[list[str]] = None,
    ) -> dict:
        """Create a new API key. Returns the plaintext key once."""
        plaintext = self.generate_key()
        key_hash = self._hash_key(plaintext)
        scopes = scopes or ["mcp:read"]

        cursor = await self.db.execute(
            """INSERT INTO api_keys (user_id, name, key_hash, scopes)
               VALUES (?, ?, ?, ?)
               RETURNING id, created_at""",
            (user_id, name, key_hash, scopes),
        )
        # The wrapper's execute with RETURNING sets lastrowid; fetchone may not
        # populate rows for fetchval path. Prefer lastrowid when available.
        key_id = self.db.lastrowid
        row = await cursor.fetchone()
        if key_id is None and row is not None:
            key_id = row["id"]
        created_at = row["created_at"] if row else datetime.now(timezone.utc).isoformat()
        if key_id is None:
            raise RuntimeError("Failed to create API key")
        return {
            "id": key_id,
            "name": name,
            "key": plaintext,
            "scopes": scopes,
            "created_at": created_at,
        }

    async def list_keys(self, user_id: int) -> list[dict]:
        """List API keys for a user (without plaintext)."""
        cursor = await self.db.execute(
            """SELECT id, name, scopes, is_active, last_used_at, created_at
               FROM api_keys
               WHERE user_id = ?
               ORDER BY created_at DESC""",
            (user_id,),
        )
        rows = await cursor.fetchall()
        return [
            {
                "id": r["id"],
                "name": r["name"],
                "scopes": r["scopes"],
                "is_active": bool(r["is_active"]),
                "last_used_at": r["last_used_at"],
                "created_at": r["created_at"],
            }
            for r in rows
        ]

    async def revoke_key(self, user_id: int, key_id: int) -> bool:
        """Revoke an API key. Returns True if a row was deleted."""
        cursor = await self.db.execute(
            "DELETE FROM api_keys WHERE id = ? AND user_id = ?",
            (key_id, user_id),
        )
        # asyncpg execute returns a string like "DELETE 1"; we can't easily get
        # rowcount from the wrapper, so fetch to confirm.
        cursor = await self.db.execute(
            "SELECT 1 FROM api_keys WHERE id = ? AND user_id = ?",
            (key_id, user_id),
        )
        return (await cursor.fetchone()) is None

    async def get_key_by_hash(self, key_hash: str) -> Optional[dict]:
        """Fetch a key by its hash."""
        cursor = await self.db.execute(
            """SELECT id, user_id, name, scopes, is_active, last_used_at
               FROM api_keys
               WHERE key_hash = ?""",
            (key_hash,),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        return {
            "id": row["id"],
            "user_id": row["user_id"],
            "name": row["name"],
            "scopes": row["scopes"],
            "is_active": bool(row["is_active"]),
            "last_used_at": row["last_used_at"],
        }

    async def find_and_verify_key(self, key: str) -> Optional[dict]:
        """Find a key by plaintext and verify it. Updates last_used_at."""
        if not key.startswith(API_KEY_PREFIX):
            return None

        # We must iterate hashes because bcrypt verification is per-row.
        cursor = await self.db.execute(
            "SELECT id, user_id, name, key_hash, scopes, is_active FROM api_keys WHERE is_active = 1"
        )
        rows = await cursor.fetchall()
        for r in rows:
            if self.verify_key(key, r["key_hash"]):
                now = datetime.now(timezone.utc).isoformat()
                await self.db.execute(
                    "UPDATE api_keys SET last_used_at = ? WHERE id = ?",
                    (now, r["id"]),
                )
                return {
                    "id": r["id"],
                    "user_id": r["user_id"],
                    "name": r["name"],
                    "scopes": r["scopes"],
                    "is_active": bool(r["is_active"]),
                }
        return None
