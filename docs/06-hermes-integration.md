# Hermes Integration — Verification

**See also:** [Backend API](03-backend-api.md) · [Project Overview](01-project-overview.md) · [Deployment](07-deployment.md) · [P4 Plan](08-p4-plan.md)

Hermes is already integrated with WealthTrack automatically. No changes needed.

## Running Automatically

| Component | Function | Database |
|----------|----------|----------|
| Cron "Daily Finance Summary" | Daily report at 8 PM WIB | `~/.keuangan/finance.db` (via finance_db.py) |
| Skill "financial-tracker" | Record transactions from chat | `~/.keuangan/finance.db` (via finance_db.py) |

Both use `finance_db.py` which is **backward compatible** — columns `user_id`, `date`, `note` were added via migration without breaking existing functionality.

## Test: Cron Works

```bash
# Check cron is active
hermes cron list

# Look for "Daily Finance Summary" — verify status is active
# Run manually to test
hermes cron run --job-id <id_from_list>
```

## Test: Financial-Tracker Skill

```bash
# Verify the skill can still read the DB
python3 ~/.hermes/skills/productivity/financial-tracker/scripts/finance_db.py recent 3
```

Expected output: 3 most recent transactions appear.

## Test: Data Consistency

Transactions entered via Hermes (chat or cron) must also appear via the API:

```bash
# 1. Check from Hermes
python3 ~/.hermes/skills/productivity/financial-tracker/scripts/finance_db.py recent 5

# 2. Check from FastAPI
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"filla","password":"password123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s "http://127.0.0.1:8080/api/v1/transactions?per_page=5" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
d = json.load(sys.stdin)
print(f'Total transactions in FastAPI: {d[\"meta\"][\"total\"]}')
print(f'Should match finance_db.py output — same database.')
"
```

## Troubleshooting

**Cron fails:** `hermes cron list` — check the `Last run` column. If there's an error, run manually:
```bash
python3 ~/.hermes/scripts/daily_finance_report.py
```

**Skill error:** Make sure migration has been run:
```bash
cd ~/dev/wealthtrack && .venv/bin/python -m backend.app.migrate_db
```
Migration is safe to re-run — only adds columns if they don't exist.

## Summary

**Zero changes required.** Hermes cron and skill continue using `finance_db.py` → `~/.keuangan/finance.db`. WealthTrack FastAPI uses the same database. Everything is compatible.

