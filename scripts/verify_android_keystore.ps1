$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$androidDir = Join-Path $projectRoot 'android'
$androidAppDir = Join-Path $androidDir 'app'
$propertiesPath = Join-Path $androidDir 'key.properties'

if (-not (Test-Path -LiteralPath $propertiesPath)) {
    throw "Release builds require android/key.properties."
}

$properties = @{}
Get-Content -LiteralPath $propertiesPath | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#')) {
        return
    }

    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2) {
        $properties[$parts[0].Trim()] = $parts[1].Trim()
    }
}

$requiredKeys = @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')
$missingKeys = @($requiredKeys | Where-Object {
    -not $properties.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string]$properties[$_])
})

if ($missingKeys.Count -gt 0) {
    throw "android/key.properties is missing required keys: $($missingKeys -join ', ')."
}

$storeFile = [string]$properties['storeFile']
if ([System.IO.Path]::IsPathRooted($storeFile)) {
    $storePath = $storeFile
} else {
    # Matches android/app/build.gradle.kts, where file(storeFile) resolves from
    # the app module directory.
    $storePath = Join-Path $androidAppDir $storeFile
}

if (-not (Test-Path -LiteralPath $storePath)) {
    throw "Release keystore file not found: $storePath."
}

$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keytoolCommand -and -not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $javaHomeKeytool = Join-Path $env:JAVA_HOME 'bin/keytool.exe'
    if (Test-Path -LiteralPath $javaHomeKeytool) {
        $keytoolCommand = Get-Item -LiteralPath $javaHomeKeytool
    }
}

if ($null -eq $keytoolCommand) {
    throw "keytool was not found. Add Java to PATH or set JAVA_HOME."
}

$keytoolPath = $keytoolCommand.Source
$keytoolOutput = & $keytoolPath -list -keystore $storePath -alias $properties['keyAlias'] -storepass $properties['storePassword'] 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Release keystore check failed for alias '$($properties['keyAlias'])'. The storePassword is incorrect, keyAlias is wrong, or the keystore is unreadable. keytool said: $keytoolOutput"
}

Write-Host "Android release keystore is readable for alias '$($properties['keyAlias'])'."
