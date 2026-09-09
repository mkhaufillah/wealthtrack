"""Suggest category and pair own-account transfer drafts."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Optional


def _parse_ts(raw: str) -> Optional[datetime]:
    text = (raw or "").strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def suggest_category_id(
    categories: list[dict],
    blob: str,
    txn_type: str,
) -> Optional[int]:
    hay = (blob or "").lower()
    if not hay:
        return None
    for cat in categories:
        if cat.get("type") != txn_type:
            continue
        raw_kw = cat.get("keywords") or "[]"
        if isinstance(raw_kw, str):
            try:
                kws = json.loads(raw_kw)
            except json.JSONDecodeError:
                kws = []
        else:
            kws = raw_kw
        for kw in kws:
            token = str(kw).strip().lower()
            if len(token) >= 2 and token in hay:
                return int(cat["id"])
    return None


def find_pair(pending: list[dict], item: dict) -> Optional[int]:
    amount = item.get("amount")
    ttype = item.get("txn_type") or item.get("type")
    bank = item.get("bank")
    if not amount or ttype not in ("expense", "income") or not bank:
        return None
    want = "income" if ttype == "expense" else "expense"
    self_id = item.get("id")
    self_ts = _parse_ts(item.get("posted_at") or "")
    best_id = None
    best_delta = None
    for other in pending:
        if other.get("id") == self_id:
            continue
        if other.get("status") and other.get("status") != "pending":
            continue
        if other.get("amount") != amount:
            continue
        otype = other.get("txn_type") or other.get("type")
        if otype != want:
            continue
        if not other.get("bank") or other.get("bank") == bank:
            continue
        ots = _parse_ts(other.get("posted_at") or "")
        if self_ts and ots:
            delta = abs((self_ts - ots).total_seconds())
            if delta > 72 * 3600:
                continue
        else:
            delta = 10**9
        if best_delta is None or delta < best_delta:
            best_delta = delta
            best_id = int(other["id"])
    return best_id


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
