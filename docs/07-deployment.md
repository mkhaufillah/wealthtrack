# Deployment — VPS Production Setup

**See also:** [Backend Implementation](04-backend-implementation.md) · [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)

> **⚠️ v0.5.3 update:** Deployment is now fully automated via self-hosted GitHub Actions runner. SSH-based deployment has been replaced. This doc reflects the current state.

## Architecture on VPS

```
                          ┌───────────────────────────────────────────────────────────────┐
                          │              VPS — 2.27.165.90 (Ubuntu 22.04)                │
                          │                                                               │
  ──► wealthtrack.filla.id ──► Nginx :80 (redirect to 443)                                │
                          |    Nginx :443 (SSL)                                           │
                          |        │                                                      │
                          |        ▼                                                      │
                          |  Reverse Proxy                                                │
                          |        │                                                      │
                          |        ▼                                                      │
                          |  FastAPI :8080 (localhost only)                               │
                          |     │          ▲                  ▲                           │
                          |     │          │                  │                           │
                          |     ▼          │                  │                           │
                          |  ┌─────────────────┐   ┌──────────────┐   ┌──────────────┐   │
                          |  │   PostgreSQL    │   │  Meilisearch │   │   Redis      │   │
                          |  │  :5432          │   │  :7700       │   │  :6379       │   │
                          |  │  (localhost     │   │  (localhost) │   │  (auth req)  │   │
                          |  │   only)         │   │              │   │              │   │
                          |  └─────────────────┘   └──────────────┘   └──────────────┘   │
                          |                                                               │
                          |  ┌──────────────────────────────────────────────────────┐     │
                          |  │  GitHub Actions Self-Hosted Runner (wealthtrack-vps) │     │
                          |  │  systemd service: actions.runner.wealthtrack-...     │     │
                          |  │  Outbound connection to GitHub — no inbound ports    │     │
                          │  │  ├── test → pytest 193 tests (Docker Postgres+Redis)       │     │
                          │  │  ├── deploy → git pull → uv pip install → sudo systemctl │     │
                          │  │  ├── build-apk → Flutter release APK + cleanup            │     │
                          │  │  └── Verify → health check                               │     │
                          |  └──────────────────────────────────────────────────────┘     │
                          |                                                               │
                          |  ┌─────────────────────────────────────┐                      │
                          |  │  Flutter Mobile (via internet)      │                      │
                          |  │  ──► https://wealthtrack.filla.id   │──► Nginx ──► FastAPI │
                          |  └─────────────────────────────────────┘                      │
                          |                                                               │
                          └───────────────────────────────────────────────────────────────┘
```

## Key Differences from Earlier Setup

| Aspect | Old (before v0.5.3) | New (current) |
|--------|---------------------|---------------|
| Deployment method | SSH via appleboy/ssh-action (port 2222) | Self-hosted GitHub Actions runner |
| GitHub secrets for VPS | `VPS_HOST`, `VPS_SSH_KEY`, `VPS_USER`, `SUDO_PASSWORD` | **All removed** — 0 SSH secrets |
| sudo for systemctl | SUDO_PASSWORD passed via secret → `echo password \| sudo -S` | **NOPASSWD** — `/etc/sudoers.d/wealthtrack` allows `systemctl restart wealthtrack` |
| Telegram notifications | Only on success/failure of deploy job | 🚀 Start + ✅/❌ Tests + ✅/❌ Deploy (4 notifications per run) |
| CORS | `["*"]` (wildcard — allowed any origin) | `["https://wealthtrack.filla.id", "http://localhost:8080", "null"]` |
| Redis auth | No password — open access on localhost | `requirepass` enabled in `/etc/redis/redis.conf` |
| PostgreSQL password | Weak (`wealthtrack123`) | 32-character random alphanumeric |
| PostgreSQL access | Tailscale network (100.64.0.0/10) allowed | `localhost` only — Tailscale removed from `pg_hba.conf` |

## Systemd Service

Config file at `deploy/wealthtrack.service`:

```ini
[Unit]
Description=WealthTrack API
After=network.target redis.service
Wants=redis.service

[Service]
Type=simple
User=hermes
WorkingDirectory=/home/hermes/dev/wealthtrack/backend
Environment=PATH=/home/hermes/.local/bin:/home/hermes/dev/wealthtrack/.venv/bin
ExecStart=/home/hermes/dev/wealthtrack/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8080
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Install:
```bash
sudo cp deploy/wealthtrack.service /etc/systemd/system/wealthtrack.service
sudo systemctl daemon-reload
sudo systemctl enable wealthtrack
sudo systemctl start wealthtrack
sudo systemctl status wealthtrack
```

## Nginx Reverse Proxy

Config file at `deploy/wealthtrack.nginx`:

```nginx
server {
    listen 80;
    server_name wealthtrack.filla.id;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name wealthtrack.filla.id;

    ssl_certificate /etc/letsencrypt/live/wealthtrack.filla.id/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/wealthtrack.filla.id/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
        proxy_connect_timeout 10s;
        proxy_buffering off;
        proxy_cache off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Enable:
```bash
sudo cp deploy/wealthtrack.nginx /etc/nginx/sites-available/wealthtrack
sudo ln -s /etc/nginx/sites-available/wealthtrack /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

## SSL Certificate

```bash
sudo certbot --nginx -d wealthtrack.filla.id --non-interactive --agree-tos -m khaufillahmohammad@gmail.com
```

Auto-renewal via systemd certbot.timer (check with `sudo systemctl status certbot.timer`).

## Backing Services

### PostgreSQL 18

```bash
sudo systemctl enable --now postgresql
```

- Runs on `127.0.0.1:5432`
- Password: 32-character random (set in `.env` as `DATABASE_URL`)
- Access restricted to localhost (`pg_hba.conf`)
- Databases: `wealthtrack` (production), `wealthtrack_test` (CI tests)

### Redis 8.8.0

```bash
# Compiled from source, runs as systemd service
sudo systemctl enable --now redis
```

- Runs on `127.0.0.1:6379`
- **`requirepass` enabled** — connection string includes password from `.env`
- Uses: rate limiting, OCR queue state, AI response cache

### Meilisearch 1.45.2

```bash
# Binary installed at /usr/local/bin/meilisearch
sudo systemctl enable --now meilisearch
```

- Runs on `127.0.0.1:7700`
- Master key in `.env`: `MEILISEARCH_MASTER_KEY`
- 512MB max indexing memory, no analytics

### Verify all services

```bash
sudo systemctl status postgresql redis meilisearch wealthtrack --no-pager
```

## Environment Variables

`backend/.env`:

| Variable | Description | Current Value |
|----------|------------|---------------|
| `SECRET_KEY` | JWT signing key (32-byte hex) | Random per deployment |
| `DEBUG` | FastAPI debug mode | `False` |
| `ACCESS_TOKEN_EXPIRE_DAYS` | JWT lifetime | `30` |
| `CORS_ORIGINS` | JSON array of allowed origins | `["https://wealthtrack.filla.id", "http://localhost:8080", "null"]` |
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://wealthtrack:<password>@localhost:5432/wealthtrack` |
| `REDIS_URL` | Redis connection string | `redis://:<password>@localhost:6379/0` |
| `OPENCODE_GO_API_KEY` | OpenCode Go API key (AI Advisor, OCR) | From `~/.hermes/.env` fallback |
| `OPENROUTER_API_KEY` | OpenRouter API key (premium Claude) | Optional |
| `BRAVE_SEARCH_API_KEY` | Brave Search API key (AI Advisor web search) | From `~/.hermes/.env` fallback |
| `SMTP_HOST/PORT/USERNAME/PASSWORD` | SMTP for email OTP | Gmail App Password |
| `MEILISEARCH_URL` | Meilisearch URL | `http://localhost:7700` |
| `MEILISEARCH_MASTER_KEY` | Meilisearch master key | From `.env` |
| `OCR_IMAGE_DIR` | Directory for uploaded OCR images | `~/ocr_images` |

## CI/CD Pipeline

### Self-Hosted Runner (wealthtrack-vps)

A GitHub Actions self-hosted runner registered on the VPS, running as a systemd service. The runner communicates **outbound** to GitHub — no ports need to be open on the VPS for deployment.

**Runner setup:**
```bash
# Download and configure runner (one-time)
cd /home/hermes/actions-runner
./config.sh --url https://github.com/mkhaufillah/wealthtrack --token <token>
sudo ./svc.sh install
sudo ./svc.sh start

# Check status
sudo systemctl status actions.runner.wealthtrack-wealthtrack.wealthtrack-vps.service
```

### Deploy Flow (git push → live)

1. **Push to `main`** triggers workflows
2. **Test phase** (self-hosted runner): runs 193 pytest tests with PostgreSQL 18 + Redis 7 service containers (Docker). Tests use `wealthtrack_test` database on port 5433, Redis on port 6380.
3. **Deploy phase** (self-hosted runner): on test success, the runner:
   - `git pull` on the VPS
   - `uv pip install -r backend/requirements.txt`
   - `sudo systemctl restart wealthtrack` (NOPASSWD)
   - HTTP health check (retries 12×, 10s apart)
4. **Notifications**: Telegram messages at every stage (start, test result, deploy result)

**Workflow trigger paths:** `backend/**`, `deploy/**`, `.github/workflows/deploy-backend.yml`

### NOPASSWD Sudo Security

Only a **single systemd command** is allowed without password via `/etc/sudoers.d/wealthtrack`:
```
hermes ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart wealthtrack
```

No other `sudo` commands are available to the runner without a password. The secret `SUDO_PASSWORD` no longer exists in GitHub.

### Previous SSH Secrets — All Removed

The following GitHub secrets were deleted as part of the migration:
- ❌ `VPS_HOST`
- ❌ `VPS_USER`
- ❌ `VPS_SSH_KEY`
- ❌ `SUDO_PASSWORD`
- ❌ `TELEGRAM_CHAT_ID` (now hardcoded in workflow)
- ❌ `TELEGRAM_TOPIC_ID` (now hardcoded in workflow)

### Remaining Secrets (5 total)

| Secret | Purpose |
|--------|---------|
| `TG_BOT_TOKEN` | Telegram bot token for CI notifications |
| `DART` | Keystore alias for APK signing |
| `JAVA` | Keystore password for APK signing |
| `FLUTTER` | Key password for APK signing |
| `OPENROUTER_API_KEY` | Optional — premium Claude model for AI Advisor |

### Telegram Notifications

All notifications go to **Keluarga Super Sapi → topic Deployment** (`chat_id=-1003997003114`, `topic_id=3`).

**Four notification events per deploy run:**
1. 🚀 "CI started" — when test job begins
2. ✅/❌ "Tests result" — immediately after test job completes
3. ✅ "Deploy success" — after health check passes
4. ❌ "Deploy failure" — if deploy job fails

### Flutter APK Build

Triggered by `build-apk.yml` on push to `main` with `mobile/**` changes or manual `workflow_dispatch`. Runs on the self-hosted runner with pre-installed Android SDK + JDK 17.

- Builds release APK (~27MB) on self-hosted runner
- Signs with uploaded keystore
- Uploads artifact (retention: 1 day)
- Falls back to GitHub Release if artifact storage is full
- **Auto-cleanup**: removes `build/` and `.dart_tool/` after every run (`always()`)
- Telegram notification on success/failure

### Test Infrastructure

| Detail | Value |
|--------|-------|
| Test runner | Self-hosted runner (wealthtrack-vps) |
| Test database | `wealthtrack_test` on PostgreSQL 18 container (port 5433) |
| Redis for tests | `redis:7-alpine` container (port 6380, no auth) |
| Test count | **193 tests** — all passing |
| Env override | `WEALTHTRACK_TEST_DATABASE_URL=postgresql://wealthtrack_test:***@localhost:5433/wealthtrack_test` |
| Docker cleanup | Weekly cron: `docker system prune -f` (`docker` dangling images) |
| Concurrency | `cancel-in-progress: true` — old runs cancelled on new push |

### Health Check

```bash
curl -s -o /dev/null -w "%{http_code}" https://wealthtrack.filla.id/api/v1/health
# Expected: 200
```

## Monitoring

```bash
# Service logs
journalctl -u wealthtrack -n 50 --no-pager

# Redis
redis-cli -a '<password>' ping  # → PONG

# Meilisearch
curl -s http://localhost:7700/health  # → {"status":"available"}

# Nginx
sudo nginx -t
sudo systemctl status nginx

# Self-hosted runner
sudo systemctl status actions.runner.wealthtrack-wealthtrack.wealthtrack-vps.service

# Full endpoint health check
curl -s https://wealthtrack.filla.id/api/v1/health | python3 -m json.tool
```

## Deployment Checklist

- [x] DNS `wealthtrack.filla.id` → VPS IP (`2.27.165.90`)
- [x] PostgreSQL running (localhost only, password-protected)
- [x] Redis running (`requirepass` enabled)
- [x] Meilisearch running (`curl localhost:7700/health` → available)
- [x] FastAPI systemd service running
- [x] Schema auto-created on startup
- [x] Nginx config installed, SSL active
- [x] Firewall: 80+443 open
- [x] Self-hosted runner registered and online
- [x] NOPASSWD sudo configured (systemctl restart wealthtrack only)
- [x] GitHub secrets cleaned (SSH secrets removed)
- [x] Telegram notifications working (start + result)
- [x] Backup cron installed
