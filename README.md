# WealthTrack 💰

[![Build APK](https://github.com/mkhaufillah/wealthtrack/actions/workflows/build-apk.yml/badge.svg)](https://github.com/mkhaufillah/wealthtrack/actions/workflows/build-apk.yml)
[![Deploy Backend](https://github.com/mkhaufillah/wealthtrack/actions/workflows/deploy-backend.yml/badge.svg)](https://github.com/mkhaufillah/wealthtrack/actions/workflows/deploy-backend.yml)



Personal finance tracker — Filla & Nahda.

**Stack:** FastAPI + SQLite + Flutter + Hermes

## Architecture

```
Hermes ──────► SQLite ◄────── FastAPI ◄────── Flutter Mobile
(cron/chat)                      │
                                 └── JWT Auth
```

Single SQLite database. No Firebase, no Postgres, no sync complexity.

## Quick Start

```bash
# Backend
cd backend
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
uv run python -m backend.app.migrate_db       # Create tables & seed users
uvicorn app.main:app --reload   # Run dev server

# At http://localhost:8080/docs
```

## Project Structure

```
docs/                  # Planning docs (agent-executable)
  ├── 01-project-overview.md
  ├── 02-database-schema.md
  ├── 03-backend-api.md
  ├── 04-backend-implementation.md
  ├── 05-flutter-mobile.md
  ├── 06-hermes-integration.md
  └── 07-deployment.md
backend/               # FastAPI application
mobile/                # Flutter app
scripts/               # DB init & seed scripts
```

## Docs (Agent-Executable)

Each `.md` file in `docs/` is designed for an AI agent to execute:

| Doc | What it covers |
|-----|---------------|
| 01 | Architecture, tech stack, data flow |
| 02 | Full SQLite schema with all tables |
| 03 | Complete API route specification |
| 04 | Step-by-step backend code (agent-ready) |
| 05 | Flutter app structure & screens |
| 06 | Hermes cron & chat integration |
| 07 | VPS deployment with systemd |

## Status

- [x] P1 — Core Backend (FastAPI + SQLite + Auth) ✅
- [ ] P2 — Hermes Integration (cron + chat input)
- [ ] P3 — Flutter Mobile MVP
- [ ] P4 — Charts, Budgets, HTTPS, Polish
