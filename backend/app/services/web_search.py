"""
Brave Search API — financial web search for AI Advisor.

Uses Brave Search API (free tier: 2,000 queries/month).
Requires BRAVE_SEARCH_API_KEY in .env.
"""

from typing import Optional
import httpx
from app.core.config import settings

SEARCH_URL = "https://api.search.brave.com/res/v1/web/search"

# ── Keyword detection ─────────────────────────────────────────

HIGH_CONFIDENCE = [
    # Indonesian
    "suku bunga", "inflasi", "ihsg", "reksadana", "obligasi",
    "deposito", "dividen", "valas", "crypto", "bitcoin",
    "harga emas", "emas hari ini", "harga saham",
    "kpr", "bi rate", "kurs", "nilai tukar",
    "pajak", "tarif pajak",
    # English
    "interest rate", "inflation", "stock price", "stock market",
    "mutual fund", "bond yield", "exchange rate", "forex",
    "gold price", "crypto price", "bitcoin price",
    "mortgage rate", "tax rate", "central bank",
]

MEDIUM_KEYWORDS = [
    # Indonesian
    "terbaru", "update", "terkini", "saat ini", "sekarang",
    "rekomendasi", "terbaik", "review", "rating",
    "prediksi", "perkiraan", "proyeksi", "ramalan", "tren",
    "bandingkan", "perbandingan", "vs",
    "perform", "kinerja", "return",
    # English
    "latest", "current", "today", "update",
    "recommendation", "best", "top", "review", "rating",
    "prediction", "forecast", "projection", "trend",
    "compare", "comparison", "vs",
    "performance", "yield",
]


def _should_search(question: str) -> bool:
    """Determine if the question needs a web search."""
    q = question.lower()

    # HIGH_CONFIDENCE — always search regardless of other words
    for kw in HIGH_CONFIDENCE:
        if kw in q:
            return True

    # MEDIUM — search if any keyword found
    for kw in MEDIUM_KEYWORDS:
        if kw in q:
            return True

    return False


async def search_web(query: str, count: int = 5) -> list[dict]:
    """
    Search Brave Web Search API.

    Returns list of dicts with keys: title, snippet, url.
    Returns empty list on error or missing API key.
    """
    api_key = settings.BRAVE_SEARCH_API_KEY
    if not api_key:
        return []

    params = {"q": query, "count": min(count, 10), "safesearch": "moderate"}

    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get(
                SEARCH_URL,
                headers={
                    "Accept": "application/json",
                    "Accept-Encoding": "gzip",
                    "X-Subscription-Token": api_key,
                },
                params=params,
            )
            if resp.status_code != 200:
                return []

            data = resp.json()
            results = []
            for item in data.get("web", {}).get("results", []):
                results.append({
                    "title": item.get("title", ""),
                    "snippet": item.get("description", ""),
                    "url": item.get("url", ""),
                })
            return results

        except Exception:
            return []


def format_search_results(results: list[dict]) -> str:
    """Format search results into a string for injection into the prompt."""
    if not results:
        return ""

    lines = ["\n[Hasil Pencarian Web]"]
    for i, r in enumerate(results, 1):
        snippet = r.get("snippet", "")
        title = r.get("title", "")
        url = r.get("url", "")
        if snippet:
            lines.append(f"{i}. {title}: {snippet}")
        else:
            lines.append(f"{i}. {title}")
    return "\n".join(lines)
