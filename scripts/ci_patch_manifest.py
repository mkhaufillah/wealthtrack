#!/usr/bin/env python3
"""CI script: patch AndroidManifest.xml for network permissions.

Called from build-apk.yml after flutter create.
Adds INTERNET permission if missing and usesCleartextTraffic to <application> tag.
Uses proper XML insertion (after manifest opening tag, before application tag).
"""
import os
import sys
import re

MANIFEST = "android/app/src/main/AndroidManifest.xml"


def patch():
    if not os.path.exists(MANIFEST):
        print(f"ERROR: {MANIFEST} not found")
        sys.exit(1)

    with open(MANIFEST) as f:
        c = f.read()

    changed = False

    # Add INTERNET permission after the <manifest ...> opening tag
    if "INTERNET" not in c:
        # Match <manifest ...> and insert permission after it
        c = re.sub(
            r'(<manifest[^>]*>)',
            r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
            c,
            count=1,
        )
        changed = True
        print("+ Added INTERNET permission")

    # Add usesCleartextTraffic to <application> tag if missing
    if "usesCleartextTraffic" not in c:
        c = c.replace("<application", '<application android:usesCleartextTraffic="true"')
        changed = True
        print('+ Added usesCleartextTraffic="true"')

    if not changed:
        print("✅ Manifest already has network permissions")
    else:
        with open(MANIFEST, "w") as f:
            f.write(c)
        print("✅ Manifest patched")


if __name__ == "__main__":
    patch()
