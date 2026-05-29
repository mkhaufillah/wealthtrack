# P4 Plan — Revised

**See also:** [Project Overview](01-project-overview.md) · [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [Dark Mode](09-dark-mode.md) · [Edit Transaction](10-edit-transaction.md)

**Based on discussion 2026-05-27.** Updated 2026-05-27: Dark mode and edit transaction date completed, moved out of P4.

> **✅ Implementation update:** P2 (Export Excel), P3 (Budgets), P4 (OCR / Smart Input), and P5 (AI Financial Advisor) have all been implemented and are now live. Details below reflect current status.

## Priority Order

| Prio | Feature | Estimasi | Dependencies | Status |
|------|---------|----------|-------------|--------|
| P0 | **Change Transaction Owner** | 0.5 hr | None | ✅ Done |
| P1 | **Charts (Reports Page)** | 2-3 hr | Summary endpoints (ready) | ✅ Done |
| — | **Dark Mode** | — | — | ✅ Done — see [09-dark-mode.md](09-dark-mode.md) |
| — | **Edit Transaction Date** | — | — | ✅ Done — see [10-edit-transaction.md](10-edit-transaction.md) |
| P2 | **Export Excel** | 1 hr | Transaction endpoints (ready) | ✅ Done |
| P3 | **Budgets** | 2-3 hr | Categories + transactions (ready) | ✅ Done |
| P4 | **OCR / Smart Input** | 3-4 hr | OpenCode Go API key | ✅ Done |
| P5 | **AI Financial Advisor** | 2-3 hr | OpenCode Go API key | ✅ Done |
| — | **Transfer Balance** | 1 hr | Household members (ready) | ✅ Done — see [03-backend-api.md](03-backend-api.md) |

**Dropped:** Categories CRUD — static is sufficient.

---

## 1. Change Transaction Owner

**Why:** In a household, sometimes expense is recorded by the wrong person. E.g., Nahda's expense was input by Filla. Allow reassigning.

**Backend only:**
- `PUT /api/v1/transactions/{id}/owner`
  - Request: `{ "user_id": 2 }`
  - Validate: `user_id` must be in the same household as current user
  - Only the current owner (or household admin) can transfer
- Model update: Add `owner` field to transaction schemas

**Mobile:** Add a "Change Owner" action in transaction detail/edit with a user picker (household members only).

**Testing:** Add test for ownership transfer validation.

---

## 2. Charts (Reports Page)

**Preview:** `sketches/charts-compact-card/index.html` and `sketches/charts-dark-dashboard/index.html`

**Components:**

| Component | Data Source | Chart Type |
|-----------|------------|------------|
| Summary cards | `/summaries/current-month` | Text cards (income, expense, balance) |
| Category breakdown (pie/donut) | `/summaries/daily?date_from=...` aggregated | `fl_chart` PieChart |
| Category comparison (horizontal bars) | Same data | `fl_chart` BarChart (horizontal) |
| Monthly trend (income vs expense) | `/summaries/monthly` × 6+ months | `fl_chart` LineChart |
| Daily activity snapshot | `/summaries/daily` | Custom bar list |

**Backend changes:**
- `GET /summaries/monthly` — add support for `?month_from=2026-01&month_to=2026-06` (multi-month)
  - Needed for trend line. Currently only supports single month.

**Mobile changes:**
- Add `fl_chart` to pubspec.yaml
- Rewrite `ReportsScreen` with actual chart widgets
- Month picker / swiper to navigate between months
- Dark/light theme support (matching existing AppTheme)

**Mockups location:** `~/dev/wealthtrack/sketches/`

---

## 3. Export Excel ✓ Implemented

**Backend:**
- `GET /api/v1/exports/yearly?year=2026`
  - Returns `.xlsx` file as download
  - Uses `openpyxl`
  - One sheet per month: 12 sheets
  - Columns: Date | Type | Category | Amount | Description | Note | Owner
  - Summary row per sheet (total income, total expense)
  - Password-protected? (optional)

**Mobile:**
- Add "Export" button in Reports/Profile page
- Triggers download → Android sharesheet (save/share via native)
- Use `dio` download directly

**Dependencies:** `openpyxl` in backend requirements.txt

---

## 4. Budgets ✓ Implemented

**Concept:** Monthly spending limits per category. Visual progress bar shows how close you are to the limit.

**Database:** Table `budgets` already exists:
```sql
CREATE TABLE budgets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  month TEXT NOT NULL,         -- '2026-05'
  category_id INTEGER NOT NULL,
  category_name TEXT NOT NULL,
  budget_amount REAL NOT NULL
);
```

**Backend (new router: `routers/budgets.py`):**
- `GET /api/v1/budgets?month=2026-05` — list budgets for a month
- `POST /api/v1/budgets` — create/update budget
  - Request: `{ "month": "2026-05", "category_id": 6, "amount": 3000000 }`
- `DELETE /api/v1/budgets/{id}` — remove budget
- `GET /api/v1/budgets/summary?month=2026-05` — budgets vs actuals
  - Returns: `[{ category, budget_amount, actual_spent, percentage, remaining }]`

**Mobile:**
- Budgets page with monthly view
- List of categories with budget bar + spent amount
- Color coding: green (< 70%), yellow (70-90%), red (> 90%)
- Add/edit budget bottom sheet
- Optional: notification when approaching limit

**Note:** Schema `backend/app/schemas/budget.py` already exist as placeholders (empty/minimal).

---

## 5. OCR / Smart Input ✓ Implemented

**Architecture:**

```
[Mobile Camera/Gallery]
        │
        ▼
[Backend POST /ocr/process]
  │  Accept: multipart/form-data (image file)
  │
  ▼
[OpenCode Go API — Kimi K2.6 (vision)]
  │  POST https://api.opencode.ai/zen/go/v1/chat/completions
  │  Model: kimi-k2.6
  │  Auth: Bearer OPENCODE_GO_KEY (from .env)
  │  Prompt: structured extraction
  │
  ▼
[Parse response → structured JSON]
  { amount: int, description: string, date: string,
    category_id: int, items: [{name, price}] }
        │
        ▼
[Mobile pre-fill Add Transaction form]
  User confirms/modifies → creates transaction
```

**Backend:**
- `POST /api/v1/ocr/process` — accepts image, returns structured data
- Store API key in `.env`: `OPENCODE_GO_API_KEY`
- Handle errors: unreadable receipt → 422 with message
- Rate limit: max 10 OCR/day per user (protect API budget)

**Mobile:**
- Camera button on Add Transaction screen
- Opens camera or gallery picker
- Uploads image, shows loading state
- Pre-fills form fields on success
- Manual edit if OCR fails

**Config:**
- Copy `OPENCODE_GO_API_KEY` from Hermes `.env` to WealthTrack `.env`
- Kimi K2.6 rate limit: 1,150 req/5h — more than enough for personal OCR

---

## 6. AI Financial Advisor ✓ Implemented

**Architecture:**

```
[Mobile: user asks financial question]
        │
        ▼
[Backend /api/v1/ai/advise]
  1. Query DB → user's financial summary
     - Current balance, income/expense trends (6 months)
     - Top spending categories
     - Current budgets + usage
  2. Construct prompt with financial context
  3. Route to model → DeepSeek Flash V4 (via OpenCode Go API)
  4. Return response
        │
        ▼
[Mobile shows response in chat-like UI]
```

**Backend endpoints:**
- `POST /api/v1/ai/advise` — ask a question
  - Request: `{ "question": "..." }`
  - Uses DeepSeek Flash V4 via OpenCode Go (no model switching)
  - Returns markdown-formatted advice

**Security restrictions (strict):**
- AI only sees data injected by the backend — no direct DB access
- No raw SQL or query strings in prompt
- No terminal/file/network tools available
- User financial data filtered to current user + their household only
- Rate limit: 20 queries/day per user
- Disclaimer: "This is AI-generated advice, not certified financial planning"

**Context injection (what the AI sees):**
```
Kamu adalah asisten finansial untuk {user_display_name}.
Anggota household: {household_members}

Data Keuangan:
- Saldo bulan ini: Rp{balance}
- Total pemasukan {month}: Rp{income}
- Total pengeluaran {month}: Rp{expense}
- Pengeluaran per kategori: {category_breakdown}
- Budget vs realisasi: {budget_summary}
- Tren 6 bulan: {trend_summary}

Pertanyaan: {question}

Berikan saran yang personal dan relevan dengan kondisi keuangan {user_display_name}.
Sertakan disclaimer jika perlu.
```

**Dependencies:**
- `httpx` for API calls (already in project)

**Key files (implemented):**
- `backend/app/routers/ai_advisor.py`
- `backend/app/schemas/advice.py` — request/response schemas

---

## Environment Variables (.env additions)

```bash
# Existing
SECRET_KEY=...
DEBUG=True
ACCESS_TOKEN_EXPIRE_DAYS=30
CORS_ORIGINS=["*"]

# New — OCR & AI Advisor (REQUIRED)
OPENCODE_GO_API_KEY=sk-...           # Copy from Hermes .env

# New — AI Advisor (optional — premium model via OpenRouter)
OPENROUTER_API_KEY=sk-or-...         # For Claude Opus (user id=1 only)

# New — AI Advisor (optional — web search)
BRAVE_SEARCH_API_KEY=...              # Brave Search for real-time data
```

---

## Timeline *(historical — all items completed)*

| Day | Feature | Deliverable |
|-----|---------|-------------|
| 1 | Change Owner + Export Excel | Backend endpoints done, mobile integration started |
| 2-3 | Charts | Working reports page with fl_chart |
| 4-5 | Budgets | Budget CRUD + mobile tracking page |
| 6-7 | OCR | End-to-end: camera → OCR → pre-fill → save |
| 8-9 | AI Advisor | Working financial advisor with market data |
