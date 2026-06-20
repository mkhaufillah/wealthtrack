#!/bin/bash
# WealthTrack Deploy Script
# Run: bash deploy/deploy.sh
# You'll be prompted for sudo password a few times.

set -e

echo "============================================"
echo "  WealthTrack — VPS Deployment"
echo "============================================"

cd "$(dirname "$0")/.."

# ─── Helper: check if nginx config is HTTP-only (no SSL refs) ───
nginx_is_http_only() {
    grep -q "listen 80;" /etc/nginx/sites-available/wealthtrack 2>/dev/null && \
    ! grep -q "listen 443" /etc/nginx/sites-available/wealthtrack 2>/dev/null
}

# ─── Helper: check if SSL cert exists and not expiring in 7d ───
ssl_cert_valid() {
    local cert="/etc/letsencrypt/live/wealthtrack.filla.id/fullchain.pem"
    [ -f "$cert" ] && sudo openssl x509 -checkend $((7*86400)) -in "$cert" &>/dev/null
}

# ─── Helper: check if a service is running ───
service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# ════════════════════════════════════════════════════
# 0. Install certbot if missing
# ════════════════════════════════════════════════════
echo ""
echo "[0/7] Checking + installing certbot..."
if ! command -v certbot &>/dev/null; then
    sudo apt update -qq && sudo apt install -y -qq certbot python3-certbot-nginx
    echo "  ✓ certbot installed"
else
    echo "  ✓ certbot already installed"
fi

# ════════════════════════════════════════════════════
# 1. Docker Build & Run (Replacing Systemd)
# ════════════════════════════════════════════════════
echo ""
echo "[1/7] Building and running Docker container..."
if ! command -v docker &>/dev/null; then
    echo "  ! Docker is not installed. Please install Docker first: https://docs.docker.com/engine/install/"
    exit 1
fi

cd backend
docker compose up -d --build
docker image prune -f
cd ..
echo "  ✓ Docker container running"

# ════════════════════════════════════════════════════
# 2. Nginx Config (HTTP-only — SSL added by certbot in step 3)
# ════════════════════════════════════════════════════
echo ""
echo "[2/7] Configuring Nginx (HTTP-only)..."
CONFIG_FILE="/etc/nginx/sites-available/wealthtrack"
CONFIG_LINK="/etc/nginx/sites-enabled/wealthtrack"

if [ -f "$CONFIG_FILE" ] && nginx_is_http_only && sudo nginx -t 2>/dev/null; then
    echo "  ✓ HTTP-only nginx config already active — skipping"
else
    python3 deploy/strip_ssl.py < deploy/wealthtrack.nginx | sudo tee "$CONFIG_FILE" > /dev/null
    sudo ln -sf "$CONFIG_FILE" "$CONFIG_LINK"
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t
    sudo systemctl reload nginx
    echo "  ✓ HTTP-only nginx config active (generated from deploy/wealthtrack.nginx)"
fi

# ════════════════════════════════════════════════════
# 3. SSL Certificate (converts HTTP→HTTPS automatically)
# ════════════════════════════════════════════════════
echo ""
echo "[3/7] Checking SSL certificate..."
if ssl_cert_valid; then
    echo "  ✓ SSL certificate valid → HTTPS already active — skipping"
else
    echo "  Requesting SSL certificate from Let's Encrypt..."
    sudo certbot --nginx -d wealthtrack.filla.id --non-interactive --agree-tos -m khaufillahmohammad@gmail.com
    sudo systemctl reload nginx
    echo "  ✓ SSL certificate installed"
fi

# ════════════════════════════════════════════════════
# 4. Verify Docker Container
# ════════════════════════════════════════════════════
echo ""
echo "[4/7] Verifying WealthTrack container..."
docker ps --filter "name=wealthtrack-backend"

# ════════════════════════════════════════════════════
# 6. Firewall
# ════════════════════════════════════════════════════
echo ""
echo "[5/7] Configuring UFW firewall..."
for port in 80 443; do
    if sudo ufw status | grep -q "$port/tcp"; then
        echo "  ✓ port $port already allowed — skipping"
    else
        sudo ufw allow "$port/tcp"
        echo "  ✓ port $port allowed"
    fi
done
sudo ufw --force enable 2>/dev/null || true

# ════════════════════════════════════════════════════
echo ""
echo "============================================"
echo "  ✅ Deployment Complete!"
echo "  https://wealthtrack.filla.id/api/v1/auth/login"
echo "============================================"
echo ""
echo "  Next: visit the URL above to verify."
echo "  If login page loads → done."
echo "  If error → Lakoni debug."
echo ""
