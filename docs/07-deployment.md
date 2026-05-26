# Deployment — VPS Production Setup

## Architecture on VPS

```
┌──────────────────────────────────────────────────┐
│  VPS (Ubuntu 22.04)                              │
│                                                   │
│  ┌────────────────────┐                           │
│  │  Hermes Agent      │  (runs as user: filla)    │
│  │  ~/.hermes/        │                           │
│  │  ├── scripts/      │                           │
│  │  │   ├── daily_*   │                           │
│  │  │   └── add_txn*  │                           │
│  │  └── data/         │                           │
│  │       └── wealth.  │                           │
│  │           track.db  │◄──── SQLite file         │
│  └────────────────────┘          ▲                │
│                                  │                │
│  ┌────────────────────┐          │                │
│  │  FastAPI (systemd) │──────────┘                │
│  │  port 8080         │                           │
│  └────────────────────┘                           │
│         │                                         │
│  ┌──────┴───────┐                                 │
│  │  nginx       │  (reverse proxy, HTTPS, P4)     │
│  │  port 443    │                                 │
│  └──────────────┘                                 │
└──────────────────────────────────────────────────┘
```

## Step 1: Systemd Service for FastAPI

Create `/etc/systemd/system/wealthtrack.service`:

```ini
[Unit]
Description=WealthTrack API
After=network.target

[Service]
Type=simple
User=filla
WorkingDirectory=/home/filla/dev/wealthtrack
Environment=PATH=/home/filla/dev/wealthtrack/.venv/bin
ExecStart=/home/filla/dev/wealthtrack/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8080
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable wealthtrack
sudo systemctl start wealthtrack
sudo systemctl status wealthtrack
```

## Step 2: Firewall

```bash
sudo ufw allow ssh
sudo ufw allow 8080/tcp
sudo ufw enable
```

## Step 3: Verify Service

```bash
# Check logs
journalctl -u wealthtrack -f

# Test API
curl http://localhost:8080/api/v1/auth/login \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"username": "filla", "password": "password123"}'

# Test from phone (replace with VPS IP)
curl http://<VPS_IP>:8080/api/v1/auth/login \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"username": "filla", "password": "password123"}'
```

## Step 4: Auto-Start on Boot

```bash
sudo systemctl enable wealthtrack
```

The service auto-restarts on crash (Restart=on-failure) and starts on boot.

## Step 5: Backup Strategy (P4, but recommended)

### SQLite Backup Script

```bash
#!/bin/bash
# ~/dev/wealthtrack/scripts/backup.sh
BACKUP_DIR=~/wealthtrack-backups
mkdir -p $BACKUP_DIR
cp ~/.hermes/data/wealthtrack.db $BACKUP_DIR/wealthtrack-$(date +%Y%m%d-%H%M%S).db
# Keep last 30 days
ls -t $BACKUP_DIR/*.db | tail -n +31 | xargs rm -f 2>/dev/null
```

Cron: daily backup

```bash
0 2 * * * ~/dev/wealthtrack/scripts/backup.sh
```

### Restore
```bash
# Stop service, copy backup, restart
sudo systemctl stop wealthtrack
cp ~/wealthtrack-backups/wealthtrack-20260526.db ~/.hermes/data/wealthtrack.db
sudo systemctl start wealthtrack
```

## Step 6: HTTPS — For Production (P4)

When you want to expose the API publicly (for Flutter app from outside your LAN):

```nginx
# /etc/nginx/sites-available/wealthtrack
server {
    listen 443 ssl;
    server_name wealthtrack.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/wealthtrack.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/wealthtrack.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

server {
    listen 80;
    server_name wealthtrack.yourdomain.com;
    return 301 https://$server_name$request_uri;
}
```

```bash
sudo apt install nginx certbot python3-certbot-nginx
sudo certbot --nginx -d wealthtrack.yourdomain.com
```

## Step 7: Monitoring Health

Simple health check endpoint (already in FastAPI):

```bash
# Every 5 minutes, log uptime
*/5 * * * * curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/docs | logger -t wealthtrack-health
```

Or use the built-in systemd health checks:

```bash
systemctl is-active wealthtrack
```

## P1 Deployment Checklist

- [x] FastAPI service created
- [x] Systemd unit configured
- [x] Service auto-starts on boot
- [x] Firewall allows port 8080
- [x] Seed data created (default users + categories)
- [ ] Test login from Swagger UI
- [ ] Test login from Flutter (once built)
- [ ] Test Hermes cron (update existing cron)
- [ ] Verify DB file exists at ~/.hermes/data/wealthtrack.db
