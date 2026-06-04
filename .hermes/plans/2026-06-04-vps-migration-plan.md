# VPS Migration Plan — WealthTrack

> **Goal:** Migrate all WealthTrack services from current VPS to a new VPS with zero data loss and minimal downtime.
>
> **Status:** Planning only — not yet executed.

---

## Current Architecture

| Service | Current VPS | Details |
|---------|-------------|---------|
| **PostgreSQL** | Local `localhost:5432` | Database `wealthtrack` |
| **Redis** | Local `localhost:6379` | Maxmemory 256MB, allkeys-lru. Only rate limiting — ephemeral data |
| **FastAPI (WealthTrack)** | systemd → uvicorn `127.0.0.1:8080` | `wealthtrack.service` |
| **Nginx** | Reverse proxy `wealthtrack.filla.id:443` | SSL via certbot |
| **Certbot** | SSL auto-renewal | Domain: `wealthtrack.filla.id` |
| **SSH** | Port `2222` | Non-standard port |
| **Deploy script** | `~/dev/wealthtrack/deploy/deploy.sh` | Supports step-by-step validation |

---

## Services Status

| Service | Active | Config |
|---------|--------|--------|
| PostgreSQL | ✅ (assumed) | Local socket, no external access |
| Redis | ✅ Active | bind 127.0.0.1:6379, CONFIG renamed |
| WealthTrack API | ✅ Active | systemd service, auto-restart |
| Nginx | ✅ Active | SSL, proxy to localhost:8080 |
| Certbot | ✅ Active | Auto-renewal hooks |
| Firewall | ✅ Active | Ports 80, 443, 2222 open |
| DB Backup | ❌ Not found | No backup script or cron detected |

---

## Migration Step-by-Step

### Phase 0: Prerequisites (New VPS)

1. **Provision new VPS** — Ubuntu 22.04/24.04 LTS
2. **Set up SSH key** — same SSH key as current VPS, port 2222
3. **Install base packages:**
   ```bash
   apt update && apt upgrade -y
   apt install -y postgresql redis nginx certbot python3.11-venv git ufw
   ```
4. **Configure firewall:**
   ```bash
   ufw allow 2222/tcp
   ufw allow 80/tcp
   ufw allow 443/tcp
   ufw enable
   ```
5. **Configure SSH to port 2222:**
   ```bash
   sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
   systemctl restart sshd
   ```

### Phase 1: PostgreSQL Migration

1. **On current VPS — dump production database:**
   ```bash
   pg_dump -U wealthtrack -h localhost -d wealthtrack -F c -f ~/wealthtrack.dump
   ```
2. **Copy dump to new VPS:**
   ```bash
   scp -P 2222 ~/wealthtrack.dump user@new-vps:~
   ```
3. **On new VPS — import database:**
   ```bash
   # Create role and database
   sudo -u postgres createuser wealthtrack -P   # Set same password
   sudo -u postgres createdb -O wealthtrack wealthtrack
   
   # Import dump
   pg_restore -U wealthtrack -h localhost -d wealthtrack -F c ~/wealthtrack.dump
   ```

### Phase 2: Redis Migration

1. **On current VPS — verify Redis data is ephemeral:**
   ```bash
   redis-cli --raw KEYS '*'
   ```
   Expected: only `ratelimit:*` keys. These are ephemeral — no need to migrate.
2. **On new VPS — configure Redis:**
   ```bash
   cp /etc/redis/redis.conf /etc/redis/redis.conf.bak
   sed -i 's/bind 127.0.0.1 ::1/bind 127.0.0.1/' /etc/redis/redis.conf
   sed -i 's/# rename-command CONFIG ""/rename-command CONFIG ""/' /etc/redis/redis.conf   # Check actual conf path
   systemctl restart redis
   ```
3. **Verify connectivity:**
   ```bash
   redis-cli ping   # Expected: PONG
   ```

### Phase 3: Application Code & Environment

1. **Clone repo on new VPS:**
   ```bash
   git clone git@github.com:mkhaufillah/wealthtrack.git ~/dev/wealthtrack
   cd ~/dev/wealthtrack
   ```
2. **Create Python virtual environment:**
   ```bash
   cd backend
   python3.11 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```
3. **Copy .env file:**
   ```bash
   scp -P 2222 user@current-vps:~/dev/wealthtrack/backend/.env ~/dev/wealthtrack/backend/.env
   ```
   Verify all credentials: `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY`, `OPENCODE_GO_API_KEY`, `OPENROUTER_API_KEY`, `SMTP_*`.

### Phase 4: Systemd Service

1. **Copy service file:**
   ```bash
   sudo cp ~/dev/wealthtrack/deploy/wealthtrack.service /etc/systemd/system/wealthtrack.service
   sudo systemctl daemon-reload
   sudo systemctl enable wealthtrack
   sudo systemctl start wealthtrack
   sudo systemctl status wealthtrack   # Verify running
   ```
2. **Verify API health:**
   ```bash
   curl -s http://127.0.0.1:8080/api/v1/health
   # Expected: {"status":"ok","database":"connected","redis":"connected"}
   ```

### Phase 5: Nginx + SSL

1. **Copy nginx config:**
   ```bash
   sudo cp ~/dev/wealthtrack/deploy/wealthtrack.nginx /etc/nginx/sites-available/wealthtrack
   sudo ln -sf /etc/nginx/sites-available/wealthtrack /etc/nginx/sites-enabled/
   ```
2. **Set up SSL (need DNS pointed to new VPS first):**
   ```bash
   # Temporarily disable reference to SSL certs if needed
   sudo nginx -t   # Verify config
   
   # Run certbot (DNS must resolve to new VPS IP)
   sudo certbot --nginx -d wealthtrack.filla.id
   sudo nginx -t && sudo systemctl reload nginx
   ```
3. **Verify SSL:**
   ```bash
   curl -sI https://wealthtrack.filla.id
   # Expected: HTTP/2 200 with valid SSL
   ```

### Phase 6: DNS Switchover

1. **Update DNS A record** for `wealthtrack.filla.id` to point to new VPS IP
2. **Wait for DNS propagation** (5 mins to 24 hours depending on TTL)
3. **Verify from external:**
   ```bash
   curl -s https://wealthtrack.filla.id/api/v1/health
   ```
4. **Test login + OCR scan from Flutter app on phone**

### Phase 7: Decommission Old VPS (after 48h)

1. **Keep old VPS running for 48 hours** as rollback option
2. **After 48h with no issues:**
   - Stop wealthtrack service on old VPS
   - Create final DB backup as archive
   - Remove old VPS or repurpose

---

## Key Configuration Files to Copy

| File | Purpose |
|------|---------|
| `~/dev/wealthtrack/backend/.env` | All secrets and environment variables |
| `~/dev/wealthtrack/deploy/wealthtrack.service` | Systemd unit file |
| `~/dev/wealthtrack/deploy/wealthtrack.nginx` | Nginx config template |
| `/etc/redis/redis.conf` | Redis config (standard, can regenerate from defaults) |
| `~/.ssh/authorized_keys` | SSH keys (can regenerate) |

---

## Services That DON'T Need Migration

| Service | Reason |
|---------|--------|
| **Redis data** | Only ephemeral rate limiting counters |
| **Hermes Agent** | It's on a different VPS (the AI bot itself) |
| **Flutter APK** | Built via CI on GitHub Actions |
| **SSL certs** | Regenerated via certbot on new VPS |
| **SSH keys** | Same keys can be used |

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| **DNS propagation delay** | Some users see old VPS | Keep old VPS running 48h |
| **.env secrets mismatch** | Auth/API calls fail | Verify .env line-by-line before cutover |
| **PostgreSQL version mismatch** | pg_dump/restore fails | Check versions: `pg_config --version` on both VPS |
| **Certbot rate limit** | Can't issue cert | Use `--dry-run` first; 5 certs/week limit per domain |
| **Firewall blocks connection** | App unreachable | Test with curl from new VPS before DNS switch |

---

## Rollback Plan

If migration fails or users report issues:

1. **Keep old VPS running** — DNS still points there until changed
2. **Revert DNS** back to old VPS IP
3. **Investigate** root cause on new VPS without downtime pressure
