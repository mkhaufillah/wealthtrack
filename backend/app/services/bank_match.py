"""Suggest category for bank drafts."""
from __future__ import annotations

import json
import re
from datetime import UTC, datetime


def _keyword_hit(hay: str, token: str) -> bool:
    """Whole-token match so 'erha' does not hit 'berhasil'."""
    if len(token) < 2:
        return False
    pat = r"(?<![a-z0-9])" + re.escape(token) + r"(?![a-z0-9])"
    return re.search(pat, hay) is not None


def suggest_category_id(
    categories: list[dict],
    blob: str,
    txn_type: str,
) -> int | None:
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
            if _keyword_hit(hay, token):
                return int(cat["id"])
    return None


def utcnow() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z")
