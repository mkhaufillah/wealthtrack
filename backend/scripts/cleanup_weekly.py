#!/usr/bin/env python3
"""
WealthTrack Weekly Cleanup Script

Cleans up old data:
  1. OCR image files older than 7 days in ~/ocr_images/
  2. OCR job history older than 7 days (excluding jobs referenced by transactions)
  3. AI chat messages older than 30 days
  4. Docker dangling images/containers (from CI test services)

Usage:
    python cleanup_weekly.py          # Dry-run: SELECT only, no DELETE
    python cleanup_weekly.py --run    # Actual cleanup
"""

import asyncio
import os
import sys
import argparse
from datetime import datetime, timezone, timedelta
from pathlib import Path


def load_env():
    """Load DATABASE_URL from backend/.env or ~/.hermes/.env (fallback)."""
    env_paths = [
        Path(os.path.expanduser("~/dev/wealthtrack/backend/.env")),
        Path(os.path.expanduser("~/.hermes/.env")),
    ]
    for env_path in env_paths:
        if env_path.exists():
            try:
                with open(env_path) as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("DATABASE_URL="):
                            return line.split("=", 1)[1]
            except (OSError, IOError) as e:
                print(f"⚠  Could not read {env_path}: {e}")
                continue
    return None


def cleanup_ocr_files(ocr_dir: Path, dry_run: bool):
    """Delete OCR image files older than 7 days."""
    print("── OCR Image Files ──")

    if not ocr_dir.exists():
        print(f"⚠  Folder does not exist: {ocr_dir}")
        print()
        return

    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    deleted = 0
    errors = 0

    try:
        items = list(ocr_dir.iterdir())
    except (OSError, PermissionError) as e:
        print(f"⚠  Cannot read folder {ocr_dir}: {e}")
        print()
        return

    for f in items:
        if not f.is_file():
            continue
        try:
            mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
            if mtime < cutoff:
                if dry_run:
                    print(f"  [DRY-RUN] Would delete: {f.name}  (mtime: {mtime.strftime('%Y-%m-%d')})")
                else:
                    f.unlink()
                    print(f"  Deleted: {f.name}")
                deleted += 1
        except Exception as e:
            print(f"  ⚠  Error processing {f.name}: {e}")
            errors += 1

    action = "Would delete" if dry_run else "Deleted"
    print(f"  {action} {deleted} file(s). Errors: {errors}")
    print()


async def cleanup_ocr_jobs(conn, dry_run: bool):
    """Delete old OCR jobs (older than 7 days) that have no transaction reference."""
    print("── OCR Jobs History ──")

    # Check if table exists
    table_exists = await conn.fetchval(
        "SELECT EXISTS ("
        "  SELECT FROM information_schema.tables "
        "  WHERE table_schema='public' AND table_name='ocr_jobs'"
        ")"
    )
    if not table_exists:
        print("⚠  Table 'ocr_jobs' does not exist. Skipping.")
        print()
        return

    # Count deletable rows (older than 7 days AND no transaction reference)
    total_deletable = await conn.fetchval(
        "SELECT count(*) FROM ocr_jobs "
        "WHERE created_at::timestamp < now() - interval '7 days' "
        "  AND transaction_id IS NULL"
    )

    # Count old rows that are kept (have transaction_id → still referenced)
    kept_with_ref = await conn.fetchval(
        "SELECT count(*) FROM ocr_jobs "
        "WHERE created_at::timestamp < now() - interval '7 days' "
        "  AND transaction_id IS NOT NULL"
    )

    print(f"  Old OCR jobs deletable (no transaction ref): {total_deletable}")
    print(f"  Old OCR jobs kept (have transaction_id):     {kept_with_ref}")

    if dry_run:
        rows = await conn.fetch(
            "SELECT id, image_filename, created_at FROM ocr_jobs "
            "WHERE created_at::timestamp < now() - interval '7 days' "
            "  AND transaction_id IS NULL "
            "ORDER BY created_at"
        )
        for r in rows:
            print(f"  [DRY-RUN] Would delete: id={r['id']}, "
                  f"file={r['image_filename']}, created={r['created_at']}")
        print(f"  Would delete {total_deletable} OCR job(s).")
    else:
        if total_deletable > 0:
            await conn.execute(
                "DELETE FROM ocr_jobs "
                "WHERE created_at::timestamp < now() - interval '7 days' "
                "  AND transaction_id IS NULL"
            )
            print(f"  Deleted {total_deletable} OCR job(s).")
        else:
            print("  No OCR jobs to delete.")

    print()


async def cleanup_ai_messages(conn, dry_run: bool):
    """Delete AI chat messages older than 30 days."""
    print("── AI Chat History ──")

    # Determine which table exists (ai_chat_messages or ai_messages)
    table_name = None
    for tbl in ["ai_chat_messages", "ai_messages"]:
        exists = await conn.fetchval(
            "SELECT EXISTS ("
            "  SELECT FROM information_schema.tables "
            "  WHERE table_schema='public' AND table_name=$1"
            ")",
            tbl,
        )
        if exists:
            table_name = tbl
            break

    if not table_name:
        print("⚠  No AI messages table found (checked ai_chat_messages, ai_messages). Skipping.")
        print()
        return

    print(f"  Using table: {table_name}")

    total_deletable = await conn.fetchval(
        f"SELECT count(*) FROM {table_name} "
        f"WHERE created_at::timestamp < now() - interval '30 days'"
    )

    print(f"  Old AI messages (>30 days): {total_deletable}")

    if dry_run:
        rows = await conn.fetch(
            f"SELECT id, role, left(created_at, 19) AS created_at "
            f"FROM {table_name} "
            f"WHERE created_at::timestamp < now() - interval '30 days' "
            f"ORDER BY created_at "
            f"LIMIT 20"
        )
        for r in rows:
            print(f"  [DRY-RUN] Would delete: id={r['id']}, "
                  f"role={r['role']}, created={r['created_at']}")
        if total_deletable > 20:
            print(f"  ... (showing first 20 of {total_deletable})")
        print(f"  Would delete {total_deletable} message(s).")
    else:
        if total_deletable > 0:
            await conn.execute(
                f"DELETE FROM {table_name} "
                f"WHERE created_at::timestamp < now() - interval '30 days'"
            )
            print(f"  Deleted {total_deletable} message(s).")
        else:
            print("  No AI messages to delete.")

    print()


async def main():
    parser = argparse.ArgumentParser(description="WealthTrack Weekly Cleanup")
    parser.add_argument(
        "--run",
        action="store_true",
        help="Actually run deletions (default: dry-run mode with SELECT only)",
    )
    args = parser.parse_args()

    dry_run = not args.run

    # ── Load database URL ──
    database_url = load_env()
    if not database_url:
        print("ERROR: DATABASE_URL not found in any .env file.")
        print("Checked: ~/dev/wealthtrack/backend/.env, ~/.hermes/.env")
        sys.exit(1)

    # Print a sanitised version of the URL (mask password)
    safe_url = database_url
    if "@" in database_url:
        user_part, host_part = database_url.split("@", 1)
        if ":" in user_part:
            scheme_user = user_part.rsplit(":", 1)[0]
            safe_url = f"{scheme_user}:****@{host_part}"
    print(f"Weekly Cleanup Script — {'❚ DRY RUN ❚' if dry_run else '⚠ LIVE RUN ⚠'}")
    print(f"  Database: {safe_url}")
    print(f"  Time:     {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print()

    # ── 1. Clean OCR image files ──
    ocr_dir = Path(os.path.expanduser("~/ocr_images"))
    cleanup_ocr_files(ocr_dir, dry_run)

    # ── 2. Clean database ──
    try:
        import asyncpg  # noqa: F811
    except ImportError:
        print("ERROR: 'asyncpg' is not installed. Install with:")
        print("       pip install asyncpg")
        sys.exit(1)

    try:
        conn = await asyncpg.connect(database_url)
        print("✅  Connected to PostgreSQL")
        print()

        try:
            await cleanup_ocr_jobs(conn, dry_run)
            await cleanup_ai_messages(conn, dry_run)
        finally:
            await conn.close()
    except Exception as e:
        print(f"❌  Database error: {e}")
        sys.exit(1)


    # ── 4. Docker cleanup ──
    print("── Docker Cleanup ──")
    rc = os.system("docker system prune -f --filter 'until=24h' 2>/dev/null")
    if rc == 0:
        print("  ✅ Docker dangling images/containers pruned.")
    else:
        print("  ⚠  Docker cleanup skipped (Docker not available or error).")
    print()
    print("─" * 40)
    if dry_run:
        print("✅  Dry-run complete. No data was modified.")
        print("    Run with --run to perform actual cleanup.")
    else:
        print("✅  Cleanup complete.")


if __name__ == "__main__":
    asyncio.run(main())
