# Backup & Restore

## Backup
Auto daily at 03:00 AM via cronjob.
Manual: `bash backend/scripts/pg_backup.sh`

## Restore
```bash
pg_restore --format=custom --dbname=postgresql://wealthtrack:wealthtrack123@localhost:5432/wealthtrack \
  /home/hermes/backups/wealthtrack/wealthtrack_20260606_030000.dump
```

## Retention
Backups kept for 7 days. Older ones auto-deleted.
