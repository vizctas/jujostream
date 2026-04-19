<#
.SYNOPSIS
    Setup native dependencies for JujoStream Windows build.
    Downloads/builds: moonlight-common-c, OpenSSL, libopus.

.DESCRIPTION
    Uses vcpkg for OpenSSL and opus (static x64).
    Clones moonlight-common-c as git submodule.

.EXAMPLE
    .\setup_windows_native_deps.ps1
#>

$ErrorActionPreference = "Stop"

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$NATIVE_DIR = Join-Path $ROOT "windows\native_streaming"
$DEPS_DIR = Join-Path $NATIVE_DIR "deps"

Write-Host "=== JujoStream Windows Native Dependencies Setup ===" -ForegroundColor Cyan

# --- 1. Git submodule ---
Write-Host "`n[1/3] Initializing moonlight-common-c submodule..." -ForegroundColor Yellow
$SUBMODULE_PATH = "windows/native_streaming/moonlight-common-c"

Push-Location $ROOT
if (-not (Test-Path (Join-Path $NATIVE_DIR "moonlight-common-c\src\Limelight.h"))) {
    git submodule add --force https://github.com/moonlight-stream/moonlight-common-c.git $SUBMODULE_PATH 2>$null
    git submodule update --init --recursive $SUBMODULE_PATH
    Write-Host "  moonlight-common-c cloned." -ForegroundColor Green
} else {
    git submodule update --init --recursive $SUBMODULE_PATH
    Write-Host "  moonlight-common-c already present." -ForegroundColor Green
}
Pop-Location

# --- 2. vcpkg check ---
Write-Host "`n[2/3] Checking vcpkg..." -ForegroundColor Yellow
$VCPKG = Get-Command vcpkg -ErrorAction SilentlyContinue
if (-not $VCPKG) {
    Write-Host "  vcpkg not found in PATH." -ForegroundColor Red
    Write-Host "  Install: https://github.com/microsoft/vcpkg" -ForegroundColor Red
    Write-Host "  Then: vcpkg integrate install" -ForegroundColor Red
    exit 1
}
Write-Host "  vcpkg found: $($VCPKG.Source)" -ForegroundColor Green

# --- 3. Install OpenSSL + opus ---
Write-Host "`n[3/3] Installing OpenSSL + opus (static x64)..." -ForegroundColor Yellow
vcpkg install openssl:x64-windows-static
vcpkg install opus:x64-windows-static

# Copy to deps/
$VCPKG_ROOT = (vcpkg env --raw VCPKG_ROOT 2>$null) ?? (Split-Path -Parent (Split-Path -Parent $VCPKG.Source))
$INSTALLED = Join-Path $VCPKG_ROOT "installed\x64-windows-static"

if (Test-Path $INSTALLED) {
    # OpenSSL
    $SSL_INC = Join-Path $DEPS_DIR "openssl\include"
    $SSL_LIB = Join-Path $DEPS_DIR "openssl\lib"
    New-Item -ItemType Directory -Force -Path $SSL_INC | Out-Null
    New-Item -ItemType Directory -Force -Path $SSL_LIB | Out-Null
    Copy-Item -Recurse -Force (Join-Path $INSTALLED "include\openssl") $SSL_INC
    Copy-Item -Force (Join-Path $INSTALLED "lib\libssl.lib") $SSL_LIB 2>$null
    Copy-Item -Force (Join-Path $INSTALLED "lib\libcrypto.lib") $SSL_LIB 2>$null

    # Opus
    $OPUS_INC = Join-Path $DEPS_DIR "opus\include"
    $OPUS_LIB = Join-Path $DEPS_DIR "opus\lib"
    New-Item -ItemType Directory -Force -Path $OPUS_INC | Out-Null
    New-Item -ItemType Directory -Force -Path $OPUS_LIB | Out-Null
    Copy-Item -Recurse -Force (Join-Path $INSTALLED "include\opus") $OPUS_INC
    Copy-Item -Force (Join-Path $INSTALLED "lib\opus.lib") $OPUS_LIB 2>$null

    Write-Host "  Dependencies copied to $DEPS_DIR" -ForegroundColor Green
} else {
    Write-Host "  WARNING: vcpkg installed dir not found at $INSTALLED" -ForegroundColor Yellow
    Write-Host "  You may need to manually copy OpenSSL + opus libs to $DEPS_DIR" -ForegroundColor Yellow
}

Write-Host "`n=== Setup complete ===" -ForegroundColor Cyan
Write-Host "Next: flutter build windows" -ForegroundColor White
