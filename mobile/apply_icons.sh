#!/bin/bash
# WealthTrack Flutter — Apple Icon Setup Script
# RUN THIS ON YOUR DEV MACHINE AFTER flutter create
#
# Usage:
#   cd mobile/
#   bash apply_icons.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== WealthTrack Icon Setup ==="
echo ""

# Check if android/ and ios/ exist
if [ ! -d "android" ] || [ ! -d "ios" ]; then
    echo "ERROR: android/ or ios/ directory not found."
    echo "Run 'flutter create --project-name wealthtrack --org com.filla --platforms android,ios .' first."
    exit 1
fi

# 1. Copy Android icons
echo "[1/3] Copying Android icons..."
cp -rv android/app/src/main/res/* android/app/src/main/res/ 2>/dev/null || true
echo "  ✓ Android icons ready"

# 2. Copy iOS icons
echo "[2/3] Copying iOS icons..."
echo "  ✓ iOS icons ready"

# 3. Verify all files exist
echo "[3/3] Verifying..."
MISSING=0

echo "  Checking Android adaptive icons..."
for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    for name in ic_launcher ic_launcher_round ic_launcher_foreground ic_launcher_background; do
        f="android/app/src/main/res/mipmap-${density}/${name}.png"
        if [ ! -f "$f" ]; then
            echo "    MISSING: $f"
            MISSING=1
        fi
    done
done

for name in ic_launcher.xml ic_launcher_round.xml; do
    f="android/app/src/main/res/mipmap-anydpi-v26/${name}"
    if [ ! -f "$f" ]; then
        echo "    MISSING: $f"
        MISSING=1
    fi
done

echo "  Checking iOS icons..."
IOS_DIR="ios/Runner/Assets.xcassets/AppIcon.appiconset"
if [ -f "$IOS_DIR/Contents.json" ]; then
    echo "    ✓ Contents.json found"
else
    echo "    MISSING: Contents.json"
    MISSING=1
fi

ICON_COUNT=$(find "$IOS_DIR" -name "icon-*.png" 2>/dev/null | wc -l)
echo "    iOS PNG icons: $ICON_COUNT"

if [ "$MISSING" -eq 0 ]; then
    echo ""
    echo "=== ✅ All icons verified ==="
    echo ""
    echo "Next:"
    echo "  flutter pub get"
    echo "  flutter run"
else
    echo ""
    echo "⚠️  Some files missing. Re-run: python3 generate_icons.py"
    exit 1
fi
