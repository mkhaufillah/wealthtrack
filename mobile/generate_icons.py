#!/usr/bin/env python3
"""Generate all app icon sizes for WealthTrack Flutter app.

This script generates the complete Android and iOS icon set from the source logo.
Run this on your DEVELOPMENT MACHINE after 'flutter create'.

Usage:
  python generate_icons.py [--source path/to/logo.png]

Environment:
  source image (white background), output goes to android/ and ios/ dirs
"""

import argparse
import json
import os
import sys
from PIL import Image

# Android mipmap densities and their scale factors (for old-style launcher icons)
ANDROID_LEGACY_SCALES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}

# Adaptive icon: 108dp x 108dp canvas at mdpi base
ADAPTIVE_BASE_SIZE = 108  # dp at mdpi (1x = 108px)
ADAPTIVE_SAFE_ZONE = 0.67  # inner 66% is safe zone (for foreground placement)

# iOS icon sizes (point size x scale => pixel size)
IOS_ICONS = [
    # (size, scale, idiom, role)
    (20, 2, "iphone", "notification"),
    (20, 3, "iphone", "notification"),
    (29, 2, "iphone", "settings"),
    (29, 3, "iphone", "settings"),
    (40, 2, "iphone", "spotlight"),
    (40, 3, "iphone", "spotlight"),
    (60, 2, "iphone", "app"),
    (60, 3, "iphone", "app"),
    (20, 2, "ipad", "notification"),
    (20, 2, "ios-marketing", "app"),  # actually 20x20 marketing
    (29, 2, "ipad", "settings"),
    (29, 2, "ios-marketing", "app"),  # 29x29 marketing
    (40, 2, "ipad", "spotlight"),
    (40, 2, "ios-marketing", "app"),  # 40x40 marketing
    (76, 2, "ipad", "app"),
    (76, 2, "ios-marketing", "app"),
    (83.5, 2, "ipad", "app"),
    (60, 2, "ios-marketing", "app"),
    (60, 3, "ios-marketing", "app"),
    (1024, 1, "ios-marketing", "app-store"),
]


def load_and_prepare(source_path):
    """Load source image, crop to content area, pad to square."""
    img = Image.open(source_path).convert("RGBA")
    w, h = img.size

    # Get bounding box of non-white/non-transparent content
    pixels = img.load()
    min_x, min_y, max_x, max_y = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            is_white = a == 0 or (r > 240 and g > 240 and b > 240)
            if not is_white:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

    if min_x > max_x:
        print("  Warning: no non-white content found, using full image")
        return img

    # Crop to content
    cropped = img.crop((min_x, min_y, max_x + 1, max_y + 1))

    # Pad to square (center content)
    cw, ch = cropped.size
    side = max(cw, ch)
    square = Image.new("RGBA", (side, side), (255, 255, 255, 255))
    x_offset = (side - cw) // 2
    y_offset = (side - ch) // 2
    square.paste(cropped, (x_offset, y_offset), cropped)

    return square


def resize_and_save(img, size_px, output_path):
    """Resize image to exact pixel size and save."""
    resized = img.resize((size_px, size_px), Image.Resampling.LANCZOS)
    # Convert to RGB for non-alpha formats
    output_path = str(output_path)
    resized.save(output_path, "PNG")
    print(f"  ✓ {output_path} ({size_px}x{size_px})")


def generate_android_legacy(img, project_root):
    """Generate legacy mipmap launcher icons (pre-API 26)."""
    base = os.path.join(project_root, "android", "app", "src", "main", "res")
    for density, scale in ANDROID_LEGACY_SCALES.items():
        size = int(48 * scale)  # legacy base size is 48dp
        dir_path = os.path.join(base, f"mipmap-{density}")
        os.makedirs(dir_path, exist_ok=True)
        output_path = os.path.join(dir_path, "ic_launcher.png")
        resize_and_save(img, size, output_path)

        # Round icon (same for simplicity)
        round_path = os.path.join(dir_path, "ic_launcher_round.png")
        resize_and_save(img, size, round_path)


def generate_android_adaptive(img, project_root):
    """Generate Android adaptive icon layers (API 26+)."""
    base = os.path.join(project_root, "android", "app", "src", "main", "res")

    # Create transparent foreground version of the logo
    # First, make white background transparent
    fg_img = img.copy()
    fg_pixels = fg_img.load()
    w, h = fg_img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = fg_pixels[x, y]
            if r > 240 and g > 240 and b > 240:
                fg_pixels[x, y] = (r, g, b, 0)

    # Background color
    bg_color = (45, 52, 74)  # Dark navy #2D344A
    bg_img = Image.new("RGBA", (w, h), bg_color + (255,))

    for density, scale in ANDROID_LEGACY_SCALES.items():
        adaptive_size = int(ADAPTIVE_BASE_SIZE * scale)
        safe_size = int(adaptive_size * ADAPTIVE_SAFE_ZONE)

        # Scale foreground to fit within the safe zone (inner 66%)
        fg_scaled = fg_img.resize((adaptive_size, adaptive_size), Image.Resampling.LANCZOS)
        fg_inner = fg_scaled.resize((safe_size, safe_size), Image.Resampling.LANCZOS)

        # Center on canvas
        content = Image.new("RGBA", (adaptive_size, adaptive_size), (0, 0, 0, 0))
        ox = (adaptive_size - safe_size) // 2
        oy = (adaptive_size - safe_size) // 2
        content.paste(fg_inner, (ox, oy), fg_inner)

        # Save foreground
        fg_dir = os.path.join(base, f"mipmap-{density}")
        os.makedirs(fg_dir, exist_ok=True)
        fg_path = os.path.join(fg_dir, "ic_launcher_foreground.png")
        content.save(fg_path, "PNG")
        print(f"  ✓ {fg_path} ({adaptive_size}x{adaptive_size}, foreground)")

        # Save background (solid color)
    # Resize background
        bg_scaled = bg_img.resize((adaptive_size, adaptive_size), Image.Resampling.LANCZOS)
        bg_path = os.path.join(fg_dir, "ic_launcher_background.png")
        bg_scaled.save(bg_path, "PNG")
        print(f"  ✓ {bg_path} ({adaptive_size}x{adaptive_size}, background)")

    # Create adaptive icon XML definitions
    anydpi_dir = os.path.join(base, "mipmap-anydpi-v26")
    os.makedirs(anydpi_dir, exist_ok=True)

    adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>"""

    for name in ["ic_launcher.xml", "ic_launcher_round.xml"]:
        path = os.path.join(anydpi_dir, name)
        with open(path, "w") as f:
            f.write(adaptive_xml)
        print(f"  ✓ {path}")


def generate_ios_icons(img, project_root):
    """Generate iOS AppIcon sizes."""
    appiconset = os.path.join(
        project_root, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
    )
    os.makedirs(appiconset, exist_ok=True)

    images = []
    for size_pt, scale, idiom, role in IOS_ICONS:
        pixel_size = int(size_pt * scale)
        filename = f"icon-{size_pt}@{scale}x-{idiom}-{role}.png"
        resize_and_save(img, pixel_size, os.path.join(appiconset, filename))

        images.append({
            "size": f"{size_pt}x{size_pt}",
            "idiom": idiom,
            "filename": filename,
            "scale": f"{scale}x",
            "role": role,
        })

    # Deduplicate by (size, idiom, scale, role)
    seen = set()
    unique_images = []
    for img_entry in images:
        key = (img_entry["size"], img_entry["idiom"], img_entry["scale"], img_entry["role"])
        if key not in seen:
            seen.add(key)
            unique_images.append(img_entry)

    contents = {
        "images": unique_images,
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }

    contents_path = os.path.join(appiconset, "Contents.json")
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
    print(f"  ✓ {contents_path}")


def update_pubspec(project_root):
    """Ensure assets are registered in pubspec.yaml."""
    pubspec_path = os.path.join(project_root, "pubspec.yaml")
    with open(pubspec_path, "r") as f:
        content = f.read()

    if "assets:" in content and "assets/logo.png" in content:
        print("  ✓ assets already in pubspec.yaml")
        return

    # Add assets section before the last line
    assets_block = """
flutter:
  uses-material-design: true
  assets:
    - assets/logo.png
"""
    if "flutter:" in content:
        # Replace flutter section
        import re
        content = re.sub(
            r"flutter:\n  uses-material-design: true",
            assets_block.strip(),
            content,
        )
        with open(pubspec_path, "w") as f:
            f.write(content)
        print(f"  ✓ Updated {pubspec_path}")


def main():
    parser = argparse.ArgumentParser(description="Generate app icons for WealthTrack")
    parser.add_argument(
        "--source",
        default="assets/logo.png",
        help="Source logo image (default: assets/logo.png)",
    )
    parser.add_argument(
        "--project-root",
        default=".",
        help="Flutter project root (default: current dir)",
    )
    parser.add_argument(
        "--platforms",
        default="android,ios",
        help="Platforms to generate icons for: android, ios, or both (default: android,ios)",
    )
    args = parser.parse_args()

    project_root = os.path.abspath(args.project_root)
    source_path = os.path.join(project_root, args.source)
    platforms = [p.strip() for p in args.platforms.split(",")]

    print(f"Source: {source_path}")
    print(f"Project root: {project_root}")
    print(f"Platforms: {platforms}")

    if not os.path.exists(source_path):
        print(f"Error: Source image not found: {source_path}")
        sys.exit(1)

    print("\n1. Loading and preparing image...")
    img = load_and_prepare(source_path)
    print(f"   Image size: {img.size}")

    if "android" in platforms:
        print("\n2. Generating Android legacy icons...")
        generate_android_legacy(img, project_root)

        print("\n3. Generating Android adaptive icons...")
        generate_android_adaptive(img, project_root)

    if "ios" in platforms:
        ios_dir = os.path.join(project_root, "ios")
        if not os.path.exists(ios_dir):
            print(f"\n4. Skipping iOS icons — '{ios_dir}' not found")
        else:
            print("\n4. Generating iOS icons...")
            generate_ios_icons(img, project_root)

    print("\n5. Updating pubspec.yaml...")
    update_pubspec(project_root)

    print("\n✅ All icons generated!")
    print("\nNext steps on your development machine:")
    print("  1. Run: flutter pub get")
    print("  2. Run: flutter build apk --debug  (or flutter build ios)")
    print("  3. Or run directly: flutter run")


if __name__ == "__main__":
    main()
