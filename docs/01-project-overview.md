# WealthTrack — Project Overview

## What This Is

WealthTrack is a personal finance tracker for Filla & Nahda. Tracks daily expenses, income, budgets, and generates periodic summaries.

Current version: **v0.7.1** — Extra Payment UX Polish (thousand separator, date format) + Household Debt Context + Penalty Cleanup.

## Related Documents

- [Database Schema](02-database-schema.md) — table definitions & seed data
- [Backend API](03-backend-api.md) — endpoint reference & auth flow
- [Backend Implementation](04-backend-implementation.md) — step-by-step build guide
- [Flutter Mobile](05-flutter-mobile.md) — mobile app design & architecture
- [Brave Search Integration](06-brave-search-integration.md) — Brave Search API integration
- [Deployment](07-deployment.md) — VPS setup, nginx, CI/CD, self-hosted runner
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
- [Extra Payment KPR & Household Debt](plans/2026-06-09-extra-payment-household-debt.md) — implemented in v0.7.0

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    VPS — 2.27.165.90 (self-hosted)                      │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────┐ │
│  │  Nginx       │──►│  FastAPI     │──►│  PostgreSQL  │   │  Redis   │ │
│  │  :443 (SSL)  │   │  :8080       │   │  :5432       │   │  :6379   │ │
│  │  wealthtrack │   │  (localhost) │   │  (localhost  │   │  (auth)  │ │
│  │  .filla.id   │   └──────┬───────┘   │   only)      │   └──────────┘ │
│  └──────────────┘          │            └──────────────┘                │
│                            │                        ┌──────────────┐   │
│                       HTTP/JSON                     │ Meilisearch  │   │
│                            │                        │ :7700 (FT)   │   │
│                            ▼                        └──────────────┘   │
│                     ┌──────────────┐                                   │
│                     │   Flutter    │    ┌─────────────────────────┐    │
│                     │   Mobile     │    │ GitHub Actions Runner   │    │
│                     │  (Android)   │    │ (self-hosted, systemd)  │    │
│                     └──────────────┘    └─────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Layer | Tech | Reason |
|-------|------|--------|
| Database | PostgreSQL 18 (via asyncpg) | Production-ready, connection pooling, strict schema |
| Full-Text Search | Meilisearch 1.45.2 (self-hosted) | Instant relevance-based search, replaces SQL LIKE, ~30MB idle |
| Rate Limiting / Queue | Redis 8.8.0 (self-hosted, with auth) | Sliding window rate limiter, OCR queue state, AI cache |
| Backend | FastAPI (Python 3.11) | Async, auto-docs, lightweight |
| Mobile | Flutter | Cross-platform, one codebase |
| Auth | JWT (username/password + email OTP) | Self-contained, no Firebase dependency |
| Server | VPS — 2.27.165.90 (Ubuntu 22.04) | Already running, no extra cost |
| CI/CD | GitHub Actions + Self-Hosted Runner | All workflows on self-hosted runner (test, deploy, APK build) |

## Single Source of Truth

**PostgreSQL is the single source of truth.** Connection via asyncpg pool.

- FastAPI — reads/writes via asyncpg pool (request-scoped connections)
- Flutter — reads/writes via FastAPI API
- Hermes cron — reads/writes directly to PostgreSQL (same VPS, no API needed)

## Project Structure

```
~/dev/wealthtrack/
├── backend/                    # FastAPI backend
│   ├── app/
│   │   ├── main.py            # App entry point, lifespan, middleware
│   │   ├── database.py        # asyncpg pool + CursorWrapper + auto-schema init
│   │   ├── core/
│   │   │   ├── config.py      # Settings, env vars (CORS, Redis auth, etc.)
│   │   │   ├── security.py    # JWT auth logic
│   │   │   ├── redis.py       # Redis connection manager
│   │   │   ├── rate_limiter.py# Redis-backed sliding window rate limiter
│   │   │   └── meilisearch.py # Meilisearch async client wrapper
│   │   ├── models/             # Raw SQL query helpers
│   │   ├── schemas/            # Pydantic models for API
│   │   ├── routers/            # Auth, transactions, categories, budgets,
│   │   │                       # summaries, households, exports, OCR,
│   │   │                       # AI advisor, health, admin categories
│   │   ├── services/           # OCR processing, web search, AI logic
│   │   ├── requirements.txt
│   │   └── run.sh
│   ├── scripts/                # Bulk indexing, CI setup
│   └── tests/                  # 313 tests (pytest-asyncio)
├── mobile/                     # Flutter project (290 tests)
├── docs/                       # Planning docs (this directory)
├── deploy/                     # Systemd service, nginx config, deploy script
├── .github/workflows/          # CI/CD pipelines
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

| Phase | Scope | Status |
|-------|-------|--------|
| P1 — Core Backend | PostgreSQL schema, FastAPI CRUD, JWT auth, init script | ✅ Done |
| P2 — Hermes Integration | Update existing cron script, input from chat | ✅ Done |
| P3 — Flutter MVP | Login, dashboard, add transaction, list transactions | ✅ Done |
| P4 — Polish | Charts, budgets, export, OCR, AI advisor, change owner | ✅ Done |
| P5 — Hardening | CI/CD self-hosted runner, CORS/Redis/DB security, Telegram v2 | ✅ Done |
| P6 — Audit Cleanup | 29 findings audited, 20 fixed, 2 cancelled, 0 bugs | ✅ Done |

## Key Design Decisions

1. **No ORM** — raw SQL with asyncpg. Simple schema, no need for migration hell.
2. **PostgreSQL connection pooling** — asyncpg pool for concurrent reads + writes. Auto-schema init on startup.
3. **JWT auth** — simple, stateless. Token stored in Flutter Secure Storage.
4. **PostgreSQL as single source** — no sync, no conflict resolution needed.
5. **Hermes talks directly to DB** — not through FastAPI. It's co-located on the same VPS.
6. **Meilisearch for full-text search** — inverted index, not SQL LIKE. Scales to millions of transactions.
7. **Redis for ephemeral state** — rate limiting and OCR queue state. Password-protected.
8. **Self-hosted CI runner** — deploys without SSH secrets. NOPASSWD sudo for systemctl only.
