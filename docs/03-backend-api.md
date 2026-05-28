# Backend API Specification — FastAPI

**See also:** [Database Schema](02-database-schema.md) · [Backend Implementation](04-backend-implementation.md) · [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)



## Base Configuration

| Setting | Value |
|---------|-------|
| Host | `0.0.0.0` |
| Port | `8080` |
| Root path | `/api/v1` |
| Auth | JWT (Bearer token) |
| Docs | Swagger at `/docs`, ReDoc at `/redoc` |

## Authentication

### POST `/api/v1/auth/register`

Register a new user.

```json
// Request
{
  "username": "filla",
  "display_name": "Filla",
  "password": "supersecret"
}

// Response 201
{
  "id": 1,
  "username": "filla",
  "display_name": "Filla",
  "created_at": "2026-05-26T10:00:00.000Z"
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
  "role": "user"
}
```

### PUT `/api/v1/auth/me`

Update current user's display name. Requires Bearer token.

```json
// Request
{
  "display_name": "Filla Baru"
}

// Response 200
{
  "id": 1,
  "username": "filla",
  "display_name": "Filla Baru",
  "role": "admin",
  "created_at": "2026-05-26T17:15:01.077Z"
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
| `category_id` | int | — | Filter by category |
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
      "total_expense": 2000000
    },
    {
      "user_id": 2,
      "display_name": "Nahda",
      "total_expense": 1250000
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
  "model": "auto"
}
```

**Model routing:**

| Model | When used |
|-------|-----------|
| `flash` | Simple questions (default for "auto") |
| `opus` | Complex analysis (triggered by keywords: *analisis, rekomendasi, portfolio*) |

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

```json
{
  "detail": {
    "code": "VALIDATION_ERROR",
    "message": "amount must be greater than 0",
    "errors": [
      {"field": "amount", "message": "must be > 0"}
    ]
  }
}
```

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
