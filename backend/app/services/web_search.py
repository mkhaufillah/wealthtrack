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
    # ── Monetary policy & macro ──
    "suku bunga", "bi rate", "suku bunga acuan",
    "inflasi", "produk domestik bruto", "pdb",
    "pertumbuhan ekonomi", "tenaga kerja", "pengangguran",
    # ── Currency ──
    "kurs", "nilai tukar", "valas", "forex",
    "kurs dollar", "kurs rupiah", "harga dollar", "usd idr",
    # ── IHSG & stock market ──
    "ihsg", "bursa efek", "bei", "pasar modal",
    "saham", "harga saham", "beli saham", "jual saham",
    "rekomendasi saham", "investasi saham",
    "portofolio saham", "diversifikasi saham",
    "saham syariah", "jakarta islamic index",
    "saham blue chip", "saham lapis kedua", "saham gorengan",
    "saham sektor", "sector rotation",
    "ipo", "right issue", "stock split", "buyback",
    # ── Stock analysis ──
    "analisa teknikal", "analisis teknikal",
    "analisa fundamental", "analisis fundamental",
    "sentimen pasar", "teknikal",
    # ── English stock ──
    "stock price", "stock market", "stock recommendation",
    "technical analysis", "fundamental analysis",
    "market sentiment", "trading volume",
    "ipo", "etf", "dividend yield", "pe ratio", "market cap",
    # ── Gold & commodities ──
    "harga emas", "emas hari ini", "gold price",
    "harga minyak dunia", "harga batubara",
    "harga sawit", "cpo", "harga cpO",
    # ── Crypto ──
    "crypto", "bitcoin", "bitcoin price", "crypto price",
    # ── Property ──
    "properti", "rumah", "harga rumah", "harga properti",
    "subsidi perumahan", "flpp",
    # ── KPR / mortgage ──
    "kpr", "kpr syariah", "kpr bersubsidi",
    "kpr rumah pertama", "kpr rumah kedua",
    "dp rumah", "down payment rumah",
    "angsuran kpr", "tenor kpr", "simulasi kpr", "btn kpr",
    "mortgage rate",
    # ── Banking ──
    "bunga bank", "bunga tabungan", "bunga deposito",
    "deposito", "giro", "tabungan berjangka",
    "ldp", "loan to deposit",
    # ── Bank names ──
    "bca", "mandiri", "bri", "bni",
    "cimb niaga", "hsbc", "permata",
    "bank syariah indonesia", "bsi",
    # ── Digital bank ──
    "bank digital", "fintech",
    "dompet digital", "e-wallet", "gopay", "ovo", "dana",
    "sea bank", "jenius", "blu",
    # ── Credit cards ──
    "kartu kredit", "limit kartu kredit",
    "tagihan kartu kredit", "kartu kredit terbaik",
    # ── Loans ──
    "pinjaman online", "pinjol",
    "kta", "kredit tanpa agunan",
    "kredit mobil", "kredit motor", "kredit rumah",
    "kredit kendaraan", "leasing",
    "kredit barang", "cicilan barang",
    "bunga pinjaman", "bunga kredit",
    # ── Credit score ──
    "skor kredit", "credit score", "bi checking",
    "slik", "blacklist bank",
    # ── Tax ──
    "pajak", "tarif pajak", "tax rate",
    "npwp", "spt tahunan", "lapor pajak",
    "pph 21", "ppn", "pph final",
    # ── Insurance ──
    "asuransi", "premi asuransi",
    "asuransi jiwa", "asuransi kesehatan",
    "asuransi pendidikan", "asuransi mobil",
    # ── Pensiun & BPJS ──
    "dana pensiun", "perencanaan pensiun",
    "bpjs ketenagakerjaan", "bpjs kesehatan",
    "jht", "jp", "iuran bpjs", "kelas bpjs", "bpjs",
    # ── Investment products ──
    "reksadana", "rdpu", "rdpt",
    "reksadana pasar uang", "reksadana pendapatan tetap",
    "reksadana campuran", "reksadana saham",
    "obligasi", "obligasi pemerintah", "obligasi korporasi",
    "sukuk", "sukuk ritel", "sbn", "sbr",
    "st012", "st010", "orip",
    "etf", "mutual fund", "bond yield",
    # ── Finance education ──
    "financial planner", "perencana keuangan",
    "cara mengatur keuangan", "tips keuangan",
    "cara hemat uang", "tips hemat",
    "dana darurat", "emergency fund",
    "perencanaan keuangan",
    # ── Debt management ──
    "bebas utang", "strategi bayar utang",
    "konsolidasi utang",
    # ── Zakat & religious ──
    "zakat", "zakat penghasilan", "zakat mal",
    "zakat fitrah", "infaq", "sedekah",
    "nishab zakat", "nishab emas",
    # ── Hajj & Umrah ──
    "biaya haji", "biaya umrah", "tabungan haji",
    # ── Marriage / wedding ──
    "biaya nikah", "biaya pernikahan",
    # ── Education fund ──
    "tabungan pendidikan", "dana pendidikan",
    "biaya sekolah", "uang kuliah", "biaya kuliah",
    "spp", "snbt", "snbp",
    # ── Vehicle prices ──
    "harga mobil", "harga motor",
    "cicilan mobil", "cicilan motor",
    # ── Commodity prices ──
    "harga pangan", "harga kebutuhan pokok",
    "harga beras", "harga minyak goreng",
    "harga daging", "harga telur",
    "harga bbm", "harga pertalite", "harga solar",
    # ── Utilities ──
    "tarif listrik", "token listrik", "pln", "tagihan listrik",
    "tarif air", "pdam", "tagihan air",
    # ── Telecom ──
    "paket internet", "indihome", "firstmedia",
    "biaya internet", "myrep", "biaya telpon",
    # ── Healthcare costs ──
    "biaya rumah sakit", "biaya dokter",
    "biaya berobat", "tarif rs",
    # ── Shopping / belanja ──
    "belanja", "perbelanjaan", "belanja online",
    "harga produk", "belanja kebutuhan",
    "diskon", "promo", "obral",
    "tokopedia", "shopee", "e-commerce",
    # ── Tickets / travel ──
    "tiket", "tiket pesawat", "tiket kereta",
    "harga tiket", "pesawat", "booking",
    # ── Side business ──
    "bisnis sampingan", "usaha sampingan",
    "side hustle", "usaha online", "bisnis online",
    "dropship", "reseller", "modal usaha",
    # ── Government programs ──
    "kartu prakerja", "bansos", "bantuan sosial",
    "subsidi", "subsidi bbm", "subsidi listrik",
    "blt", "bantuan langsung tunai",
    "upah minimum", "umr", "umk",
    # ── Economic indicators ──
    "central bank", "interest rate", "inflation",
    # ── Living costs ──
    "biaya hidup", "kebutuhan sehari hari",
    "kenaikan harga",
]

MEDIUM_KEYWORDS = [
    # Indonesian recency
    "terbaru", "update", "terkini", "saat ini", "sekarang",
    "realtime", "real-time", "live",
    # Indonesian comparison & opinion
    "rekomendasi", "terbaik", "review", "rating",
    "bandingkan", "perbandingan", "vs",
    "beda", "perbedaan", "pilih", "mana yang",
    "layak", "worth it", "mahal", "murah",
    "menguntungkan", "potensi", "peluang",
    "laris", "populer", "diminati",
    # Indonesian prediction
    "prediksi", "perkiraan", "proyeksi", "ramalan", "tren",
    "simulasi", "kalkulator",
    # Indonesian performance
    "perform", "kinerja", "return", "keuntungan", "risiko",
    # Indonesian guidance
    "cara", "tips", "panduan", "tutorial",
    "biaya", "tarif", "ongkos", "harga", "produk",
    "daftar", "list", "urutan",
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
    # General knowledge triggers
    "apa itu", "pengertian", "definisi",
    "perbedaan", "arti",
    "contoh", "perhitungan",
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
