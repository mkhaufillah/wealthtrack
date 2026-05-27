# WealthTrack 💰

[![Build APK](https://github.com/mkhaufillah/wealthtrack/actions/workflows/build-apk.yml/badge.svg)](https://github.com/mkhaufillah/wealthtrack/actions/workflows/build-apk.yml)
[![Deploy Backend](https://github.com/mkhaufillah/wealthtrack/actions/workflows/deploy-backend.yml/badge.svg)](https://github.com/mkhaufillah/wealthtrack/actions/workflows/deploy-backend.yml)

Personal finance tracker for **Filla & Nahda** — manage household expenses, income, and budgets together.

**Stack:** FastAPI + SQLite + Flutter (Android) + Hermes Agent

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
  ├── 07-deployment.md
  └── 08-p4-plan.md
backend/               # FastAPI application
mobile/                # Flutter app (Android)
scripts/               # DB init & seed scripts
```

## Features

### Backend API
- **Auth** — register, login (JWT 30-day), profile update, password change, account delete
- **Transactions** — CRUD with pagination, filtering by type/date/category, sorting
- **Categories** — list with type filter, pre-seeded
- **Summaries** — daily, monthly, household (combined across members), current-month shorthand
- **Household** — shared household with invite codes, multi-user transaction listing & summaries

### Mobile (Flutter)
- **Auth screens** — Login & Register with validation, password visibility toggle
- **Dashboard** — balance card (income/expense), recent transactions list
- **Transactions** — list with pull-to-refresh, add transaction with category picker & amount field
- **Reports** — monthly summary cards, category breakdown, daily snapshot, household split,
  household category breakdown, household daily breakdown (grouped by day)
- **Profile** — user info display (stub ready for extension)

### Hermes Integration
- Cron-based daily finance summary delivery to Telegram/WhatsApp
- Expense recording via chat input
- Invoice processing with EasyOCR

## Status

- [x] P1 — Core Backend (FastAPI + SQLite + Auth) ✅
- [x] P2 — Hermes Integration (cron + chat input) ✅
- [x] P3 — Flutter Mobile MVP ✅
- [ ] P4 — Charts, Budgets, Export, OCR, AI Advisor, Change Owner (see [docs/08-p4-plan.md](docs/08-p4-plan.md))
