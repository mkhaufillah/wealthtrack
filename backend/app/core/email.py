"""SMTP email sending utility for WealthTrack.

Uses Python's built-in smtplib — no extra dependencies.
Configure via SMTP_* env vars in backend/.env or ~/.hermes/.env.
"""

import smtplib
import random
import string
from email.mime.text import MIMEText

from app.core.config import settings


def generate_otp(length: int = 6) -> str:
    """Generate a numeric OTP code of the given length."""
    return "".join(random.choices(string.digits, k=length))


def send_email(to_email: str, subject: str, body: str) -> None:
    """Send a plain-text email via SMTP.

    Raises smtplib.SMTPException on failure.
    """
    if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
        raise RuntimeError(
            "SMTP not configured. Set SMTP_USERNAME and SMTP_PASSWORD in .env"
        )

    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = subject
    msg["From"] = f"{settings.EMAIL_FROM_NAME} <{settings.EMAIL_FROM}>"
    msg["To"] = to_email

    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
        server.starttls()
        server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
        server.send_message(msg)


def send_otp_email(to_email: str, otp: str) -> None:
    """Send the OTP verification email."""
    subject = "WealthTrack — Email Verification Code"
    body = (
        f"Your WealthTrack verification code is:\n\n"
        f"    {otp}\n\n"
        f"This code expires in 10 minutes. If you did not request this, "
        f"please ignore this email.\n\n"
        f"— WealthTrack"
    )
    send_email(to_email, subject, body)
