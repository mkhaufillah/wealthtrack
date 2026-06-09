# WealthTrack — Personal Finance Tracker

A personal finance tracker. Tracks daily expenses, income, budgets, and generates periodic summaries. Built with FastAPI + PostgreSQL + Redis + Meilisearch + Flutter + AI features. **v0.7.0** — Extra Payment KPR (Reduce Installment / Reduce Tenor) + Household Debt (shared family debt visibility).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    VPS — 2.27.165.90 (self-hosted)                  │
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────┐ │
│  │  Nginx       │──►│  FastAPI     │──►│  PostgreSQL  │   │Redis │ │
│  │  :443 (SSL)  │   │  :8080       │   │  :5432       │   │:6379 │ │
│  │  wealthtrack │   │  (localhost) │   │  wealthtrack │   │(auth)│ │
│  │  .filla.id   │   └──────┬───────┘   └──────────────┘   └──────┘ │
│  └──────────────┘          │                                        │
│                            │ HTTP/JSON                              │
│                            ▼                                        │
│                     ┌──────────────┐   ┌──────────────────────┐    │
│                     │  Flutter     │   │  Meilisearch 1.45.2  │    │
│                     │  Mobile      │   │  :7700 (full-text)   │    │
│                     │  (Android)   │   └──────────────────────┘    │
│                     └──────────────┘                                │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  GitHub Actions Self-Hosted Runner (wealthtrack-vps)            │   │
│  │  ├── test: pytest, 221 tests (Docker Postgres+Redis)         │   │
│  │  ├── deploy: git pull → restart systemd                      │   │
│  │  └── build-apk: Flutter → release APK cleanup                │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Layer | Tech | Purpose |
|-------|------|---------|
| Database | PostgreSQL 18 (via asyncpg) | Primary data store, strict schema |
| Full-Text Search | Meilisearch 1.45.2 (self-hosted) | Instant relevance-based search |
| Rate Limiting / Queue | Redis 8.8.0 (self-hosted, with auth) | Sliding window rate limiter, OCR queue |
| Backend | FastAPI (Python 3.11) | Async, auto-docs, lightweight |
| Mobile | Flutter (Android + iOS later) | Cross-platform, one codebase |
| Auth | JWT (username/password + email OTP) | Self-contained, no Firebase |
| Server | VPS self-hosted, Ubuntu 22.04 | Already running, no extra cost |
| CI/CD | GitHub Actions + Self-Hosted Runner | All workflows on self-hosted VPS (test, deploy, build APK) |
| Domain | wealthtrack.filla.id | Nginx reverse proxy, Let's Encrypt SSL |

## Project Structure

```
~/dev/wealthtrack/
├── backend/                    # FastAPI backend
│   ├── app/
│   │   ├── main.py            # App entry point, lifespan, middleware
│   │   ├── database.py        # asyncpg pool + CursorWrapper + auto-schema init
│   │   ├── core/
│   │   │   ├── config.py      # Settings, env vars
│   │   │   ├── security.py    # JWT auth logic
│   │   │   ├── redis.py       # Redis connection manager (with auth)
│   │   │   ├── rate_limiter.py# Sliding window rate limiter (Redis-backed)
│   │   │   └── meilisearch.py # Meilisearch async client wrapper
│   │   ├── routers/           # Auth, transactions, categories, budgets,
│   │   │                      # summaries, households, exports, OCR,
│   │   │                      # ai_advisor, health
│   │   ├── schemas/           # Pydantic models for API
│   │   ├── services/          # OCR, web_search, AI logic
│   │   ├── requirements.txt
│   │   └── run.sh
│   ├── scripts/
│   │   ├── bulk_index_meilisearch.py
│   │   └── ci_release_setup.py
│   └── tests/                 # 221 tests (pytest + pytest-asyncio)
├── mobile/                    # Flutter project
├── docs/                      # Planning & reference docs
│   ├── 01-project-overview.md
│   ├── 02-database-schema.md
│   ├── 03-backend-api.md
│   ├── 04-backend-implementation.md
│   ├── 05-flutter-mobile.md
│   ├── 06-hermes-integration.md
│   ├── 07-deployment.md
│   ├── 08-p4-plan.md
│   └── ...                    # Feature-specific docs
├── deploy/                    # Systemd service, nginx config, deploy script
├── .github/workflows/         # CI/CD pipelines
└── README.md
```

## CI/CD Pipeline

### Workflows

| Workflow | Trigger | Jobs | Notifications |
|----------|---------|------|---------------|
| `deploy-backend.yml` | Push to `main` (backend/), workflow_dispatch | `test` → `deploy` (both self-hosted) | 🚀 Started → ✅/❌ Tests → ✅/❌ Deploy |
| `build-apk.yml` | Push to `main` (mobile/), workflow_dispatch | Build APK on self-hosted runner | ✅/❌ APK result |

### Telegram Notifications (v2)

Every CI run sends **start + result notifications** to Keluarga Super Sapi → topic Deployment:
- **🚀** CI started (when tests begin)
- **✅/❌** Tests result (immediately after test job)
- **✅** Deploy success (after health check passes)
- **❌** Deploy failure (after deploy fails)

### Secrets (remaining — 5 total)

| Secret | Purpose |
|--------|---------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot for CI notifications |
| `KEYSTORE_BASE64` | Keystore file (base64) for APK signing |
| `KEY_ALIAS` | Keystore alias for APK signing |
| `KEYSTORE_PASSWORD` | Keystore password for APK signing |
| `KEY_PASSWORD` | Key password for APK signing |

## Security

| Layer | What's Done |
|-------|------------|
| **CORS** | Restricted to `wealthtrack.filla.id`, `localhost:8080` (no wildcard) |
| **Redis** | `requirepass` enabled — not publicly accessible |
| **PostgreSQL** | 32-character random password, only localhost connections allowed via `pg_hba.conf` |
| **JWT** | Random SECRET_KEY per deployment (32-byte hex), 30-day expiry |
| **CI/CD** | No SSH secrets in GitHub — NOPASSWD sudo only for `systemctl restart wealthtrack` |
| **API** | Rate limiting (IP-based + user-based on Redis) |
| **OCR** | Per-user queue (1 active job), system semaphore (2 concurrent), 5 OCR/day limit per user |
| **AI Advisor** | Rate limit: 20 queries/day per user, no raw SQL in prompts |

## Key Design Decisions

1. **No ORM** — Raw SQL with asyncpg. Simple schema, no migration hell.
2. **PostgreSQL connection pooling** — asyncpg pool (min 2, max 10) for concurrent reads + writes.
3. **Auto schema init** — Tables + indexes created with `IF NOT EXISTS` on startup. Zero manual migration.
4. **JWT auth** — Stateless. Token stored in Flutter Secure Storage.
5. **Self-hosted runner** — Deploys on git push without SSH secrets. NOPASSWD sudo for systemctl only.
6. **Redis with auth** — Rate limiting and OCR queue survive server restarts. No open access.
7. **Meilisearch for full-text search** — Inverted index scales to millions of transactions.
8. **Hermes talks directly to DB** — Not through FastAPI. Co-located on same VPS.

## Phase Status

|| Phase | Scope | Status |
||-------|-------|--------|
|| P1 — Core Backend | PostgreSQL schema, FastAPI CRUD, JWT auth | ✅ Done |
|| P2 — Hermes Integration | Cron scripts, chat input | ✅ Done |
|| P3 — Flutter MVP | Login, dashboard, add/list transactions | ✅ Done |
|| P4 — Polish | Charts, budgets, export, OCR, AI advisor, change owner | ✅ Done |
|| P5 — Hardening | CI/CD self-hosted runner, CORS/Redis/DB security, Telegram v2 | ✅ Done |
|| P6 — Audit Cleanup | 29 findings audited, 20 fixed, 2 cancelled, 0 bugs | ✅ Done |
|| P7 — Debt Tracker | KPR Calculator + Credit Card Management + Android Widget | ✅ Done |
||| P8 — Home Polishing | Refresh, spacing, projection, due_date, white screen fix | ✅ Done |
||| P9 — Extra Payment KPR + Household Debt | Extra Payment (Option A: Reduce Installment, Option B: Reduce Tenor), preview comparison, household debt aggregation | ✅ Done |

## Deployment

| Service | Status | Port | Access |
|---------|--------|------|--------|
| FastAPI (WealthTrack) | systemd | 127.0.0.1:8080 | Nginx reverse proxy |
| PostgreSQL 18 | systemd | 127.0.0.1:5432 | Localhost only |
| Redis 8.8.0 | systemd | 127.0.0.1:6379 | Password protected |
| Meilisearch 1.45.2 | systemd | 127.0.0.1:7700 | Master key protected |
| Nginx | systemd | 0.0.0.0:80,443 | Public (SSL via Let's Encrypt) |
| GitHub Runner | systemd | Outbound only | Self-hosted, no inbound ports |

See [Deployment Guide](docs/07-deployment.md) for full setup instructions.

## API Docs

- **Swagger UI:** `https://wealthtrack.filla.id/docs`
- **ReDoc:** `https://wealthtrack.filla.id/redoc`
- **Health:** `https://wealthtrack.filla.id/api/v1/health`

See [Backend API](docs/03-backend-api.md) for full endpoint reference.
