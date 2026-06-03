"""
Bulk index all existing transactions into Meilisearch.

Usage:
    python -m scripts.bulk_index_meilisearch

This is a one-shot script. It reads all transactions from PostgreSQL
and pushes them to the Meilisearch index. Existing documents are
overwritten (idempotent). Run this after deploying the Meilisearch
integration to backfill historical data.
"""

import sys
import os

# Ensure the backend package is importable
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import psycopg2
import psycopg2.extras
from app.core.config import settings
from app.core.meilisearch import clear_index, bulk_index_documents, Index


def main():
    print(f"Connecting to PostgreSQL: {settings.DATABASE_URL.split('@')[0].split(':')[0]+':****@'+settings.DATABASE_URL.split('@')[1] if '@' in settings.DATABASE_URL else settings.DATABASE_URL}")
    conn = psycopg2.connect(settings.DATABASE_URL)
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute(
        """SELECT id, description, type, amount, category_id, user_id,
                  COALESCE(date, LEFT(created_at::text, 10)) as date
           FROM transactions
           ORDER BY id"""
    )
    rows = cur.fetchall()
    cur.close()
    conn.close()

    if not rows:
        print("No transactions found. Nothing to index.")
        return

    total = len(rows)
    print(f"Found {total} transactions. Indexing into Meilisearch...")

    # Connect to Meilisearch
    from app.core.meilisearch import INDEX_NAME
    import meilisearch
    client = meilisearch.Client(settings.MEILISEARCH_URL, settings.MEILISEARCH_MASTER_KEY)

    # Create/ensure index with correct settings
    client.create_index(INDEX_NAME, {"primaryKey": "id"})
    client.index(INDEX_NAME).update_searchable_attributes(["description"])
    client.index(INDEX_NAME).update_filterable_attributes(
        ["user_id", "type", "category_id", "date"]
    )
    client.index(INDEX_NAME).update_sortable_attributes(["date", "amount"])

    # Clear existing docs
    client.index(INDEX_NAME).delete_all_documents()

    # Batch insert in chunks of 500
    BATCH_SIZE = 500
    docs = []
    for row in rows:
        docs.append({
            "id": row["id"],
            "description": row.get("description", "") or "",
            "type": row["type"],
            "amount": int(row["amount"]),
            "category_id": int(row["category_id"]),
            "user_id": int(row["user_id"]),
            "date": row.get("date") or "",
        })

        if len(docs) >= BATCH_SIZE:
            client.index(INDEX_NAME).add_documents(docs)
            print(f"  Indexed {len(docs)} documents...")
            docs = []

    # Remaining
    if docs:
        client.index(INDEX_NAME).add_documents(docs)
        print(f"  Indexed {len(docs)} documents (final batch)...")

    # Verify
    stats = client.index(INDEX_NAME).get_stats()
    print(f"\n✅ Done! Meilisearch now has {stats.number_of_documents} indexed transactions.")


if __name__ == "__main__":
    main()
