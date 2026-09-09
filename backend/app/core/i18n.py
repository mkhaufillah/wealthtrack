"""Locale helpers and category copy_key map."""
from __future__ import annotations

from app.core.redis import get_redis

DEFAULT_LOCALE = "id-ID"
SUPPORTED_LOCALES = ("id-ID", "en-US")

# (canonical Indonesian name, type) → ui_copy key
CATEGORY_COPY_KEYS: dict[tuple[str, str], str] = {
    ("Makanan & Minuman", "expense"): "cat.n.food",
    ("Transportasi & Bensin", "expense"): "cat.n.transport",
    ("Belanja Bulanan", "expense"): "cat.n.shopping",
    ("Hiburan", "expense"): "cat.n.entertainment",
    ("Tagihan & Cicilan", "expense"): "cat.n.bills",
    ("Kesehatan", "expense"): "cat.n.health",
    ("Pendidikan", "expense"): "cat.n.education",
    ("Tabungan & Investasi", "expense"): "cat.n.savings",
    ("Kebutuhan Bayi/Anak", "expense"): "cat.n.baby",
    ("Lainnya", "expense"): "cat.n.expense.other",
    ("Transfer", "expense"): "cat.n.expense.transfer",
    ("Dana Darurat", "expense"): "cat.n.expense.emergency",
    ("Kebutuhan Rumah", "expense"): "cat.n.home",
    ("Hobi & Belajar", "expense"): "cat.n.hobby",
    ("Protein, Buah, dan Sayuran", "expense"): "cat.n.protein",
    ("Kebutuhan Pribadi", "expense"): "cat.n.personal",
    ("Gaji", "income"): "cat.n.salary",
    ("Freelance", "income"): "cat.n.freelance",
    ("Bonus & THR", "income"): "cat.n.bonus",
    ("Penarikan Tabungan & Investasi", "income"): "cat.n.withdrawal",
    ("Lainnya", "income"): "cat.n.income.other",
    ("Transfer", "income"): "cat.n.income.transfer",
    ("Dana Darurat", "income"): "cat.n.income.emergency",
    ("Hasil Investasi", "income"): "cat.n.investment",
}


def normalize_locale(raw: str | None) -> str:
    if not raw:
        return DEFAULT_LOCALE
    low = raw.strip().lower().replace("_", "-")
    if low in ("en", "en-us", "en-gb"):
        return "en-US"
    if low in ("id", "id-id", "in", "in-id"):
        return "id-ID"
    if raw in SUPPORTED_LOCALES:
        return raw
    return DEFAULT_LOCALE


def copy_catalog(locale: str) -> dict[str, str]:
    from app.core.ui_copy_en import COPY_EN
    from app.core.ui_seed import COPY_ID

    loc = normalize_locale(locale)
    if loc == "en-US":
        return {**COPY_ID, **COPY_EN}
    return dict(COPY_ID)


def locale_from_request(headers) -> str:
    raw = headers.get("x-locale") or ""
    if not raw:
        accept = headers.get("accept-language") or headers.get("Accept-Language") or ""
        raw = accept.split(",")[0].split(";")[0]
    return normalize_locale(raw)


# Indonesian live details → copy key (old APKs still send no X-Locale)
DETAIL_TO_KEY: dict[str, str] = {
    "Ada yang gak beres. Coba lagi ya.": "err.generic",
    "Data gak valid. Cek isian kamu ya.": "err.validation",
    "Gak ada internet. Cek koneksi, coba lagi.": "err.network",
    "Sesi habis. Masuk lagi ya.": "err.session",
    "Kebanyakan request. Tunggu sebentar ya.": "err.rate_limit",
    "Kebanyakan request. Tunggu sebentar, coba lagi.": "err.rate_limit",
    "Username atau password salah": "err.credentials",
}


def error_body(locale: str, detail: str) -> dict:
    if not isinstance(detail, str):
        return {"detail": str(detail)}
    key = DETAIL_TO_KEY.get(detail, "")
    if not key and "." in detail and detail in copy_catalog("id-ID"):
        key = detail
    if not key:
        return {"detail": detail}
    text = copy_catalog(locale).get(key, detail)
    return {"detail": text, "code": key}


def cache_key(locale: str) -> str:
    return f"ui:bootstrap:{normalize_locale(locale)}"


async def bust_bootstrap_cache() -> None:
    try:
        redis = await get_redis()
        for loc in SUPPORTED_LOCALES:
            await redis.delete(cache_key(loc))
    except Exception:
        pass
