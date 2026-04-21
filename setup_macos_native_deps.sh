#!/bin/bash
# =============================================================================
# setup_macos_native_deps.sh
#
# Downloads and builds native dependencies for the macOS Flutter target:
#   • moonlight-common-c  (GameStream protocol library)
#   • OpenSSL 3.x         (TLS used by moonlight-common-c)
#   • libopus             (audio codec)
#
# All artefacts land in:
#   macos/Runner/native_bridge/moonlight-common-c/
#   macos/Runner/native_bridge/deps/{openssl,opus}/
#
# Usage:
#   chmod +x setup_macos_native_deps.sh
#   ./setup_macos_native_deps.sh
#
# Requirements: Xcode Command Line Tools, cmake, make
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/macos/Runner/native_bridge"
DEPS_DIR="$BRIDGE_DIR/deps"
MOONLIGHT_DIR="$BRIDGE_DIR/moonlight-common-c"

OPENSSL_VERSION="3.3.1"
OPUS_VERSION="1.5.2"
MOONLIGHT_REPO="https://github.com/moonlight-stream/moonlight-common-c.git"
MOONLIGHT_REF="master"

CPU_COUNT=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log()   { echo "[macos-deps] $*"; }
error() { echo "[macos-deps] ERROR: $*" >&2; exit 1; }

# Verify Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    error "Xcode Command Line Tools not installed. Run: xcode-select --install"
fi

# Verify cmake
if ! command -v cmake &>/dev/null; then
    error "cmake not found. Install via: brew install cmake"
fi

log "Dependencies dir : $DEPS_DIR"
log "moonlight dir    : $MOONLIGHT_DIR"
mkdir -p "$DEPS_DIR/openssl" "$DEPS_DIR/opus"

# =============================================================================
# 1. moonlight-common-c
# =============================================================================
log ""
log "===== moonlight-common-c ====="

if [ -d "$MOONLIGHT_DIR/.git" ] || [ -f "$MOONLIGHT_DIR/.git" ]; then
    log "  Already present (submodule or prior clone). Skipping clone…"
else
    log "  Cloning $MOONLIGHT_REPO …"
    git clone --depth 1 --recursive -b "$MOONLIGHT_REF" \
        "$MOONLIGHT_REPO" "$MOONLIGHT_DIR" || \
        error "Failed to clone moonlight-common-c."
fi

# Ensure nested submodules (enet, reedsolomon) are present
git -C "$MOONLIGHT_DIR" submodule update --init --recursive --quiet 2>/dev/null || true
log "  moonlight-common-c ready."

# =============================================================================
# 2. OpenSSL (universal macOS binary: arm64 + x86_64)
# =============================================================================
log ""
log "===== OpenSSL $OPENSSL_VERSION ====="

OPENSSL_OUT="$DEPS_DIR/openssl"
if [ -f "$OPENSSL_OUT/lib/libssl.a" ]; then
    log "  Already built. Skipping."
else
    log "  Downloading OpenSSL $OPENSSL_VERSION …"
    curl -# -L \
        "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" \
        -o "$TMP_DIR/openssl.tar.gz" || error "Failed to download OpenSSL."

    tar xf "$TMP_DIR/openssl.tar.gz" -C "$TMP_DIR"
    OPENSSL_SRC="$TMP_DIR/openssl-${OPENSSL_VERSION}"

    build_openssl() {
        local ARCH=$1
        local TARGET=$2
        local OUT="$TMP_DIR/openssl-$ARCH"
        mkdir -p "$OUT"

        pushd "$OPENSSL_SRC" > /dev/null

        make distclean &>/dev/null || true

        ./Configure "$TARGET" \
            no-shared no-tests no-docs \
            --prefix="$OUT" \
            --openssldir="$OUT" \
            CFLAGS="-arch $ARCH -mmacosx-version-min=12.0" \
            LDFLAGS="-arch $ARCH" \
            &>/dev/null

        make -j"$CPU_COUNT" build_libs &>/dev/null
        make install_dev &>/dev/null
        popd > /dev/null
        log "    Built OpenSSL for $ARCH"
    }

    log "  Building arm64 …"
    build_openssl "arm64"  "darwin64-arm64-cc"
    log "  Building x86_64 …"
    build_openssl "x86_64" "darwin64-x86_64-cc"

    log "  Creating universal (fat) binary …"
    mkdir -p "$OPENSSL_OUT/lib" "$OPENSSL_OUT/include"

    # Merge static libraries
    for LIB in libssl.a libcrypto.a; do
        lipo -create \
            "$TMP_DIR/openssl-arm64/lib/$LIB" \
            "$TMP_DIR/openssl-x86_64/lib/$LIB" \
            -output "$OPENSSL_OUT/lib/$LIB"
    done

    # Copy headers (identical for both arches)
    rsync -a --quiet "$TMP_DIR/openssl-arm64/include/" "$OPENSSL_OUT/include/"
    log "  OpenSSL ready at $OPENSSL_OUT"
fi

# =============================================================================
# 3. libopus (universal macOS binary: arm64 + x86_64)
# =============================================================================
log ""
log "===== libopus $OPUS_VERSION ====="

OPUS_OUT="$DEPS_DIR/opus"
if [ -f "$OPUS_OUT/lib/libopus.a" ]; then
    log "  Already built. Skipping."
else
    log "  Downloading libopus $OPUS_VERSION …"
    curl -# -L \
        "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" \
        -o "$TMP_DIR/opus.tar.gz" || error "Failed to download libopus."

    tar xf "$TMP_DIR/opus.tar.gz" -C "$TMP_DIR"
    OPUS_SRC="$TMP_DIR/opus-${OPUS_VERSION}"

    build_opus() {
        local ARCH=$1
        local HOST=$2
        local OUT="$TMP_DIR/opus-$ARCH"
        mkdir -p "$OUT"

        pushd "$OPUS_SRC" > /dev/null
        make distclean &>/dev/null || true
        ./configure \
            --host="$HOST" \
            --prefix="$OUT" \
            --disable-shared \
            --enable-static \
            --disable-doc \
            --disable-extra-programs \
            CFLAGS="-arch $ARCH -mmacosx-version-min=12.0 -O2" \
            &>/dev/null
        make -j"$CPU_COUNT" &>/dev/null
        make install &>/dev/null
        popd > /dev/null
        log "    Built libopus for $ARCH"
    }

    log "  Building arm64 …"
    build_opus "arm64"  "aarch64-apple-darwin"
    log "  Building x86_64 …"
    build_opus "x86_64" "x86_64-apple-darwin"

    log "  Creating universal (fat) binary …"
    mkdir -p "$OPUS_OUT/lib" "$OPUS_OUT/include"
    lipo -create \
        "$TMP_DIR/opus-arm64/lib/libopus.a" \
        "$TMP_DIR/opus-x86_64/lib/libopus.a" \
        -output "$OPUS_OUT/lib/libopus.a"
    rsync -a --quiet "$TMP_DIR/opus-arm64/include/" "$OPUS_OUT/include/"
    log "  libopus ready at $OPUS_OUT"
fi

# =============================================================================
# Summary
# =============================================================================
log ""
log "===== All dependencies ready ====="
log ""
log "Next steps:"
log "  1. Open macos/Runner.xcodeproj in Xcode"
log "  2. Runner → Build Settings:"
log "       Objective-C Bridging Header → Runner/Runner-Bridging-Header.h"
log "       Header Search Paths (add, recursive):"
log "         \$(SRCROOT)/Runner/native_bridge/moonlight-common-c/src"
log "         \$(SRCROOT)/Runner/native_bridge/moonlight-common-c/enet/include"
log "         \$(SRCROOT)/Runner/native_bridge/deps/openssl/include"
log "         \$(SRCROOT)/Runner/native_bridge/deps/opus/include"
log "       Library Search Paths:"
log "         \$(SRCROOT)/Runner/native_bridge/deps/openssl/lib"
log "         \$(SRCROOT)/Runner/native_bridge/deps/opus/lib"
log "       Other Linker Flags: -lssl -lcrypto -lopus"
log "  3. Runner → Build Phases → Compile Sources — add:"
log "       Runner/native_bridge/moonlight_bridge_mac.c"
log "       Runner/native_bridge/callbacks_mac.c"
log "       Runner/native_bridge/moonlight-common-c/src/*.c"
log "       Runner/native_bridge/moonlight-common-c/enet/*.c"
log "       Runner/native_bridge/moonlight-common-c/reedsolomon/rs.c"
log "  4. flutter build macos"
log ""
log "  Or run the Xcode config script: ./setup_macos_xcode.sh"
