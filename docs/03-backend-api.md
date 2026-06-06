# Backend API Specification — FastAPI

**See also:** [Database Schema](02-database-schema.md) · [Backend Implementation](04-backend-implementation.md) · [Flutter Mobile](05-flutter-mobile.md) · [Transfer Balance](12-transfer-balance.md) · [Admin Category CRUD](17-admin-category-crud.md) · [P4 Plan](08-p4-plan.md)



## Base Configuration

| Setting | Value |
|---------|-------|
| Host | `127.0.0.1` (Nginx reverse proxy on port 443) |
| Port | `8080` |
| Root path | `/api/v1` |
| Auth | JWT (Bearer token) |
| Docs | Swagger at `/docs`, ReDoc at `/redoc` |

## Authentication

### POST `/api/v1/auth/send-otp`

Send a 6-digit OTP code to the given email for registration. Rate limited to 3/minute.

```json
// Request
{
  "email": "newuser@example.com"
}

// Response 200
{
  "message": "OTP sent to email"
}

// Error 500 — SMTP not configured
{
  "detail": "Failed to send email: SMTP not configured. Set SMTP_USERNAME and SMTP_PASSWORD in .env"
}
```

### POST `/api/v1/auth/register`

Register a new user with email verification. Requires a valid OTP from `/auth/send-otp` first.

```json
// Request
{
  "email": "newuser@example.com",
  "otp_code": "482917",
  "username": "newuser",
  "display_name": "New User",
  "password": "supersecret"
}

// Response 201
{
  "id": 3,
  "username": "newuser",
  "display_name": "New User",
  "email": "newuser@example.com",
  "role": "user",
  "cycle_start_day": 1,
  "created_at": "2026-05-31T10:00:00.000Z"
}

// Error 400 — No OTP sent
{
  "detail": "No OTP sent to this email. Request one via /auth/send-otp first"
}

// Error 400 — Wrong OTP
{
  "detail": "Invalid OTP code"
}

// Error 400 — OTP expired
{
  "detail": "OTP has expired. Request a new one"
}

// Error 409 — Email taken
{
  "detail": "Email already registered"
}
```

### POST `/api/v1/auth/login`

Returns JWT token (expires 30 days).

```json
// Request
{
  "username": "filla",
  "password": "supersecret"
}

// Response 200
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer",
  "expires_in": 2592000
}
```

### GET `/api/v1/auth/me`

Returns current user info. Requires Bearer token.

```json
// Response 200
{
  "id": 1,
  "username": "filla",
  "display_name": "Filla",
  "email": "khaufillahmohammad@gmail.com",
  "role": "admin",
  "cycle_start_day": 25,
  "created_at": "2026-05-26T17:15:01.077Z"
}
```

### PUT `/api/v1/auth/me`

Update current user's display name, cycle start day, and/or email. Requires Bearer token.

```json
// Request — all fields optional
{
  "display_name": "Filla Baru",
  "cycle_start_day": 10,
  "email": "baru@gmail.com"
}

// Response 200
{
  "id": 1,
  "username": "filla",
  "display_name": "Filla Baru",
  "email": "baru@gmail.com",
  "role": "admin",
  "cycle_start_day": 10,
  "created_at": "2026-05-26T17:15:01.077Z"
}

// Error 409 — email taken
{
  "detail": "Email already in use"
}
```

### PUT `/api/v1/auth/password`

Change password. Requires Bearer token + current password verification.

```json
// Request
{
  "current_password": "password123",
  "new_password": "newsecure456"
}

// Response 200
{
  "message": "Password updated successfully"
}

// Error 400 — wrong current password
{
  "detail": "Current password is incorrect"
}
```

### DELETE `/api/v1/auth/me`

Delete the current user account and all associated transactions. Requires Bearer token.

```json
// Response 204 (No Content)
```

**Note:** This is irreversible. All transactions owned by this user are also deleted (CASCADE).

## Categories

### GET `/api/v1/categories`

List all categories. Optional `?type=expense` or `?type=income`.

```json
// Response 200
[
  {
    "id": 1,
    "name": "Makan & Minum",
    "type": "expense",
    "icon": "🍽️",
    "is_default": true
  }
]
```

## Households

Household endpoints manage shared household groups. All endpoints require Bearer token.

### POST `/api/v1/households`

Create a new household. The creator becomes the admin.

```json
// Request
{
  "name": "Home"
}

// Response 201
{
  "id": 1,
  "name": "Home",
  "invite_code": "L62TI5ZG",
  "created_by": 1
}
```

### POST `/api/v1/households/join`

Join an existing household using its invite code.

```json
// Request
{
  "invite_code": "L62TI5ZG"
}

// Response 200
{
  "message": "Joined household successfully",
  "household_id": 1
}

// Error 404
{
  "detail": "Invalid invite code"
}
```

### GET `/api/v1/households/me`

Get current user's household with all members.

```json
// Response 200
{
  "id": 1,
  "name": "Home",
  "invite_code": "L62TI5ZG",
  "members": [
    {
      "user_id": 1,
      "display_name": "Filla",
      "role": "admin"
    },
    {
      "user_id": 2,
      "display_name": "Nahda",
      "role": "member"
    }
  ]
}

// Error 404
{
  "detail": "Not a member of any household"
}
```

### GET `/api/v1/households/invite-code`

Get the invite code for the current user's household.

```json
// Response 200
{
  "invite_code": "L62TI5ZG"
}
```

## Transactions

### GET `/api/v1/transactions`

List transactions with pagination and filters.

**Query params:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `page` | int | 1 | Page number |
| `per_page` | int | 50 | Items per page (max 100) |
| `type` | str | — | Filter: 'expense' or 'income' |
| `category_id` | int | — | Filter by single category |
| `category_ids` | str | — | Filter by multiple categories (comma-separated IDs) |
| `q` | str | — | Search by description (full-text via Meilisearch) |
| `date_from` | str | — | Start date 'YYYY-MM-DD' |
| `date_to` | str | — | End date 'YYYY-MM-DD' |
| `sort` | str | '-date' | Sort field: 'date', '-date', 'amount', '-amount', 'name', '-name' |

```json
// Response 200
{
  "data": [
    {
      "id": 42,
      "amount": 50000,
      "type": "expense",
      "description": "Nasi Goreng",
      "note": "Makan siang",
      "date": "2026-05-26",
      "category": {
        "id": 1,
        "name": "Makan & Minum",
        "name_en": "Food & Drinks",
        "icon": "🍽️"
      },
      "user": {
        "id": 1,
        "display_name": "Filla"
      },
      "created_at": "2026-05-26T12:00:00.000Z"
    }
  ],
  "meta": {
    "page": 1,
    "per_page": 50,
    "total": 1234,
    "total_pages": 25
  }
}
```

### POST `/api/v1/transactions`

Create a new transaction.

```json
// Request
{
  "type": "expense",
  "category_id": 1,
  "amount": 50000,
  "description": "Nasi Goreng",
  "note": "Makan siang",
  "date": "2026-05-26"
}

// Response 201
{
  "id": 42,
  "amount": 50000,
  ...full transaction object
}
```

### PUT `/api/v1/transactions/{id}`

Update a transaction. Only owner can update.

```json
// Request (partial update)
{
  "amount": 55000,
  "note": "Makan siang + es teh"
}

// Response 200
{
  "id": 42,
  ...updated transaction object
}
```

### GET `/api/v1/transactions/{id}`

Get a single transaction by ID. Only the owner can view their own transaction.

```json
// Response 200
{
  "id": 42,
  "amount": 50000,
  "type": "expense",
  "description": "Nasi Goreng",
  "note": "Makan siang",
  "date": "2026-05-26",
  "category": {
    "id": 1,
    "name": "Makan & Minum",
    "icon": "🍽️"
  },
  "user": {
    "id": 1,
    "display_name": "Filla"
  },
  "created_at": "2026-05-26T12:00:00.000Z"
}

// Error 404
{
  "detail": "Transaction not found"
}
```

### GET `/api/v1/transactions/household`

List transactions of **all household members**. Requires the user to be part of a household.

**Query params:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `page` | int | 1 | Page number |
| `per_page` | int | 100 | Items per page (max 200) |
| `type` | str | — | Filter: 'expense' or 'income' |
| `date_from` | str | — | Start date 'YYYY-MM-DD' |
| `date_to` | str | — | End date 'YYYY-MM-DD' |
| `sort` | str | '-date' | Sort field: 'date', '-date', 'amount', '-amount' |

```json
// Response 200
{
  "data": [
    {
      "id": 42,
      "amount": 50000,
      "type": "expense",
      "description": "Nasi Goreng",
      "note": "Makan siang",
      "date": "2026-05-26",
      "category": {
        "id": 1,
        "name": "Makan & Minum",
        "name_en": "Food & Drinks",
        "icon": "🍽️"
      },
      "user": {
        "id": 1,
        "display_name": "Filla"
      },
      "created_at": "2026-05-26T12:00:00.000Z"
    }
  ],
  "meta": {
    "page": 1,
    "per_page": 100,
    "total": 42,
    "total_pages": 1
  }
}
```

// Error 404 — user is not a member of any household
{
  "detail": "Not a member of any household"
}
```

### DELETE `/api/v1/transactions/{id}`

Delete a transaction. Only owner can delete.

```json
// Response 204 (No Content)
```

### PUT `/api/v1/transactions/{id}/owner`

Transfer transaction ownership to another household member.

**Auth:** Bearer token

```json
// Request
{
  "user_id": 2
}

// Response 200
{
  "message": "Transaction ownership transferred successfully"
}
```

**Validation:** Target user must be in the same household.

### POST `/api/v1/transactions/transfer`

Transfer balance to one or more household members. Creates paired expense (sender) and income (recipient) transactions using the "Transfer" category (both expense and income). If the categories don't exist, they are auto-created.

**Auth:** Bearer token

```json
// Request
{
  "date": "2026-05-28",
  "transfers": [
    {"user_id": 2, "amount": 3000000},
    {"user_id": 2, "amount": 500000}
  ]
}

// Response 201
{
  "transactions": [
    {
      "sender_expense": {
        "id": 42,
        "type": "expense",
        "amount": 3000000,
        "description": "Transfer to user 2",
        "date": "2026-05-28",
        "category": {
          "id": 9,
          "name": "Transfer",
          "icon": "🔄"
        },
        "user": {
          "id": 1,
          "display_name": "Ayah"
        }
      },
      "recipient_income": {
        "id": 43,
        "type": "income",
        "amount": 3000000,
        "description": "Transfer from user 1",
        "date": "2026-05-28",
        "category": {
          "id": 10,
          "name": "Transfer",
          "icon": "🔄"
        },
        "user": {
          "id": 2,
          "display_name": "Ibu"
        }
      }
    }
  ]
}
```

**Validation:**
- Sender must be a member of a household
- All recipients must be in the same household as the sender
- Amount must be > 0
- At least 1 recipient, max 10 recipients
- Categories "Transfer" (expense) and "Transfer" (income) are auto-created if they don't exist

## Summaries & Dashboard

### GET `/api/v1/summaries/daily`

Daily summary for a date range.

**Query params:** `date_from`, `date_to` (default: today)

```json
// Response 200
{
  "date_from": "2026-05-01",
  "date_to": "2026-05-26",
  "total_income": 5000000,
  "total_expense": 3250000,
  "balance": 1750000,
  "by_category": [
    {
      "category_id": 1,
      "category_name": "Makan & Minum",
      "category_name_en": "Food & Drinks",
      "icon": "🍽️",
      "total": 1200000,
      "count": 24,
      "percentage": 36.9
    }
  ],
  "by_user": [
    {
      "user_id": 1,
      "display_name": "Filla",
      "total_expense": 2000000,
      "total_income": 0
    },
    {
      "user_id": 2,
      "display_name": "Nahda",
      "total_expense": 1250000,
      "total_income": 0
    }
  ]
}
```

### GET `/api/v1/summaries/household`

Household-wide summary across **all users**. Still requires authentication (logged-in user), but returns combined data.

**Query params:** `date_from`, `date_to` (default: today)

```json
// Response 200
{
  "date_from": "2026-05-01",
  "date_to": "2026-05-26",
  "total_income": 15000000,
  "total_expense": 8500000,
  "balance": 6500000,
  "by_category": [
    {
      "category_id": 1,
      "category_name": "Makan & Minum",
      "category_name_en": "Food & Drinks",
      "icon": "🍽️",
      "total": 1200000,
      "count": 24,
      "percentage": 36.9
    }
  ],
  "by_user": [
    {
      "user_id": 1,
      "display_name": "Filla",
      "total_expense": 5000000,
      "total_income": 10000000
    },
    {
      "user_id": 2,
      "display_name": "Nahda",
      "total_expense": 3500000,
      "total_income": 5000000
    }
  ]
}
```

### GET `/api/v1/summaries/monthly`

Monthly summary for a given month.

**Query params:** `?month=2026-05`

```json
// Response 200
{
  "month": "2026-05",
  "total_income": 15000000,
  "total_expense": 8500000,
  "balance": 6500000,
  "categories": [...],
  "daily_snapshot": [
    {"date": "2026-05-01", "expense": 120000, "income": 0},
    {"date": "2026-05-02", "expense": 85000, "income": 0}
  ]
}
```

The response also includes an `income_categories` array (same structure as `categories`) for per-category income breakdown.

### GET `/api/v1/summaries/current-month`

Quick endpoint — shorthand for `/summaries/monthly?month=<current>`.

## Budgets

### GET `/api/v1/budgets?month=YYYY-MM`

List budgets for a specific month.

**Auth:** Bearer token

**Query params:** `month` (required, format: `YYYY-MM`)

```json
// Response 200
[
  {
    "id": 1,
    "month": "2026-05",
    "category_id": 1,
    "category_name": "Makan & Minum",
    "category_name_en": "Food & Drinks",
    "category_icon": "🍽️",
    "amount": 2000000,
    "user_id": 1
  }
]
```

### POST `/api/v1/budgets`

Create or update a budget (upsert). If a budget already exists for the same month and category, it will be updated.

**Auth:** Bearer token

```json
// Request
{
  "month": "2026-05",
  "category_id": 1,
  "amount": 2000000
}

// Response 201
{
  "id": 1,
  "month": "2026-05",
  "category_id": 1,
  "category_name": "Makan & Minum",
  "category_icon": "🍽️",
  "amount": 2000000,
  "user_id": 1
}
```

### DELETE `/api/v1/budgets/{id}`

Delete a budget. Only the owner can delete.

**Auth:** Bearer token

```json
// Response 204 (No Content)
```

### GET `/api/v1/budgets/summary?month=YYYY-MM`

Budget vs actual spending comparison for a month.

**Auth:** Bearer token

**Query params:** `month` (required, format: `YYYY-MM`)

```json
// Response 200
[
  {
    "category_id": 1,
    "category_name": "Makan & Minum",
    "category_name_en": "Food & Drinks",
    "category_icon": "🍽️",
    "budget_amount": 2000000,
    "actual_spent": 1800000,
    "percentage": 90.0,
    "remaining": 200000
  }
]
```

**Color coding logic (mobile):**

| Condition | Color |
|-----------|-------|
| percentage < 75% | 🟢 Green (on track) |
| percentage >= 75% and < 100% | 🟡 Yellow (warning) |
| percentage >= 100% | 🔴 Red (overspent) |

### GET `/api/v1/budgets/suggestions?month=YYYY-MM&num_cycles=3`

AI-powered budget suggestions based on historical spending analysis.

**Auth:** Bearer token

**Query params:**
- `month` (required, format: `YYYY-MM`) — target month for suggestions
- `num_cycles` (optional, default 3, max 12) — number of past billing cycles to analyze

**Logic:** For each expense category with transaction history, calculates average spending across the last N cycles, then rounds up to the nearest Rp10,000 (minimum Rp10,000). Categories that already have a budget for this month are marked `has_budget: true` but still returned for reference.

```json
// Response 200
{
  "items": [
    {
      "category_id": 1,
      "category_name": "Makanan & Minuman",
      "category_name_en": "Food & Drinks",
      "category_icon": "🍽️",
      "suggested_amount": 1500000,
      "historical_avg": 1420000,
      "historical_max": 1850000,
      "months_analyzed": 3,
      "has_budget": true,
      "existing_amount": 1200000
    }
  ],
  "total_suggested": 5000000,
  "total_income": 8000000,
  "warning": ""
}
```

The `warning` field is populated when `total_suggested > total_income`.

### GET `/api/v1/budgets/health?month=YYYY-MM`

Budget health forecast — mid-cycle projections and per-category risk assessment.

**Auth:** Bearer token

**Query params:**
- `month` (required, format: `YYYY-MM`) — target month

**Response:**

```json
{
  "days_elapsed": 6,
  "total_days": 30,
  "cycle_progress_pct": 20.0,
  "categories": [
    {
      "category_id": 1,
      "category_name": "Makanan & Minuman",
      "category_icon": "🍽️",
      "budget_amount": 1500000,
      "actual_spent": 450000,
      "percentage": 30.0,
      "remaining": 1050000,
      "daily_rate": 75000,
      "projected_end": 2250000,
      "projected_remaining": -750000,
      "health": "at_risk"
    }
  ]
}
```

**Health status mapping:**

| Status | Meaning |
|--------|---------|
| `healthy` | Under 70% spent or well within budget |
| `warning` | 70-99% spent, or projected to exceed |
| `at_risk` | Projected spending > budget by current rate |
| `exhausted` | Budget fully consumed (100%+) |

**Projection formula:** `projected_end = (actual_spent / days_elapsed) × total_days`

### GET `/api/v1/summaries/all-time-category-balance`

Returns lifetime balance for Savings & Investment and Emergency Funds categories. Used by the home screen dashboard widget.

**Auth:** Bearer token

```
// Response 200
{
  "savings_investment": {
    "total_expense": 74331609,
    "total_income": 0,
    "balance": 74331609
  },
  "emergency_funds": {
    "total_expense": 22331609,
    "total_income": 0,
    "balance": 22331609
  }
}
```

**Formula:** `balance = total_expense - total_income`. Savings & Investment balance includes: expense transactions (Tabungan & Investasi / Savings & Investment — money set aside) minus income transactions (Penarikan Tabungan & Investasi / Savings & Investment Disbursed — money withdrawn). Note: Hasil Investasi / Savings & Investment Return (dividends, capital gains) is EXCLUDED from this balance by design. Emergency Funds: expense (top up) minus income (disbursement). Both scoped to the authenticated user.

## Exports

### GET `/api/v1/exports/yearly?year=2026`

Export yearly transactions as an Excel (.xlsx) file.

**Auth:** Bearer token

**Query params:** `year` (required, format: `YYYY`)

**Response:** File download

- **Content-Type:** `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
- **Filename:** `transactions_2026.xlsx`

**Spreadsheet structure:**

- 12 sheets, one per month (e.g., "Jan 2026", "Feb 2026", ...)
- Columns: Date, Type, Category, Amount, Description, Note, Owner
- Summary row per sheet with totals for income, expense, and balance

## OCR / Smart Input

### POST `/api/v1/ocr/process`

Upload a receipt image for OCR extraction. Uses vision AI (Kimi K2.6) to parse receipt data.

**Auth:** Bearer token

**Content-Type:** `multipart/form-data`

**Body:**

| Field | Type | Description |
|-------|------|-------------|
| `file` | image file | Receipt image (JPEG, PNG) |

```json
// Response 200
{
  "amount": 50000,
  "description": "Nasi Goreng",
  "date": "2026-05-26",
  "type": "expense",
  "confidence": 0.95
}
```

**Rate limit:** 10 requests per day per user.

## AI Financial Advisor

### POST `/api/v1/ai/advise`

Ask financial questions with full user context injected for personalized advice.

**Auth:** Bearer token

```json
// Request
{
  "question": "Bagaimana cara menghemat pengeluaran bulan ini?",
  "model": "flash"
}
```

**Request fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `question` | string | required | Financial question |
| `model` | string | `"flash"` | `"flash"` for DeepSeek V4 (all users), `"opus"` for Claude Opus (admin only) |
| `history` | array | `[]` | Last 10 chat exchanges (max) for conversation continuity. Each item: `{"role": "user"|"assistant", "content": "..."}` |

**Model routing:**

| Model | When used |
|-------|-----------|
| `flash` | Fast, budget — default for all (OpenCode Go) |
| `opus` | Deep analysis — admin only, via OpenRouter |

```json
// Response 200
{
  "answer": "Berdasarkan pengeluaran bulan ini...",
  "model_used": "flash"
}
```

**Context injected into prompt:**

- Current account balance
- Monthly income/expense summary
- 6-month spending trends
- Active budget vs actual spending
- Household members

**Disclaimer:** This is an AI-generated financial suggestion and should not be considered professional financial advice. Always consult a licensed financial advisor for major financial decisions.

### POST `/api/v1/ai/advise/stream`

Same as `/advise` but returns a Server-Sent Events (SSE) stream for real-time token-by-token display.

**Request:** Same as `/advise`.

**Response:** SSE stream:

```
data: {"token":"Berdasarkan"}

data: {"token":" pengeluaran"}

data: {"token":" Anda"}

data: [DONE]
```

The client accumulates these tokens and updates the chat bubble progressively for a real-time typing effect.

## Health

### GET `/api/v1/health`

Lightweight health check. Does not require authentication.

```json
// Response 200 — healthy
{
  "status": "healthy"
}

// Response 200 — DB degraded (service still runs)
{
  "status": "degraded"
}
```

## Error Response Format

All errors follow FastAPI's standard HTTPException format:

```json
{
  "detail": "Transaction not found"
}
```

Validation errors use FastAPI's default `RequestValidationError` format:

```json
{
  "detail": [
    {
      "type": "value_error",
      "loc": ["body", "amount"],
      "msg": "amount must be greater than 0",
      "input": -5000
    }
  ]
}
```

- **400** — Bad request (validation, wrong current password, etc.)
- **401** — Missing or invalid token
- **404** — Resource not found
- **409** — Conflict (duplicate username, etc.)
- **422** — Request validation error (Pydantic)
- **429** — Rate limit exceeded
- **500** — Internal server error

## Auth Headers

All endpoints except `/auth/register` and `/auth/login` require:

```
Authorization: Bearer <token>
```

## CORS

CORS origins are configured via `settings.cors_origins_list`, which reads from `CORS_ORIGINS` env var (JSON string). Default: Flutter web dev server + production domain.

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_methods=["*"],
    allow_headers=["*"],
)
```
