# Deployment — VPS Production Setup

**See also:** [Backend Implementation](04-backend-implementation.md) · [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)



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
                          |  │  finance.db     │◄──── Hermes cron also read this          │
                          |  └─────────────────┘                                          │
                          |                                                               │
                          |  ┌─────────────────────────────────────┐                      │
                          |  │  Hermes Agent (same VPS)            │                      │
                          |  │  ├── cron: daily_finance_report.py  │──► SQLite (legacy) │
                          |  │  ├── skill: financial-tracker       │──► SQLite (legacy) │
                          |  │  └── chat: add_transaction.py       │──► SQLite (legacy) │
                          |  └─────────────────────────────────────┘                      │
                          |  ┌─────────────────────────────────────┐                      │
                          |  │  Flutter Mobile (via internet)      │                      │
                          |  │  ──► https://wealthtrack.filla.id   │──► Nginx ──► FastAPI │
                          |  └─────────────────────────────────────┘                      │
                          |                                                               │
  	                      └───────────────────────────────────────────────────────────────┘
```

## Key Differences from Standard Setup

| Aspect | Before (old doc) | After (update) |
|-------|-------------------|-------------------|
| DB path | `~/.hermes/data/wealthtrack.db` | `~/.keuangan/finance.db` (existing) |
| FastAPI bind | `0.0.0.0:8080` | `127.0.0.1:8080` (localhost only) |
| Public exposure | Port 8080 directly | Nginx reverse proxy via 443 |
| Domain | — | `wealthtrack.filla.id` |
| SSH port | 22 | **2222** |
| Firewall | Only 80 + 443 | 80 + 443 (SSH 2222 via internal VPN) |

## Step 1: Systemd Service for FastAPI

Config file is at `deploy/wealthtrack.service`:

```ini
[Unit]
Description=WealthTrack API
After=network.target

[Service]
Type=simple
User=filla
WorkingDirectory=/home/filla/dev/wealthtrack/backend
Environment=PATH=/home/filla/.local/bin:/home/filla/dev/wealthtrack/.venv/bin
ExecStart=/home/filla/dev/wealthtrack/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8080
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Install and start:

```bash
sudo cp deploy/wealthtrack.service /etc/systemd/system/wealthtrack.service
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

Config file is at `deploy/wealthtrack.nginx`:

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

    # Reverse proxy to FastAPI
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Increase timeouts for AI Advisor SSE streaming
        proxy_read_timeout 120s;
        proxy_connect_timeout 10s;

        # Disable buffering for SSE (Server-Sent Events)
        proxy_buffering off;
        proxy_cache off;

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
sudo cp deploy/wealthtrack.nginx /etc/nginx/sites-available/wealthtrack
sudo ln -s /etc/nginx/sites-available/wealthtrack /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default  # optional: disable default site
sudo nginx -t  # test config
sudo systemctl reload nginx
```

## Step 3: SSL Certificate (Let's Encrypt)

Run **AFTER** DNS `wealthtrack.filla.id` points to the VPS IP.

> 💡 **One-command deploy:** `bash deploy/deploy.sh` — does steps 1-7 automatically (installs certbot if missing).
> Or follow each step manually below.

```bash
sudo certbot --nginx -d wealthtrack.filla.id --non-interactive --agree-tos -m khaufillahmohammad@gmail.com
```

If DNS is not ready yet, run this later:

```bash
# Check DNS first
dig +short A wealthtrack.filla.id
# Should return VPS IP: 2.27.165.124
```

### Auto-Renewal (Certbot)

SSL certificates from Let's Encrypt expire after 90 days. Certbot auto-renews via a systemd timer:

```bash
# Check the timer is active
sudo systemctl status certbot.timer

# Test renewal (dry-run)
sudo certbot renew --dry-run

# The default certbot installation creates:
#   /etc/systemd/system/certbot.timer  — runs twice daily
#   /etc/systemd/system/certbot.service — the renewal command
# No manual cron needed.
```

Certbot auto-updates the nginx config on renewal — `sudo systemctl reload nginx` is handled automatically.

## Step 4: Firewall

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## Step 4.5: Environment Variables

Before starting the service, **create `backend/.env`** with a random SECRET_KEY:

```bash
cd ~/dev/wealthtrack
python3 -c "import secrets; f=open('backend/.env','w'); f.write(f'SECRET_KEY={secrets.token_hex(32)}\nDEBUG=True\nACCESS_TOKEN_EXPIRE_DAYS=30\n')"
```

The CI deploy workflow (`deploy-backend.yml`) auto-generates `backend/.env` if it doesn't exist on the server. For manual/local deployment, run the one-liner above.

| Variable | Description | Default |
|----------|------------|---------|
| `SECRET_KEY` | JWT signing key (must be unique per deployment) | `change-me-in-production-use-env` (app warns) |
| `DEBUG` | FastAPI debug mode | `True` |
| `ACCESS_TOKEN_EXPIRE_DAYS` | JWT token lifetime in days | `30` |
| `CORS_ORIGINS` | Allowed origins (JSON array) | `["http://localhost:8080", "http://127.0.0.1:8080", "https://wealthtrack.filla.id"]` |
| `OPENCODE_GO_API_KEY` | API key for OpenCode Go (AI Advisor, OCR) | `""` (read from ~/.hermes/.env fallback) |
| `OPENROUTER_API_KEY` | API key for OpenRouter (premium Claude model) | `""` (optional) |
| `BRAVE_SEARCH_API_KEY` | API key for Brave Search (real-time web data for AI Advisor) | `""` (read from ~/.hermes/.env fallback) |
| `DB_PATH` | Override default database path | `~/.keuangan/finance.db` |

## Step 5: Deploy Flow (Initial)

```bash
# 1. Pull repo
cd ~/dev/wealthtrack && git pull

# 2. Activate venv
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
```bash
# Login and test API
TOKEN=$(curl -s -X POST https://wealthtrack.filla.id/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"filla","password":"password123"}' | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s -H "Authorization: Bearer $TOKEN" \
  https://wealthtrack.filla.id/api/v1/categories | python3 -m json.tool
```
```

## Step 6: Deploy Flow (Updates)

```bash
cd ~/dev/wealthtrack && git pull
source .venv/bin/activate
uv pip install -r backend/requirements.txt

# Run migration if schema changed (safe to run every time)
uv run python -m backend.app.migrate_db

# Restart service
sudo systemctl restart wealthtrack

# Reload nginx if config changed
sudo systemctl reload nginx

# Verify
curl -s -o /dev/null -w "%{http_code}" https://wealthtrack.filla.id/api/v1/health
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

## Step 8: CI/CD Pipeline

### Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `build-apk.yml` | Push to `main` with `mobile/**` changes, or `workflow_dispatch` | Installs Flutter, runs tests, builds release APK (~27MB), uploads artifact (retained 1 day). |
| `deploy-backend.yml` | Push to `main` with `backend/**` or `deploy/**` changes, or `workflow_dispatch` | Runs tests → deploys via SSH → restart systemd service → health check. |

### Telegram Notifications

Both workflows send build/deploy results to **Forum Anak Intern → topic #🤖-deployment**, with:

- ✅ **Success** — commit SHA short hash + link to run
- ❌ **Failure** — commit SHA + direct link to GitHub Actions logs

### Required Secrets

| Secret | Description |
|--------|------------|
| `TELEGRAM_BOT_TOKEN` | Bot token for CI notifications |
| `TELEGRAM_CHAT_ID` | Telegram group ID (`-1003981338873` — Forum Anak Intern) |
| `TELEGRAM_TOPIC_ID` | Topic ID within group (`4723` — #🤖-Deployment) |
| `VPS_HOST` + `VPS_USER` + `VPS_SSH_KEY` | SSH access for backend deployment |
| `KEYSTORE_BASE64` + `KEYSTORE_PASSWORD` + `KEY_ALIAS` + `KEY_PASSWORD` | APK release signing |

### Artifact Storage

- Only **release APK** is uploaded (no debug APK).
- Retention: **1 day** — artifacts auto-expire within 24 hours.
- Free quota: ~500MB. At ~27MB/run, this allows ~18 runs before cleanup cycles kick in.

## Step 9: Monitoring

```bash
# Check service status
sudo systemctl status wealthtrack

# Check logs
journalctl -u wealthtrack -n 50 --no-pager

# Check nginx
sudo nginx -t
sudo systemctl status nginx

# HTTP endpoint health check
curl -s -o /dev/null -w "%{http_code}" https://wealthtrack.filla.id/api/v1/auth/login
```

## Flutter App Configuration

In Flutter, API base URL change to:

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
