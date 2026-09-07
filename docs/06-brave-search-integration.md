# Brave Search Integration

**See also:** [Backend API](03-backend-api.md) · [Project Overview](01-project-overview.md) · [Deployment](07-deployment.md) · [P4 Plan](08-p4-plan.md)

The AI Advisor uses the Brave Search API for live financial context (rates, gold, equities) when the user’s question matches relevant keywords.

## How it works

1. **Keyword detection** — `backend/app/services/web_search.py` checks the question against `HIGH_CONFIDENCE` and `MEDIUM_KEYWORDS`:
   - High confidence (always search): `suku bunga`, `inflasi`, `ihsg`, `harga emas`, `stock price`, `gold price`, etc.
   - Medium (search if present): `terbaru`, `update`, `latest`, `prediksi`, `forecast`, etc.
2. **API call** — On a match, the backend calls `https://api.search.brave.com/res/v1/web/search` with `BRAVE_SEARCH_API_KEY`.
3. **Prompt injection** — Results are formatted and injected as `[Hasil Pencarian Web]` so the model can cite current data.

## Configuration

`BRAVE_SEARCH_API_KEY` is loaded in order from:

- `backend/.env` — primary
- `~/.hermes/.env` — fallback (Hermes env)

If no key is set, the AI Advisor still runs; web search is skipped.
