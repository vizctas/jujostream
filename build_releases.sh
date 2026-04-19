#!/bin/bash

# ──────────────────────────────────────────────────────────────────
# Jujo Client — Release Build Script
# Builds: Android APK, Android AppBundle, macOS App
# ──────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Environment ──────────────────────────────────────────────────
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Documents/android-sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# ── Validation ──��────────────────────────────────────────────────
if ! command -v flutter &>/dev/null; then
    echo "ERROR: flutter not found in PATH"
    exit 1
fi

if ! "$JAVA_HOME/bin/java" -version &>/dev/null; then
    echo "ERROR: Java not found at JAVA_HOME=$JAVA_HOME"
    exit 1
fi

FAILURES=0

echo "========================================"
echo " Starting Jujo Client Release Builds"
echo " Java:    $("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
echo " Flutter: $(flutter --version | head -1)"
echo "========================================"

# ── Step 1: Android APK ─────────────────────────────────────────
echo ""
echo "[1/3] Building Android APK (Release)..."
if flutter build apk --release; then
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    if [[ -f "$APK_PATH" ]]; then
        APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
        echo "  ✅ APK: $APK_PATH ($APK_SIZE)"
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
        AAB_SIZE=$(du -h "$AAB_PATH" | cut -f1)
        echo "  ✅ AAB: $AAB_PATH ($AAB_SIZE)"
    fi
else
    echo "  ⚠️  AppBundle build had issues (check warnings above)"
    # Check if AAB was generated despite the warning
    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    if [[ -f "$AAB_PATH" ]]; then
        AAB_SIZE=$(du -h "$AAB_PATH" | cut -f1)
        echo "  ✅ AAB was still generated: $AAB_PATH ($AAB_SIZE)"
    else
        echo "  ❌ AAB was NOT generated"
        FAILURES=$((FAILURES + 1))
    fi
fi

# ── Step 3: macOS ────────────────────────────────────────────────
echo ""
if [[ "$(uname)" == "Darwin" ]]; then
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
    echo "[3/3] Skipping macOS build (not on macOS — detected: $(uname))"
fi

# ── Summary ──────────────────────────────────────────────────────
echo ""
echo "========================================"
if [[ $FAILURES -eq 0 ]]; then
    echo " ✅ All builds completed successfully!"
else
    echo " ⚠️  Completed with $FAILURES failure(s)"
fi
echo "========================================"

exit $FAILURES
