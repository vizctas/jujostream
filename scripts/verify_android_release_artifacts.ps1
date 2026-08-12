param(
    [Parameter(Mandatory = $true)] [string] $PlayApk,
    [Parameter(Mandatory = $true)] [string] $FireApk,
    [string] $ExpectedSigner = 'ec0769dc9d131705af4ceea71f520f9c31482283f16a8f581937ee5e68d8e749'
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$expectedPackage = 'com.vizcorp.moonlight_jujo_stream'

function Resolve-BuildTool([string] $name) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    $directory = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $directory) { throw 'Android build-tools not found' }
    $suffix = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        if ($name -eq 'apksigner') { '.bat' } else { '.exe' }
    } else { '' }
    $path = Join-Path $directory.FullName ($name + $suffix)
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing build tool: $path" }
    return $path
}

function Assert-Contains([string] $value, [string] $expected, [string] $message) {
    if (-not $value.Contains($expected)) { throw $message }
}

function Assert-Excludes([string] $value, [string] $forbidden, [string] $message) {
    if ($value.Contains($forbidden)) { throw $message }
}

function Read-Certificate([string] $tool, [string] $apk) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& $tool verify --verbose --print-certs $apk 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $apk" }
        return $output.ToLowerInvariant()
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

$play = (Resolve-Path -LiteralPath $PlayApk).Path
$fire = (Resolve-Path -LiteralPath $FireApk).Path
$aapt2 = Resolve-BuildTool 'aapt2'
$apksigner = Resolve-BuildTool 'apksigner'
$playPermissions = (& $aapt2 dump permissions $play | Out-String)
$firePermissions = (& $aapt2 dump permissions $fire | Out-String)
Assert-Contains $playPermissions "package: $expectedPackage" 'Play package mismatch'
Assert-Contains $firePermissions "package: $expectedPackage" 'Fire package mismatch'
Assert-Excludes $playPermissions 'REQUEST_INSTALL_PACKAGES' 'Play APK contains installer permission'
Assert-Contains $firePermissions 'REQUEST_INSTALL_PACKAGES' 'Fire APK lacks installer permission'

$playCertificate = Read-Certificate $apksigner $play
$fireCertificate = Read-Certificate $apksigner $fire
Assert-Contains $playCertificate $ExpectedSigner.ToLowerInvariant() 'Play signer mismatch'
Assert-Contains $fireCertificate $ExpectedSigner.ToLowerInvariant() 'Fire signer mismatch'

@{
    package = $expectedPackage
    signerSha256 = $ExpectedSigner.ToUpperInvariant()
    playSha256 = (Get-FileHash -LiteralPath $play -Algorithm SHA256).Hash
    fireSha256 = (Get-FileHash -LiteralPath $fire -Algorithm SHA256).Hash
    playHasInstallerPermission = $false
    fireHasInstallerPermission = $true
} | ConvertTo-Json
