# Brave Search Integration — Verification

**See also:** [Backend API](03-backend-api.md) · [Project Overview](01-project-overview.md) · [Deployment](07-deployment.md) · [P4 Plan](08-p4-plan.md)

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
