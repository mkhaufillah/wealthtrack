# Database Schema — WealthTrack

> **Source of truth:** `backend/app/database.py` — schema is auto-created on app startup via `_init_schema()` (idempotent). All `CREATE TABLE`, `CREATE INDEX`, and `ALTER TABLE` statements live in the `SCHEMA_SQL` constant.

## Database

| Item | Value |
|------|-------|
| Engine | PostgreSQL (via asyncpg) |
| Connection | asyncpg pool (`DATABASE_URL` env var) |
| Pool | min 2, max 10 connections |
| Cache / Queue | Redis — rate limiting, OCR queue, AI cache |
| Search | Meilisearch — full-text transaction search |

## Tables (16 total)

### `users`

```sql
CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    username        TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    password_hash   TEXT NOT NULL,
    role            TEXT NOT NULL DEFAULT 'user',
    email           TEXT DEFAULT '',
    cycle_start_day INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email != '';
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| username | `TEXT` | `NOT NULL`, `UNIQUE` |
| display_name | `TEXT` | `NOT NULL` |
| password_hash | `TEXT` | `NOT NULL` |
| role | `TEXT` | `NOT NULL DEFAULT 'user'` |
| email | `TEXT` | `DEFAULT ''` |
| cycle_start_day | `INTEGER` | `NOT NULL DEFAULT 1` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

**Indexes:**
- `idx_users_email` — UNIQUE partial index on `email` WHERE `email != ''`

---

### `email_verifications`

```sql
CREATE TABLE IF NOT EXISTS email_verifications (
    id         SERIAL PRIMARY KEY,
    email      TEXT NOT NULL,
    code       TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    verified   INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_email_verifications_email ON email_verifications(email);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| email | `TEXT` | `NOT NULL` |
| code | `TEXT` | `NOT NULL` |
| expires_at | `TEXT` | `NOT NULL` |
| verified | `INTEGER` | `NOT NULL DEFAULT 0` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

Used for registration OTP flow. OTPs expire after 10 minutes. Each email can have multiple entries (latest one is checked).

---

### `categories`

```sql
CREATE TABLE IF NOT EXISTS categories (
    id         SERIAL PRIMARY KEY,
    name       TEXT NOT NULL,
    type       TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    icon       TEXT DEFAULT '',
    is_default INTEGER DEFAULT 0,
    sort_order INTEGER DEFAULT 0,
    name_en    TEXT DEFAULT '',
    keywords   TEXT DEFAULT '[]'
);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| name | `TEXT` | `NOT NULL` |
| type | `TEXT` | `NOT NULL`, `CHECK(type IN ('income', 'expense'))` |
| icon | `TEXT` | `DEFAULT ''` |
| is_default | `INTEGER` | `DEFAULT 0` |
| sort_order | `INTEGER` | `DEFAULT 0` |
| name_en | `TEXT` | `DEFAULT ''` |
| keywords | `TEXT` | `DEFAULT '[]'` |

Seeded with ~15 categories (5 income + 10 expense). `keywords` stores a JSON array string used for ML-based auto-categorization.

---

### `transactions`

```sql
CREATE TABLE IF NOT EXISTS transactions (
    id            SERIAL PRIMARY KEY,
    type          TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    amount        INTEGER NOT NULL,
    category_id   INTEGER REFERENCES categories(id),
    category_name TEXT DEFAULT '',
    description   TEXT DEFAULT '',
    source        TEXT DEFAULT 'manual',
    image_path    TEXT DEFAULT '',
    created_at    TEXT DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    user_id       INTEGER REFERENCES users(id),
    date          TEXT,
    note          TEXT DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_transactions_user     ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date     ON transactions(COALESCE(date, LEFT(created_at, 10)));
CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date DESC NULLS LAST);
```

**Additional indexes (defined after `ai_messages` table):**
```sql
CREATE INDEX IF NOT EXISTS idx_transactions_user_type_date ON transactions(user_id, type, COALESCE(date, LEFT(created_at, 10)));
CREATE INDEX IF NOT EXISTS idx_transactions_user_cat_date ON transactions(user_id, category_id, COALESCE(date, LEFT(created_at, 10)) DESC);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| type | `TEXT` | `NOT NULL`, `CHECK(type IN ('income', 'expense'))` |
| amount | `INTEGER` | `NOT NULL` (in IDR, no decimals) |
| category_id | `INTEGER` | `REFERENCES categories(id)` |
| category_name | `TEXT` | `DEFAULT ''` (denormalized) |
| description | `TEXT` | `DEFAULT ''` |
| source | `TEXT` | `DEFAULT 'manual'` |
| image_path | `TEXT` | `DEFAULT ''` |
| created_at | `TEXT` | `DEFAULT TO_CHAR(NOW(), ...)` |
| user_id | `INTEGER` | `REFERENCES users(id)` |
| date | `TEXT` | (nullable, YYYY-MM-DD format) |
| note | `TEXT` | `DEFAULT ''` |

**Foreign Keys:**
- `category_id` → `categories(id)`
- `user_id` → `users(id)`

**Indexes (6 total):**
- `idx_transactions_user` — on `user_id`
- `idx_transactions_category` — on `category_id`
- `idx_transactions_date` — on `COALESCE(date, LEFT(created_at, 10))`
- `idx_transactions_user_date` — on `(user_id, date DESC NULLS LAST)`
- `idx_transactions_user_type_date` — on `(user_id, type, COALESCE(date, LEFT(created_at, 10)))`
- `idx_transactions_user_cat_date` — on `(user_id, category_id, COALESCE(date, LEFT(created_at, 10)) DESC)`

---

### `budgets`

```sql
CREATE TABLE IF NOT EXISTS budgets (
    id            SERIAL PRIMARY KEY,
    user_id       INTEGER NOT NULL REFERENCES users(id),
    month         TEXT NOT NULL,
    category_id   INTEGER NOT NULL,
    category_name TEXT NOT NULL,
    budget_amount INTEGER NOT NULL,
    cycle_on      INTEGER NOT NULL DEFAULT 1,
    UNIQUE(user_id, month, category_id)
);

CREATE INDEX IF NOT EXISTS idx_budgets_user_month ON budgets(user_id, month);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| user_id | `INTEGER` | `NOT NULL`, `REFERENCES users(id)` |
| month | `TEXT` | `NOT NULL` (YYYY-MM format) |
| category_id | `INTEGER` | `NOT NULL` |
| category_name | `TEXT` | `NOT NULL` |
| budget_amount | `INTEGER` | `NOT NULL` (in IDR) |
| cycle_on | `INTEGER` | `NOT NULL DEFAULT 1` |

**Foreign Keys:**
- `user_id` → `users(id)`

**Unique constraints:**
- `UNIQUE(user_id, month, category_id)`

---

### `households`

```sql
CREATE TABLE IF NOT EXISTS households (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    created_by  INTEGER NOT NULL REFERENCES users(id),
    created_at  TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| name | `TEXT` | `NOT NULL` |
| invite_code | `TEXT` | `NOT NULL`, `UNIQUE` |
| created_by | `INTEGER` | `NOT NULL`, `REFERENCES users(id)` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

**Foreign Keys:**
- `created_by` → `users(id)`

---

### `household_members`

```sql
CREATE TABLE IF NOT EXISTS household_members (
    user_id      INTEGER NOT NULL REFERENCES users(id),
    household_id INTEGER NOT NULL REFERENCES households(id),
    role         TEXT NOT NULL DEFAULT 'member',
    joined_at    TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    PRIMARY KEY (user_id, household_id)
);

CREATE INDEX IF NOT EXISTS idx_household_members_user      ON household_members(user_id);
CREATE INDEX IF NOT EXISTS idx_household_members_household ON household_members(household_id);
```

| Column | Type | Constraints |
|--------|------|-------------|
| user_id | `INTEGER` | `NOT NULL`, `REFERENCES users(id)`, part of composite PK |
| household_id | `INTEGER` | `NOT NULL`, `REFERENCES households(id)`, part of composite PK |
| role | `TEXT` | `NOT NULL DEFAULT 'member'` |
| joined_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

**Primary Key:** `(user_id, household_id)` — composite, no separate `id` column. This means the `CursorWrapper.lastrowid` path gracefully falls through when `RETURNING id` fails with `UndefinedColumnError`, executing the INSERT normally.

**Foreign Keys:**
- `user_id` → `users(id)`
- `household_id` → `households(id)`

---

### `ocr_jobs`

```sql
CREATE TABLE IF NOT EXISTS ocr_jobs (
    id               SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL REFERENCES users(id),
    image_filename   TEXT,
    status           TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'completed', 'failed')),
    transaction_id   INTEGER REFERENCES transactions(id),
    error            TEXT,
    raw_text         TEXT,
    created_at       TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    completed_at     TEXT
);

CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_status ON ocr_jobs(user_id, status);
```

**Additional index (defined after `ai_messages` table):**
```sql
CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user_created ON ocr_jobs(user_id, created_at DESC);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| user_id | `INTEGER` | `NOT NULL`, `REFERENCES users(id)` |
| image_filename | `TEXT` | (nullable) |
| status | `TEXT` | `NOT NULL DEFAULT 'processing'`, `CHECK(status IN ('processing', 'completed', 'failed'))` |
| transaction_id | `INTEGER` | `REFERENCES transactions(id)` |
| error | `TEXT` | (nullable) |
| raw_text | `TEXT` | (nullable) |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |
| completed_at | `TEXT` | (nullable) |

**Foreign Keys:**
- `user_id` → `users(id)`
- `transaction_id` → `transactions(id)`

---

### `ai_messages`

```sql
CREATE TABLE IF NOT EXISTS ai_messages (
    id                SERIAL PRIMARY KEY,
    user_id           INTEGER NOT NULL REFERENCES users(id),
    role              TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content           TEXT NOT NULL DEFAULT '',
    status            TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'complete', 'error', 'error:hidden')),
    model             TEXT NOT NULL DEFAULT 'flash',
    parent_message_id INTEGER REFERENCES ai_messages(id),
    created_at        TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_ai_messages_user ON ai_messages(user_id, created_at);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| user_id | `INTEGER` | `NOT NULL`, `REFERENCES users(id)` |
| role | `TEXT` | `NOT NULL`, `CHECK(role IN ('user', 'assistant'))` |
| content | `TEXT` | `NOT NULL DEFAULT ''` |
| status | `TEXT` | `NOT NULL DEFAULT 'processing'`, `CHECK(status IN ('processing', 'complete', 'error', 'error:hidden'))` |
| model | `TEXT` | `NOT NULL DEFAULT 'flash'` |
| parent_message_id | `INTEGER` | `REFERENCES ai_messages(id)` (self-referencing FK for conversation threads) |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

**Foreign Keys:**
- `user_id` → `users(id)`
- `parent_message_id` → `ai_messages(id)` (self-referencing)

---

### `kpr_simulations`

```sql
CREATE TABLE IF NOT EXISTS kpr_simulations (
    id                     SERIAL PRIMARY KEY,
    user_id                INTEGER NOT NULL REFERENCES users(id),
    name                   TEXT NOT NULL DEFAULT 'KPR Simulation',
    property_price         INTEGER NOT NULL DEFAULT 0,
    down_payment           INTEGER NOT NULL DEFAULT 0,
    total_loan             INTEGER NOT NULL DEFAULT 0,
    tenor_months           INTEGER NOT NULL DEFAULT 120,
    interest_type          TEXT NOT NULL DEFAULT 'fixed' CHECK(interest_type IN ('fixed', 'floating', 'graduated', 'mix')),
    base_interest_rate     NUMERIC(6,4) NOT NULL DEFAULT 0.075,
    graduated_increment    NUMERIC(6,4) NOT NULL DEFAULT 0.005,
    graduated_every_months INTEGER NOT NULL DEFAULT 12,
    start_month            INTEGER NOT NULL DEFAULT 1,
    start_year             INTEGER NOT NULL DEFAULT 2026,
    due_date               INTEGER DEFAULT NULL,
    created_at             TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_simulations_user ON kpr_simulations(user_id, created_at DESC);
```

**Columns added via ALTER TABLE (household debt support + legacy migration):**
```sql
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS household_id       INTEGER REFERENCES households(id);
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS display_order      INTEGER NOT NULL DEFAULT 0;
-- Legacy column migration (safe on existing)
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS base_interest_rate     NUMERIC(6,4) NOT NULL DEFAULT 0.075;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS graduated_increment    NUMERIC(6,4) NOT NULL DEFAULT 0.005;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS graduated_every_months INTEGER NOT NULL DEFAULT 12;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_month            INTEGER NOT NULL DEFAULT 1;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_year             INTEGER NOT NULL DEFAULT 2026;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS due_date               INTEGER DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_kpr_simulations_household ON kpr_simulations(household_id);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| user_id | `INTEGER` | `NOT NULL`, `REFERENCES users(id)` |
| name | `TEXT` | `NOT NULL DEFAULT 'KPR Simulation'` |
| property_price | `INTEGER` | `NOT NULL DEFAULT 0` |
| down_payment | `INTEGER` | `NOT NULL DEFAULT 0` |
| total_loan | `INTEGER` | `NOT NULL DEFAULT 0` |
| tenor_months | `INTEGER` | `NOT NULL DEFAULT 120` |
| interest_type | `TEXT` | `NOT NULL DEFAULT 'fixed'`, `CHECK(interest_type IN ('fixed', 'floating', 'graduated', 'mix'))` |
| base_interest_rate | `NUMERIC(6,4)` | `NOT NULL DEFAULT 0.075` |
| graduated_increment | `NUMERIC(6,4)` | `NOT NULL DEFAULT 0.005` |
| graduated_every_months | `INTEGER` | `NOT NULL DEFAULT 12` |
| start_month | `INTEGER` | `NOT NULL DEFAULT 1` |
| start_year | `INTEGER` | `NOT NULL DEFAULT 2026` |
| due_date | `INTEGER` | `DEFAULT NULL` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |
| household_id | `INTEGER` | `REFERENCES households(id)` *(added via ALTER TABLE)* |
| display_order | `INTEGER` | `NOT NULL DEFAULT 0` *(added via ALTER TABLE)* |

**Foreign Keys:**
- `user_id` → `users(id)`
- `household_id` → `households(id)`

---

### `kpr_rate_periods`

```sql
CREATE TABLE IF NOT EXISTS kpr_rate_periods (
    id            SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    period_start  INTEGER NOT NULL,
    period_end    INTEGER NOT NULL,
    interest_rate NUMERIC(6,4) NOT NULL,
    rate_type     TEXT NOT NULL DEFAULT 'fixed' CHECK(rate_type IN ('fixed', 'floating')),
    created_at    TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_rate_periods_sim ON kpr_rate_periods(simulation_id);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| simulation_id | `INTEGER` | `NOT NULL`, `REFERENCES kpr_simulations(id) ON DELETE CASCADE` |
| period_start | `INTEGER` | `NOT NULL` (month number) |
| period_end | `INTEGER` | `NOT NULL` (month number) |
| interest_rate | `NUMERIC(6,4)` | `NOT NULL` |
| rate_type | `TEXT` | `NOT NULL DEFAULT 'fixed'`, `CHECK(rate_type IN ('fixed', 'floating'))` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

**Foreign Keys:**
- `simulation_id` → `kpr_simulations(id) ON DELETE CASCADE`

---

### `kpr_monthly_schedules`

```sql
CREATE TABLE IF NOT EXISTS kpr_monthly_schedules (
    id               SERIAL PRIMARY KEY,
    simulation_id    INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    month_number     INTEGER NOT NULL,
    payment          INTEGER NOT NULL,
    principal        INTEGER NOT NULL,
    interest         INTEGER NOT NULL,
    remaining_balance INTEGER NOT NULL,
    rate_type        TEXT NOT NULL,
    interest_rate    NUMERIC(6,4) NOT NULL,
    UNIQUE(simulation_id, month_number)
);

CREATE INDEX IF NOT EXISTS idx_kpr_schedules_sim ON kpr_monthly_schedules(simulation_id);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| simulation_id | `INTEGER` | `NOT NULL`, `REFERENCES kpr_simulations(id) ON DELETE CASCADE` |
| month_number | `INTEGER` | `NOT NULL` |
| payment | `INTEGER` | `NOT NULL` |
| principal | `INTEGER` | `NOT NULL` |
| interest | `INTEGER` | `NOT NULL` |
| remaining_balance | `INTEGER` | `NOT NULL` |
| rate_type | `TEXT` | `NOT NULL` |
| interest_rate | `NUMERIC(6,4)` | `NOT NULL` |

**Foreign Keys:**
- `simulation_id` → `kpr_simulations(id) ON DELETE CASCADE`

**Unique constraints:**
- `UNIQUE(simulation_id, month_number)`

---

### `kpr_extra_payments`

```sql
CREATE TABLE IF NOT EXISTS kpr_extra_payments (
    id                     SERIAL PRIMARY KEY,
    simulation_id          INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    amount                 INTEGER NOT NULL,
    apply_month            INTEGER NOT NULL,
    reduction_type         TEXT NOT NULL DEFAULT 'tenor' CHECK(reduction_type IN ('tenor', 'installment')),
    old_remaining_balance  INTEGER NOT NULL,
    new_remaining_balance  INTEGER NOT NULL,
    old_remaining_months   INTEGER NOT NULL,
    new_remaining_months   INTEGER NOT NULL,
    old_installment        INTEGER NOT NULL DEFAULT 0,
    new_installment        INTEGER NOT NULL DEFAULT 0,
    total_interest_saved   INTEGER NOT NULL DEFAULT 0,
    original_end_date      TEXT DEFAULT '',
    new_end_date           TEXT DEFAULT '',
    created_at             TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_kpr_extra_payments_sim ON kpr_extra_payments(simulation_id);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| simulation_id | `INTEGER` | `NOT NULL`, `REFERENCES kpr_simulations(id) ON DELETE CASCADE` |
| amount | `INTEGER` | `NOT NULL` |
| apply_month | `INTEGER` | `NOT NULL` |
| reduction_type | `TEXT` | `NOT NULL DEFAULT 'tenor'`, `CHECK(reduction_type IN ('tenor', 'installment'))` |
| old_remaining_balance | `INTEGER` | `NOT NULL` |
| new_remaining_balance | `INTEGER` | `NOT NULL` |
| old_remaining_months | `INTEGER` | `NOT NULL` |
| new_remaining_months | `INTEGER` | `NOT NULL` |
| old_installment | `INTEGER` | `NOT NULL DEFAULT 0` |
| new_installment | `INTEGER` | `NOT NULL DEFAULT 0` |
| total_interest_saved | `INTEGER` | `NOT NULL DEFAULT 0` |
| original_end_date | `TEXT` | `DEFAULT ''` |
| new_end_date | `TEXT` | `DEFAULT ''` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

**Foreign Keys:**
- `simulation_id` → `kpr_simulations(id) ON DELETE CASCADE`

> **Note:** The `penalty_rate` and `penalty_amount` columns were removed from this table in v0.7.1. See `backend/scripts/migrate_v0_7_1.py` for the migration.

---

### `credit_cards`

```sql
CREATE TABLE IF NOT EXISTS credit_cards (
    id               SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL REFERENCES users(id),
    name             TEXT NOT NULL,
    card_number_last4 TEXT DEFAULT '',
    billing_date     INTEGER NOT NULL DEFAULT 1,
    due_date         INTEGER NOT NULL DEFAULT 15,
    credit_limit     INTEGER DEFAULT 0,
    created_at       TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_credit_cards_user ON credit_cards(user_id);
```

**Columns added via ALTER TABLE (household debt support):**
```sql
ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS household_id  INTEGER REFERENCES households(id);
ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_credit_cards_household ON credit_cards(household_id);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| user_id | `INTEGER` | `NOT NULL`, `REFERENCES users(id)` |
| name | `TEXT` | `NOT NULL` |
| card_number_last4 | `TEXT` | `DEFAULT ''` |
| billing_date | `INTEGER` | `NOT NULL DEFAULT 1` |
| due_date | `INTEGER` | `NOT NULL DEFAULT 15` |
| credit_limit | `INTEGER` | `DEFAULT 0` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |
| household_id | `INTEGER` | `REFERENCES households(id)` *(added via ALTER TABLE)* |
| display_order | `INTEGER` | `NOT NULL DEFAULT 0` *(added via ALTER TABLE)* |

**Foreign Keys:**
- `user_id` → `users(id)`
- `household_id` → `households(id)`

---

### `credit_card_transactions`

```sql
CREATE TABLE IF NOT EXISTS credit_card_transactions (
    id               SERIAL PRIMARY KEY,
    card_id          INTEGER NOT NULL REFERENCES credit_cards(id) ON DELETE CASCADE,
    description      TEXT NOT NULL DEFAULT '',
    amount           INTEGER NOT NULL,
    category_id      INTEGER REFERENCES categories(id),
    transaction_date TEXT NOT NULL,
    is_installment   INTEGER NOT NULL DEFAULT 0,
    installment_id   INTEGER REFERENCES credit_card_installments(id),
    created_at       TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_cc_transactions_card  ON credit_card_transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_cc_transactions_date ON credit_card_transactions(transaction_date DESC);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| card_id | `INTEGER` | `NOT NULL`, `REFERENCES credit_cards(id) ON DELETE CASCADE` |
| description | `TEXT` | `NOT NULL DEFAULT ''` |
| amount | `INTEGER` | `NOT NULL` |
| category_id | `INTEGER` | `REFERENCES categories(id)` |
| transaction_date | `TEXT` | `NOT NULL` |
| is_installment | `INTEGER` | `NOT NULL DEFAULT 0` |
| installment_id | `INTEGER` | `REFERENCES credit_card_installments(id)` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

**Foreign Keys:**
- `card_id` → `credit_cards(id) ON DELETE CASCADE`
- `category_id` → `categories(id)`
- `installment_id` → `credit_card_installments(id)`

> **Note:** `installment_id` references `credit_card_installments`, which is created *after* `credit_card_transactions` in the SQL. This is a forward reference; the schema init script handles it because PostgreSQL defers FK validation until commit time within the same multi-statement execution.

---

### `credit_card_installments`

```sql
CREATE TABLE IF NOT EXISTS credit_card_installments (
    id               SERIAL PRIMARY KEY,
    card_id          INTEGER NOT NULL REFERENCES credit_cards(id) ON DELETE CASCADE,
    description      TEXT NOT NULL DEFAULT '',
    total_amount     INTEGER NOT NULL,
    monthly_amount   INTEGER NOT NULL,
    total_months     INTEGER NOT NULL,
    remaining_months INTEGER NOT NULL,
    start_month      TEXT NOT NULL,
    created_at       TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);

CREATE INDEX IF NOT EXISTS idx_cc_installments_card ON credit_card_installments(card_id);
```

| Column | Type | Constraints |
|--------|------|-------------|
| id | `SERIAL` | `PRIMARY KEY` |
| card_id | `INTEGER` | `NOT NULL`, `REFERENCES credit_cards(id) ON DELETE CASCADE` |
| description | `TEXT` | `NOT NULL DEFAULT ''` |
| total_amount | `INTEGER` | `NOT NULL` |
| monthly_amount | `INTEGER` | `NOT NULL` |
| total_months | `INTEGER` | `NOT NULL` |
| remaining_months | `INTEGER` | `NOT NULL` |
| start_month | `TEXT` | `NOT NULL` |
| created_at | `TEXT` | `NOT NULL DEFAULT TO_CHAR(NOW(), ...)` |

**Foreign Keys:**
- `card_id` → `credit_cards(id) ON DELETE CASCADE`

---

## Relationship Summary

| FK | Source Table | Target Table | ON DELETE |
|----|-------------|-------------|-----------|
| `user_id` | `transactions` | `users` | *(none)* |
| `category_id` | `transactions` | `categories` | *(none)* |
| `user_id` | `budgets` | `users` | *(none)* |
| `created_by` | `households` | `users` | *(none)* |
| `user_id` | `household_members` | `users` | *(none)* |
| `household_id` | `household_members` | `households` | *(none)* |
| `user_id` | `ocr_jobs` | `users` | *(none)* |
| `transaction_id` | `ocr_jobs` | `transactions` | *(none)* |
| `user_id` | `ai_messages` | `users` | *(none)* |
| `parent_message_id` | `ai_messages` | `ai_messages` | *(none)* |
| `user_id` | `kpr_simulations` | `users` | *(none)* |
| `household_id` | `kpr_simulations` | `households` | *(none)* |
| `simulation_id` | `kpr_rate_periods` | `kpr_simulations` | `CASCADE` |
| `simulation_id` | `kpr_monthly_schedules` | `kpr_simulations` | `CASCADE` |
| `simulation_id` | `kpr_extra_payments` | `kpr_simulations` | `CASCADE` |
| `user_id` | `credit_cards` | `users` | *(none)* |
| `household_id` | `credit_cards` | `households` | *(none)* |
| `card_id` | `credit_card_transactions` | `credit_cards` | `CASCADE` |
| `category_id` | `credit_card_transactions` | `categories` | *(none)* |
| `installment_id` | `credit_card_transactions` | `credit_card_installments` | *(none)* |
| `card_id` | `credit_card_installments` | `credit_cards` | `CASCADE` |

---

## Migration ALTER TABLE Statements

These `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` statements are executed at startup alongside `CREATE TABLE IF NOT EXISTS` — they add columns to existing tables without breaking production data.

```sql
-- kpr_simulations: household debt support + legacy numeric migration
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS household_id       INTEGER REFERENCES households(id);
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS display_order      INTEGER NOT NULL DEFAULT 0;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS base_interest_rate     NUMERIC(6,4) NOT NULL DEFAULT 0.075;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS graduated_increment    NUMERIC(6,4) NOT NULL DEFAULT 0.005;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS graduated_every_months INTEGER NOT NULL DEFAULT 12;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_month            INTEGER NOT NULL DEFAULT 1;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_year             INTEGER NOT NULL DEFAULT 2026;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS due_date               INTEGER DEFAULT NULL;

-- credit_cards: household debt support
ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS household_id  INTEGER REFERENCES households(id);
ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;
```

### Removed Columns (v0.7.1)

The `penalty_rate` and `penalty_amount` columns were removed from `kpr_extra_payments` in version 0.7.1. See `backend/scripts/migrate_v0_7_1.py` for the migration script:

```python
ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS penalty_rate;
ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS penalty_amount;
```

---

## `_init_schema()` Execution

The entire schema — all `CREATE TABLE`, `CREATE INDEX`, and `ALTER TABLE` statements — is defined in a single `SCHEMA_SQL` string constant (lines 188–432 of `app/database.py`). The `_init_schema()` function splits this string on `;` and executes each non-empty, non-comment statement individually:

```python
async def _init_schema(conn):
    """Create tables and indexes if they don't exist. Idempotent."""
    for statement in SCHEMA_SQL.split(';'):
        stmt = statement.strip()
        if stmt and not stmt.startswith('--'):
            try:
                await conn.execute(stmt)
            except Exception as e:
                print(f"Schema init warning (non-fatal): {e}")
```

This runs once at startup inside `init_pool()` on the first acquired connection. Errors are non-fatal (logged but don't crash startup), making the process fully idempotent for both fresh installs and upgrades.

---

## Household-Aware Query Pattern

The app supports household (group) financial management. When a user belongs to a household, certain queries must include data from all household members rather than just the current user.

The pattern is used in `transactions.py`, `summaries.py`, `kpr.py`, `credit_cards.py`, and `ai_advisor.py`:

1. **Lookup the user's household** — query `household_members` for the current user's `household_id`
2. **Join through `household_members`** — use `JOIN household_members hm2 ON hm2.user_id = t.user_id` to scope the query to all members of the same household
3. **Filter by household** — add `hm2.household_id = ?` to the WHERE clause

Example from `transactions.py`:

```python
# Get user's household
cursor = await db.execute(
    "SELECT household_id FROM household_members WHERE user_id = ?",
    (current_user["id"],),
)
hm = await cursor.fetchone()
if not hm:
    raise HTTPException(status_code=404, detail="Not a member of any household")
household_id = hm["household_id"]

# Query all household members' transactions
join_clause = "FROM transactions t JOIN household_members hm2 ON hm2.user_id = t.user_id"
where = ["hm2.household_id = ?"]
params = [household_id]
```

The same pattern is used for KPR simulations and credit cards (which have their own `household_id` FK columns) — in those cases, the filter is simply `WHERE household_id = ?` without the join.

---

## Amount Format

All monetary amounts are stored as `INTEGER` (in IDR, no decimals). Display formatting is done in Flutter / Hermes output.

---

## Redis-Based Rate Limiter

The rate limiter at `backend/app/core/rate_limiter.py` uses a Redis-backed **sliding window** implemented as an atomic Lua script:

- **Key pattern:** `ratelimit:{key}` (e.g., `ratelimit:ocr:user_42`, `ratelimit:ai:user_42`)
- **Data structure:** Redis Sorted Set (ZSET) — each request is a member with its timestamp as score
- **Atomicity:** The Lua script (`_SLIDING_WINDOW_LUA`) atomically removes expired entries (score < `now - window`), counts remaining entries, and either rejects or adds the new entry — preventing TOCTOU race conditions

```lua
local key = KEYS[1]
local max = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local window_start = now - window

redis.call('zremrangebyscore', key, 0, window_start)
local count = redis.call('zcard', key)

if count >= max then
    return {0, count}
end

redis.call('zadd', key, now, tostring(now))
local new_count = count + 1
redis.call('expire', key, window * 2)
return {1, new_count}
```

Usage:
- OCR endpoint: `rate_limit("ocr", max_requests=10, window_sec=86400)` — 10 per day
- AI advisor: `rate_limit("ai", max_requests=30, window_sec=60)` — 30 per minute
- The decorator and function raise `HTTPException(status_code=429)` when the limit is exceeded

---

## Meilisearch Full-Text Search Index

Defined in `backend/app/core/meilisearch.py`:

| Setting | Value |
|---------|-------|
| Index name | `"transactions"` |
| Primary key | `id` |
| Searchable attributes | `["description"]` |
| Filterable attributes | `["user_id", "type", "category_id", "date"]` |
| Sortable attributes | `["date", "amount"]` |

**Document structure indexed per transaction:**

```json
{
  "id": 123,
  "description": "Grocery shopping",
  "type": "expense",
  "amount": 150000,
  "category_id": 5,
  "user_id": 42,
  "date": "2026-06-13"
}
```

**Lifecycle:**
- On transaction create/update → `index_document(txn_dict)` is called from the transaction router
- On transaction delete → `delete_document(txn_id)` is called
- All calls run via `anyio.to_thread.run_sync()` to avoid blocking the async event loop
- A `bulk_index_documents()` helper is available for migration/seed scripts (sync)
- Search results return transaction IDs via `search_descriptions(q, filters, sort, offset, limit)`

---

## Backup

The database is backed up via `pg_dump`. For automated backups, set up a cron job:

```bash
pg_dump -U wealthtrack -d wealthtrack > ~/wealthtrack-backups/wealthtrack-$(date +%Y%m%d-%H%M%S).sql
```
