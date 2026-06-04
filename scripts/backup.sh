#!/bin/bash
# WealthTrack Backup — PostgreSQL
# Scheduled via cron: 0 2 * * * ~/dev/wealthtrack/scripts/backup.sh

BACKUP_DIR=~/wealthtrack-backups
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# PostgreSQL backup
pg_dump -U wealthtrack -d wealthtrack > "$BACKUP_DIR/wealthtrack-$TIMESTAMP.sql" 2>/dev/null

# Keep last 30 backups
ls -t "$BACKUP_DIR"/*.sql 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null
echo "Backup done: $BACKUP_DIR/wealthtrack-$TIMESTAMP.sql"
