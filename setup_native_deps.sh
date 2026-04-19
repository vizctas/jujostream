#!/bin/bash
# ============================================================================
# setup_native_deps.sh - Download and build native dependencies
#
# This script sets up OpenSSL and libopus for Android NDK compilation.
# Run this once before building the Flutter app.
#
# Usage: ./setup_native_deps.sh
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_DIR="$SCRIPT_DIR/android/app/src/main/cpp"
DEPS_DIR="$CPP_DIR/deps"
ABIS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")

get_cpu_count() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 2
    fi
}

CPU_COUNT="$(get_cpu_count)"
TMP_WORK_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t native_deps)"
trap 'rm -rf "$TMP_WORK_DIR"' EXIT

# Detect NDK
if [ -z "$ANDROID_NDK_HOME" ] && [ -n "$NDK_HOME" ]; then
    ANDROID_NDK_HOME="$NDK_HOME"
fi

if [ -z "$ANDROID_NDK_HOME" ]; then
    # Try common locations
    if [ -n "$ANDROID_SDK_ROOT" ] && [ -d "$ANDROID_SDK_ROOT/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$ANDROID_SDK_ROOT/ndk/"* 2>/dev/null | sort -V | tail -1)
    elif [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$ANDROID_HOME/ndk/"* 2>/dev/null | sort -V | tail -1)
    elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
    elif [ -d "$HOME/Android/Sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Android/Sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
    elif [ -d "$LOCALAPPDATA/Android/Sdk/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$LOCALAPPDATA/Android/Sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
    fi
fi

if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "ERROR: Android NDK not found. Set ANDROID_NDK_HOME environment variable."
    echo "Example: export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/27.0.12077973"
    exit 1
fi

echo "Using NDK: $ANDROID_NDK_HOME"
echo "Dependencies dir: $DEPS_DIR"

mkdir -p "$DEPS_DIR"

NDK_PREBUILT_DIR="$(ls -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/"* 2>/dev/null | head -1)"
if [ -z "$NDK_PREBUILT_DIR" ] || [ ! -d "$NDK_PREBUILT_DIR" ]; then
    echo "ERROR: NDK LLVM toolchain prebuilt directory not found."
    echo "Expected under: $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/"
    exit 1
fi

echo "Using toolchain: $NDK_PREBUILT_DIR"

# ============================================================================
# OpenSSL
# ============================================================================
echo ""
echo "========================================="
echo "Setting up OpenSSL for Android"
echo "========================================="

OPENSSL_VERSION="3.3.1"
OPENSSL_DIR="$DEPS_DIR/openssl"

if [ -f "$OPENSSL_DIR/arm64-v8a/libssl.a" ]; then
    echo "OpenSSL already built. Skipping."
else
    echo "Downloading OpenSSL $OPENSSL_VERSION..."
    cd "$TMP_WORK_DIR"
    curl -LO "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" 2>/dev/null || {
        echo "WARNING: Could not download OpenSSL."
        echo "You can manually place pre-built OpenSSL libraries at:"
        echo "  $OPENSSL_DIR/<abi>/libssl.a"
        echo "  $OPENSSL_DIR/<abi>/libcrypto.a"
        echo "  $OPENSSL_DIR/include/openssl/*.h"
        echo ""
        echo "Alternative: Copy from the original jujostream project:"
        echo "  app/src/main/jni/moonlight-core/openssl/"
    }

    if [ -f "openssl-${OPENSSL_VERSION}.tar.gz" ]; then
        tar xzf "openssl-${OPENSSL_VERSION}.tar.gz"
        cd "openssl-${OPENSSL_VERSION}"

        mkdir -p "$OPENSSL_DIR/include"

        for ABI in "${ABIS[@]}"; do
            echo "Building OpenSSL for $ABI..."
            mkdir -p "$OPENSSL_DIR/$ABI"

            case $ABI in
                armeabi-v7a)
                    ARCH="android-arm"
                    ;;
                arm64-v8a)
                    ARCH="android-arm64"
                    ;;
                x86)
                    ARCH="android-x86"
                    ;;
                x86_64)
                    ARCH="android-x86_64"
                    ;;
            esac

            export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
            export PATH="$NDK_PREBUILT_DIR/bin:$PATH"

            # -fPIC is required because these static libs are linked into
            # a shared library (libjujostream_native.so). Without it,
            # armeabi-v7a fails with R_ARM_REL32 relocation errors.
            #
            # For armeabi-v7a, we also need no-asm because OpenSSL's
            # pre-generated ARM assembly files use R_ARM_REL32 relocations
            # against OPENSSL_armcap_P that are incompatible with -fPIC
            # on NDK 28+. The C fallback is ~10-15% slower for crypto
            # operations but this only affects 32-bit ARM devices.
            EXTRA_FLAGS=""
            if [ "$ABI" = "armeabi-v7a" ]; then
                EXTRA_FLAGS="no-asm"
            fi

            ./Configure $ARCH \
                -D__ANDROID_API__=24 \
                -fPIC \
                no-shared \
                no-tests \
                no-ui-console \
                $EXTRA_FLAGS \
                --prefix="$OPENSSL_DIR/$ABI"

            make -j"$CPU_COUNT"
            cp libssl.a "$OPENSSL_DIR/$ABI/"
            cp libcrypto.a "$OPENSSL_DIR/$ABI/"
            make clean
        done

        # Copy headers
        cp -r include/openssl "$OPENSSL_DIR/include/"

        cd "$TMP_WORK_DIR"
        rm -rf "openssl-${OPENSSL_VERSION}" "openssl-${OPENSSL_VERSION}.tar.gz"
    fi
fi

# ============================================================================
# libopus
# ============================================================================
echo ""
echo "========================================="
echo "Setting up libopus for Android"
echo "========================================="

OPUS_VERSION="1.5.2"
OPUS_DIR="$DEPS_DIR/opus"

if [ -f "$OPUS_DIR/arm64-v8a/libopus.a" ]; then
    echo "libopus already built. Skipping."
else
    echo "Downloading libopus $OPUS_VERSION..."
    cd "$TMP_WORK_DIR"
    curl -LO "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" 2>/dev/null || {
        echo "WARNING: Could not download libopus."
        echo "You can manually place pre-built libopus at:"
        echo "  $OPUS_DIR/<abi>/libopus.a"
        echo "  $OPUS_DIR/include/opus/*.h"
    }

    if [ -f "opus-${OPUS_VERSION}.tar.gz" ]; then
        tar xzf "opus-${OPUS_VERSION}.tar.gz"
        cd "opus-${OPUS_VERSION}"

        mkdir -p "$OPUS_DIR/include"

        TOOLCHAIN="$NDK_PREBUILT_DIR"

        for ABI in "${ABIS[@]}"; do
            echo "Building libopus for $ABI..."
            mkdir -p "$OPUS_DIR/$ABI"

            case $ABI in
                armeabi-v7a)
                    HOST="armv7a-linux-androideabi"
                    CC_PREFIX="armv7a-linux-androideabi24"
                    ;;
                arm64-v8a)
                    HOST="aarch64-linux-android"
                    CC_PREFIX="aarch64-linux-android24"
                    ;;
                x86)
                    HOST="i686-linux-android"
                    CC_PREFIX="i686-linux-android24"
                    ;;
                x86_64)
                    HOST="x86_64-linux-android"
                    CC_PREFIX="x86_64-linux-android24"
                    ;;
            esac

            export CC="$TOOLCHAIN/bin/${CC_PREFIX}-clang"
            export CXX="$TOOLCHAIN/bin/${CC_PREFIX}-clang++"
            export AR="$TOOLCHAIN/bin/llvm-ar"
            export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"

            ./configure \
                --host=$HOST \
                --prefix="$OPUS_DIR/$ABI" \
                --disable-shared \
                --enable-static \
                --disable-doc \
                --disable-extra-programs \
                CFLAGS="-O2"

            make -j"$CPU_COUNT"
            cp .libs/libopus.a "$OPUS_DIR/$ABI/"
            make clean
        done

        # Copy headers
        cp -r include/* "$OPUS_DIR/include/"

        cd "$TMP_WORK_DIR"
        rm -rf "opus-${OPUS_VERSION}" "opus-${OPUS_VERSION}.tar.gz"
    fi
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "========================================="
echo "Setup Summary"
echo "========================================="
echo ""

for ABI in "${ABIS[@]}"; do
    echo "[$ABI]"
    [ -f "$OPENSSL_DIR/$ABI/libssl.a" ] && echo "  ✅ OpenSSL" || echo "  ❌ OpenSSL (missing)"
    [ -f "$OPENSSL_DIR/$ABI/libcrypto.a" ] && echo "  ✅ OpenSSL crypto" || echo "  ❌ OpenSSL crypto (missing)"
    [ -f "$OPUS_DIR/$ABI/libopus.a" ] && echo "  ✅ libopus" || echo "  ❌ libopus (missing)"
done

echo ""
echo "If any dependencies are missing, you can:"
echo "1. Copy pre-built libs from the original jujostream project"
echo "2. Build them manually using the NDK"
echo "3. Re-run this script after fixing any download issues"
echo ""
echo "Next step: flutter build apk"
