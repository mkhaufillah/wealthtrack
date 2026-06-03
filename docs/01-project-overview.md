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
│  │ (cron +  │───►│ (port 8080) │───►│             │   │
│  │  agent)  │    │             │    └─────────────┘   │
│  └──────────┘    └──────┬──────┘          ▲           │
│                         │                 │           │
│                    HTTP/JSON           search IDs     │
│                         │                 │           │
│                         ▼          ┌─────────────┐   │
│                  ┌──────────────┐   │ Meilisearch │   │
│                  │    Flutter   │   │ (full-text) │   │
│                  │    Mobile    │   └─────────────┘   │
│                  │  (Android +  │   ┌─────────────┐   │
│                  │   iOS later) │   │ Redis 8.8   │   │
│                  └──────────────┘   │ (limiter +  │   │
│                                     │  OCR queue) │   │
│                                     └─────────────┘   │
└───────────────────────────────────────────────────────┘
```

## Tech Stack

| Layer | Tech | Reason |
|-------|------|--------|
| Database | PostgreSQL (via asyncpg) — `DATABASE_URL` env var | Production-ready, connection pooling, strict schema |
| Full-Text Search | Meilisearch 1.45.2 (self-hosted) | Instant relevance-based search, replaces SQL LIKE, ~30MB idle |
| Rate Limiting / Queue | Redis 8.8.0 (self-hosted) | Sliding window rate limiter, OCR queue state |
| Backend | FastAPI (Python) | Async, auto-docs, lightweight |
| Mobile | Flutter | Cross-platform, one codebase |
| Auth | JWT (simple username/password) | Self-contained, no Firebase dependency |
| Server | Existing VPS self-hosted | Already running, no extra cost |

## Single Source of Truth

**PostgreSQL is the single source of truth.** Connection via asyncpg pool.

- FastAPI — reads/writes via asyncpg pool (request-scoped connections)
- Flutter — reads/writes via FastAPI API
- Existing data (27 transactions) remains safe, no data migration needed

## Project Structure

```
~/dev/wealthtrack/
├── backend/                    # FastAPI backend
│   ├── app/
│   │   ├── main.py            # App entry point, middleware
│   │   ├── database.py        # asyncpg pool + CursorWrapper
│   │   ├── core/
│   │   │   ├── config.py      # Settings, env vars
│   │   │   ├── security.py    # JWT auth logic
│   │   │   ├── redis.py       # Redis connection manager
│   │   │   ├── rate_limiter.py# Sliding window rate limiter
│   │   │   └── meilisearch.py # Meilisearch async client wrapper
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
| Chat message | User → Hermes | Hermes agent writes via Python script | PostgreSQL |
| Cron scheduled | DailyReport | Python script reads PostgreSQL, generates summary | PostgreSQL (read) |
| Mobile app | Filla/Nahda | Flutter → HTTP POST → FastAPI → PostgreSQL | PostgreSQL (via API) |

### Read Path

| Method | Who | Data Source |
|--------|-----|-------------|
| Chat "recap" | User via Hermes | PostgreSQL (via pool) |
| Cron summary | Scheduled | PostgreSQL (via pool) |
| Mobile dashboard | Flutter | FastAPI REST API (HTTP GET) |

## Phase Plan

| Phase | Scope | Goal |
|-------|-------|------|
| P1 — Core Backend | PostgreSQL schema, FastAPI CRUD, JWT auth, init script | API ready, testable via Swagger |
| P2 — Hermes Integration | Update existing cron script, input from chat | Daily summary works with new DB |
| P3 — Flutter MVP | Login, dashboard, add transaction, list transactions | Mobile usable for daily tracking |
|| [P4 — Polish (Revised)](08-p4-plan.md) | Charts, budgets, export, OCR, AI advisor, change owner | Feature-complete for daily use |

## Key Design Decisions

1. **No ORM** — raw SQL with asyncpg. Simple schema, no need for migration hell.
2. **PostgreSQL connection pooling** — asyncpg pool for concurrent reads + writes.
3. **JWT auth** — simple, stateless. Token stored in Flutter Secure Storage.
4. **PostgreSQL as single source** — no sync, no conflict resolution needed.
5. **Hermes talks directly to DB** — not through FastAPI. It's co-located on the same VPS.
6. **Meilisearch for full-text search** — description search uses inverted index, not SQL LIKE. Scale to millions of transactions without performance degradation. Meilisearch returns matched IDs → PostgreSQL fetches full rows with JOINs.
7. **Redis for ephemeral state** — rate limiting and OCR queue state stored in Redis, not in PostgreSQL or in-memory. Survives server restarts.
