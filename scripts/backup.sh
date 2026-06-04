#!/bin/bash
# WealthTrack Backup — PostgreSQL + legacy SQLite
# Scheduled via cron: 0 2 * * * ~/dev/wealthtrack/scripts/backup.sh

BACKUP_DIR=~/wealthtrack-backups
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# PostgreSQL backup
export PGPASSWORD=$(grep DATABASE_URL ~/dev/wealthtrack/backend/.env | sed 's/.*:\/\///' | sed 's/@.*//' | sed 's/.*://')
DB_NAME=wealthtrack
pg_dump -U wealthtrack -d $DB_NAME > "$BACKUP_DIR/wealthtrack-$TIMESTAMP.sql" 2>/dev/null

# Legacy SQLite backup (if exists)
if [ -f ~/.keuangan/finance.db ]; then
    cp ~/.keuangan/finance.db "$BACKUP_DIR/finance-$TIMESTAMP.db"
fi

# Keep last 30 backups
ls -t "$BACKUP_DIR"/*.sql 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null
ls -t "$BACKUP_DIR"/*.db 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null
echo "Backup done: $BACKUP_DIR"
