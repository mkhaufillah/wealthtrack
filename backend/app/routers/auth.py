from fastapi import APIRouter, Depends, HTTPException, status
import aiosqlite

from app.database import get_db
from app.core.security import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)
from app.schemas.user import (
    UserRegister,
    UserLogin,
    TokenOut,
    UpdateProfileIn,
    ChangePasswordIn,
    MessageOut,
)
from app.core.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", status_code=201)
async def register(data: UserRegister, db: aiosqlite.Connection = Depends(get_db)):
    cursor = await db.execute("SELECT id FROM users WHERE username = ?", (data.username,))
    if await cursor.fetchone():
        raise HTTPException(status_code=409, detail="Username already exists")
    pw_hash = hash_password(data.password)
    cursor = await db.execute(
        "INSERT INTO users (username, display_name, password_hash) VALUES (?, ?, ?)",
        (data.username, data.display_name, pw_hash),
    )
    await db.commit()

    cursor = await db.execute(
        "SELECT id, username, display_name, role, created_at FROM users WHERE id = ?",
        (cursor.lastrowid,),
    )
    user = await cursor.fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return dict(user)


@router.post("/login")
async def login(data: UserLogin, db: aiosqlite.Connection = Depends(get_db)):
    cursor = await db.execute(
        "SELECT * FROM users WHERE username = ?", (data.username,)
    )
    user = await cursor.fetchone()
    if not user or not verify_password(data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    token = create_access_token(user["id"], user["username"])
    return TokenOut(
        access_token=token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_DAYS * 86400,
    )


@router.get("/me")
async def me(
    current_user: dict = Depends(get_current_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    cursor = await db.execute(
        "SELECT id, username, display_name, role, created_at FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user = await cursor.fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return dict(user)


@router.put("/me")
async def update_profile(
    data: UpdateProfileIn,
    current_user: dict = Depends(get_current_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    await db.execute(
        "UPDATE users SET display_name = ? WHERE id = ?",
        (data.display_name, current_user["id"]),
    )
    await db.commit()

    cursor = await db.execute(
        "SELECT id, username, display_name, role, created_at FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user = await cursor.fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return dict(user)


@router.put("/password")
async def change_password(
    data: ChangePasswordIn,
    current_user: dict = Depends(get_current_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    cursor = await db.execute(
        "SELECT password_hash FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user = await cursor.fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not verify_password(data.current_password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Current password is incorrect")

    new_hash = hash_password(data.new_password)
    await db.execute(
        "UPDATE users SET password_hash = ? WHERE id = ?",
        (new_hash, current_user["id"]),
    )
    await db.commit()

    return MessageOut(message="Password updated successfully")


@router.delete("/me", status_code=204)
async def delete_account(
    current_user: dict = Depends(get_current_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    # Delete all transactions owned by this user
    await db.execute(
        "DELETE FROM transactions WHERE user_id = ?",
        (current_user["id"],),
    )
    # Delete the user
    await db.execute(
        "DELETE FROM users WHERE id = ?",
        (current_user["id"],),
    )
    await db.commit()
    return None
