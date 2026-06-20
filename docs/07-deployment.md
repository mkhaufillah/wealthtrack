# Deployment — VPS Production Setup

**See also:** [Backend Implementation](04-backend-implementation.md) · [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)

> **⚠️ v0.7.2 update:** Backend is now Dockerized and deployment is handled by GitHub-hosted runners (`ubuntu-latest`) via SSH.

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
                          |  Docker Container (wealthtrack-backend)                       │
                          |  --network host (binds to :8080)                              │
                          |     │          ▲                  ▲                           │
                          |     │          │                  │                           │
                          |     ▼          │                  │                           │
                          |  ┌─────────────────┐   ┌──────────────┐   ┌──────────────┐   │
                          |  │   PostgreSQL    │   │  Meilisearch │   │   Redis      │   │
                          |  │  :5432          │   │  :7700       │   │  :6379       │   │
                          |  │  (localhost     │   │  (localhost) │   │  (auth req)  │   │
                          |  │   only)         │   │              │   │              │   │
                          |  └─────────────────┘   └──────────────┘   └──────────────┘   │
                          └───────────────────────────────────────────────────────────────┘
                                   ▲
                                   │ SSH Deploy
                          ┌────────┴─────────────────────────────────────────────┐
                          │  GitHub Actions (ubuntu-latest)                      │
                          │  ├── test → pytest 313 tests (Docker Postgres+Redis) │
                          │  ├── deploy → SSH → docker build & run               │
                          │  └── build-apk → Flutter 290 tests → APK release     │
                          └──────────────────────────────────────────────────────┘
```

## Key Differences from Earlier Setup

| Aspect | Old (before v0.7.2) | New (current) |
|--------|---------------------|---------------|
| Runner | Self-hosted GitHub Actions runner | GitHub-hosted `ubuntu-latest` |
| Application Host | Native via systemd + virtualenv | Docker Container (`python:3.11-slim`) |
| Deployment method | `systemctl restart wealthtrack` | SSH via `appleboy/ssh-action` |
| GitHub secrets for VPS | None | `SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY` |

## Docker Container (Replaces Systemd)

The backend is now fully containerized. A Docker container handles the application running on port 8080.

To manually deploy on the server:
```bash
cd ~/dev/wealthtrack/backend
docker build -t wealthtrack-backend .
docker stop wealthtrack-backend 2>/dev/null || true
docker rm wealthtrack-backend 2>/dev/null || true
docker run -d --name wealthtrack-backend --network host --restart unless-stopped $([ -f .env ] && echo "--env-file .env") wealthtrack-backend
```
*Note: We use `--network host` so the container can resolve `localhost` natively to the host PostgreSQL and Redis instances without modifying the connection strings.*

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

### GitHub-Hosted Runner (`ubuntu-latest`)

Deployments are handled by GitHub's ephemeral `ubuntu-latest` runners. The test database (PostgreSQL and Redis) are spun up as service containers during the test job. 

### Deploy Flow (git push → live)

1. **Push to `main`** triggers workflows
2. **Test phase** (GitHub runner): runs 313 pytest tests (backend) with PostgreSQL 18 + Redis 7 service containers (Docker).
3. **Deploy phase** (GitHub runner): on test success, the runner connects via SSH (`appleboy/ssh-action`):
   - `git pull` on the VPS
   - Builds new Docker image
   - Restarts Docker container `wealthtrack-backend` on the VPS
   - HTTP health check (retries 12×, 10s apart)
4. **Notifications**: Telegram messages at every stage (start, test result, deploy result)

**Workflow trigger paths:** `backend/**`, `deploy/**`, `.github/workflows/deploy-backend.yml`

### Required Secrets

| Secret | Purpose |
|--------|---------|
| `SERVER_HOST` | VPS IP address for SSH deploy |
| `SERVER_USER` | VPS username for SSH deploy |
| `SERVER_SSH_KEY` | Private SSH key for VPS deployment |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token for CI notifications |
| `KEYSTORE_BASE64` | Keystore file (base64) for APK signing |
| `KEY_ALIAS` | Keystore alias for APK signing |
| `KEYSTORE_PASSWORD` | Keystore password for APK signing |
| `KEY_PASSWORD` | Key password for APK signing |

### Telegram Notifications

All notifications go to **Keluarga Super Sapi → topic Deployment** (`chat_id=-1003997003114`, `topic_id=3`).

**Four notification events per deploy run:**
1. 🚀 "CI started" — when test job begins
2. ✅/❌ "Tests result" — immediately after test job completes
3. ✅ "Deploy success" — after health check passes
4. ❌ "Deploy failure" — if deploy job fails

### Flutter APK Build

Triggered by `build-apk.yml` on push to `main` with `mobile/**` changes or manual `workflow_dispatch`. Runs on GitHub-hosted runner (`ubuntu-latest`).

- Builds release APK (~27MB)
- Signs with uploaded keystore
- Uploads artifact (retention: 1 day)
- Falls back to GitHub Release if artifact storage is full
- **Auto-cleanup**: removes `build/` and `.dart_tool/` after every run (`always()`)
- Telegram notification on success/failure

### Test Infrastructure

| Detail | Value |
|--------|-------|
| Test runner | GitHub-hosted runner (`ubuntu-latest`) |
| Test database | `wealthtrack_test` on PostgreSQL 18 container (port 5433) |
| Redis for tests | `redis:7-alpine` container (port 6380, no auth) |
| Test count | **603 total** (313 backend + 290 Flutter) |
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
docker logs -f wealthtrack-backend

# Redis
redis-cli -a '<password>' ping  # → PONG

# Meilisearch
curl -s http://localhost:7700/health  # → {"status":"available"}

# Nginx
sudo nginx -t
sudo systemctl status nginx

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
- [x] Docker installed and running
- [x] SSH credentials configured in GitHub Secrets
- [x] Telegram notifications working (start + result)
- [x] Backup cron installed
