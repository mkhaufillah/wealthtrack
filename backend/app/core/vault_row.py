"""Pack/unpack money rows. JSON blob AES + OPE + category trace."""

from __future__ import annotations

import json
from decimal import Decimal

from app.core.vault import (
    aes_decrypt,
    aes_encrypt,
    category_trace,
    is_aes_token,
    ope_decode,
    ope_encode,
)


def pack_money(
    dek: bytes,
    *,
    amount: int,
    description: str = "",
    note: str = "",
    category_id: int | None = None,
    category_name: str = "",
    extra: dict | None = None,
) -> dict:
    payload = {
        "amount": int(amount),
        "description": description or "",
        "note": note or "",
        "category_id": category_id,
        "category_name": category_name or "",
    }
    if extra:
        payload.update(extra)
    def _jsonable(v):
        if isinstance(v, Decimal):
            return float(v)
        return v

    payload = {k: _jsonable(v) for k, v in payload.items()}
    blob = aes_encrypt(dek, json.dumps(payload, separators=(",", ":"), ensure_ascii=False))
    ope_amt = int(amount)
    if ope_amt < 0:
        ope_amt = 0
    out = {
        "vault_blob": blob,
        "amount_ord": ope_encode(dek, ope_amt),
        "amount": 0,
        "description": "",
        "note": "",
        "category_name": "",
    }
    if category_id is not None:
        out["category_trace"] = category_trace(dek, int(category_id))
        out["category_id"] = None
    return out


def open_row(row: dict) -> dict:
    from app.core.vault_ctx import current_dek

    return unpack_money(current_dek(), dict(row))


def unpack_money(dek: bytes | None, row: dict) -> dict:
    data = dict(row)
    blob = data.get("vault_blob") or ""
    if dek and blob and is_aes_token(str(blob)):
        inner = json.loads(aes_decrypt(dek, str(blob)))
        for k, v in inner.items():
            if k == "vault_blob":
                continue
            data[k] = v
        data["amount"] = int(data.get("amount") or 0)
        data["description"] = data.get("description") or ""
        data["note"] = data.get("note") or ""
    return data


def ope_sum_to_plain(dek: bytes, sum_ord: int, count: int) -> int:
    if count <= 0:
        return 0
    # sum(a_i + off) = sum(a) + n*off
    from app.core.vault import ope_offset

    return int(sum_ord) - int(count) * ope_offset(dek)
