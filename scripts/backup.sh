#!/bin/bash
# WealthTrack SQLite Backup
# Scheduled via cron: 0 2 * * * ~/dev/wealthtrack/scripts/backup.sh

BACKUP_DIR=~/wealthtrack-backups
mkdir -p "$BACKUP_DIR"
cp ~/.keuangan/finance.db "$BACKUP_DIR/finance-$(date +%Y%m%d-%H%M%S).db"
# Keep last 30 days
ls -t "$BACKUP_DIR"/*.db 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null
echo "Backup done: $(ls -lh "$BACKUP_DIR"/*.db 2>/dev/null | tail -1)"
