from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
import asyncpg

from app.database import get_db, CursorWrapper
from app.core.security import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)
from app.core.limiter import limiter
from app.core.email import generate_otp, send_otp_email
from app.schemas.user import (
    UserRegister,
    SendOtpIn,
    UserLogin,
    TokenOut,
    UpdateProfileIn,
    ChangePasswordIn,
    MessageOut,
)
from app.core.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])

OTP_EXPIRE_MINUTES = 10


@router.post("/send-otp", status_code=200)
@limiter.limit("3/minute")
async def send_otp(request: Request, data: SendOtpIn, db: CursorWrapper = Depends(get_db)):
    """Send an OTP code to the given email for registration."""
    otp = generate_otp()
    expires_at = (
        datetime.now(timezone.utc) + timedelta(minutes=OTP_EXPIRE_MINUTES)
    ).isoformat()

    await db.execute(
        "INSERT INTO email_verifications (email, code, expires_at) VALUES (?, ?, ?)",
        (data.email, otp, expires_at),
    )
    # auto-committed

    try:
        send_otp_email(data.email, otp)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to send email: {e}")

    return {"message": "OTP sent to email"}


@router.post("/register", status_code=201)
@limiter.limit("5/minute")
async def register(request: Request, data: UserRegister, db: CursorWrapper = Depends(get_db)):
    cursor = await db.execute("SELECT id FROM users WHERE username = ?", (data.username,))
    if await cursor.fetchone():
        raise HTTPException(status_code=409, detail="Username already exists")

    cursor = await db.execute("SELECT id FROM users WHERE email = ?", (data.email,))
    if await cursor.fetchone():
        raise HTTPException(status_code=409, detail="Email already registered")

    # Verify OTP
    cursor = await db.execute(
        """SELECT code, expires_at, verified
           FROM email_verifications
           WHERE email = ?
           ORDER BY created_at DESC
           LIMIT 1""",
        (data.email,),
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=400, detail="No OTP sent to this email. Request one via /auth/send-otp first")

    if row["code"] != data.otp_code:
        raise HTTPException(status_code=400, detail="Invalid OTP code")

    if row["verified"]:
        raise HTTPException(status_code=400, detail="OTP already used")

    expires_at = datetime.fromisoformat(row["expires_at"])
    if expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP has expired. Request a new one")

    # Mark OTP as verified
    await db.execute(
        "UPDATE email_verifications SET verified = 1 WHERE email = ? AND code = ?",
        (data.email, data.otp_code),
    )

    pw_hash = hash_password(data.password)
    cursor = await db.execute(
        "INSERT INTO users (username, display_name, password_hash, email) VALUES (?, ?, ?, ?)",
        (data.username, data.display_name, pw_hash, data.email),
    )
    # auto-committed

    cursor = await db.execute(
        "SELECT id, username, display_name, email, role, COALESCE(cycle_start_day, 1) as cycle_start_day, created_at FROM users WHERE id = ?",
        (cursor.lastrowid,),
    )
    user = await cursor.fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return dict(user)


@router.post("/login")
@limiter.limit("10/minute")
async def login(request: Request, data: UserLogin, db: CursorWrapper = Depends(get_db)):
    cursor = await db.execute(
        "SELECT id, username, password_hash, role FROM users WHERE username = ?", (data.username,)
    )
    user = await cursor.fetchone()
    if not user or not verify_password(data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    token = create_access_token(user["id"], user["username"], user["role"])
    return TokenOut(
        access_token=token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_DAYS * 86400,
    )


@router.get("/me")
async def me(
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    cursor = await db.execute(
        "SELECT id, username, display_name, email, role, COALESCE(cycle_start_day, 1) as cycle_start_day, created_at FROM users WHERE id = ?",
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
    db: CursorWrapper = Depends(get_db),
):
    updates = {}
    if data.display_name is not None:
        updates["display_name"] = data.display_name
    if data.cycle_start_day is not None:
        updates["cycle_start_day"] = data.cycle_start_day
    if data.email is not None:
        # Check email not taken
        cursor = await db.execute(
            "SELECT id FROM users WHERE email = ? AND id != ?",
            (data.email, current_user["id"]),
        )
        if await cursor.fetchone():
            raise HTTPException(status_code=409, detail="Email already in use")
        updates["email"] = data.email

    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = ?" for k in updates)
    await db.execute(
        f"UPDATE users SET {set_clause} WHERE id = ?",
        list(updates.values()) + [current_user["id"]],
    )
    # auto-committed

    cursor = await db.execute(
        "SELECT id, username, display_name, email, role, COALESCE(cycle_start_day, 1) as cycle_start_day, created_at FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user = await cursor.fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return dict(user)


@router.put("/password")
@limiter.limit("5/minute")
async def change_password(
    request: Request,
    data: ChangePasswordIn,
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    cursor = await db.execute(
        "SELECT password_hash FROM users WHERE id = ?",
        (current_user["id"],),
    )
    user = await cursor.fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not verify_password(data.current_password, user["password_hash"]):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    new_hash = hash_password(data.new_password)
    await db.execute(
        "UPDATE users SET password_hash = ? WHERE id = ?",
        (new_hash, current_user["id"]),
    )
    # auto-committed

    return MessageOut(message="Password updated successfully")


@router.delete("/me", status_code=204)
async def delete_account(
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    # Delete all members of households owned by this user (cascade)
    await db.execute(
        "DELETE FROM household_members WHERE household_id IN (SELECT id FROM households WHERE created_by = ?)",
        (current_user["id"],),
    )
    # Delete household membership for this user
    await db.execute(
        "DELETE FROM household_members WHERE user_id = ?",
        (current_user["id"],),
    )
    # Delete households owned by this user
    await db.execute(
        "DELETE FROM households WHERE created_by = ?",
        (current_user["id"],),
    )
    # Delete OCR jobs owned by this user (table always exists in production)
    await db.execute(
        "DELETE FROM ocr_jobs WHERE user_id = ?",
        (current_user["id"],),
    )
    # Delete all transactions owned by this user
    await db.execute(
        "DELETE FROM transactions WHERE user_id = ?",
        (current_user["id"],),
    )
    # Delete all budgets owned by this user
    await db.execute(
        "DELETE FROM budgets WHERE user_id = ?",
        (current_user["id"],),
    )
    # Delete the user
    await db.execute(
        "DELETE FROM users WHERE id = ?",
        (current_user["id"],),
    )
    # auto-committed
    return None
