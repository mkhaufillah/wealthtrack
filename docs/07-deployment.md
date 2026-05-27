# Deployment — VPS Production Setup

## Architecture on VPS

```
                          ┌───────────────────────────────────────────────────────────────┐
                          │              VPS (Ubuntu 22.04)                               │
                          │                                                               │
  ──► wealthtrack.filla.id ──► Nginx :80 (redirect to 443)                                │
                          |    Nginx :443 (SSL)                                           │
                          |        │                                                      │
                          |        ▼                                                      │
                          |  Reverse Proxy                                                │
                          |        │                                                      │
                          |        ▼                                                      │
                          |  FastAPI :8080 (localhost only)                               │
                          |        │                                                      │
                          |        ▼                                                      │
                          |  ┌─────────────────┐                                          │
                          |  │  ~/.keuangan/   │                                          │
                          |  │  finance.db     │◄──── Hermes cron juga baca ini           │
                          |  └─────────────────┘                                          │
                          |                                                               │
                          |  ┌─────────────────────────────────────┐                      │
                          |  │  Hermes Agent (same VPS)            │                      │
                          |  │  ├── cron: daily_finance_report.py  │──► SQLite langsung   │
                          |  │  ├── skill: financial-tracker       │──► SQLite langsung   │
                          |  │  └── chat: add_transaction.py       │──► SQLite langsung   │
                          |  └─────────────────────────────────────┘                      │
                          |  ┌─────────────────────────────────────┐                      │
                          |  │  Flutter Mobile (via internet)      │                      │
                          |  │  ──► https://wealthtrack.filla.id   │──► Nginx ──► FastAPI │
                          |  └─────────────────────────────────────┘                      │
                          |                                                               │
```

## Key Differences from Standard Setup

| Aspect | Before (old doc) | After (update) |
|-------|-------------------|-------------------|
| DB path | `~/.hermes/data/wealthtrack.db` | `~/.keuangan/finance.db` (existing) |
| FastAPI bind | `0.0.0.0:8080` | `127.0.0.1:8080` (localhost only) |
| Public exposure | Port 8080 langsung | Nginx reverse proxy via 443 |
| Domain | — | `wealthtrack.filla.id` |
| Firewall | Only 80 + 443 (8080 doesn't need to be configured — default deny) |

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
Environment=PATH=/home/filla/.local/bin:/home/filla/dev/wealthtrack/.venv/bin
ExecStart=/home/filla/dev/wealthtrack/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8080
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

## Step 2: Nginx Reverse Proxy

### Install Nginx

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
```

### Configure Virtual Host

Create `/etc/nginx/sites-available/wealthtrack`:

```nginx
server {
    listen 80;
    server_name wealthtrack.filla.id;

    # Redirect HTTP → HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name wealthtrack.filla.id;

    # SSL — will be filled by certbot later
    ssl_certificate /etc/letsencrypt/live/wealthtrack.filla.id/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/wealthtrack.filla.id/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Reverse proxy ke FastAPI
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (future use)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Static files (optional, for frontend)
    location /static/ {
        alias /home/filla/dev/wealthtrack/backend/static/;
        expires 30d;
    }
}
```

Enable site:

```bash
sudo ln -s /etc/nginx/sites-available/wealthtrack /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default  # optional: disable default site
sudo nginx -t  # test config
sudo systemctl reload nginx
```

## Step 3: SSL Certificate (Let's Encrypt)

Run **AFTER** DNS `wealthtrack.filla.id` points to the VPS IP.

```bash
sudo certbot --nginx -d wealthtrack.filla.id --non-interactive --agree-tos -m khaufillahmohammad@gmail.com
```

If DNS is not ready yet, run this later:

```bash
# Check DNS first
dig +short A wealthtrack.filla.id
# Should return VPS IP: 2.27.165.124
```

## Step 4: Firewall

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## Step 5: Deploy Flow (Initial)

```bash
# 1. Pull repo
cd ~/dev/wealthtrack && git pull

# 2. Aktifkan venv
source .venv/bin/activate

# 3. Install/update deps
uv pip install -r backend/requirements.txt

# 4. Run migration (once only, or when schema changes)
uv run python -m backend.app.migrate_db

# 5. Restart service
sudo systemctl restart wealthtrack

# 6. Reload nginx (if config changed)
sudo systemctl reload nginx

# 7. Verifikasi
curl https://wealthtrack.filla.id/api/v1/categories -H "Authorization: Bearer $(curl -s -X POST https://wealthtrack.filla.id/api/v1/auth/login -H 'Content-Type: application/json' -d '{"username":"filla","password":"password123"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')"
```

## Step 6: Deploy Flow (Updates)

```bash
cd ~/dev/wealthtrack && git pull
source .venv/bin/activate
uv pip install -r backend/requirements.txt
sudo systemctl restart wealthtrack
```

## Step 7: Backup SQLite

```bash
#!/bin/bash
# ~/dev/wealthtrack/scripts/backup.sh
BACKUP_DIR=~/wealthtrack-backups
mkdir -p "$BACKUP_DIR"
cp ~/.keuangan/finance.db "$BACKUP_DIR/finance-$(date +%Y%m%d-%H%M%S).db"
# Keep last 30 days
ls -t "$BACKUP_DIR"/*.db | tail -n +31 | xargs rm -f 2>/dev/null
echo "Backup done: $(ls -lh "$BACKUP_DIR"/*.db | tail -1)"
```

Cron:

```bash
0 2 * * * ~/dev/wealthtrack/scripts/backup.sh
```

## Step 8: Monitoring

```bash
# Cek service
sudo systemctl status wealthtrack

# Cek log
journalctl -u wealthtrack -n 50 --no-pager

# Cek nginx
sudo nginx -t
sudo systemctl status nginx

# HTTP endpoint health check
curl -s -o /dev/null -w "%{http_code}" https://wealthtrack.filla.id/api/v1/auth/login
```

## Flutter App Configuration

Di Flutter, API base URL diatur ke:

```dart
// lib/core/constants.dart
class AppConstants {
  static const String apiBaseUrl = 'https://wealthtrack.filla.id/api/v1';
}
```

## Deployment Checklist

- [ ] DNS `wealthtrack.filla.id` → VPS IP (`2.27.165.124`)
- [ ] FastAPI systemd service running
- [ ] DB migration already ran
- [ ] Nginx config installed
- [ ] SSL certificate (run certbot after DNS is ready)
- [ ] Firewall: 80+443 open (8080 default deny via ufw)
- [ ] Backup cron installed
- [ ] Hermes cron `Daily Finance Summary` still running (check with `hermes cron list`)
