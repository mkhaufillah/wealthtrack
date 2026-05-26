# WealthTrack — Project Overview

## What This Is

WealthTrack is a personal finance tracker for Filla & Nahda. Tracks daily expenses, income, budgets, and generates periodic summaries.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    VPS (self-hosted)                  │
│                                                       │
│  ┌──────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │  Hermes   │    │   FastAPI    │    │   SQLite     │  │
│  │ (cron +   │───►│  (port 8080) │───►│ wealthtrack  │  │
│  │  agent)   │    │             │    │   .db       │  │
│  └──────────┘    └──────┬──────┘    └─────────────┘  │
│                         │                             │
│                    HTTP/JSON                          │
│                         │                             │
└─────────────────────────┼─────────────────────────────┘
                          │
                          ▼
                  ┌──────────────┐
                  │    Flutter    │
                  │    Mobile     │
                  │  (Android +   │
                  │   iOS nanti)  │
                  └──────────────┘
```

## Tech Stack

| Layer | Tech | Reason |
|-------|------|--------|
| Database | SQLite (via aiosqlite) | Zero maintenance, 1-file backup, handles 50MB+ easily |
| Backend | FastAPI (Python) | Async, auto-docs, lightweight |
| Mobile | Flutter | Cross-platform, one codebase |
| Auth | JWT (simple username/password) | Self-contained, no Firebase dependency |
| Server | Existing VPS self-hosted | Already running, no extra cost |

## Single Source of Truth

**SQLite is the only database.** No Firestore, no Firebase, no Postgres.

- Hermes writes directly to SQLite
- FastAPI writes to SQLite
- Flutter reads/writes via FastAPI API
- Cron reads from SQLite directly

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
│   ├── requirements.txt
│   └── run.sh                  # Start script
├── mobile/                     # Flutter project (initialized separately)
├── scripts/
│   ├── init_db.py              # Create tables & seed default categories
│   └── seed_data.py            # Optional sample data for dev
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
| Chat "rekap" | User via Hermes | SQLite (direct) |
| Cron summary | Scheduled | SQLite (direct) |
| Mobile dashboard | Flutter | FastAPI REST API (HTTP GET) |

## Phase Plan

| Phase | Scope | Goal |
|-------|-------|------|
| P1 — Core Backend | SQLite schema, FastAPI CRUD, JWT auth, init script | API ready, testable via Swagger |
| P2 — Hermes Integration | Update existing cron script, input from chat | Daily summary works with new DB |
| P3 — Flutter MVP | Login, dashboard, add transaction, list transactions | Mobile usable for daily tracking |
| P4 — Polish | Charts, budgets, categories management, export | Feature-complete for daily use |

## Key Design Decisions

1. **No ORM** — raw SQL with aiosqlite. Simple schema, no need for migration hell.
2. **WAL mode** — `PRAGMA journal_mode=WAL;` for concurrent reads + writes.
3. **JWT auth** — simple, stateless. Token stored in Flutter Secure Storage.
4. **SQLite as single source** — no sync, no conflict resolution needed.
5. **Hermes talks directly to DB** — not through FastAPI. It's co-located on the same VPS.
