"""Auth router — thin HTTP adapter.

All business logic lives in :mod:`app.services.auth_service`.
The router handles HTTP concerns: parsing requests, authentication via
``get_current_user``, rate limiting, and translating service-layer
exceptions to HTTP responses.
"""

from fastapi import APIRouter, Depends, HTTPException, Request

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.core.limiter import limiter
from app.schemas.user import (
    UserRegister,
    SendOtpIn,
    UserLogin,
    UpdateProfileIn,
    ChangePasswordIn,
)
from app.services.auth_service import (
    AuthService,
    UsernameAlreadyExistsError,
    EmailAlreadyRegisteredError,
    NoOtpSentError,
    InvalidOtpError,
    OtpAlreadyUsedError,
    OtpExpiredError,
    EmailSendError,
    InvalidCredentialsError,
    UserNotFoundError,
    EmailAlreadyInUseError,
    NoFieldsToUpdateError,
    InvalidPasswordError,
)

router = APIRouter(prefix="/auth", tags=["auth"])


# ── Send OTP ─────────────────────────────────────────────────────────


@router.post("/send-otp", status_code=200)
@limiter.limit("3/minute")
async def send_otp(
    request: Request,
    data: SendOtpIn,
    db: CursorWrapper = Depends(get_db),
):
    """Send an OTP code to the given email for registration."""
    svc = AuthService(db)
    try:
        return await svc.send_otp(data.email)
    except EmailSendError as e:
        raise HTTPException(status_code=500, detail=f"Failed to send email: {e}")


# ── Register ─────────────────────────────────────────────────────────


@router.post("/register", status_code=201)
@limiter.limit("5/minute")
async def register(
    request: Request,
    data: UserRegister,
    db: CursorWrapper = Depends(get_db),
):
    """Register a new user after OTP verification."""
    svc = AuthService(db)
    try:
        return await svc.register(data)
    except UsernameAlreadyExistsError:
        raise HTTPException(status_code=409, detail="Username already exists")
    except EmailAlreadyRegisteredError:
        raise HTTPException(status_code=409, detail="Email already registered")
    except NoOtpSentError:
        raise HTTPException(
            status_code=400,
            detail="No OTP sent to this email. Request one via /auth/send-otp first",
        )
    except InvalidOtpError:
        raise HTTPException(status_code=400, detail="Invalid OTP code")
    except OtpAlreadyUsedError:
        raise HTTPException(status_code=400, detail="OTP already used")
    except OtpExpiredError:
        raise HTTPException(status_code=400, detail="OTP has expired. Request a new one")
    except UserNotFoundError:
        raise HTTPException(status_code=404, detail="User not found")


# ── Login ────────────────────────────────────────────────────────────


@router.post("/login")
@limiter.limit("10/minute")
async def login(
    request: Request,
    data: UserLogin,
    db: CursorWrapper = Depends(get_db),
):
    """Authenticate user and return a JWT bearer token."""
    svc = AuthService(db)
    try:
        return await svc.login(data)
    except InvalidCredentialsError:
        raise HTTPException(status_code=401, detail="Invalid username or password")


# ── Get Me ───────────────────────────────────────────────────────────


@router.get("/me")
async def me(
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    """Return the authenticated user's profile."""
    svc = AuthService(db)
    try:
        return await svc.get_me(current_user["id"])
    except UserNotFoundError:
        raise HTTPException(status_code=404, detail="User not found")


# ── Update Profile ───────────────────────────────────────────────────


@router.put("/me")
async def update_profile(
    data: UpdateProfileIn,
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    """Update the authenticated user's display name, email, or cycle start day."""
    svc = AuthService(db)
    try:
        return await svc.update_profile(current_user["id"], data)
    except EmailAlreadyInUseError:
        raise HTTPException(status_code=409, detail="Email already in use")
    except NoFieldsToUpdateError:
        raise HTTPException(status_code=400, detail="No fields to update")
    except UserNotFoundError:
        raise HTTPException(status_code=404, detail="User not found")


# ── Change Password ──────────────────────────────────────────────────


@router.put("/password")
@limiter.limit("5/minute")
async def change_password(
    request: Request,
    data: ChangePasswordIn,
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    """Change the authenticated user's password."""
    svc = AuthService(db)
    try:
        return await svc.change_password(current_user["id"], data)
    except UserNotFoundError:
        raise HTTPException(status_code=404, detail="User not found")
    except InvalidPasswordError:
        raise HTTPException(status_code=400, detail="Current password is incorrect")


# ── Delete Account ───────────────────────────────────────────────────


@router.delete("/me", status_code=204)
async def delete_account(
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    """Delete the authenticated user and all associated data."""
    svc = AuthService(db)
    await svc.delete_account(current_user["id"])
    return None
