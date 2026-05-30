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
    "kpr syariah", "kpr rumah pertama", "kpr rumah kedua",
    "dp rumah", "down payment rumah", "angsuran kpr",
    "tenor kpr", "simulasi kpr", "btn kpr",
    "pajak", "tarif pajak",
    # Stock market & analysis
    "saham", "analisa teknikal", "analisis teknikal",
    "analisa fundamental", "analisis fundamental",
    "sentimen pasar", "rekomendasi saham",
    "pasar modal", "bursa efek", "bei",
    "ipo", "right issue", "stock split", "buyback",
    "saham syariah", "jakarta islamic index",
    "beli saham", "jual saham", "investasi saham",
    "portofolio saham", "diversifikasi saham",
    "sector rotation", "saham sektor",
    # Property & housing
    "properti", "rumah", "harga rumah", "harga properti",
    "subsidi perumahan", "flpp", "kpr bersubsidi",
    # Banking & savings
    "bunga bank", "bunga tabungan", "bunga deposito",
    "suku bunga acuan", "giro", "tabungan berjangka",
    "ldp", "loan to deposit",
    # Insurance
    "asuransi", "premi asuransi", "asuransi jiwa",
    "asuransi kesehatan", "asuransi pendidikan",
    # General finance & economy
    "produk domestik bruto", "pdb", "pertumbuhan ekonomi",
    "tenaga kerja", "pengangguran", "upah minimum",
    "umr", "umk", "harga pangan", "harga kebutuhan pokok",
    "kartu prakerja", "bansos", "bantuan sosial",
    "subsidi", "subsidi bbm", "subsidi listrik",
    "blt", "bantuan langsung tunai",
    # Investment products
    "reksadana pasar uang", "reksadana pendapatan tetap",
    "reksadana campuran", "reksadana saham", "rdpu", "rdpt",
    "etf", "sbn", "sukuk", "obligasi pemerintah",
    "obligasi korporasi", "sukuk ritel", "sbr",
    "st012", "st010", "orip",
    # Defined contribution
    "dana pensiun", "bpjs ketenagakerjaan", "jht", "jp",
    # English
    "interest rate", "inflation", "stock price", "stock market",
    "mutual fund", "bond yield", "exchange rate", "forex",
    "gold price", "crypto price", "bitcoin price",
    "mortgage rate", "tax rate", "central bank",
    # English
    "technical analysis", "fundamental analysis",
    "market sentiment", "stock recommendation",
    "ipo", "etf", "dividend yield", "pe ratio",
    "market cap", "trading volume",
    # Credit cards
    "kartu kredit", "limit kartu kredit",
    "tagihan kartu kredit", "kartu kredit terbaik",
    # Loans & financing
    "pinjaman online", "pinjol", "kta",
    "kredit tanpa agunan", "kredit mobil",
    "kredit motor", "kredit rumah", "kredit kendaraan",
    "leasing", "kredit barang", "cicilan barang",
    # Credit score
    "skor kredit", "credit score", "bi checking",
    "slik", "blacklist bank",
    # Fintech & digital
    "fintech", "bank digital",
    "dompet digital", "e-wallet", "gopay", "ovo",
    "dana aplikasi", "sea bank", "jenius",
    # Emergency fund
    "dana darurat", "emergency fund",
    # Education fund
    "tabungan pendidikan", "dana pendidikan",
    "biaya sekolah", "uang kuliah", "biaya kuliah",
    # Side business
    "bisnis sampingan", "usaha sampingan",
    "side hustle", "investasi bisnis",
    "usaha kecil", "modal usaha",
    # Restructuring
    "restrukturisasi", "keringanan pembayaran",
    "penundaan pembayaran", "rescheduling",
]

MEDIUM_KEYWORDS = [
    # Indonesian
    "terbaru", "update", "terkini", "saat ini", "sekarang",
    "rekomendasi", "terbaik", "review", "rating",
    "prediksi", "perkiraan", "proyeksi", "ramalan", "tren",
    "bandingkan", "perbandingan", "vs",
    "perform", "kinerja", "return",
    "keuntungan", "risiko", "resiko",
    "cara", "tips", "panduan", "tutorial",
    "beda", "perbedaan", "pilih", "mana yang",
    "layak", "worth it", "mahal", "murah",
    "laris", "populer", "diminati",
    "simulasi", "kalkulator",
    "biaya", "tarif", "ongkos",
    "daftar", "list", "urutan",
    "menguntungkan", "potensi", "peluang",
    # English
    "latest", "current", "today", "update",
    "recommendation", "best", "top", "review", "rating",
    "prediction", "forecast", "projection", "trend",
    "compare", "comparison", "vs",
    "performance", "yield",
    "how to", "guide", "tips", "tutorial",
    "cost", "fee", "rate",
    "list", "ranking", "top",
    "profitable", "potential", "opportunity",
    "definition", "meaning", "explanation",
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
