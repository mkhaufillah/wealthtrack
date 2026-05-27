# Backend API Specification — FastAPI

**See also:** [Database Schema](02-database-schema.md) · [Backend Implementation](04-backend-implementation.md) · [Flutter Mobile](05-flutter-mobile.md)



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
