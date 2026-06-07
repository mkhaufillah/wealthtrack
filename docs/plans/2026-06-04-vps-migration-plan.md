# VPS Migration Plan — WealthTrack

> **For Hermes:** Execute this plan phase-by-phase using subagent-driven-development.

**Goal:** Migrate all WealthTrack services from old VPS (2.27.165.124) to new VPS (2.27.165.90) with zero data loss and minimal downtime.

**Architecture:** Full stack migration — PostgreSQL dump & restore, Redis fresh setup (ephemeral data), application code clone, systemd service, Nginx reverse proxy, and SSL via certbot. DNS cutover at the end.

**Tech Stack:** PostgreSQL 16, Redis 7, FastAPI/uvicorn, Nginx, certbot, systemd, Ubuntu 22.04

---

## Pre-Flight: Current Architecture

| Service | Current State | Details |
|---------|--------------|---------|
| PostgreSQL | Local `localhost:5432` | Database `wealthtrack` |
| Redis | Local `localhost:6379` | Maxmemory 256MB, allkeys-lru. Only rate limiting — ephemeral |
| FastAPI | systemd → uvicorn `127.0.0.1:8080` | `wealthtrack.service` |
| Nginx | Reverse proxy → SSL | `wealthtrack.filla.id` with certbot |
| SSH | Port `2222` | Non-standard |
| Deploy script | `~/dev/wealthtrack/deploy/deploy.sh` | Supports step-by-step validation |

---

## Task List

---

### PHASE 0: Prerequisites (New VPS)

---

### Task 0.1: Provision & Secure New VPS

**Objective:** Set up base system on 2.27.165.90 with all dependencies.

**Files:**
- Execute on new VPS

**Step 1: Base packages**
```bash
apt update && apt upgrade -y
apt install -y postgresql redis nginx certbot python3.11-venv git ufw
```

**Step 2: Firewall**
```bash
ufw allow 2222/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

**Step 3: SSH port**
```bash
sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
systemctl restart sshd
```

**Verify:** SSH into new VPS on port 2222.

---

### Task 0.2: Configure Tailscale on New VPS

**Objective:** Add new VPS to Tailscale network for private connectivity to Hermes Agent VPS.

**Files:**
- Execute on new VPS

**Step 1:** Install & auth:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

**Step 2:** Verify IP:
```bash
tailscale ip -4
# Expected: 100.x.x.x (save this for pg_hba.conf)
```

**Step 3:** Add Tailscale IP to Hermes Agent's pg_hba.conf (on Hermes VPS):
```bash
echo "host all all <new-tailscale-ip>/32 md5" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
sudo systemctl reload postgresql
```

---

### Task 0.3: Git Clone & Dependencies

**Objective:** Get code and Python deps on new VPS.

**Step 1:** Clone repo:
```bash
git clone git@github.com:mkhaufillah/wealthtrack.git ~/dev/wealthtrack
```

**Step 2:** Python venv:
```bash
cd ~/dev/wealthtrack/backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

**Step 3:** Copy `.env` from old VPS:
```bash
scp -P 2222 user@old-vps:~/dev/wealthtrack/backend/.env ~/dev/wealthtrack/backend/.env
```

**Verify:** `.env` has all keys: `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY`, `OPENCODE_GO_API_KEY`, `OPENROUTER_API_KEY`, `SMTP_*`.

---

### PHASE 1: Database Migration

---

### Task 1.1: Dump & Restore PostgreSQL

**Objective:** Export production DB from old VPS, import to new VPS.

**Step 1:** On old VPS — create dump:
```bash
pg_dump -U wealthtrack -h localhost -d wealthtrack -F c -f ~/wealthtrack.dump
```

**Step 2:** Copy to new VPS:
```bash
scp -P 2222 ~/wealthtrack.dump user@new-vps:~
```

**Step 3:** On new VPS — import:
```bash
sudo -u postgres createuser wealthtrack -P   # Set same password
sudo -u postgres createdb -O wealthtrack wealthtrack
pg_restore -U wealthtrack -h localhost -d wealthtrack -F c ~/wealthtrack.dump
```

**Step 4:** Update `pg_hba.conf` on new VPS to allow only local + Tailscale:
```
# local
local all all peer
host  wealthtrack wealthtrack 127.0.0.1/32 md5
host  wealthtrack wealthtrack ::1/128     md5
# Tailscale (Hermes Agent)
host  wealthtrack wealthtrack <hermes-tailscale-ip>/32 md5
```

**Verify:**
```bash
psql -U wealthtrack -d wealthtrack -c "SELECT count(*) FROM transactions;"
# Should match old VPS count
```

---

### PHASE 2: Redis (Fresh Setup)

---

### Task 2.1: Configure Redis on New VPS

**Objective:** Redis data is ephemeral (rate limiting counters only) — no dump needed.

```bash
# Default config is fine — bind to localhost only
systemctl restart redis
redis-cli ping
# Expected: PONG
```

---

### PHASE 3: Application & Systemd

---

### Task 3.1: Set Up Systemd Service

**Objective:** Run FastAPI via systemd on new VPS.

**Files:**
- Create: `/etc/systemd/system/wealthtrack.service` (from `deploy/wealthtrack.service`)

**Step 1:** Deploy service file:
```bash
sudo cp ~/dev/wealthtrack/deploy/wealthtrack.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable wealthtrack
sudo systemctl start wealthtrack
```

**Step 2:** Verify health:
```bash
sudo systemctl status wealthtrack
curl -s http://127.0.0.1:8080/api/v1/health
# Expected: {"status":"ok","database":"connected","redis":"connected"}
```

---

### PHASE 4: Nginx & SSL

---

### Task 4.1: Set Up Reverse Proxy

**Objective:** Route `wealthtrack.filla.id` → localhost:8080 with SSL.

**Files:**
- Copy: `deploy/wealthtrack.nginx` → `/etc/nginx/sites-available/wealthtrack.filla.id`

**Step 1:** Deploy Nginx config:
```bash
sudo cp ~/dev/wealthtrack/deploy/wealthtrack.nginx /etc/nginx/sites-available/wealthtrack.filla.id
sudo ln -sf /etc/nginx/sites-available/wealthtrack.filla.id /etc/nginx/sites-enabled/
```

**Step 2:** SSL via certbot (DNS must point to new VPS first):
```bash
sudo certbot --nginx -d wealthtrack.filla.id
sudo nginx -t && sudo systemctl reload nginx
```

**Verify:**
```bash
curl -sI https://wealthtrack.filla.id
# Expected: HTTP/2 200 with valid SSL
```

---

### PHASE 5: GitHub Actions Runner

---

### Task 5.1: Set Up Self-Hosted Runner on New VPS

**Objective:** Move GitHub Actions runner from old VPS to new VPS for CI/CD deployment.

**Files:**
- Follow existing `self-hosted-github-runner` skill setup

**Step 1:** Install runner:
```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.323.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.323.0/actions-runner-linux-x64-2.323.0.tar.gz
tar xzf actions-runner-linux-x64-2.323.0.tar.gz
./config.sh --url https://github.com/mkhaufillah/wealthtrack --token <token> --labels self-hosted,linux --name wealthtrack-vps
```

**Step 2:** Install as service:
```bash
sudo ./svc.sh install hermes
sudo ./svc.sh start
```

**Verify:**
```bash
sudo ./svc.sh status
# Expected: Active: active (running)
```

---

### PHASE 6: DNS Cutover

---

### Task 6.1: Update DNS & Verify

**Objective:** Point `wealthtrack.filla.id` to new VPS IP, verify everything works.

**Step 1:** Update A record for `wealthtrack.filla.id` → `2.27.165.90`

**Step 2:** Wait for propagation (5 min to 24h depending on TTL)

**Step 3:** Verify from external:
```bash
curl -s https://wealthtrack.filla.id/api/v1/health
```

**Step 4:** Test full flow:
- Login from Flutter app on phone
- Add a test transaction
- Scan a receipt (OCR)
- Check AI Advisor

---

### PHASE 7: Decommission Old VPS

---

### Task 7.1: Keep & Monitor

**Objective:** Keep old VPS running for 48h as rollback option.

- Keep both VPS running
- If issues, revert DNS to old VPS IP
- After 48h with no issues, stop `wealthtrack.service` on old VPS
- Create final DB backup as archive
- Remove or repurpose old VPS

---

## Configuration Files Checklist

| File | Action |
|------|--------|
| `~/dev/wealthtrack/backend/.env` | Copy from old VPS, verify every value |
| `~/dev/wealthtrack/deploy/wealthtrack.service` | Deploy to `/etc/systemd/system/` |
| `~/dev/wealthtrack/deploy/wealthtrack.nginx` | Deploy to `/etc/nginx/sites-available/` |
| `/etc/redis/redis.conf` | Default config, bind localhost only |
| `~/.ssh/authorized_keys` | Same keys, may need to copy |

## Services That DON'T Need Migration

| Service | Reason |
|---------|--------|
| Redis data | Only ephemeral rate limiting counters |
| Hermes Agent | Runs on separate VPS (the AI bot itself) |
| Flutter APK | Built via CI on GitHub Actions |
| SSL certs | Regenerated via certbot on new VPS |
| SSH keys | Same keys can be reused |

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| DNS propagation delay | Some users see old VPS | Keep old VPS running 48h |
| `.env` secrets mismatch | Auth/API calls fail | Verify `.env` line-by-line before cutover |
| PostgreSQL version mismatch | pg_dump/restore fails | Check `pg_config --version` on both VPS |
| Certbot rate limit | Can't issue cert | Use `--dry-run` first; 5 certs/week limit |
| Firewall blocks connection | App unreachable | Test with curl before DNS switch |

## Rollback Plan

If migration fails or users report issues:

1. **Keep old VPS running** — DNS still points there until changed
2. **Revert DNS** back to old VPS IP (`2.27.165.124`)
3. **Investigate** root cause on new VPS without downtime pressure
