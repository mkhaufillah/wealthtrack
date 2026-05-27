#!/bin/bash
# WealthTrack Flutter — Setup Script
# Run this on your DEVELOPMENT MACHINE (not VPS).
# Prerequisites: Flutter SDK installed

set -e
cd "$(dirname "$0")"

echo "=== WealthTrack Flutter Setup ==="
echo ""

# Step 1: Create Flutter project (generates android/, ios/, web/)
echo "[1/4] Creating Flutter project structure..."
flutter create --project-name wealthtrack --org com.filla --platforms android,ios .
echo "  ✓ Project structure created"

# Step 2: Apply app icon
echo ""
echo "[2/4] Applying app icon..."
if [ -f "generate_icons.py" ]; then
    python3 generate_icons.py
else
    echo "  ⚠️  generate_icons.py not found, skipping icon setup"
fi
echo "  ✓ App icon applied"

# Step 3: Install dependencies
echo ""
echo "[3/4] Installing dependencies..."
flutter pub get
echo "  ✓ Dependencies installed"

# Step 4: Verify
echo ""
echo "[4/4] Verifying..."
dart analyze lib/
echo ""
echo "=== ✅ Setup Complete ==="
echo "Run: flutter run"
echo "Build APK: flutter build apk --debug"
