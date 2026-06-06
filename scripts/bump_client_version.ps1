# Bumps the patch version from the latest client-X.Y.Z git tag.
# Usage: powershell -NoProfile -File scripts/bump_client_version.ps1
param([string]$LatestTag = "")

if ([string]::IsNullOrEmpty($LatestTag)) {
    $LatestTag = git describe --tags --match "client-[0-9]*" --abbrev=0 2>$null
}

if ([string]::IsNullOrEmpty($LatestTag)) {
    Write-Output "1.0.0"
    exit 0
}

if ($LatestTag -match '^client-(\d+\.\d+\.)(\d+)$') {
    $patch = [int]$matches[2] + 1
    Write-Output ($matches[1] + $patch.ToString())
} else {
    Write-Output "1.0.0"
}
