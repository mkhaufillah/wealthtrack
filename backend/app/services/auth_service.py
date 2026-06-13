"""Auth service — pure business logic, no FastAPI dependency.

Encapsulates all authentication and user management logic including
registration, login, OTP verification, profile updates, password changes,
and account deletion.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import logging

from app.database import CursorWrapper
from app.core.security import hash_password, verify_password, create_access_token
from app.core.email import generate_otp, send_otp_email
from app.core.config import settings
from app.schemas.user import (
    UserRegister,
    UserLogin,
    TokenOut,
    UpdateProfileIn,
    ChangePasswordIn,
)

logger = logging.getLogger(__name__)

OTP_EXPIRE_MINUTES = 10


# ── Domain exceptions ───────────────────────────────────────────────


class UsernameAlreadyExistsError(Exception):
    """Raised when a username is already taken."""

    def __init__(self, username: str) -> None:
        self.username = username
        super().__init__(f"Username '{username}' already exists")


class EmailAlreadyRegisteredError(Exception):
    """Raised when an email is already registered."""

    def __init__(self, email: str) -> None:
        self.email = email
        super().__init__(f"Email '{email}' already registered")


class NoOtpSentError(Exception):
    """Raised when trying to register without a prior OTP request."""

    def __init__(self) -> None:
        super().__init__(
            "No OTP sent to this email. Request one via /auth/send-otp first"
        )


class InvalidOtpError(Exception):
    """Raised when the provided OTP code does not match."""

    def __init__(self) -> None:
        super().__init__("Invalid OTP code")


class OtpAlreadyUsedError(Exception):
    """Raised when the OTP has already been used."""

    def __init__(self) -> None:
        super().__init__("OTP already used")


class OtpExpiredError(Exception):
    """Raised when the OTP has expired."""

    def __init__(self) -> None:
        super().__init__("OTP has expired. Request a new one")


class EmailSendError(Exception):
    """Raised when sending the OTP email fails."""

    def __init__(self, detail: str) -> None:
        self.detail = detail
        super().__init__(detail)


class InvalidCredentialsError(Exception):
    """Raised when login credentials are incorrect."""

    def __init__(self) -> None:
        super().__init__("Invalid username or password")


class UserNotFoundError(Exception):
    """Raised when a user lookup fails."""

    def __init__(self) -> None:
        super().__init__("User not found")


class EmailAlreadyInUseError(Exception):
    """Raised when trying to update to an email already used by another user."""

    def __init__(self, email: str) -> None:
        self.email = email
        super().__init__(f"Email '{email}' already in use")


class NoFieldsToUpdateError(Exception):
    """Raised when an update request provides no fields to change."""

    def __init__(self) -> None:
        super().__init__("No fields to update")


class InvalidPasswordError(Exception):
    """Raised when the current password provided is incorrect."""

    def __init__(self) -> None:
        super().__init__("Current password is incorrect")


# ── Service ─────────────────────────────────────────────────────────


class AuthService:
    """Service layer for authentication and user management.

    Instantiated with a ``CursorWrapper`` obtained from the FastAPI
    ``get_db`` dependency.  All business logic lives here, not in the
    router.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    # ── Helpers ────────────────────────────────────────────────────

    async def _get_user_by_id(self, user_id: int) -> dict | None:
        """Fetch a user row by id, returning a dict or None."""
        cursor = await self.db.execute(
            "SELECT id, username, display_name, email, role, "
            "COALESCE(cycle_start_day, 1) as cycle_start_day, created_at "
            "FROM users WHERE id = ?",
            (user_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    # ── Send OTP ────────────────────────────────────────────────────

    async def send_otp(self, email: str) -> dict:
        """Generate, persist, and send an OTP code to the given email.

        Returns a confirmation message dict.
        Raises ``EmailSendError`` if the SMTP send fails.
        """
        otp = generate_otp()
        expires_at = (
            datetime.now(timezone.utc) + timedelta(minutes=OTP_EXPIRE_MINUTES)
        ).isoformat()

        await self.db.execute(
            "INSERT INTO email_verifications (email, code, expires_at) VALUES (?, ?, ?)",
            (email, otp, expires_at),
        )

        try:
            send_otp_email(email, otp)
        except Exception as e:
            raise EmailSendError(str(e))

        return {"message": "OTP sent to email"}

    # ── Register ────────────────────────────────────────────────────

    async def register(self, data: UserRegister) -> dict:
        """Register a new user after verifying the OTP code.

        Validates uniqueness of username and email, verifies OTP,
        creates the user record, and returns the new user dict.
        """
        # Check username uniqueness
        cursor = await self.db.execute(
            "SELECT id FROM users WHERE username = ?", (data.username,)
        )
        if await cursor.fetchone():
            raise UsernameAlreadyExistsError(data.username)

        # Check email uniqueness
        cursor = await self.db.execute(
            "SELECT id FROM users WHERE email = ?", (data.email,)
        )
        if await cursor.fetchone():
            raise EmailAlreadyRegisteredError(data.email)

        # Verify OTP
        cursor = await self.db.execute(
            """SELECT code, expires_at, verified
               FROM email_verifications
               WHERE email = ?
               ORDER BY created_at DESC
               LIMIT 1""",
            (data.email,),
        )
        row = await cursor.fetchone()
        if not row:
            raise NoOtpSentError()

        if row["code"] != data.otp_code:
            raise InvalidOtpError()

        if row["verified"]:
            raise OtpAlreadyUsedError()

        expires_at = datetime.fromisoformat(row["expires_at"])
        if expires_at < datetime.now(timezone.utc):
            raise OtpExpiredError()

        # Mark OTP as verified
        await self.db.execute(
            "UPDATE email_verifications SET verified = 1 WHERE email = ? AND code = ?",
            (data.email, data.otp_code),
        )

        # Create user
        pw_hash = hash_password(data.password)
        cursor = await self.db.execute(
            "INSERT INTO users (username, display_name, password_hash, email) "
            "VALUES (?, ?, ?, ?)",
            (data.username, data.display_name, pw_hash, data.email),
        )

        user = await self._get_user_by_id(cursor.lastrowid)
        if not user:
            raise UserNotFoundError()
        return user

    # ── Login ───────────────────────────────────────────────────────

    async def login(self, data: UserLogin) -> TokenOut:
        """Authenticate user by username/password and return a JWT token.

        Raises ``InvalidCredentialsError`` if the username does not exist
        or the password is wrong.
        """
        cursor = await self.db.execute(
            "SELECT id, username, password_hash, role FROM users WHERE username = ?",
            (data.username,),
        )
        user = await cursor.fetchone()
        if not user or not verify_password(data.password, user["password_hash"]):
            raise InvalidCredentialsError()

        token = create_access_token(user["id"], user["username"], user["role"])
        return TokenOut(
            access_token=token,
            expires_in=settings.ACCESS_TOKEN_EXPIRE_DAYS * 86400,
        )

    # ── Get Me ──────────────────────────────────────────────────────

    async def get_me(self, user_id: int) -> dict:
        """Return the authenticated user's profile dict.

        Raises ``UserNotFoundError`` if the user id does not exist.
        """
        user = await self._get_user_by_id(user_id)
        if not user:
            raise UserNotFoundError()
        return user

    # ── Update Profile ──────────────────────────────────────────────

    async def update_profile(self, user_id: int, data: UpdateProfileIn) -> dict:
        """Update the authenticated user's profile fields.

        Supports updating ``display_name``, ``cycle_start_day``, and
        ``email``.  Email uniqueness is validated against other users.
        Returns the updated user dict.
        """
        updates = {}
        if data.display_name is not None:
            updates["display_name"] = data.display_name
        if data.cycle_start_day is not None:
            updates["cycle_start_day"] = data.cycle_start_day
        if data.email is not None:
            # Check email not taken by another user
            cursor = await self.db.execute(
                "SELECT id FROM users WHERE email = ? AND id != ?",
                (data.email, user_id),
            )
            if await cursor.fetchone():
                raise EmailAlreadyInUseError(data.email)
            updates["email"] = data.email

        if not updates:
            raise NoFieldsToUpdateError()

        set_clause = ", ".join(f"{k} = ?" for k in updates)
        await self.db.execute(
            f"UPDATE users SET {set_clause} WHERE id = ?",
            list(updates.values()) + [user_id],
        )

        user = await self._get_user_by_id(user_id)
        if not user:
            raise UserNotFoundError()
        return user

    # ── Change Password ─────────────────────────────────────────────

    async def change_password(self, user_id: int, data: ChangePasswordIn) -> dict:
        """Verify current password and update to new password.

        Returns a confirmation message dict.
        """
        cursor = await self.db.execute(
            "SELECT password_hash FROM users WHERE id = ?",
            (user_id,),
        )
        user = await cursor.fetchone()
        if not user:
            raise UserNotFoundError()

        if not verify_password(data.current_password, user["password_hash"]):
            raise InvalidPasswordError()

        new_hash = hash_password(data.new_password)
        await self.db.execute(
            "UPDATE users SET password_hash = ? WHERE id = ?",
            (new_hash, user_id),
        )

        return {"message": "Password updated successfully"}

    # ── Delete Account ──────────────────────────────────────────────

    async def delete_account(self, user_id: int) -> None:
        """Delete the user account and all associated data.

        Operates inside a database transaction to ensure atomicity.
        Removes households, memberships, OCR jobs, transactions, budgets,
        and finally the user record.
        """
        async with self.db.transaction():
            # Delete all members of households owned by this user
            await self.db.execute(
                "DELETE FROM household_members "
                "WHERE household_id IN (SELECT id FROM households WHERE created_by = ?)",
                (user_id,),
            )
            # Delete household membership for this user
            await self.db.execute(
                "DELETE FROM household_members WHERE user_id = ?",
                (user_id,),
            )
            # Delete households owned by this user
            await self.db.execute(
                "DELETE FROM households WHERE created_by = ?",
                (user_id,),
            )
            # Delete OCR jobs owned by this user
            await self.db.execute(
                "DELETE FROM ocr_jobs WHERE user_id = ?",
                (user_id,),
            )
            # Delete all transactions owned by this user
            await self.db.execute(
                "DELETE FROM transactions WHERE user_id = ?",
                (user_id,),
            )
            # Delete all budgets owned by this user
            await self.db.execute(
                "DELETE FROM budgets WHERE user_id = ?",
                (user_id,),
            )
            # Delete the user
            await self.db.execute(
                "DELETE FROM users WHERE id = ?",
                (user_id,),
            )
