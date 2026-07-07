from datetime import datetime, timedelta, timezone
from typing import Optional
from jose import jwt, JWTError
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from app.core.config import settings
from app.database import get_db, pool
from app.services.api_key_service import ApiKeyService, API_KEY_PREFIX

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer()


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(user_id: int, username: str, role: str = "user") -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=settings.ACCESS_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": str(user_id),
        "username": username,
        "role": role,
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


async def _get_user_from_api_key(token: str, db) -> Optional[dict]:
    """Validate an API key and return user info if valid."""
    if not token.startswith(API_KEY_PREFIX):
        return None
    service = ApiKeyService(db)
    key_data = await service.find_and_verify_key(token)
    if not key_data:
        return None
    cursor = await db.execute(
        "SELECT id, username, role FROM users WHERE id = ?",
        (key_data["user_id"],),
    )
    user = await cursor.fetchone()
    if not user:
        return None
    return {
        "id": user["id"],
        "username": user["username"],
        "role": user.get("role", "user"),
        "auth_type": "api_key",
        "api_key_scopes": key_data["scopes"],
    }


async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db = Depends(get_db),
) -> dict:
    """Dependency: returns user dict from JWT token or API key."""
    token = credentials.credentials

    # Try API key first (fast prefix check)
    if token.startswith(API_KEY_PREFIX):
        if db is None:
            raise HTTPException(status_code=401, detail="DB not available")
        user = await _get_user_from_api_key(token, db)
        if user:
            return user
        raise HTTPException(status_code=401, detail="Invalid API key")

    # Fall back to JWT
    payload = decode_token(token)
    return {
        "id": int(payload["sub"]),
        "username": payload["username"],
        "role": payload.get("role", "user"),
        "auth_type": "jwt",
        "api_key_scopes": None,
    }
