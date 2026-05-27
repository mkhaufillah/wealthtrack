#!/bin/bash
# WealthTrack Deploy Script
# Run: bash deploy/deploy.sh
# You'll be prompted for sudo password a few times.

set -e

echo "============================================"
echo "  WealthTrack — VPS Deployment"
echo "============================================"

cd "$(dirname "$0")/.."

# 0. Install certbot if missing
echo ""
echo "[0/7] Checking + installing certbot..."
if ! command -v certbot &>/dev/null; then
    sudo apt update -qq && sudo apt install -y -qq certbot python3-certbot-nginx
    echo "  ✓ certbot installed"
else
    echo "  ✓ certbot already installed"
fi

# 1. Systemd Service
echo ""
echo "[1/7] Installing systemd service..."
sudo cp deploy/wealthtrack.service /etc/systemd/system/wealthtrack.service
sudo systemctl daemon-reload
sudo systemctl enable wealthtrack

# 2. Nginx Config (HTTP-only first — SSL added by certbot)
echo ""
echo "[2/7] Configuring Nginx (HTTP-only)..."
sudo tee /etc/nginx/sites-available/wealthtrack > /dev/null <<'NGINX'
server {
    listen 80;
    server_name wealthtrack.filla.id;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /static/ {
        alias /home/filla/dev/wealthtrack/backend/static/;
        expires 30d;
    }
}
NGINX
sudo ln -sf /etc/nginx/sites-available/wealthtrack /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
echo "  ✓ HTTP-only nginx config active"

# 3. SSL Certificate (converts HTTP→HTTPS automatically)
echo ""
echo "[3/7] Requesting SSL certificate from Let's Encrypt..."
sudo certbot --nginx -d wealthtrack.filla.id --non-interactive --agree-tos -m khaufillahmohammad@gmail.com
sudo systemctl reload nginx
echo "  ✓ SSL certificate installed"

# 4. Run Migration
echo ""
echo "[4/7] Running database migration..."
source .venv/bin/activate
uv run python -m backend.app.migrate_db

# 5. Start Service
echo ""
echo "[5/7] Starting WealthTrack service..."
sudo systemctl start wealthtrack
sudo systemctl status wealthtrack --no-pager

# 6. Firewall
echo ""
echo "[6/7] Configuring UFW firewall..."
for port in 80 443; do
    if sudo ufw status | grep -q "$port/tcp"; then
        echo "  ✓ port $port already allowed — skipping"
    else
        sudo ufw allow "$port/tcp"
        echo "  ✓ port $port allowed"
    fi
done
sudo ufw --force enable 2>/dev/null || true

echo ""
echo "============================================"
echo "  ✅ Deployment Complete!"
echo "  https://wealthtrack.filla.id/api/v1/auth/login"
echo "============================================"
