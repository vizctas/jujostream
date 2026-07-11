# mic-test.ps1 — Deploy the client-mic build to the phone and watch the mic path.
#
# Usage (from the client repo root, on branch feature/client-mic):
#   .\mic-test.ps1                 # connect + install existing release APK + logcat
#   .\mic-test.ps1 -Build          # build the release APK first, then install + logcat
#   .\mic-test.ps1 -Target 192.168.3.137:5555   # override the device target
#
# What it does: connects adb to the phone (TLS service by default), installs the
# release APK (-r, keeps pairing/data), pre-grants RECORD_AUDIO so the prompt
# won't block, clears logcat, then streams ONLY the mic-relevant tags.
#
# Then, on the phone: open the app, start a stream to the host (with the new
# server build running), talk into the mic. Watch for:
#   OboeMic          I  Mic capture started: rate=48000 ch=1 frame=960
#   JujostreamBridge I  Starting mic capture
# and on the HOST server log:  "client mic: receiver ready (Jujo Stream Mic In)"
# and confirm input on the host's "Jujo Stream Mic In" device (Audacity / voice app).

param(
    [string]$Target = "adb-R5CXB1BEZPE-AELcl8._adb-tls-connect._tcp",
    [string[]]$FallbackTargets = @("192.168.3.137:5555", "192.168.3.240:5555"),
    [string]$ApkPath = "build\app\outputs\flutter-apk\app-release.apk",
    [string]$PackageId = "com.vizcorp.moonlight_jujo_stream",
    [switch]$Build
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "  [INFO] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [ERR]  $m" -ForegroundColor Red }

# --- Supabase dart-defines (publishable key — public by design) ---
$DartDefines = @(
    "--dart-define=SUPABASE_URL=https://faadppubtdxjnnvubnsi.supabase.co",
    "--dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xSfpJSBypMPXXCWeeYBgVQ_U6gu57NH"
)

# --- 1. Optional build ---
if ($Build) {
    Info "Building release APK with mic (dart-defines included)..."
    & flutter build apk --release @DartDefines
    if ($LASTEXITCODE -ne 0) { Fail "APK build failed."; exit 1 }
    Ok "APK built."
}

if (-not (Test-Path $ApkPath)) {
    Fail "APK not found at $ApkPath. Run with -Build first."
    exit 1
}

# --- 2. Connect to the phone ---
Info "Restarting adb server..."
& adb kill-server | Out-Null
& adb start-server | Out-Null

$device = $null
foreach ($t in @($Target) + $FallbackTargets) {
    Info "adb connect $t"
    $out = (& adb connect $t 2>&1 | Out-String)
    if ($out -match "connected to (\S+)") {
        $device = $Matches[1]
        Ok "Connected: $device"
        break
    }
    Warn ($out.Trim())
}

if (-not $device) {
    Fail "Could not connect to the phone. Is wireless debugging on and the phone on the same network?"
    & adb devices -l
    exit 1
}

# --- 3. Install ---
Info "Installing APK on $device (-r keeps data/pairing)..."
$install = (& adb -s $device install -r $ApkPath 2>&1 | Out-String)
if ($install -notmatch "Success") {
    Fail "Install failed:"; Write-Host $install
    exit 1
}
Ok "Installed."

# --- 4. Pre-grant RECORD_AUDIO ---
Info "Granting RECORD_AUDIO (so the prompt won't block the test)..."
try { & adb -s $device shell pm grant $PackageId android.permission.RECORD_AUDIO 2>&1 | Out-Null; Ok "RECORD_AUDIO granted." }
catch { Warn "Could not pre-grant (the app will prompt on first stream): $_" }

# --- 5. Watch the mic path ---
& adb -s $device logcat -c
Write-Host ""
Ok "Now on the phone: open the app, start a stream to the host, and talk."
Info "Streaming mic logs (Ctrl+C to stop). Expect 'Mic capture started' when the stream connects."
Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
& adb -s $device logcat -s OboeMic JujostreamBridge StreamingPlugin
