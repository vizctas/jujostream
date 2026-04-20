#!/usr/bin/env bash

# ──────────────────────────────────────────────────────────────────
# Jujo Client — Release Build Script (Cross-Platform)
# Builds: Android APK, Android AppBundle, macOS App
# Works on: macOS (ARM/Intel), Windows (Git Bash / WSL), Linux
# ──────────────────────────────────────────────────────────────────

set -euo pipefail

# ── OS Detection ─────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Darwin)  PLATFORM="macos" ;;
    Linux)   PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    *)       PLATFORM="unknown" ;;
esac

# ── JAVA_HOME Auto-Detection ────────────────────────────────────
# Priority: env var > common locations per OS
resolve_java_home() {
    # If already set and valid, use it
    if [[ -n "${JAVA_HOME:-}" ]] && [[ -x "$JAVA_HOME/bin/java" ]]; then
        return 0
    fi

    local candidates=()

    case "$PLATFORM" in
        macos)
            # Homebrew ARM (Apple Silicon)
            candidates+=("/opt/homebrew/opt/openjdk@21")
            candidates+=("/opt/homebrew/opt/openjdk@17")
            candidates+=("/opt/homebrew/opt/openjdk")
            # Homebrew Intel
            candidates+=("/usr/local/opt/openjdk@21")
            candidates+=("/usr/local/opt/openjdk@17")
            candidates+=("/usr/local/opt/openjdk")
            # macOS java_home utility
            if /usr/libexec/java_home &>/dev/null; then
                candidates+=("$(/usr/libexec/java_home 2>/dev/null)")
            fi
            ;;
        windows)
            # Common Windows JDK paths (via Git Bash / MSYS2)
            for jdk_dir in "/c/Program Files/Java"/jdk-* "/c/Program Files/Eclipse Adoptium"/jdk-* "$LOCALAPPDATA/Programs"/jdk-* ; do
                [[ -d "$jdk_dir" ]] && candidates+=("$jdk_dir")
            done
            # Android Studio bundled JDK
            candidates+=("$LOCALAPPDATA/Android/Sdk/jbr" "$HOME/AppData/Local/Android/Sdk/jbr")
            ;;
        linux)
            candidates+=("/usr/lib/jvm/java-21-openjdk-amd64")
            candidates+=("/usr/lib/jvm/java-17-openjdk-amd64")
            candidates+=("/usr/lib/jvm/default-java")
            # SDKMAN
            for jdk_dir in "$HOME/.sdkman/candidates/java"/*/; do
                [[ -d "$jdk_dir" ]] && candidates+=("$jdk_dir")
            done
            ;;
    esac

    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate/bin/java" ]]; then
            export JAVA_HOME="$candidate"
            return 0
        fi
    done

    return 1
}

# ── ANDROID_HOME Auto-Detection ─────────────────────────────────
resolve_android_home() {
    # If already set and valid, use it
    if [[ -n "${ANDROID_HOME:-}" ]] && [[ -d "$ANDROID_HOME/platform-tools" ]]; then
        return 0
    fi

    local candidates=()

    case "$PLATFORM" in
        macos)
            candidates+=("$HOME/Documents/android-sdk")
            candidates+=("$HOME/Library/Android/sdk")
            ;;
        windows)
            candidates+=("$LOCALAPPDATA/Android/Sdk")
            candidates+=("$HOME/AppData/Local/Android/Sdk")
            candidates+=("$HOME/Documents/android-sdk")
            ;;
        linux)
            candidates+=("$HOME/Android/Sdk")
            candidates+=("$HOME/android-sdk")
            candidates+=("$HOME/Documents/android-sdk")
            ;;
    esac

    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate/platform-tools" ]]; then
            export ANDROID_HOME="$candidate"
            return 0
        fi
    done

    return 1
}

# ── Resolve Environment ─────────────────────────────────────────
if ! resolve_java_home; then
    echo "ERROR: Could not find a valid JDK installation."
    echo "  Set JAVA_HOME manually or install OpenJDK 17/21."
    exit 1
fi

if ! resolve_android_home; then
    echo "ERROR: Could not find Android SDK."
    echo "  Set ANDROID_HOME manually or install via Android Studio / sdkmanager."
    exit 1
fi

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# ── Validation ───────────────────────────────────────────────────
if ! command -v flutter &>/dev/null; then
    echo "ERROR: flutter not found in PATH"
    exit 1
fi

if ! "$JAVA_HOME/bin/java" -version &>/dev/null; then
    echo "ERROR: Java not working at JAVA_HOME=$JAVA_HOME"
    exit 1
fi

# ── Android Signing Pre-Check ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_PROPS="$SCRIPT_DIR/android/key.properties"

if [[ ! -f "$KEY_PROPS" ]]; then
    echo "ERROR: android/key.properties not found."
    echo "  Release builds require a signing config."
    echo "  Copy android/key.properties.example → android/key.properties"
    echo "  and fill in your keystore details."
    exit 1
fi

# Validate keystore file exists (read storeFile from key.properties)
STORE_FILE=$(grep -E '^\s*storeFile\s*=' "$KEY_PROPS" | sed 's/.*=\s*//' | tr -d '[:space:]')
if [[ -n "$STORE_FILE" ]]; then
    # Resolve relative path from android/ directory
    if [[ "$STORE_FILE" != /* ]] && [[ "$STORE_FILE" != [A-Z]:* ]]; then
        STORE_FILE_ABS="$SCRIPT_DIR/android/$STORE_FILE"
    else
        STORE_FILE_ABS="$STORE_FILE"
    fi
    if [[ ! -f "$STORE_FILE_ABS" ]]; then
        echo "ERROR: Keystore file not found: $STORE_FILE"
        echo "  Resolved to: $STORE_FILE_ABS"
        exit 1
    fi
fi

# ── File Size (cross-platform) ──────────────────────────────────
# macOS `du -h` and GNU `du -h` behave the same for this use case,
# but `stat` differs. We use `du -h` which is POSIX-compatible.
file_size() {
    du -h "$1" 2>/dev/null | cut -f1 | tr -d '[:space:]'
}

FAILURES=0

echo "========================================"
echo " Jujo Client — Release Builds"
echo " Platform: $PLATFORM ($ARCH)"
echo " Java:     $("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
echo " Flutter:  $(flutter --version --machine 2>/dev/null | grep -o '"frameworkVersion":"[^"]*"' | cut -d'"' -f4 || flutter --version 2>&1 | head -1)"
echo " Android:  $ANDROID_HOME"
echo "========================================"

# ── Step 1: Android APK ─────────────────────────────────────────
echo ""
echo "[1/3] Building Android APK (Release)..."
if flutter build apk --release; then
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    if [[ -f "$APK_PATH" ]]; then
        echo "  ✅ APK: $APK_PATH ($(file_size "$APK_PATH"))"
    fi
else
    echo "  ❌ APK build failed"
    FAILURES=$((FAILURES + 1))
fi

# ── Step 2: Android AppBundle ────────────────────────────────────
echo ""
echo "[2/3] Building Android AppBundle (Release)..."
if flutter build appbundle --release; then
    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    if [[ -f "$AAB_PATH" ]]; then
        echo "  ✅ AAB: $AAB_PATH ($(file_size "$AAB_PATH"))"
    fi
else
    echo "  ⚠️  AppBundle build had issues (check warnings above)"
    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    if [[ -f "$AAB_PATH" ]]; then
        echo "  ✅ AAB was still generated: $AAB_PATH ($(file_size "$AAB_PATH"))"
    else
        echo "  ❌ AAB was NOT generated"
        FAILURES=$((FAILURES + 1))
    fi
fi

# ── Step 3: macOS ────────────────────────────────────────────────
echo ""
if [[ "$PLATFORM" == "macos" ]]; then
    echo "[3/3] Building macOS (Release)..."
    if flutter build macos --release; then
        APP_PATH="build/macos/Build/Products/Release"
        if [[ -d "$APP_PATH" ]]; then
            echo "  ✅ macOS: $APP_PATH/"
        fi
    else
        echo "  ❌ macOS build failed"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "[3/3] Skipping macOS build (not on macOS — detected: $PLATFORM)"
fi

# ── Summary ───────────────────────────────��──────────────────────
echo ""
echo "========================================"
if [[ $FAILURES -eq 0 ]]; then
    echo " ✅ All builds completed successfully!"
else
    echo " ⚠️  Completed with $FAILURES failure(s)"
fi
echo "========================================"

exit $FAILURES
