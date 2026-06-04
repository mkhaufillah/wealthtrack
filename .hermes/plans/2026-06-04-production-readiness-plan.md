# Production Readiness Plan — WealthTrack

> **Goal:** Harden WealthTrack for public release by fixing security, infrastructure, and reliability gaps.
>
> **Status:** Planning only — execute after VPS migration.

---

## Priority Matrix

| # | Item | Severity | Effort | Dependencies |
|---|------|----------|--------|--------------|
| P0 | `DEBUG=False` | 🔴 Critical | 1 file | None |
| P1 |`SECRET_KEY` → env | 🔴 Critical | 1 check | None |
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

## Phase 1: 🔴 Critical Security (Do First)

### P0: Set `DEBUG=False`

**Files:**
- Modify: `backend/app/core/config.py:17`

```python
DEBUG: bool = False
```

**Verification:** Restart app, hit `/api/v1/health` — response should NOT include stack traces on errors.

---

### P1: Verify `SECRET_KEY`

**Check:** In `backend/.env`, confirm `SECRET_KEY` is not `"change-me-in-production-use-env"`.

Generate a strong key:
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```
Copy output to `backend/.env`:
```env
SECRET_KEY=<generated-key>
```

**Verification:** Restart app, login should still work (new tokens signed with new key — old tokens invalidated).

---

### P2: Add Password Policy

**Files:**
- Create: `backend/app/core/password_policy.py`
- Modify: `backend/app/routers/auth.py:94`

1. **New file `backend/app/core/password_policy.py`:**
```python
import re
from fastapi import HTTPException

MIN_LENGTH = 8
REQUIRE_UPPER = True    # At least one uppercase
REQUIRE_LOWER = True    # At least one lowercase
REQUIRE_DIGIT = True    # At least one digit
REQUIRE_SPECIAL = True  # At least one special char

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

2. **Modify `auth.py:94`** — add validation before hash:
```python
from app.core.password_policy import validate_password

# In register():
validate_password(data.password)
pw_hash = hash_password(data.password)
```

**Verification:**
```bash
# Test weak password rejected
curl -X POST https://wealthtrack.filla.id/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"test","email":"test@test.com","password":"1","display_name":"Test"}'
# Expected: 422 with password policy message
```

---

### P3: Lock CORS Origins

**Modify:** `backend/app/core/config.py:36-41`

```python
# Before:
CORS_ORIGINS: str = '["*"]'

# After — lock to actual frontend origins:
CORS_ORIGINS: str = '["https://wealthtrack.filla.id", "https://app.wealthtrack.filla.id"]'
```

Add a comment explaining each origin.

**Verification:** Request from `curl -H "Origin: https://evil.com"` — should not include `Access-Control-Allow-Origin: *`.

---

### P4: Shorter Token Expiry + Refresh Token

**Files:**
- Modify: `backend/app/core/config.py:34`
- Create: `backend/app/routers/refresh.py`

1. **Change token expiry** in `config.py:34`:
```python
ACCESS_TOKEN_EXPIRE_HOURS: int = 168     # 7 days
REFRESH_TOKEN_EXPIRE_DAYS: int = 30      # 30 days
```

2. **Create `backend/app/routers/refresh.py`:**
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

3. **Update `create_access_token`** in `security.py` — add `type` field and use hours:
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

4. **Register router** in `main.py`:
```python
from app.routers import refresh as refresh_router
app.include_router(refresh_router, prefix="/api/v1")
```

**Verification:** Login, get token, verify it expires in 7 days.

---

## Phase 2: 🟡 Infrastructure & Cost Control

### P5: Auth Rate Limiting Audit

**Files:**
- Modify: `backend/app/routers/auth.py:31-32`

Current limits:
- `/auth/send-otp` — 3/minute ✅
- `/auth/register` — 5/minute ✅
- `/auth/login` — 10/minute → tighten to **5/minute**

Add IP-based + username-based tracking to prevent credential stuffing:
```python
# On login failure, add Redis increment with 5-min TTL
# Block after 5 failed attempts per username in 15 minutes
```

---

### P6: Database Backup

**Create:** `scripts/backup-db.sh` (in deploy/ directory):

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

# Optional: rsync to offsite
# rsync -avz "$BACKUP_DIR/" backup@offsite:/backups/wealthtrack/
```

**Add cron:** `0 3 * * * /home/filla/dev/wealthtrack/deploy/backup-db.sh`

**Verification:** Run script, check `.dump` file exists. Restore to a test DB to verify.

---

### P7: Email Service Upgrade

**Current:** SMTP Gmail from VPS root.

Switch to **SendGrid** (or Resend, Mailgun, AWS SES):

1. Create SendGrid account → API key
2. Update `.env`:
```env
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=<sendgrid-api-key>
```
Or better: use SendGrid's HTTP API via `sendgrid` pip package.

**Verification:** Send a test OTP email.

---

### P8: OCR Cost Control

**Files:**
- Modify: `backend/app/core/config.py` — add tiered limits
- Modify: `backend/app/routers/ocr.py` — hard cap check

**Approach:**
1. Add `MAX_OCR_PER_DAY: int = 10` in config.py (user-defined config)
2. Add `OCR_TIER: str = "standard"` — future: paid tier gets more scans
3. The Redis rate limiter already enforces per-day limit (currently 30). Keep 30.
4. Add a **daily budget cap** — global Redis key `ocr:daily_budget` tracking total OCR calls across all users. If total > budget (e.g., 1000/day), reject all new scans.
5. Add **admin endpoint** to view/reset usage.

**Simplified first pass:**
```python
# In config.py
OCR_DAILY_LIMIT_PER_USER: int = 10
OCR_GLOBAL_DAILY_BUDGET: int = 500
```

---

### P9: AI Advisor Cost Control

**Files:**
- Modify: `backend/app/core/config.py` — add AI limits
- Modify: `backend/app/routers/ai_advisor.py` — check limit

**Approach:**
1. Add `AI_CHAT_LIMIT_PER_USER: int = 20` per day (Redis key)
2. Track via Redis: `ratelimit:ai:user_{user_id}`
3. "Flash" model only for non-admin users (already implemented)
4. Add max response tokens cap: `16384` is very high — reduce to `4096` for flash model
5. Add web search debouncing — don't search web if same/similar question asked within 5 minutes

**In `ai_advisor.py`** above the chat endpoint:
```python
from app.core.rate_limiter import check_rate_limit

@router.post("/chat")
async def ai_chat(...):
    await check_rate_limit(
        key=f"ai:user_{current_user['id']}",
        max_requests=settings.AI_CHAT_LIMIT_PER_USER,
        window_sec=86400,
        error_message="Daily AI chat limit reached",
    )
```

---

## Phase 3: 🟡🟢 Feature Completeness

### P10: Password Reset Flow

**Files:**
- Create: `backend/app/routers/auth.py` — `POST /auth/forgot-password` & `POST /auth/reset-password`
- Modify: `backend/app/core/email.py` — reset email template

1. **`POST /auth/forgot-password`** — accept email, send reset link with token (OTP-based, same as registration)
2. **`POST /auth/reset-password`** — accept email + OTP + new password
3. Rate-limited: 1/minute per email (prevent abuse)

---

### P11: User Deletion Flow

**Files:**
- Add: `backend/app/routers/auth.py` — `DELETE /auth/account`

```python
@router.delete("/account", status_code=204)
async def delete_account(current_user=Depends(get_current_user), db=Depends(get_db)):
    """Delete user account and all associated data."""
    # Order matters due to FK constraints:
    # 1. ocr_jobs → transactions → budgets → household_members → users
    await db.execute("DELETE FROM ocr_jobs WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM ai_messages WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM transactions WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM budgets WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM household_members WHERE user_id = ?", (current_user["id"],))
    await db.execute("DELETE FROM email_verifications WHERE email IN (SELECT email FROM users WHERE id = ?)", (current_user["id"],))
    await db.execute("DELETE FROM users WHERE id = ?", (current_user["id"],))
```

---

### P12: Error Messages Audit

Search for bare `HTTPException` calls with raw messages:

```bash
grep -rn 'HTTPException' backend/app/routers/ | grep -v "test_"
```

Replace raw tech messages:
- `"Vision API error: {status_code}"` → `"Image processing failed. Please try again."`
- `"Invalid or corrupted image file"` → already human-readable ✅
- `"Failed to send email: {e}"` → `"Unable to send verification email. Please try again later."`

---

### P13: ToS / Privacy Policy

Create a static page at `/legal`:
- Simple HTML served from FastAPI `static/` directory
- Or a separate route `GET /api/v1/legal/tos` and `GET /api/v1/legal/privacy`
- Content: standard financial app ToS (user data ownership, no financial advice disclaimer)

---

### P14: Monitoring / Sentry

**Add Sentry to FastAPI:**

```python
# backend/app/core/sentry.py
import sentry_sdk
from app.core.config import settings

def init_sentry():
    if settings.SENTRY_DSN:
        sentry_sdk.init(
            dsn=settings.SENTRY_DSN,
            traces_sample_rate=0.1,  # 10% of requests
            environment="production",
        )
```

In `main.py:23`, add `init_sentry()`.

**Additional:**
- Add `@app.exception_handler` for logging all 500s with stack trace
- Add structured logging: JSON logs to stdout (systemd journal)

---

### P15: Onboarding Flow

When a new user registers with $0 balance:
- Auto-create a "Welcome" transaction (Rp0 description)
- Show a "Getting Started" banner with 3 steps:
  1. Add your first transaction
  2. Set a monthly budget
  3. Scan a receipt

---

## Phase Execution Order

```
Week 1: 🔴 P0-P4 (Security)
  Day 1: P0 (DEBUG=False) + P1 (SECRET_KEY check) + P2 (Password policy)
  Day 2: P3 (CORS) + P4 (Token expiry)
  Day 3: Test everything, fix issues

Week 2: 🟡 P5-P10 (Infra & Cost)
  Day 1: P5 (Auth audit) + P6 (Backup)
  Day 2: P7 (Email) + P8 (OCR cost)
  Day 3: P9 (AI cost) + P10 (Password reset)

Week 3: 🟢 P11-P15 (Features)
  Day 1: P11 (Account deletion) + P12 (Error messages)
  Day 2: P13 (ToS/Privacy) + P14 (Sentry)
  Day 3: P15 (Onboarding) + integration testing
```
