"""Parse Indonesian bank-app push notifications into draft fields.

Allow-list only. No credentials. Amounts in rupiah integer.
"""
from __future__ import annotations

import hashlib
import re

# Play package → slug. User-supplied allow-list is the source of truth.
BANK_PACKAGES: dict[str, str] = {
    "com.bca": "bca",
    "id.bmri.livin": "mandiri",
    "id.co.bri.brimo": "bri",
    "com.jago.digitalBanking": "jago",
    "id.co.bankfama.android": "superbank",
    "com.krom.android": "krom",
    "id.co.btn.mobilebanking.android": "btn",
    "id.co.bankbkemobile.digitalbank": "seabank",
    "com.bibit.bibitid": "bibit",
    "com.stockbit.android": "stockbit",
    "com.telkom.mwallet": "linkaja",
    "id.flip": "flip",
    "ovo.id": "ovo",
    "com.gojek.gopay": "gopay",
    "id.dana": "dana",
    "com.shopeepay.id": "shopeepay",
}

INCOME_HINTS = (
    "transfer masuk",
    "dana masuk",
    "uang masuk",
    "diterima",
    "terima dari",
    "masuk dari",
    "kredit rp",
    "kredit idr",
    "top up",
    "topup",
    "top-up",
    "gaji",
    "refund",
    "pengembalian",
    "kamu terima",
    "dapat transfer",
)
EXPENSE_HINTS = (
    "debit",
    "keluar",
    "dibayar",
    "transfer ke",
    "transfer keluar",
    "pindahin ke",
    "pemindahan uang",
    "bayar ke",
    "qris",
    "pembelian",
    "pembayaran",
    "belanja",
    "tarik",
    "atm",
    "purchase",
)

# Keep in sync with BankCapture.parseAmount (Dart) and AmountDetect (Kotlin).
# Gate HP = server: has_amount == parse_amount is not None.
_CURRENCY_BEFORE = re.compile(
    r"(?:rp\.?|idr|rupiah|usd|us\$|\$)\s*([0-9][0-9.\s,]*)",
    re.IGNORECASE,
)
_CURRENCY_AFTER = re.compile(
    r"([0-9][0-9.\s,]*)\s*(?:rp\.?|idr|rupiah|usd|us\$|\$)",
    re.IGNORECASE,
)
_CONTEXT_AMOUNT = re.compile(
    r"(?:debit|kredit|nominal|sebesar|amount|paid|received|transfer|qris|"
    r"bayar|pembelian|pembayaran)\s*:?\s*([0-9][0-9.\s,]*)",
    re.IGNORECASE,
)
_BARE_GROUPED_RE = re.compile(
    r"(?<![0-9.])([1-9][0-9]{0,2}(?:[.,\s][0-9]{3}){1,4})(?![0-9])"
)
_AMOUNT_STRIP = re.compile(
    r"(?:rp\.?|idr|rupiah|usd|us\$|\$)\s*[0-9][0-9.\s,]*|"
    r"[0-9][0-9.\s,]*\s*(?:rp\.?|idr|rupiah|usd)",
    re.IGNORECASE,
)


def bank_for_package(package: str) -> str | None:
    pkg = (package or "").strip()
    if not pkg:
        return None
    known = BANK_PACKAGES.get(pkg)
    if known:
        return known
    slug = pkg.rsplit(".", 1)[-1]
    slug = re.sub(r"[^a-zA-Z0-9_]+", "", slug).lower()[:40]
    return slug or "other"


def _normalize_number(raw: str) -> int | None:
    s = (raw or "").replace("\u00a0", " ").strip()
    s = re.sub(r",-+$", "", s)
    s = s.replace(" ", "")
    if not s or not re.search(r"\d", s):
        return None
    if s[0] == "0":
        return None
    if "," in s and "." in s:
        if s.rfind(",") > s.rfind("."):
            s = s.split(",")[0].replace(".", "")
        else:
            s = s.split(".")[0].replace(",", "")
    elif "," in s:
        parts = s.split(",")
        if len(parts) == 2 and 1 <= len(parts[1]) <= 2:
            s = parts[0]
        else:
            s = s.replace(",", "")
    elif "." in s:
        parts = s.split(".")
        if len(parts) == 2 and 1 <= len(parts[1]) <= 2:
            s = parts[0]
        else:
            s = s.replace(".", "")
    if not s.isdigit():
        return None
    value = int(s)
    if value <= 0 or value > 10_000_000_000:
        return None
    return value


def _first_amount(text: str, pattern: re.Pattern[str]) -> int | None:
    for match in pattern.finditer(text or ""):
        end = match.end()
        if end < len(text) and text[end] == "%":
            continue
        value = _normalize_number(match.group(1))
        if value is not None:
            return value
    return None


def parse_amount(blob: str) -> int | None:
    text = blob or ""
    for pattern in (_CURRENCY_BEFORE, _CURRENCY_AFTER, _CONTEXT_AMOUNT, _BARE_GROUPED_RE):
        value = _first_amount(text, pattern)
        if value is not None:
            return value
    return None


def has_amount(blob: str) -> bool:
    return parse_amount(blob) is not None


def _hint_hit(hay: str, phrase: str) -> bool:
    if len(phrase) < 2:
        return False
    pat = r"(?<![a-z0-9])" + re.escape(phrase) + r"(?![a-z0-9])"
    return re.search(pat, hay) is not None


def parse_type(blob: str) -> str:
    lower = (blob or "").lower()
    expense_hit = any(_hint_hit(lower, h) for h in EXPENSE_HINTS)
    if expense_hit:
        return "expense"
    if re.search(r"(?<![a-z0-9])kredit\s*(rp|idr)", lower) and "kartu kredit" not in lower:
        return "income"
    income_hit = any(_hint_hit(lower, h) for h in INCOME_HINTS)
    if income_hit:
        return "income"
    return "expense"


def parse_merchant(blob: str) -> str:
    text = re.sub(r"\s+", " ", blob or "").strip()
    text = _AMOUNT_STRIP.sub(" ", text)
    text = re.sub(r"\b(?:rp\.?|idr|rupiah|usd)\b", " ", text, flags=re.IGNORECASE)
    text = text.replace("$", " ")
    lower = text.lower()
    for marker in (" ke ", " di ", " dari ", " kepada "):
        idx = lower.find(marker)
        if idx >= 0:
            rest = text[idx + len(marker) :].strip(" -·|,")
            rest = re.sub(r"\s+", " ", rest).strip()
            if rest:
                return rest[:120]
    cleaned = re.sub(r"\s+", " ", text).strip(" -·|,")
    return cleaned[:120]


def fingerprint(package: str, posted_at: str, amount: int | None, blob: str) -> str:
    day = (posted_at or "")[:10]
    norm = re.sub(r"\s+", " ", (blob or "").lower()).strip()
    raw = f"{package}|{day}|{amount or 0}|{norm}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def parse_notification(package: str, title: str, text: str) -> dict:
    """Return parsed fields. ``bank`` is None when package is not allow-listed."""
    bank = bank_for_package(package)
    blob = f"{title or ''} {text or ''}".strip()
    amount = parse_amount(blob)
    return {
        "bank": bank,
        "amount": amount,
        "type": parse_type(blob),
        "merchant": parse_merchant(blob),
        "parsed": amount is not None,
    }
