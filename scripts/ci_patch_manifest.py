#!/usr/bin/env python3
"""CI script: patch AndroidManifest.xml for network permissions.

Called from build-apk.yml after flutter create.
Adds INTERNET permission if missing and usesCleartextTraffic to <application> tag.
"""
import os
import sys

MANIFEST = "android/app/src/main/AndroidManifest.xml"

def patch():
    if not os.path.exists(MANIFEST):
        print(f"ERROR: {MANIFEST} not found")
        sys.exit(1)

    with open(MANIFEST) as f:
        c = f.read()

    changed = False

    # Add INTERNET permission if missing
    if "INTERNET" not in c:
        c = c.replace("<manifest", '<manifest\n    <uses-permission android:name="android.permission.INTERNET"/>')
        changed = True
        print("+ Added INTERNET permission")

    # Add usesCleartextTraffic to application tag if missing
    if 'usesCleartextTraffic' not in c:
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
