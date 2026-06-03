# Hermes Integration — Verification

**See also:** [Backend API](03-backend-api.md) · [Project Overview](01-project-overview.md) · [Deployment](07-deployment.md) · [P4 Plan](08-p4-plan.md)

Hermes is already integrated with WealthTrack automatically. No changes needed.

## Running Automatically

| Component | Function | Database |
|----------|----------|----------|
| Cron "Daily Finance Summary" | Daily report at 8 PM WIB | `~/.keuangan/finance.db` (via finance_db.py) |
| Skill "financial-tracker" | Record transactions from chat | `~/.keuangan/finance.db` (via finance_db.py) |

Both use `finance_db.py` which is **backward compatible** — columns `user_id`, `date`, `note` were added via migration without breaking existing functionality.

## Brave Search Integration

The AI Advisor uses Brave Search API to fetch real-time financial data (e.g., current interest rates, gold prices, stock market) when the user's question contains relevant keywords.

### How It Works

1. **Keyword Detection** — `backend/app/services/web_search.py` checks the user's question against `HIGH_CONFIDENCE` and `MEDIUM_KEYWORDS` lists:
   - High confidence keywords (always trigger search): `suku bunga`, `inflasi`, `ihsg`, `harga emas`, `stock price`, `gold price`, etc.
   - Medium keywords (trigger search if present): `terbaru`, `update`, `latest`, `prediksi`, `forecast`, etc.

2. **API Call** — If keywords match, the backend calls `https://api.search.brave.com/res/v1/web/search` with the `BRAVE_SEARCH_API_KEY`.

3. **Context Injection** — Search results are formatted and injected into the AI prompt as `[Hasil Pencarian Web]` so the model can reference current data.

### Configuration

`BRAVE_SEARCH_API_KEY` is loaded from two sources (in order):
- `backend/.env` — primary location
- `~/.hermes/.env` — fallback (Hermes env), so WealthTrack can reuse an existing key

If no key is found, the AI Advisor still works but without web search capabilities.

### Transfer Categories

Two special categories named "Transfer" were added for the transfer balance feature:

| id | name | type | icon |
|----|------|------|------|
| 16 | Transfer | expense | 🔄 |
| 17 | Transfer | income | 🔄 |

These are auto-created by the backend at startup via `POST /api/v1/transactions/transfer`. The `finance_db.py` script used by Hermes cron/skill is backward compatible — it only inserts into columns it knows about and ignores unknown columns.

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

**Skill error:** Ensure PostgreSQL is running and `DATABASE_URL` is set in `backend/.env`.
Migration is automatic — no manual migration step needed.

## Summary

**Zero changes required.** Hermes cron and skill continue using `finance_db.py` → `~/.keuangan/finance.db`. WealthTrack FastAPI uses the same database. Everything is compatible.

