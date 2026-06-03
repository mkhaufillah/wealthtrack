# WealthTrack — Project Overview

## What This Is

WealthTrack is a personal finance tracker for Filla & Nahda. Tracks daily expenses, income, budgets, and generates periodic summaries.


## Related Documents

- [Database Schema](02-database-schema.md) — table definitions & seed data
- [Backend API](03-backend-api.md) — endpoint reference & auth flow
- [Backend Implementation](04-backend-implementation.md) — step-by-step build guide
- [Flutter Mobile](05-flutter-mobile.md) — mobile app design & architecture
- [Hermes Integration](06-hermes-integration.md) — connecting Hermes cron & skill
- [Deployment](07-deployment.md) — VPS setup, nginx, CI/CD
- [P4 Plan](08-p4-plan.md) — updated feature roadmap: charts, budgets, export, OCR, AI advisor, change owner
- [Dark Mode](09-dark-mode.md) — dark theme implementation for Flutter
- [Edit Transaction](10-edit-transaction.md) — edit flow & UI states
- [Delete Transaction](11-delete-transaction.md) — delete flow & confirmation dialog
- [Transfer Balance](12-transfer-balance.md) — send money between household members
- [AI Chat History](13-ai-chat-history.md) — local chat persistence on-device
- [Custom Billing Cycle](14-custom-billing-cycle.md) — cycle-based summaries & budgets
- [Improvement Plan AI & OCR](15-improvement-plan-ai-ocr.md) — AI Advisor & OCR improvements roadmap
- [OCR Scanner](16-ocr-scanner.md) — receipt scanning with vision AI
- [Admin Category CRUD](17-admin-category-crud.md) — category management for admin


## Architecture

```
┌───────────────────────────────────────────────────────┐
│                    VPS (self-hosted)                  │
│                                                       │
│  ┌──────────┐    ┌─────────────┐    ┌─────────────┐   │
│  │  Hermes  │    │  FastAPI    │    │  PostgreSQL │   │
│  │ (cron +  │───►│ (port 8080) │───►│ finance.db  │   │
│  │  agent)  │    │             │    │             │   │
│  └──────────┘    └──────┬──────┘    └─────────────┘   │
│                         │                             │
│                    HTTP/JSON                          │
│                         │                             │
└─────────────────────────┼─────────────────────────────┘
                          │
                          ▼
                  ┌──────────────┐
                  │    Flutter   │
                  │    Mobile    │
                  │  (Android +  │
                  │   iOS later) │
                  └──────────────┘
```

## Tech Stack

| Layer | Tech | Reason |
|-------|------|--------|
| Database | PostgreSQL (via asyncpg) — `DATABASE_URL` env var | Production-ready, connection pooling, strict schema |
| Backend | FastAPI (Python) | Async, auto-docs, lightweight |
| Mobile | Flutter | Cross-platform, one codebase |
| Auth | JWT (simple username/password) | Self-contained, no Firebase dependency |
| Server | Existing VPS self-hosted | Already running, no extra cost |

## Single Source of Truth

**PostgreSQL is the single source of truth.** Connection via asyncpg pool.

- FastAPI — reads/writes via asyncpg pool (request-scoped connections)
- SQLite backup (`~/.keuangan/finance.db`) — preserved but no longer used at runtime
- Flutter — reads/writes via FastAPI API
- Existing data (27 transactions) remains safe, no data migration needed

## Project Structure

```
~/dev/wealthtrack/
├── backend/                    # FastAPI backend
│   ├── app/
│   │   ├── main.py            # App entry point, middleware
│   │   ├── database.py        # SQLite connection, WAL mode
│   │   ├── core/
│   │   │   ├── config.py      # Settings, env vars
│   │   │   └── security.py    # JWT auth logic
│   │   ├── models/
│   │   │   ├── user.py        # SQLAlchemy-style models (raw SQL)
│   │   │   ├── transaction.py
│   │   │   ├── category.py
│   │   │   └── budget.py
│   │   ├── schemas/
│   │   │   ├── user.py        # Pydantic models for API
│   │   │   ├── transaction.py
│   │   │   ├── category.py
│   │   │   └── budget.py
│   │   └── routers/
│   │       ├── auth.py        # Login, register
│   │       ├── transactions.py
│   │       ├── categories.py
│   │       ├── budgets.py
│   │       └── summaries.py   # Dashboard & report endpoints
│   │       ├── households.py  # Household management & invite codes
│   │       ├── exports.py     # Yearly Excel export
│   │       ├── ocr.py         # Receipt OCR processing
│   │       ├── ai_advisor.py  # AI financial advisor
│   │       └── health.py      # Health check endpoint
│   │   ├── services/
│   │   │   └── web_search.py  # Brave Search for AI Advisor
│   │   ├── requirements.txt
│   │   └── run.sh             # Start script
├── mobile/                     # Flutter project (initialized separately)
├── docs/                       # Planning docs (this directory)
└── README.md
```

## Data Flow Summary

### Write Path (Input)

| Method | Who | How | DB |
|--------|-----|-----|----|
| Chat message | User → Hermes | Hermes agent writes via Python script | SQLite |
| Cron scheduled | DailyReport | Python script reads SQLite, generates summary | SQLite (read) |
| Mobile app | Filla/Nahda | Flutter → HTTP POST → FastAPI → SQLite | SQLite (via API) |

### Read Path

| Method | Who | Data Source |
|--------|-----|-------------|
| Chat "recap" | User via Hermes | SQLite (direct) |
| Cron summary | Scheduled | SQLite (direct) |
| Mobile dashboard | Flutter | FastAPI REST API (HTTP GET) |

## Phase Plan

| Phase | Scope | Goal |
|-------|-------|------|
| P1 — Core Backend | SQLite schema, FastAPI CRUD, JWT auth, init script | API ready, testable via Swagger |
| P2 — Hermes Integration | Update existing cron script, input from chat | Daily summary works with new DB |
| P3 — Flutter MVP | Login, dashboard, add transaction, list transactions | Mobile usable for daily tracking |
|| [P4 — Polish (Revised)](08-p4-plan.md) | Charts, budgets, export, OCR, AI advisor, change owner | Feature-complete for daily use |

## Key Design Decisions

1. **No ORM** — raw SQL with aiosqlite. Simple schema, no need for migration hell.
2. **WAL mode** — `PRAGMA journal_mode=WAL;` for concurrent reads + writes.
3. **JWT auth** — simple, stateless. Token stored in Flutter Secure Storage.
4. **SQLite as single source** — no sync, no conflict resolution needed.
5. **Hermes talks directly to DB** — not through FastAPI. It's co-located on the same VPS.
