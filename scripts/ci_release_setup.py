#!/usr/bin/env python3
"""CI script: setup release signing for Flutter Android build.

Called from build-apk.yml after flutter create.
1. Decodes keystore from env var
2. Writes key.properties
3. Patches android/app/build.gradle(.kts) with signing config

Supports both Groovy DSL (.gradle) and Kotlin DSL (.gradle.kts).
"""
import os
import sys
import base64

ANDROID_DIR = "android"
APP_DIR = os.path.join(ANDROID_DIR, "app")
KEYSTORE_FILE = "wealthtrack.p12"
KEY_PROPS = "key.properties"


def find_gradle_file():
    """Find the app-level build.gradle (Groovy or Kotlin DSL)."""
    for name in ["build.gradle", "build.gradle.kts"]:
        path = os.path.join(APP_DIR, name)
        if os.path.exists(path):
            return path
    return None


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


def patch_gradle_groovy(gradle_path):
    """Patch Groovy DSL build.gradle with release signing config."""
    with open(gradle_path) as f:
        content = f.read()

    # 1. Add keystore properties loading after last 'apply plugin:' line
    keystore_header = """
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
"""
    apply_lines = [
        i for i, line in enumerate(content.split("\n"))
        if line.strip().startswith("apply plugin:")
    ]
    if apply_lines:
        last_apply = apply_lines[-1]
        lines = content.split("\n")
        lines.insert(last_apply + 1, "")
        lines.insert(last_apply + 2, keystore_header.strip())
        content = "\n".join(lines)

    # 2. Replace default buildTypes block with signingConfigs + release signing
    old_block = """    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now,
            // so `flutter run --release` works.
            signingConfig signingConfigs.debug
        }
    }"""

    new_block = """    signingConfigs {
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

    if old_block in content:
        content = content.replace(old_block, new_block)
        print(f"Patched {gradle_path} (Groovy DSL)")
    else:
        print(f"WARNING: Could not find default buildTypes block in {gradle_path}")
        print("--- current file ---")
        print(content)
        print("--- end ---")

    with open(gradle_path, "w") as f:
        f.write(content)


def patch_gradle_kts(gradle_path):
    """Patch Kotlin DSL build.gradle.kts with release signing config."""
    with open(gradle_path) as f:
        content = f.read()

    # 1. Add keystore properties loading after plugins block
    keystore_imports = """import java.io.FileInputStream
import java.util.Properties

"""
    keystore_block = """
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
"""
    # Insert imports after any existing imports (or at start)
    import_lines = [
        i for i, line in enumerate(content.split("\n"))
        if line.strip().startswith("import ")
    ]
    if import_lines:
        last_import = import_lines[-1]
        lines = content.split("\n")
        lines.insert(last_import + 1, "")
        lines.insert(last_import + 2, keystore_imports.strip())
        content = "\n".join(lines)

    # Insert keystoreBlock after plugins block (before android block)
    # Look for the closing of plugins block: the last line with just '}'
    lines = content.split("\n")
    plugin_end = -1
    for i, line in enumerate(lines):
        if line.strip() == "}" and i > 0 and "plugins" in lines[i-1].lower():
            plugin_end = i
    if plugin_end >= 0:
        lines.insert(plugin_end + 1, "")
        lines.insert(plugin_end + 2, keystore_block.strip())
        content = "\n".join(lines)

    # 2. Add signingConfigs and patch buildTypes
    old_block = """    buildTypes {
        getByName("release") {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now,
            // so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }"""

    new_block = """    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"].toString()
            keyPassword = keystoreProperties["keyPassword"].toString()
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"].toString()
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
    }"""

    if old_block in content:
        content = content.replace(old_block, new_block)
        print(f"Patched {gradle_path} (Kotlin DSL)")
    else:
        # Try alternative block format (no comments)
        old_block_alt = """    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }"""
        if old_block_alt in content:
            content = content.replace(old_block_alt, """    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"].toString()
            keyPassword = keystoreProperties["keyPassword"].toString()
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"].toString()
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
    }""")
            print(f"Patched {gradle_path} (Kotlin DSL, alt block)")
        else:
            print(f"WARNING: Could not find default buildTypes block in {gradle_path}")
            print("--- current file ---")
            print(content)
            print("--- end ---")

    with open(gradle_path, "w") as f:
        f.write(content)


def patch_build_gradle():
    """Detect DSL variant and patch accordingly."""
    gradle_path = find_gradle_file()
    if not gradle_path:
        print("ERROR: No build.gradle file found in android/app/ — run flutter create first")
        sys.exit(1)

    if gradle_path.endswith(".kts"):
        patch_gradle_kts(gradle_path)
    else:
        patch_gradle_groovy(gradle_path)


if __name__ == "__main__":
    setup_keystore()
    write_key_properties()
    patch_build_gradle()
    print("Release signing setup complete.")
