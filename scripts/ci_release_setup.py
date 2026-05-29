#!/usr/bin/env python3
"""CI script: setup release signing for Flutter Android build.

Called from build-apk.yml after flutter create.
1. Decodes keystore from env var
2. Writes key.properties
3. Patches android/app/build.gradle with signing config
"""
import os
import sys
import base64

ANDROID_DIR = "android"
APP_DIR = os.path.join(ANDROID_DIR, "app")
KEYSTORE_FILE = "wealthtrack.p12"
KEY_PROPS = "key.properties"

def setup_keystore():
    """Decode base64 keystore from KEYSTORE_BASE64 env var."""
    b64 = os.environ.get("KEYSTORE_BASE64")
    if not b64:
        print("ERROR: KEYSTORE_BASE64 env var not set")
        sys.exit(1)
    os.makedirs(APP_DIR, exist_ok=True)
    keystore_path = os.path.join(APP_DIR, KEYSTORE_FILE)
    with open(keystore_path, "wb") as f:
        f.write(base64.b64decode(b64))
    print(f"Keystore written: {keystore_path}")

def write_key_properties():
    """Write key.properties from env vars."""
    store_password = os.environ.get("KEYSTORE_PASSWORD", "")
    key_alias = os.environ.get("KEY_ALIAS", "")
    key_password = os.environ.get("KEY_PASSWORD", "")

    props_path = os.path.join(ANDROID_DIR, KEY_PROPS)
    with open(props_path, "w") as f:
        f.write(f"storeFile={KEYSTORE_FILE}\n")
        f.write(f"storePassword={store_password}\n")
        f.write(f"keyAlias={key_alias}\n")
        f.write(f"keyPassword={key_password}\n")
    print(f"key.properties written: {props_path}")

def patch_build_gradle():
    """Patch android/app/build.gradle with release signing config."""
    gradle_path = os.path.join(APP_DIR, "build.gradle")
    if not os.path.exists(gradle_path):
        print(f"ERROR: {gradle_path} not found — run flutter create first")
        sys.exit(1)

    with open(gradle_path) as f:
        content = f.read()

    # 1. Add keystore properties loading after apply plugin lines
    keystore_header = """
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
"""
    # Insert after last "apply plugin:" line
    apply_lines = []
    for i, line in enumerate(content.split("\n")):
        if line.strip().startswith("apply plugin:"):
            apply_lines.append(i)
    if apply_lines:
        last_apply = apply_lines[-1]
        lines = content.split("\n")
        lines.insert(last_apply + 1, "")
        lines.insert(last_apply + 2, keystore_header.strip())
        content = "\n".join(lines)

    # 2. Add signingConfigs block and patch buildTypes
    # Replace default buildTypes block
    old_build_types = """    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now,
            // so `flutter run --release` works.
            signingConfig signingConfigs.debug
        }
    }"""

    new_build_types = """    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }"""

    if old_build_types in content:
        content = content.replace(old_build_types, new_build_types)
        print("Patched: signingConfigs + release signingConfig")
    else:
        print("WARNING: Could not find default buildTypes block — manual check needed")
        print("--- current build.gradle ---")
        print(content)
        print("--- end ---")

    with open(gradle_path, "w") as f:
        f.write(content)

if __name__ == "__main__":
    setup_keystore()
    write_key_properties()
    patch_build_gradle()
    print("Release signing setup complete.")
