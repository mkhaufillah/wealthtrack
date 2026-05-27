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

# 2. Nginx Config
echo ""
echo "[2/7] Configuring Nginx..."
sudo cp deploy/wealthtrack.nginx /etc/nginx/sites-available/wealthtrack
sudo ln -sf /etc/nginx/sites-available/wealthtrack /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

# 3. Run Migration
echo ""
echo "[3/7] Running database migration..."
source .venv/bin/activate
uv run python -m backend.app.migrate_db

# 4. Start Service
echo ""
echo "[4/7] Starting WealthTrack service..."
sudo systemctl start wealthtrack
sudo systemctl status wealthtrack --no-pager

# 5. SSL Certificate
echo ""
echo "[5/7] Requesting SSL certificate from Let's Encrypt..."
sudo certbot --nginx -d wealthtrack.filla.id --non-interactive --agree-tos -m khaufillahmohammad@gmail.com
sudo systemctl reload nginx

# 6. Firewall
echo ""
echo "[6/7] Configuring UFW firewall..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

echo ""
echo "============================================"
echo "  ✅ Deployment Complete!"
echo "  https://wealthtrack.filla.id/api/v1/auth/login"
echo "============================================"
