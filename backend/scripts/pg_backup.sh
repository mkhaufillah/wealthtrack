#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/home/hermes/backups/wealthtrack}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Source project .env untuk mendapatkan DATABASE_URL asli
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
if [ -f "$ENV_FILE" ]; then
  DB_URL="$(grep -oP '^DATABASE_URL=\K.*' "$ENV_FILE" | head -1)"
fi

# Override dengan env var jika diset (prioritas lebih tinggi)
DB_URL="${WEALTHTRACK_DATABASE_URL:-${DB_URL:-}}"
if [ -z "$DB_URL" ]; then
  echo "ERROR: WEALTHTRACK_DATABASE_URL atau DATABASE_URL tidak ditemukan"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

# Extract connection parts from URL
DB_USER=$(echo "$DB_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')
DB_PASS=$(echo "$DB_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
DB_HOST=$(echo "$DB_URL" | sed -n 's|.*@\([^:]*\):.*|\1|p')
DB_PORT=$(echo "$DB_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
DB_NAME=$(echo "$DB_URL" | sed -n 's|.*/\([^?]*\)|\1|p')

export PGPASSWORD="$DB_PASS"

pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  --format=custom \
  --compress=9 \
  --file="$BACKUP_DIR/wealthtrack_$TIMESTAMP.dump"

# Remove backups older than RETENTION_DAYS
find "$BACKUP_DIR" -name "wealthtrack_*.dump" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $BACKUP_DIR/wealthtrack_$TIMESTAMP.dump"
