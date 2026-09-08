"""Parse Indonesian bank-app push notifications into draft fields.

Allow-list only. No credentials. Amounts in rupiah integer.
"""
from __future__ import annotations

import hashlib
import re
from typing import Optional

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
    "kredit",
    "masuk",
    "diterima",
    "terima",
    "transfer masuk",
    "dana masuk",
    "uang masuk",
    "top up",
    "topup",
    "top-up",
    "gaji",
    "refund",
    "pengembalian",
)
EXPENSE_HINTS = (
    "debit",
    "keluar",
    "dibayar",
    "transfer ke",
    "transfer keluar",
    "qris",
    "bayar",
    "pembelian",
    "pembayaran",
    "belanja",
    "tarik",
    "atm",
    "purchase",
)

_AMOUNT_RE = re.compile(
    r"(?:rp|idr)\s*([0-9]{1,3}(?:[.\s][0-9]{3})+(?:,[0-9]+)?|[0-9]+)",
    re.IGNORECASE,
)
_BARE_GROUPED_RE = re.compile(r"\b([0-9]{1,3}(?:\.[0-9]{3}){1,4})\b")


def bank_for_package(package: str) -> Optional[str]:
    return BANK_PACKAGES.get((package or "").strip())


def _to_rupiah(raw: str) -> Optional[int]:
    cleaned = raw.replace(" ", "").replace("\u00a0", "")
    if "," in cleaned and "." in cleaned:
        # 1.250.000,50 → drop sen
        cleaned = cleaned.split(",")[0].replace(".", "")
    elif "," in cleaned:
        cleaned = cleaned.split(",")[0]
    else:
        cleaned = cleaned.replace(".", "")
    if not cleaned.isdigit():
        return None
    value = int(cleaned)
    if value <= 0 or value > 10_000_000_000:
        return None
    return value


def parse_amount(blob: str) -> Optional[int]:
    text = blob or ""
    match = _AMOUNT_RE.search(text)
    if match:
        return _to_rupiah(match.group(1))
    match = _BARE_GROUPED_RE.search(text)
    if match:
        return _to_rupiah(match.group(1))
    return None


def parse_type(blob: str) -> str:
    lower = (blob or "").lower()
    income_hit = any(h in lower for h in INCOME_HINTS)
    expense_hit = any(h in lower for h in EXPENSE_HINTS)
    if income_hit and not expense_hit:
        return "income"
    return "expense"


def parse_merchant(blob: str) -> str:
    text = re.sub(r"\s+", " ", blob or "").strip()
    text = _AMOUNT_RE.sub(" ", text)
    text = re.sub(r"\b(?:rp|idr)\b", " ", text, flags=re.IGNORECASE)
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


def fingerprint(package: str, posted_at: str, amount: Optional[int], blob: str) -> str:
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
