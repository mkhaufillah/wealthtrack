# Production Readiness Plan — WealthTrack

> **For Hermes:** Execute this plan phase-by-phase using subagent-driven-development.

**Goal:** Harden WealthTrack for public release by fixing security, infrastructure, and reliability gaps.

**Architecture:** Incremental hardening — security patches first (config/lockdown), then infrastructure (backups/cost controls), then feature completeness (password reset/onboarding). Each phase independently deployable.

**Tech Stack:** FastAPI, PostgreSQL, Redis, Flutter, certbot, Sentry (optional)

---

## Priority Matrix

| # | Item | Severity | Effort | Dependencies |
|---|------|----------|--------|--------------|
| P0 | `DEBUG=False` | 🔴 Critical | 1 file | None |
| P1 | `SECRET_KEY` → env | 🔴 Critical | 1 check | None |
| P2 | Password policy | 🔴 Critical | 2 files | None |
| P3 | `CORS_ORIGINS` → locked list | 🔴 Critical | 1 file | Need frontend domain |
| P4 | Token expiry 30d → 7d + refresh | 🔴 Critical | 2 files | None |
| P5 | Auth rate limiting audit | 🟡 Medium | 2 files | None |
| P6 | Database backup | 🟡 Medium | 1 script + cron | None |
| P7 | Email service upgrade | 🟡 Medium | .env change + SendGrid | SendGrid account |
| P8 | OCR cost control | 🟡 Medium | 2 files | None |
| P9 | AI Advisor cost control | 🟡 Medium | 1 file | None |
| P10 | Password reset flow | 🟡 Medium | 3 files | None |
| P11 | User deletion flow | 🟢 Nice-to-have | 3 files | None |
| P12 | Error messages audit | 🟢 Nice-to-have | ~10 files | None |
| P13 | ToS / Privacy Policy page | 🟢 Nice-to-have | 1 page | Legal review |
| P14 | Monitoring / Sentry | 🟢 Nice-to-have | 3 files | Sentry account |
| P15 | Onboarding flow | 🟢 Nice-to-have | 2 files | None |

---

## Task List

---

### PHASE 1: 🔴 Critical Security (Do First)

---

### Task 1.1: Set `DEBUG=False`

**Objective:** Disable debug mode so error responses don't leak stack traces.

**Files:**
- Modify: `backend/app/core/config.py`

Change `DEBUG: bool` from `True` to `False`:
```python
DEBUG: bool = False
```

**Verify:** Restart app, hit `/api/v1/health` — errors should return clean JSON, not stack traces.

---

### Task 1.2: Verify `SECRET_KEY` is Not Default

**Objective:** Ensure `SECRET_KEY` is a strong random value, not the placeholder.

**Files:**
- Check: `backend/.env`

**Step 1:** Generate strong key if needed:
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```

**Step 2:** Update `backend/.env`:
```env
SECRET_KEY=<generated-key>
```

**Verify:** Restart app — login should still work (old tokens invalidated, new ones signed with new key).

---

### Task 1.3: Add Password Policy

**Objective:** Enforce minimum password requirements on registration.

**Files:**
- Create: `backend/app/core/password_policy.py`
- Modify: `backend/app/routers/auth.py`

**Step 1:** Create `password_policy.py`:

```python
import re
from fastapi import HTTPException

MIN_LENGTH = 8
REQUIRE_UPPER = True
REQUIRE_LOWER = True
REQUIRE_DIGIT = True
REQUIRE_SPECIAL = True

def validate_password(password: str) -> None:
    errors = []
    if len(password) < MIN_LENGTH:
        errors.append(f"Password must be at least {MIN_LENGTH} characters")
    if REQUIRE_UPPER and not re.search(r'[A-Z]', password):
        errors.append("Password must contain an uppercase letter")
    if REQUIRE_LOWER and not re.search(r'[a-z]', password):
        errors.append("Password must contain a lowercase letter")
    if REQUIRE_DIGIT and not re.search(r'\d', password):
        errors.append("Password must contain a digit")
    if REQUIRE_SPECIAL and not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        errors.append("Password must contain a special character")
    if errors:
        raise HTTPException(status_code=422, detail="; ".join(errors))
```

**Step 2:** Add validation in `routers/auth.py` register endpoint:
```python
from app.core.password_policy import validate_password

# Before hash:
validate_password(data.password)
pw_hash = hash_password(data.password)
```

**Verify:**
```bash
curl -X POST https://wealthtrack.filla.id/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"test","email":"test@test.com","password":"weak","display_name":"Test"}'
# Expected: 422 with password policy message
```

---

### Task 1.4: Lock CORS Origins

**Objective:** Replace wildcard CORS with explicit allowed origins.

**Files:**
- Modify: `backend/app/core/config.py`

Change from:
```python
CORS_ORIGINS: str = '["*"]'
```
To:
```python
CORS_ORIGINS: str = '["https://wealthtrack.filla.id"]'
```

**Verify:** Request from `curl -H "Origin: https://evil.com"` should not include `Access-Control-Allow-Origin: *`.

---

### Task 1.5: Shorter Token Expiry + Refresh Token

**Objective:** Reduce access token lifetime from 30 days to 7 days, add refresh token mechanism.

**Files:**
- Modify: `backend/app/core/config.py`
- Create: `backend/app/routers/refresh.py`
- Modify: `backend/app/core/security.py`
- Modify: `backend/app/main.py`

**Step 1:** Update config:
```python
ACCESS_TOKEN_EXPIRE_HOURS: int = 168     # 7 days
REFRESH_TOKEN_EXPIRE_DAYS: int = 30      # 30 days
```

**Step 2:** Create `routers/refresh.py`:
```python
from fastapi import APIRouter, Depends, HTTPException
from jose import jwt
from app.core.security import create_access_token, decode_token
from app.core.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/refresh")
async def refresh_token(refresh_token: str):
    try:
        payload = decode_token(refresh_token)
        if payload.get("type") != "refresh":
            raise HTTPException(401, "Invalid token")
        new_token = create_access_token(
            user_id=payload["sub"],
            username=payload["username"],
            role=payload["role"],
        )
        return {"access_token": new_token, "token_type": "bearer"}
    except Exception:
        raise HTTPException(401, "Invalid or expired refresh token")
```

**Step 3:** Update `create_access_token` in `security.py` to use hours + add `type`:
```python
def create_access_token(user_id: int, username: str, role: str = "user") -> str:
    expire = datetime.now(timezone.utc) + timedelta(hours=settings.ACCESS_TOKEN_EXPIRE_HOURS)
    payload = {
        "sub": str(user_id),
        "username": username,
        "role": role,
        "type": "access",
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
```

**Step 4:** Register router in `main.py`:
```python
from app.routers import refresh as refresh_router
app.include_router(refresh_router, prefix="/api/v1")
```

**Verify:** Login, decode JWT — check `exp` is 7 days out.

---

### PHASE 2: 🟡 Infrastructure & Cost Control

---

### Task 2.1: Auth Rate Limiting Audit

**Objective:** Tighten rate limits and add credential stuffing protection.

**Files:**
- Modify: `backend/app/routers/auth.py`

**Step 1:** Tighten login limit from 10/minute to 5/minute.

**Step 2:** Add IP + username-based tracking:
```python
# On login failure, Redis increment with 5-min TTL
# Block after 5 failed attempts per username in 15 minutes
```

---

### Task 2.2: Database Backup Automation

**Objective:** Automated daily pg_dump with 7-day retention.

**Files:**
- Create: `deploy/backup-db.sh`

```bash
#!/bin/bash
set -e
BACKUP_DIR="/var/backups/wealthtrack"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"
pg_dump -U wealthtrack -h localhost -d wealthtrack \
  -F c -f "$BACKUP_DIR/wealthtrack_$TIMESTAMP.dump"

# Keep last 7 days
find "$BACKUP_DIR" -name "wealthtrack_*.dump" -mtime +$RETENTION_DAYS -delete
```

**Step 2:** Install cron:
```
0 3 * * * /home/hermes/dev/wealthtrack/deploy/backup-db.sh
```

**Verify:** Run script manually, check `.dump` file exists with correct data.

---

### Task 2.3: Email Service Upgrade

**Objective:** Move from SMTP Gmail to SendGrid for reliable email delivery.

**Files:**
- Modify: `backend/.env`

Update SMTP credentials:
```env
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=<sendgrid-api-key>
```

**Verify:** Request OTP — email should arrive within seconds.

---

### Task 2.4: OCR Cost Control

**Objective:** Hard daily caps on OCR usage per user and globally.

**Files:**
- Modify: `backend/app/core/config.py`
- Modify: `backend/app/routers/ocr.py`

**Step 1:** In `config.py`:
```python
OCR_DAILY_LIMIT_PER_USER: int = 10
OCR_GLOBAL_DAILY_BUDGET: int = 500
```

**Step 2:** In `routers/ocr.py`, add check before processing:
```python
# Per-user Redis counter: ratelimit:ocr:user_{user_id}
# Global Redis counter: ocr:daily_budget
# Reject if either limit exceeded
```

---

### Task 2.5: AI Advisor Cost Control

**Objective:** Cap daily AI chat usage and reduce token waste.

**Files:**
- Modify: `backend/app/core/config.py`
- Modify: `backend/app/routers/ai_advisor.py`

**Step 1:** In `config.py`:
```python
AI_CHAT_LIMIT_PER_USER: int = 20  # per day
```

**Step 2:** Track via Redis `ratelimit:ai:user_{user_id}` with 86400s window.

**Step 3:** Reduce max response tokens from 16384 to 4096 for flash model.

---

### PHASE 3: 🟡🟢 Feature Completeness

---

### Task 3.1: Password Reset Flow

**Objective:** Allow users to reset forgotten passwords via email OTP.

**Files:**
- Modify: `backend/app/routers/auth.py` — add forgot-password and reset-password endpoints
- Modify: `backend/app/core/email.py` — add reset email template

**Endpoints:**
- `POST /auth/forgot-password` — accepts email, sends OTP
- `POST /auth/reset-password` — accepts email + OTP + new password

**Rate limit:** 1/minute per email.

---

### Task 3.2: User Deletion Flow

**Objective:** Allow users to permanently delete their account and all associated data.

**Files:**
- Add: `backend/app/routers/auth.py` — `DELETE /auth/account`

```python
@router.delete("/account", status_code=204)
async def delete_account(current_user=Depends(get_current_user), db=Depends(get_db)):
    """Delete user account and all associated data."""
    # Order matters due to FK constraints
    await db.execute("DELETE FROM ocr_jobs WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM ai_messages WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM transactions WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM budgets WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM household_members WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM email_verifications WHERE email IN (SELECT email FROM users WHERE id = ?)", (current_user["id"],))
    await db.execute("DELETE FROM users WHERE id = ?", (current_user["id"],))
```

---

### Task 3.3: Error Messages Audit

**Objective:** Replace technical error messages with user-friendly text.

**Files:**
- Audit: All `backend/app/routers/*.py`

Replace patterns:
- `"Vision API error: {status_code}"` → `"Image processing failed. Please try again."`
- `"Failed to send email: {e}"` → `"Unable to send verification email. Please try again later."`
- Keep existing user-friendly messages unchanged.

Search:
```bash
grep -rn 'HTTPException' backend/app/routers/ | grep -v "test_"
```

---

### Task 3.4: ToS / Privacy Policy Page

**Objective:** Serve legal pages at `/legal` route.

**Files:**
- Create: `backend/static/tos.html`, `backend/static/privacy.html`
- Or add routes: `GET /api/v1/legal/tos`, `GET /api/v1/legal/privacy`

**Content:** Standard financial app ToS — user data ownership, no financial advice disclaimer.

---

### Task 3.5: Monitoring / Sentry (Optional)

**Objective:** Add error tracking for production visibility.

**Files:**
- Create: `backend/app/core/sentry.py`
- Modify: `backend/app/main.py`

```python
# sentry.py
import sentry_sdk
from app.core.config import settings

def init_sentry():
    if settings.SENTRY_DSN:
        sentry_sdk.init(
            dsn=settings.SENTRY_DSN,
            traces_sample_rate=0.1,
            environment="production",
        )
```

Register in `main.py` startup. Add `@app.exception_handler` for structured 500 logging.

---

### Task 3.6: Onboarding Flow

**Objective:** Guide new users through first steps.

**Files:**
- Modify: `mobile/lib/features/home/`
- Modify: `backend/app/routers/` if needed

When new user registers with $0 balance:
- Show "Getting Started" banner with 3 steps:
  1. Add your first transaction
  2. Set a monthly budget
  3. Scan a receipt

---

## Phase Execution Order

```
Week 1: 🔴 P0-P4 (Security)
  Day 1: P0 (DEBUG=False) + P1 (SECRET_KEY) + P2 (Password policy)
  Day 2: P3 (CORS) + P4 (Token expiry)
  Day 3: Test everything, fix issues

Week 2: 🟡 P5-P10 (Infra & Cost)
  Day 1: P5 (Auth audit) + P6 (Backup)
  Day 2: P7 (Email) + P8 (OCR cost)
  Day 3: P9 (AI cost) + P10 (Password reset)

Week 3: 🟢 P11-P15 (Features)
  Day 1: P11 (Account deletion) + P12 (Error messages)
  Day 2: P13 (ToS/Privacy) + P14 (Sentry)
  Day 3: P15 (Onboarding) + Integration testing
```

## Summary of All Changes

| # | Change | Files | Phase |
|---|--------|-------|-------|
| P0 | Disable debug mode | `core/config.py` | 🔴 |
| P1 | Strong SECRET_KEY | `.env` | 🔴 |
| P2 | Password policy | `core/password_policy.py`, `routers/auth.py` | 🔴 |
| P3 | Locked CORS origins | `core/config.py` | 🔴 |
| P4 | Token expiry + refresh | `core/config.py`, `routers/refresh.py`, `core/security.py`, `main.py` | 🔴 |
| P5 | Auth rate limit audit | `routers/auth.py` | 🟡 |
| P6 | DB backup automation | `deploy/backup-db.sh`, cron | 🟡 |
| P7 | Email service upgrade | `.env` | 🟡 |
| P8 | OCR cost control | `core/config.py`, `routers/ocr.py` | 🟡 |
| P9 | AI Advisor cost control | `core/config.py`, `routers/ai_advisor.py` | 🟡 |
| P10 | Password reset flow | `routers/auth.py`, `core/email.py` | 🟡 |
| P11 | User deletion flow | `routers/auth.py` | 🟢 |
| P12 | Error messages audit | All `routers/` | 🟢 |
| P13 | ToS / Privacy policy | New static/legal pages | 🟢 |
| P14 | Sentry monitoring | `core/sentry.py`, `main.py` | 🟢 |
| P15 | Onboarding flow | Flutter home screen + backend | 🟢 |
