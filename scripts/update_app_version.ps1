param (
    [string]$NewVersion
)

if (-not $NewVersion) {
    Write-Host "No version supplied, skipping version update."
    exit 0
}

# Ensure execution context is the repository root
$RepoRoot = Resolve-Path "$PSScriptRoot/.."
cd $RepoRoot

# 1. Parse pubspec.yaml to get the current version and build number
$PubspecPath = "pubspec.yaml"
if (-not (Test-Path $PubspecPath)) {
    Write-Error "pubspec.yaml not found at $PubspecPath"
    exit 1
}

$PubspecContent = Get-Content -Path $PubspecPath -Raw
# Find version line (e.g. version: 1.1.12+14)
if ($PubspecContent -match 'version:\s*([0-9\.]+)\+(\d+)') {
    $CurrentVersion = $Matches[1]
    $CurrentBuildNumber = [int]$Matches[2]
} else {
    Write-Error "Could not parse version from pubspec.yaml"
    exit 1
}

# Determine the new build number
$NewBuildNumber = $CurrentBuildNumber
if ($NewVersion -ne $CurrentVersion) {
    $NewBuildNumber = $CurrentBuildNumber + 1
}

Write-Host "Updating version to: $NewVersion+$NewBuildNumber (was: $CurrentVersion+$CurrentBuildNumber)"

# Update pubspec.yaml
$UpdatedPubspecContent = $PubspecContent -replace 'version:\s*[0-9\.]+\+\d+', "version: $NewVersion+$NewBuildNumber"
Set-Content -Path $PubspecPath -Value $UpdatedPubspecContent -Encoding ascii

# 2. Update android/local.properties
$LocalPropertiesPath = "android/local.properties"
if (Test-Path $LocalPropertiesPath) {
    $LocalPropertiesContent = Get-Content -Path $LocalPropertiesPath -Raw
    # Replace or add flutter.versionName
    if ($LocalPropertiesContent -match 'flutter\.versionName=') {
        $LocalPropertiesContent = $LocalPropertiesContent -replace 'flutter\.versionName=[^\r\n]*', "flutter.versionName=$NewVersion"
    } else {
        $LocalPropertiesContent += "`r`nflutter.versionName=$NewVersion"
    }
    # Replace or add flutter.versionCode
    if ($LocalPropertiesContent -match 'flutter\.versionCode=') {
        $LocalPropertiesContent = $LocalPropertiesContent -replace 'flutter\.versionCode=[^\r\n]*', "flutter.versionCode=$NewBuildNumber"
    } else {
        $LocalPropertiesContent += "`r`nflutter.versionCode=$NewBuildNumber"
    }
    Set-Content -Path $LocalPropertiesPath -Value $LocalPropertiesContent -Encoding ascii
}

# 3. Update lib/utils/app_version.dart
$AppVersionDartPath = "lib/utils/app_version.dart"
if (Test-Path $AppVersionDartPath) {
    $Template = @'
const String kAppVersion = '<VERSION>';
const int kAppBuildNumber = <BUILD>;
const String kAppVersionDisplay = 'v$kAppVersion - beta';
'@
    $DartContent = $Template.Replace('<VERSION>', $NewVersion).Replace('<BUILD>', $NewBuildNumber.ToString())
    Set-Content -Path $AppVersionDartPath -Value $DartContent -Encoding ascii
}

Write-Host "Version update completed successfully!"
