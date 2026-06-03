"""
Meilisearch client wrapper for WealthTrack.

Provides:
- init_meilisearch / close_meilisearch — lifecycle hooks
- index_document / delete_document — CRUD indexing
- search_descriptions — full-text search → returns [transaction_id, ...]
"""

import functools
from typing import Optional

import meilisearch
from meilisearch.index import Index

from app.core.config import settings

_client: Optional[meilisearch.Client] = None
_index: Optional[Index] = None

INDEX_NAME = "transactions"
SEARCHABLE_ATTRIBUTES = ["description"]
FILTERABLE_ATTRIBUTES = ["user_id", "type", "category_id", "date"]
SORTABLE_ATTRIBUTES = ["date", "amount"]


async def init_meilisearch():
    """Create the client and ensure the index exists with proper settings."""
    global _client, _index

    url = settings.MEILISEARCH_URL
    key = settings.MEILISEARCH_MASTER_KEY

    _client = meilisearch.Client(url, key)

    # Create index if not exists
    try:
        _client.create_index(INDEX_NAME, {"primaryKey": "id"})
    except meilisearch.errors.MeilisearchApiError:
        pass  # already exists

    _index = _client.index(INDEX_NAME)

    # Update index settings — these are idempotent
    _client.index(INDEX_NAME).update_searchable_attributes(SEARCHABLE_ATTRIBUTES)
    _client.index(INDEX_NAME).update_filterable_attributes(FILTERABLE_ATTRIBUTES)
    _client.index(INDEX_NAME).update_sortable_attributes(SORTABLE_ATTRIBUTES)


def close_meilisearch():
    global _client, _index
    _client = None
    _index = None


def get_index() -> Index:
    if _index is None:
        raise RuntimeError("Meilisearch not initialised — call init_meilisearch() first")
    return _index


# ── Document CRUD (run in thread pool from async handlers) ──


def _index_document_sync(txn: dict) -> None:
    """Index a single transaction document into Meilisearch.

    ``txn`` must contain at minimum:
      id, description, type, amount, category_id, user_id, date
    """
    doc = {
        "id": txn["id"],
        "description": txn.get("description", "") or "",
        "type": txn["type"],
        "amount": int(txn["amount"]),
        "category_id": int(txn["category_id"]),
        "user_id": int(txn["user_id"]),
        "date": txn.get("date") or "",
    }
    get_index().add_documents([doc])


def _delete_document_sync(txn_id: int) -> None:
    """Remove a transaction document from Meilisearch."""
    get_index().delete_document(txn_id)


def _search_sync(q: str, filters: Optional[list[str]] = None,
                 sort: Optional[list[str]] = None,
                 offset: int = 0, limit: int = 50) -> dict:
    """Search transactions and return full Meilisearch response."""
    return get_index().search(q, {
        "filter": filters,
        "sort": sort,
        "offset": offset,
        "limit": limit,
        "attributesToRetrieve": ["id"],
    })


# ── Async wrappers (to be called from FastAPI route handlers) ──

async def index_document(txn: dict) -> None:
    """Index (create/update) a transaction document into Meilisearch."""
    import anyio
    await anyio.to_thread.run_sync(_index_document_sync, txn)


async def delete_document(txn_id: int) -> None:
    """Remove a transaction from Meilisearch."""
    import anyio
    await anyio.to_thread.run_sync(_delete_document_sync, txn_id)


async def search_descriptions(
    q: str,
    filters: Optional[list[str]] = None,
    sort: Optional[list[str]] = None,
    offset: int = 0,
    limit: int = 50,
) -> list[int]:
    """Search transactions by description, return matching transaction IDs."""
    import anyio
    result = await anyio.to_thread.run_sync(
        _search_sync, q, filters, sort, offset, limit
    )
    return [hit["id"] for hit in result.get("hits", [])]


async def get_total_count(q: str, filters: Optional[list[str]] = None) -> int:
    """Get total number of matching documents (for pagination)."""
    import anyio
    result = await anyio.to_thread.run_sync(
        _search_sync, q, filters, None, 0, 0
    )
    return result.get("estimatedTotalHits", 0) or result.get("totalHits", 0)


# ── Bulk index helper (sync, for scripts) ──

def bulk_index_documents(docs: list[dict]) -> None:
    """Index multiple documents at once (sync, for migration scripts)."""
    get_index().add_documents(docs)


def clear_index() -> None:
    """Delete all documents from the index (for re-indexing)."""
    get_index().delete_all_documents()
