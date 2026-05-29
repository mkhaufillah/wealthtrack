# Changelog

## v0.2.0 — Household Finance (2026-05-28)

### Core Features

- **Auth** — Register, login, JWT session persistence, profile management
- **Transactions** — CRUD with categories, date filter, search, household split view
- **Household** — Create/join via invite code, combined dashboard, change transaction owner
- **Budgets** — Per-category monthly limits with progress tracking in mobile
- **Reports** — Monthly summary, category breakdown, daily snapshot, household split, charts (pie/bar/line)

### P4 Features

- **Transfer Balance** — Move funds between household members with dedicated category
- **AI Financial Advisor** — Streaming chat with Brave Search integration, model toggle (Flash/Opus)
- **OCR Invoice Scanner** — Camera/gallery upload with auto-prefill via Kimi K2.6 vision
- **Excel Export** — Yearly multi-sheet export (openpyxl) with download & share
- **Charts** — Interactive pie/bar/line charts with fl_chart, conditional labels

### UI & UX

- **Dark Mode** — Full theme toggle in profile with light/dark consistency across all screens
- **Amount Field** — Rp prefix, numeric formatting, focus UX
- **Pull-to-refresh** — On transactions, budgets, and reports screens
- **Transaction Edit** — Edit all fields inline from the transaction tile menu
- **Delete Account** — With FK cascade cleanup

### Infrastructure

- **CI/CD** — GitHub Actions: APK build on push, auto-deploy backend via SSH
- **Deployment** — Systemd service, nginx reverse proxy, certbot SSL, backup script
- **Security** — Rate limiting, role-based access, CORS restrict, global error handler

### Test Coverage

- **Backend** — 109 tests (auth, transactions, budgets, households, summaries, AI advisor, OCR, exports)
- **Mobile** — 106+ Flutter widget tests (auth, home, transactions, budgets, reports, profile, transfer)

### Docs

- 12 feature docs covering architecture, API, deployment, and mobile UI
- EDN API endpoint spec with schemas, examples, and error codes

---

For detailed commit history, see [GitHub](https://github.com/filla/wealthtrack/commits/main).
