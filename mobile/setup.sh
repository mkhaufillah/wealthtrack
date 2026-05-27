#!/bin/bash
# WealthTrack Flutter — Setup Script
# Run this on your DEVELOPMENT MACHINE (not VPS).
# Prerequisites: Flutter SDK installed

set -e
cd "$(dirname "$0")"

echo "=== WealthTrack Flutter Setup ==="
echo ""

# Step 1: Create Flutter project (generates android/, ios/, web/)
echo "[1/3] Creating Flutter project structure..."
flutter create --project-name wealthtrack --org com.filla --platforms android,ios .
echo "  ✓ Project structure created"

# Step 2: Install dependencies
echo ""
echo "[2/3] Installing dependencies..."
flutter pub get
echo "  ✓ Dependencies installed"

# Step 3: Verify
echo ""
echo "[3/3] Verifying..."
dart analyze lib/
echo ""
echo "=== ✅ Setup Complete ==="
echo "Run: flutter run"
echo "Build APK: flutter build apk --debug"
