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
import re
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
ADAPTIVE_SAFE_ZONE = 0.55  # keep mascot inside OneUI extra crop; no baked plate

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


def load_and_prepare(source_path, padding=0.12):
    """Load source image, crop to content area, pad to square with breathing room."""
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
    cw, ch = cropped.size

    # Scale down to add padding (breathing room) around the content
    scale_factor = 1 - 2 * padding
    scaled_cw = max(1, int(cw * scale_factor))
    scaled_ch = max(1, int(ch * scale_factor))
    scaled = cropped.resize((scaled_cw, scaled_ch), Image.Resampling.LANCZOS)

    # Pad to square on a TRANSPARENT canvas. Never bake a white/peach plate —
    # Samsung OneUI masks adaptive icons and a baked plate becomes a double-box.
    side = max(cw, ch)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    x_offset = (side - scaled_cw) // 2
    y_offset = (side - scaled_ch) // 2
    square.paste(scaled, (x_offset, y_offset), scaled)

    return square


PEACH = (255, 232, 220)  # #FFE8DC


def _is_plate_pixel(r, g, b, a) -> bool:
    if a == 0:
        return True
    if r > 228 and g > 228 and b > 228:
        return True
    if abs(r - PEACH[0]) < 18 and abs(g - PEACH[1]) < 22 and abs(b - PEACH[2]) < 22:
        return True
    mx, mn = max(r, g, b), min(r, g, b)
    if mx > 200 and (mx - mn) < 40 and a < 255:
        return True
    return False


def knock_out_plate(img: Image.Image) -> Image.Image:
    """Mascot-only RGBA. Drops white/peach plates and gray defringe from bg removal."""
    fg = img.convert("RGBA")
    px = fg.load()
    w, h = fg.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if _is_plate_pixel(r, g, b, a):
                px[x, y] = (r, g, b, 0)
    bbox = fg.getbbox()
    return fg.crop(bbox) if bbox else fg


def composite_on_peach(mascot: Image.Image, size_px: int) -> Image.Image:
    canvas = Image.new("RGBA", (size_px, size_px), PEACH + (255,))
    art = knock_out_plate(mascot)
    factor = size_px / max(art.size)
    fw = max(1, int(art.size[0] * factor))
    fh = max(1, int(art.size[1] * factor))
    inner = art.resize((fw, fh), Image.Resampling.LANCZOS)
    canvas.paste(inner, ((size_px - fw) // 2, (size_px - fh) // 2), inner)
    return canvas


def resize_and_save(img, size_px, output_path):
    """Resize image to exact pixel size and save."""
    resized = img.resize((size_px, size_px), Image.Resampling.LANCZOS)
    # Convert to RGB for non-alpha formats
    output_path = str(output_path)
    resized.save(output_path, "PNG")
    print(f"  V {output_path} ({size_px}x{size_px})")


def generate_android_legacy(img, project_root):
    """Generate legacy mipmap launcher icons (pre-API 26)."""
    base = os.path.join(project_root, "android", "app", "src", "main", "res")
    for density, scale in ANDROID_LEGACY_SCALES.items():
        size = int(48 * scale)  # legacy base size is 48dp
        dir_path = os.path.join(base, f"mipmap-{density}")
        os.makedirs(dir_path, exist_ok=True)
        legacy = composite_on_peach(img, size)
        output_path = os.path.join(dir_path, "ic_launcher.png")
        legacy.save(output_path, "PNG")
        print(f"  V {output_path} ({size}x{size})")
        round_path = os.path.join(dir_path, "ic_launcher_round.png")
        legacy.save(round_path, "PNG")
        print(f"  V {round_path} ({size}x{size})")


def generate_android_adaptive(img, project_root):
    """Generate Android adaptive icon layers (API 26+).

    Adaptive icons MUST be full-bleed: the OS masks the canvas to a squircle /
    circle. A foreground image that carries its own rounded-square background
    shows a visible box behind the mask (double-box on Samsung OneUI).
    Foreground = mascot art scaled into the 66% safe zone on TRANSPARENT canvas.
    Background = solid brand peach, edge to edge.
    """
    base = os.path.join(project_root, "android", "app", "src", "main", "res")

    # Mascot art only on transparent canvas. OS supplies the peach plate.
    fg_img = knock_out_plate(img)

    for density, scale in ANDROID_LEGACY_SCALES.items():
        adaptive_size = int(ADAPTIVE_BASE_SIZE * scale)
        safe_size = int(adaptive_size * ADAPTIVE_SAFE_ZONE)

        # Scale art (not the whole padded square) to fit within the safe zone
        art_w, art_h = fg_img.size
        factor = safe_size / max(art_w, art_h)
        fw = max(1, int(art_w * factor))
        fh = max(1, int(art_h * factor))
        fg_inner = fg_img.resize((fw, fh), Image.Resampling.LANCZOS)

        # Center on canvas
        content = Image.new("RGBA", (adaptive_size, adaptive_size), (0, 0, 0, 0))
        ox = (adaptive_size - fw) // 2
        oy = (adaptive_size - fh) // 2
        content.paste(fg_inner, (ox, oy), fg_inner)

        # Save foreground
        fg_dir = os.path.join(base, f"mipmap-{density}")
        os.makedirs(fg_dir, exist_ok=True)
        fg_path = os.path.join(fg_dir, "ic_launcher_foreground.png")
        content.save(fg_path, "PNG")
        print(f"  V {fg_path} ({adaptive_size}x{adaptive_size}, foreground)")

        bg_scaled = Image.new("RGBA", (adaptive_size, adaptive_size), PEACH + (255,))
        bg_path = os.path.join(fg_dir, "ic_launcher_background.png")
        bg_scaled.save(bg_path, "PNG")
        print(f"  V {bg_path} ({adaptive_size}x{adaptive_size}, background)")

    # Create adaptive icon XML definitions
    anydpi_dir = os.path.join(base, "mipmap-anydpi-v26")
    os.makedirs(anydpi_dir, exist_ok=True)

    adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>"""

    for name in ["ic_launcher.xml", "ic_launcher_round.xml"]:
        path = os.path.join(anydpi_dir, name)
        with open(path, "w") as f:
            f.write(adaptive_xml)
        print(f"  V {path}")


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
    print(f"  V {contents_path}")


def update_pubspec(project_root):
    """Ensure assets/logo.png is registered in pubspec.yaml, without duplicates."""
    pubspec_path = os.path.join(project_root, "pubspec.yaml")
    with open(pubspec_path, "r") as f:
        content = f.read()

    if "assets/logo.png" in content:
        print("  V assets/logo.png already in pubspec.yaml")
        return

    # Find the existing assets: line and append logo.png
    # Match the assets: line through to end of its list (indented items following it)
    if re.search(r"^  assets:", content, re.MULTILINE):
        # Already has an assets section -- append to it
        content = re.sub(
            r"^(  assets:.*?)(?=\n\S|\Z)",
            lambda m: m.group(1) + "\n    - assets/logo.png",
            content,
            count=1,
            flags=re.DOTALL,
        )
    else:
        # No assets section -- add one inside the flutter: block
        # Find the flutter: block and add assets after uses-material-design
        content = re.sub(
            r"(  uses-material-design: true\n)",
            lambda m: m.group(1) + "  assets:\n    - assets/logo.png\n",
            content,
            count=1,
        )

    with open(pubspec_path, "w") as f:
        f.write(content)
    print(f"  V Updated {pubspec_path}")


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

    mark_path = os.path.join(project_root, "assets", "logo_mark.png")
    mark = knock_out_plate(Image.open(source_path))
    # Small transparent pad so dark-mode login doesn't clip fringe.
    pad = max(8, int(max(mark.size) * 0.04))
    padded = Image.new("RGBA", (mark.size[0] + 2 * pad, mark.size[1] + 2 * pad), (0, 0, 0, 0))
    padded.paste(mark, (pad, pad), mark)
    os.makedirs(os.path.dirname(mark_path), exist_ok=True)
    padded.save(mark_path, "PNG")
    print(f"   V {mark_path} ({padded.size[0]}x{padded.size[1]}, transparent mark)")

    if "android" in platforms:
        print("\n2. Generating Android legacy icons...")
        generate_android_legacy(img, project_root)

        print("\n3. Generating Android adaptive icons...")
        generate_android_adaptive(img, project_root)

    if "ios" in platforms:
        ios_dir = os.path.join(project_root, "ios")
        if not os.path.exists(ios_dir):
            print(f"\n4. Skipping iOS icons -- '{ios_dir}' not found")
        else:
            print("\n4. Generating iOS icons...")
            generate_ios_icons(img, project_root)

    print("\n5. Updating pubspec.yaml...")
    update_pubspec(project_root)

    print("\nDone! All icons generated.")
    print("\nNext steps on your development machine:")
    print("  1. Run: flutter pub get")
    print("  2. Run: flutter build apk --debug  (or flutter build ios)")
    print("  3. Or run directly: flutter run")


if __name__ == "__main__":
    main()
