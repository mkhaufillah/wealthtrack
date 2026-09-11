"""Vault-aware SQL helpers. Never log DEK."""

from __future__ import annotations

from app.core.vault import category_trace
from app.core.vault_ctx import current_dek


def parse_cat_ids(category_id=None, category_ids=None) -> list[int]:
    ids: list[int] = []
    if category_ids:
        ids = [int(x.strip()) for x in str(category_ids).split(",") if x.strip().isdigit()]
    elif category_id is not None and str(category_id).strip() != "":
        ids = [int(category_id)]
    return ids


def append_category_filter(
    where: list[str],
    params: list,
    category_id=None,
    category_ids=None,
) -> None:
    ids = parse_cat_ids(category_id, category_ids)
    if not ids:
        return
    dek = current_dek()
    if dek is None:
        return
    traces = [category_trace(dek, i) for i in ids]
    ph = ",".join("?" * len(traces))
    where.append(f"t.category_trace IN ({ph})")
    params.extend(traces)
