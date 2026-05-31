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
uv venv
source .venv/bin/activate
uv pip install -r backend/requirements.txt
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
  ├── 08-p4-plan.md
  ├── 09-dark-mode.md
  ├── 10-edit-transaction.md
  ├── 11-delete-transaction.md
  ├── 12-transfer-balance.md
  ├── 13-ai-chat-history.md
  ├── 14-custom-billing-cycle.md
  ├── 15-improvement-plan-ai-ocr.md
  ├── 16-ocr-scanner.md
  └── 17-admin-category-crud.md
backend/               # FastAPI application
mobile/                # Flutter app (Android)
scripts/               # DB init & seed scripts
```

## Features

### Backend API
- **Auth** — register, login (JWT 30-day), profile update, password change, account delete, cycle start day
- **Transactions** — CRUD with pagination, filtering by type/date/category, sorting, change owner
- **Categories** — CRUD (admin), English display name (`name_en`) in every response, keyword mapping for Hermes OCR classification
- **Summaries** — daily, monthly, household (combined across members), current-month shorthand, cycle-aware date ranges, per-category income breakdown
- **Household** — shared household with invite codes, multi-user transaction listing & summaries
- **Budgets** — CRUD with upsert, monthly budget vs actual spending summary, cycle-aware actuals, per-row cycle_on, non-budget expense awareness, **AI-powered budget suggestions from historical spending**, **budget health forecasting with mid-cycle projections**
- **Transfer Balance** — create paired send/transfer transactions between household members
- **Reports** — monthly summary cards, category breakdown, daily snapshot, household split
- **Export** — yearly Excel (.xlsx) export with 12 monthly sheets
- **OCR / Smart Input** — receipt image upload processed via Kimi K2.6 vision AI
- **AI Advisor** — personalized financial advice using DeepSeek Flash V4 with Brave Search, cycle-aware context
- **Health** — lightweight health check endpoint

### Mobile (Flutter)
- **Auth screens** — Login & Register with validation, password visibility toggle
- **Dashboard** — balance card (income/expense) with cycle range label, AI Financial Advisor card, savings & emergency fund widget, recent transactions list
- **Transactions** — list with pull-to-refresh, add/edit/delete transaction with category picker & amount field, search by description, filter by type & category, sort by date/amount/name, paginated browsing
- **Reports** — interactive charts (pie, bar, line) using fl_chart, monthly summary cards, category breakdown, daily snapshot, household split, savings rate, daily average
- **Budgets** — monthly budget tracking with progress bars and color coding, exhausted message on overspent categories, non-budget expense awareness ("Outside Budget" section), **budget suggestion review sheet with accept/decline per category**
- **AI Advisor** — chat-like interface with streaming responses and web search
- **Transfer Balance** — send money to household members directly from the app
- **Dark Mode** — full dark theme support with system preference detection
- **Profile** — user info display, edit profile, change password, logout

### Hermes Integration
- Cron-based daily finance summary delivery to Telegram/WhatsApp
- Expense recording via chat input
- Invoice processing with OCR (Hermes vision API)
- Brave Search powered AI financial advisor

## Status

- [x] P1 — Core Backend (FastAPI + SQLite + Auth) ✅
- [x] P2 — Hermes Integration (cron + chat input) ✅
- [x] P3 — Flutter Mobile MVP ✅
- [x] P4 — Charts, Budgets, Export, OCR, AI Advisor, Change Owner ✅
- [x] P5 — AI chat history (local persistence, sliding window 10, clear on logout) ✅
