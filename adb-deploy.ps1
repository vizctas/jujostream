param(
    [string]$ProjectDir = $PSScriptRoot,
    [string]$ApkPath = "",
    [string]$AabPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-release.apk"
}

if ([string]::IsNullOrWhiteSpace($AabPath)) {
    $AabPath = Join-Path $ProjectDir "build\app\outputs\bundle\release\app-release.aab"
}

$defaultIps = @(
    "192.168.3.240",
    "192.168.3.137"
)

$tlsService = "adb-R5CXB1BEZPE-AELcl8._adb-tls-connect._tcp"

# ============================================================
# DART DEFINES / SUPABASE CONFIG
# ============================================================

$SupabaseUrl = "https://faadppubtdxjnnvubnsi.supabase.co"
$SupabasePublishableKey = "sb_publishable_xSfpJSBypMPXXCWeeYBgVQ_U6gu57NH"

$DartDefines = @(
    "--dart-define=SUPABASE_URL=$SupabaseUrl",
    "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SupabasePublishableKey"
)

# ============================================================
# UI HELPERS
# ============================================================

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [ERROR] $Message" -ForegroundColor Red
}

function Pause-Tool {
    Write-Host ""
    Read-Host "  Press ENTER to continue"
}

function Show-Header {
    Clear-Host

    $ascii = @"
        ____. ____  ____     ____.   ________    _________  _________  _______    _______       _____      _____
       |    ||    ||    |   |    |  /  _____/   /   _____/  \_   ___ \ \      \   \      \     /  _  \    /     \
       |    ||    ||    |   |    | /   \  ___   \_____  \   /    \  \/ /   |   \  /   |   \   /  /_\  \  /  \ /  \
   /\__|    ||    ||    |___|    | \    \_\  \  /        \  \     \___/    |    \/    |    \ /    |    \/    Y    \
   \________||____||________|____|  \______  / /_______  /   \______  /\____|__  /\____|__  / \____|__  /\____|__  /
                                          \/          \/           \/         \/         \/          \/         \/

       ================================================================================================
                                JUJO.STREAM - ANDROID BUILD & ADB DEPLOY TOOL
                                   Register. Build. Stream. Deploy. Hot Test.
       ================================================================================================
"@

    Write-Host $ascii -ForegroundColor Cyan
    Write-Host "  Project : $ProjectDir" -ForegroundColor DarkGray
    Write-Host "  APK     : $ApkPath" -ForegroundColor DarkGray
    Write-Host "  Defines : SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-InteractiveMenu {
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$DefaultIndex = 0
    )

    $selectedIndex = $DefaultIndex

    while ($true) {
        Show-Header

        Write-Host "  +-------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host ("  | {0,-47} |" -f $Title) -ForegroundColor DarkGray
        Write-Host "  +-------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $selectedIndex) {
                Write-Host ("    > {0}" -f $Options[$i]) -ForegroundColor Black -BackgroundColor Cyan
            }
            else {
                Write-Host ("      {0}" -f $Options[$i]) -ForegroundColor Gray
            }
        }

        Write-Host ""
        Write-Host "  Use UP / DOWN arrows to move, ENTER to select, ESC to go back/exit." -ForegroundColor DarkGray

        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            "UpArrow" {
                if ($selectedIndex -gt 0) {
                    $selectedIndex--
                }
                else {
                    $selectedIndex = $Options.Count - 1
                }
            }

            "DownArrow" {
                if ($selectedIndex -lt ($Options.Count - 1)) {
                    $selectedIndex++
                }
                else {
                    $selectedIndex = 0
                }
            }

            "Enter" {
                return $selectedIndex
            }

            "Escape" {
                return -1
            }
        }
    }
}

function Read-Number {
    param(
        [string]$Prompt,
        [int]$Min,
        [int]$Max
    )

    do {
        $raw = Read-Host "  $Prompt"
        $number = 0

        if ([int]::TryParse($raw, [ref]$number)) {
            if ($number -ge $Min -and $number -le $Max) {
                return $number
            }
        }

        Write-Fail "Invalid number. Enter a value from $Min to $Max."
    } while ($true)
}

# ============================================================
# COMMAND HELPERS
# ============================================================

function Test-CommandExists {
    param([string]$Command)

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Assert-CommandExists {
    param([string]$Command)

    if (-not (Test-CommandExists $Command)) {
        throw "Command '$Command' was not found. Make sure it is installed and available in PATH."
    }
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $text = ($output | Out-String).Trim()

        if (-not $Silent -and $text) {
            Write-Host $text
        }

        return [PSCustomObject]@{
            Success  = ($exitCode -eq 0)
            ExitCode = $exitCode
            Output   = $text
        }
    }
    catch {
        return [PSCustomObject]@{
            Success  = $false
            ExitCode = -1
            Output   = $_.Exception.Message
        }
    }
}

function Test-ToolRequirements {
    try {
        Assert-CommandExists "adb"
        Assert-CommandExists "flutter"

        if (-not (Test-Path $ProjectDir)) {
            throw "Project directory not found: $ProjectDir"
        }

        $pubspecPath = Join-Path $ProjectDir "pubspec.yaml"

        if (-not (Test-Path $pubspecPath)) {
            throw "pubspec.yaml not found. Make sure this script is inside the Flutter project folder."
        }

        return $true
    }
    catch {
        Write-Fail $_.Exception.Message
        return $false
    }
}

# ============================================================
# ADB FUNCTIONS
# ============================================================

function Restart-AdbServer {
    Write-Info "Restarting ADB server..."

    Invoke-ExternalCommand -FilePath "adb" -Arguments @("kill-server") -Silent | Out-Null
    Start-Sleep -Seconds 1

    $start = Invoke-ExternalCommand -FilePath "adb" -Arguments @("start-server") -Silent
    Start-Sleep -Seconds 1

    if ($start.Success) {
        Write-Ok "ADB server restarted."
    }
    else {
        Write-Fail "ADB server could not be restarted."
        Write-Host $start.Output
    }
}

function Connect-AdbDevice {
    param([string]$Target)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        Write-Warn "Empty target skipped."
        return $false
    }

    $result = Invoke-ExternalCommand -FilePath "adb" -Arguments @("connect", $Target) -Silent

    if ($result.Output -match "connected to|already connected") {
        Write-Ok "$Target -> $($result.Output)"
        return $true
    }

    Write-Warn "$Target -> $($result.Output)"
    return $false
}

function Resolve-TlsDevice {
    param([string]$ServiceName)

    Write-Info "Trying TLS service: $ServiceName"

    $result = Invoke-ExternalCommand -FilePath "adb" -Arguments @("connect", $ServiceName) -Silent

    if ($result.Output -match "connected to (.+)") {
        $resolved = $matches[1].Trim()
        Write-Ok "$ServiceName -> $resolved"
        return $resolved
    }

    Write-Warn "$ServiceName not available."
    return $null
}

function Connect-DefaultDevices {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return
    }

    Restart-AdbServer

    Write-Host ""
    Write-Info "Connecting to default devices..."

    foreach ($ip in $defaultIps) {
        Connect-AdbDevice -Target $ip | Out-Null
    }

    Write-Host ""
    Resolve-TlsDevice -ServiceName $tlsService | Out-Null

    Write-Host ""
    Show-ConnectedDevices
}

function Connect-NewDevice {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return
    }

    $target = Read-Host "  Enter device IP, IP:PORT, or TLS service"

    if ([string]::IsNullOrWhiteSpace($target)) {
        Write-Warn "No device entered."
        Pause-Tool
        return
    }

    Connect-AdbDevice -Target $target | Out-Null

    Write-Host ""
    Show-ConnectedDevices
}

function Get-ConnectedDevices {
    $result = Invoke-ExternalCommand -FilePath "adb" -Arguments @("devices", "-l") -Silent

    if (-not $result.Success) {
        Write-Fail "Could not read ADB devices."
        Write-Host $result.Output
        return @()
    }

    $devices = @()
    $lines = $result.Output -split "`r?`n"

    foreach ($line in $lines) {
        if ($line -match "^\s*(\S+)\s+device\s") {
            $devices += $matches[1]
        }
    }

    return $devices
}

function Show-ConnectedDevices {
    Write-Info "Connected devices:"

    $result = Invoke-ExternalCommand -FilePath "adb" -Arguments @("devices", "-l") -Silent

    if ($result.Output) {
        Write-Host $result.Output -ForegroundColor Gray
    }
    else {
        Write-Warn "No output from adb devices."
    }
}

function Select-Device {
    $devices = Get-ConnectedDevices

    if ($devices.Count -eq 0) {
        Write-Fail "No connected devices found."
        return $null
    }

    Write-Host ""
    Write-Info "Available devices:"

    for ($i = 0; $i -lt $devices.Count; $i++) {
        Write-Host "  [$($i + 1)] $($devices[$i])"
    }

    Write-Host ""

    $selection = Read-Number -Prompt "Select device number" -Min 1 -Max $devices.Count
    return $devices[$selection - 1]
}

# ============================================================
# BUILD FUNCTIONS
# ============================================================

function Invoke-FlutterBuildApk {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return $false
    }

    Write-Info "Building release APK with Supabase dart-defines..."

    Push-Location $ProjectDir

    try {
        $args = @(
            "build",
            "apk",
            "--release"
        ) + $DartDefines

        $result = Invoke-ExternalCommand -FilePath "flutter" -Arguments $args -Silent

        if ($result.Success -and (Test-Path $ApkPath)) {
            Write-Ok "APK build successful."
            Write-Host "  APK: $ApkPath" -ForegroundColor Gray
            Write-Host "  Dart defines included: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY" -ForegroundColor DarkGray
            return $true
        }

        Write-Fail "APK build failed."
        Write-Host $result.Output
        return $false
    }
    catch {
        Write-Fail "Unexpected error while building APK."
        Write-Host $_.Exception.Message
        return $false
    }
    finally {
        Pop-Location
    }
}

function Invoke-FlutterBuildAab {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return $false
    }

    Write-Info "Building release AAB with Supabase dart-defines..."

    Push-Location $ProjectDir

    try {
        $args = @(
            "build",
            "appbundle",
            "--release"
        ) + $DartDefines

        $result = Invoke-ExternalCommand -FilePath "flutter" -Arguments $args -Silent

        if ($result.Success -and (Test-Path $AabPath)) {
            Write-Ok "AAB build successful."
            Write-Host "  AAB: $AabPath" -ForegroundColor Gray
            Write-Host "  Dart defines included: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY" -ForegroundColor DarkGray
            return $true
        }

        Write-Fail "AAB build failed."
        Write-Host $result.Output
        return $false
    }
    catch {
        Write-Fail "Unexpected error while building AAB."
        Write-Host $_.Exception.Message
        return $false
    }
    finally {
        Pop-Location
    }
}

# ============================================================
# HOT TEST FUNCTIONS
# ============================================================

function Invoke-FlutterRunOnDevice {
    param([string]$Device)

    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($Device)) {
        Write-Fail "No device selected."
        Pause-Tool
        return $false
    }

    Write-Info "Starting Flutter hot test on device:"
    Write-Host "  $Device" -ForegroundColor Gray
    Write-Host ""
    Write-Warn "This runs: flutter run -d $Device with Supabase dart-defines."
    Write-Warn "Keep this PowerShell window open for hot reload."
    Write-Host ""
    Write-Host "  Flutter shortcuts while running:" -ForegroundColor Cyan
    Write-Host "    r  Hot reload" -ForegroundColor Gray
    Write-Host "    R  Hot restart" -ForegroundColor Gray
    Write-Host "    q  Quit flutter run" -ForegroundColor Gray
    Write-Host ""

    Push-Location $ProjectDir

    try {
        $args = @(
            "run",
            "-d",
            $Device
        ) + $DartDefines

        & flutter @args

        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-Ok "Flutter run finished."
            return $true
        }

        Write-Fail "Flutter run finished with exit code $exitCode."
        return $false
    }
    catch {
        Write-Fail "Unexpected error while running Flutter."
        Write-Host $_.Exception.Message
        return $false
    }
    finally {
        Pop-Location
    }
}

function HotTest-SelectedDevice {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return
    }

    $device = Select-Device

    if (-not $device) {
        Pause-Tool
        return
    }

    Invoke-FlutterRunOnDevice -Device $device | Out-Null
    Pause-Tool
}

function HotTest-FirstDevice {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return
    }

    $devices = Get-ConnectedDevices

    if ($devices.Count -eq 0) {
        Write-Fail "No connected devices found."
        Pause-Tool
        return
    }

    $device = $devices[0]

    Invoke-FlutterRunOnDevice -Device $device | Out-Null
    Pause-Tool
}

function HotTest-AllDevicesSequential {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return
    }

    $devices = Get-ConnectedDevices

    if ($devices.Count -eq 0) {
        Write-Fail "No connected devices found."
        Pause-Tool
        return
    }

    Write-Warn "Flutter run is interactive and blocks the console."
    Write-Warn "Devices will run one by one, not all at the same time."
    Write-Warn "Press 'q' inside Flutter to move to the next device."
    Write-Host ""

    foreach ($device in $devices) {
        Invoke-FlutterRunOnDevice -Device $device | Out-Null
    }

    Pause-Tool
}

# ============================================================
# DEPLOY FUNCTIONS
# ============================================================

function Test-ApkExists {
    if (-not (Test-Path $ApkPath)) {
        Write-Fail "APK not found:"
        Write-Host "  $ApkPath" -ForegroundColor Gray
        Write-Warn "Build the APK first."
        return $false
    }

    return $true
}

function Install-ApkOnDevice {
    param([string]$Device)

    if (-not (Test-ApkExists)) {
        return $false
    }

    Write-Info "Installing APK on $Device..."

    $result = Invoke-ExternalCommand -FilePath "adb" -Arguments @("-s", $Device, "install", "-r", $ApkPath) -Silent

    if ($result.Output -match "Success") {
        Write-Ok "$Device -> Install successful."
        return $true
    }

    Write-Fail "$Device -> Install failed."
    Write-Host $result.Output
    return $false
}

function Deploy-ToAllDevices {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return
    }

    if (-not (Test-ApkExists)) {
        Pause-Tool
        return
    }

    $devices = Get-ConnectedDevices

    if ($devices.Count -eq 0) {
        Write-Fail "No connected devices found."
        Pause-Tool
        return
    }

    Write-Info "Deploying to $($devices.Count) device(s)..."
    Write-Host ""

    $success = 0
    $failed = 0

    foreach ($device in $devices) {
        $installed = Install-ApkOnDevice -Device $device

        if ($installed) {
            $success++
        }
        else {
            $failed++
        }

        Write-Host ""
    }

    Write-Info "Deploy summary:"
    Write-Ok "Successful: $success"

    if ($failed -gt 0) {
        Write-Fail "Failed: $failed"
    }
    else {
        Write-Ok "Failed: 0"
    }

    Pause-Tool
}

function Deploy-ToSelectedDevice {
    Show-Header

    if (-not (Test-ToolRequirements)) {
        Pause-Tool
        return
    }

    if (-not (Test-ApkExists)) {
        Pause-Tool
        return
    }

    $device = Select-Device

    if (-not $device) {
        Pause-Tool
        return
    }

    Write-Host ""
    Install-ApkOnDevice -Device $device | Out-Null

    Pause-Tool
}

function Build-ApkAndDeployAll {
    $built = Invoke-FlutterBuildApk

    if (-not $built) {
        Pause-Tool
        return
    }

    Deploy-ToAllDevices
}

function Build-ApkAndDeploySelected {
    $built = Invoke-FlutterBuildApk

    if (-not $built) {
        Pause-Tool
        return
    }

    Deploy-ToSelectedDevice
}

# ============================================================
# MENU FUNCTIONS
# ============================================================

function Get-MainMenuChoice {
    return Show-InteractiveMenu -Title "MAIN MENU" -Options @(
        "Connect to ADB devices",
        "Hot test Flutter run",
        "Deploy existing APK",
        "Build APK",
        "Build AAB",
        "Build APK and deploy",
        "Restart ADB server",
        "Show connected devices",
        "Exit"
    )
}

function Get-ConnectMenuChoice {
    return Show-InteractiveMenu -Title "CONNECT TO DEVICES" -Options @(
        "Connect to default devices",
        "Connect to new device",
        "Back to main menu"
    )
}

function Get-HotTestMenuChoice {
    return Show-InteractiveMenu -Title "HOT TEST FLUTTER RUN" -Options @(
        "Run on selected device",
        "Run on first connected device",
        "Run on all devices sequentially",
        "Back to main menu"
    )
}

function Get-DeployMenuChoice {
    return Show-InteractiveMenu -Title "DEPLOY EXISTING APK" -Options @(
        "Deploy to all connected devices",
        "Deploy to selected device",
        "Back to main menu"
    )
}

function Get-BuildDeployMenuChoice {
    return Show-InteractiveMenu -Title "BUILD APK AND DEPLOY" -Options @(
        "Build and deploy to all devices",
        "Build and deploy to selected device",
        "Back to main menu"
    )
}

# ============================================================
# MAIN LOOP
# ============================================================

do {
    $choice = Get-MainMenuChoice

    switch ($choice) {
        0 {
            do {
                $sub = Get-ConnectMenuChoice

                switch ($sub) {
                    0 {
                        Connect-DefaultDevices
                        Pause-Tool
                    }
                    1 {
                        Connect-NewDevice
                    }
                    2 {
                        break
                    }
                    -1 {
                        break
                    }
                }
            } while ($sub -ne 2 -and $sub -ne -1)
        }

        1 {
            do {
                $sub = Get-HotTestMenuChoice

                switch ($sub) {
                    0 {
                        HotTest-SelectedDevice
                    }
                    1 {
                        HotTest-FirstDevice
                    }
                    2 {
                        HotTest-AllDevicesSequential
                    }
                    3 {
                        break
                    }
                    -1 {
                        break
                    }
                }
            } while ($sub -ne 3 -and $sub -ne -1)
        }

        2 {
            do {
                $sub = Get-DeployMenuChoice

                switch ($sub) {
                    0 {
                        Deploy-ToAllDevices
                    }
                    1 {
                        Deploy-ToSelectedDevice
                    }
                    2 {
                        break
                    }
                    -1 {
                        break
                    }
                }
            } while ($sub -ne 2 -and $sub -ne -1)
        }

        3 {
            Invoke-FlutterBuildApk | Out-Null
            Pause-Tool
        }

        4 {
            Invoke-FlutterBuildAab | Out-Null
            Pause-Tool
        }

        5 {
            do {
                $sub = Get-BuildDeployMenuChoice

                switch ($sub) {
                    0 {
                        Build-ApkAndDeployAll
                    }
                    1 {
                        Build-ApkAndDeploySelected
                    }
                    2 {
                        break
                    }
                    -1 {
                        break
                    }
                }
            } while ($sub -ne 2 -and $sub -ne -1)
        }

        6 {
            Show-Header

            if (Test-CommandExists "adb") {
                Restart-AdbServer
            }
            else {
                Write-Fail "ADB was not found in PATH."
            }

            Pause-Tool
        }

        7 {
            Show-Header

            if (Test-CommandExists "adb") {
                Show-ConnectedDevices
            }
            else {
                Write-Fail "ADB was not found in PATH."
            }

            Pause-Tool
        }

        8 {
            Show-Header
            Write-Host "  Goodbye!" -ForegroundColor Cyan
            Write-Host ""
        }

        -1 {
            Show-Header
            Write-Host "  Goodbye!" -ForegroundColor Cyan
            Write-Host ""
            $choice = 8
        }
    }

} while ($choice -ne 8)