param(
    [ValidateSet("PreBuild", "PostBuild", "All")]
    [string]$Phase = "All",
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$ReleaseDir = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
    $ReleaseDir = Join-Path $RepoRoot "build\windows\x64\runner\Release"
}

function Invoke-PreBuildPatch {
    $depsPath = Join-Path $RepoRoot ".flutter-plugins-dependencies"
    if (-not (Test-Path -LiteralPath $depsPath)) {
        return
    }

    $dependencies = Get-Content -LiteralPath $depsPath -Raw | ConvertFrom-Json
    $winPlugins = @($dependencies.plugins.windows)
    foreach ($plugin in $winPlugins) {
        if ($plugin.name -eq "flutter_local_notifications_windows" -and -not [string]::IsNullOrWhiteSpace($plugin.path)) {
            $ffiDart = Join-Path $plugin.path "lib\src\plugin\ffi.dart"
            if (Test-Path -LiteralPath $ffiDart) {
                $content = [System.IO.File]::ReadAllText($ffiDart)
                $oldSnippet = @"
  final DynamicLibrary _library = DynamicLibrary.open(
    'flutter_local_notifications_windows.dll',
  );
"@
                $newSnippet = @"
  final DynamicLibrary _library = (() {
    try {
      return DynamicLibrary.open('local_notifications_windows.dll');
    } catch (_) {
      return DynamicLibrary.open('flutter_local_notifications_windows.dll');
    }
  })();
"@
                if ($content.Contains("'flutter_local_notifications_windows.dll'") -and -not $content.Contains("'local_notifications_windows.dll'")) {
                    $updated = $content.Replace($oldSnippet, $newSnippet)
                    if ($updated -eq $content) {
                        $updated = $content.Replace(
                            "DynamicLibrary.open(`n    'flutter_local_notifications_windows.dll',`n  )",
                            "(() { try { return DynamicLibrary.open('local_notifications_windows.dll'); } catch (_) { return DynamicLibrary.open('flutter_local_notifications_windows.dll'); } })()"
                        )
                    }
                    if ($updated -ne $content) {
                        [System.IO.File]::WriteAllText($ffiDart, $updated, [System.Text.UTF8Encoding]::new($false))
                        Write-Output "[PreBuild] Patched flutter_local_notifications_windows ffi.dart to load local_notifications_windows.dll"
                    }
                }
            }
        }
    }
}

function Update-PeAsciiString {
    param(
        [string]$FilePath,
        [string]$OldString,
        [string]$NewString
    )
    if ($NewString.Length -gt $OldString.Length) {
        throw "NewString '$NewString' cannot be longer than OldString '$OldString'."
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $latin1 = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
    $text = $latin1.GetString($bytes)

    $search = $OldString + "`0"
    $replacement = $NewString + ("`0" * ($OldString.Length - $NewString.Length + 1))
    $repBytes = $latin1.GetBytes($replacement)

    $idx = $text.IndexOf($search, [System.StringComparison]::Ordinal)
    $patchedCount = 0
    while ($idx -ge 0) {
        [System.Array]::Copy($repBytes, 0, $bytes, $idx, $repBytes.Length)
        $patchedCount++
        $idx = $text.IndexOf($search, $idx + $search.Length, [System.StringComparison]::Ordinal)
    }

    if ($patchedCount -gt 0) {
        [System.IO.File]::WriteAllBytes($FilePath, $bytes)
    }
    return $patchedCount
}

function Invoke-PostBuildPatch {
    if (-not (Test-Path -LiteralPath $ReleaseDir)) {
        throw "Windows Release directory not found: $ReleaseDir"
    }

    $pePairs = @(
        @{ Old = "flutter_windows.dll"; New = "windows.dll" },
        @{ Old = "flutter_secure_storage_windows_plugin.dll"; New = "secure_storage_windows_plugin.dll" },
        @{ Old = "flutter_local_notifications_windows.dll"; New = "local_notifications_windows.dll" }
    )

    # 1. Patch PE import/export descriptor strings in exe and all dlls
    $binaries = Get-ChildItem -LiteralPath $ReleaseDir -File |
        Where-Object { $_.Extension -in @(".exe", ".dll") }

    foreach ($bin in $binaries) {
        foreach ($pair in $pePairs) {
            $count = Update-PeAsciiString -FilePath $bin.FullName -OldString $pair.Old -NewString $pair.New
            if ($count -gt 0) {
                Write-Output "[PostBuild] Patched $($pair.Old) -> $($pair.New) ($count occurrence(s)) in $($bin.Name)"
            }
        }
    }

    # 2. Rename any flutter_* files in Release directory
    $flutterFiles = Get-ChildItem -LiteralPath $ReleaseDir -File |
        Where-Object { $_.Name -like "flutter_*" }

    foreach ($file in $flutterFiles) {
        $newName = $file.Name -replace "^flutter_", ""
        $targetPath = Join-Path $ReleaseDir $newName
        if (Test-Path -LiteralPath $targetPath) {
            Remove-Item -LiteralPath $targetPath -Force
        }
        Rename-Item -LiteralPath $file.FullName -NewName $newName -Force
        Write-Output "[PostBuild] Renamed $($file.Name) -> $newName"
    }

    # 3. Rename data/flutter_assets -> data/assets and clean flutter_* sub-entries
    $dataDir = Join-Path $ReleaseDir "data"
    if (Test-Path -LiteralPath $dataDir) {
        $flutterAssetsDir = Join-Path $dataDir "flutter_assets"
        $cleanAssetsDir = Join-Path $dataDir "assets"
        if (Test-Path -LiteralPath $flutterAssetsDir) {
            if (Test-Path -LiteralPath $cleanAssetsDir) {
                Remove-Item -LiteralPath $cleanAssetsDir -Recurse -Force
            }
            Rename-Item -LiteralPath $flutterAssetsDir -NewName "assets" -Force
            Write-Output "[PostBuild] Renamed data\flutter_assets -> data\assets"
        }

        $webNotifPkg = Join-Path $cleanAssetsDir "packages\flutter_local_notifications_web"
        if (Test-Path -LiteralPath $webNotifPkg) {
            Remove-Item -LiteralPath $webNotifPkg -Recurse -Force
            Write-Output "[PostBuild] Removed unused web asset directory packages\flutter_local_notifications_web"
        }
    }

    # 4. Bundle libcrypto-4-x64.dll if imported from System32 so target machines don't fail with 0xc0000135
    $sysCryptoDll = Join-Path $env:SystemRoot "System32\libcrypto-4-x64.dll"
    $destCryptoDll = Join-Path $ReleaseDir "libcrypto-4-x64.dll"
    if ((Test-Path -LiteralPath $sysCryptoDll) -and -not (Test-Path -LiteralPath $destCryptoDll)) {
        Copy-Item -LiteralPath $sysCryptoDll -Destination $destCryptoDll -Force
        Write-Output "[PostBuild] Bundled libcrypto-4-x64.dll into Windows Release folder"
    }
}

if ($Phase -in @("PreBuild", "All")) {
    Invoke-PreBuildPatch
}

if ($Phase -in @("PostBuild", "All")) {
    if (Test-Path -LiteralPath $ReleaseDir) {
        Invoke-PostBuildPatch
    }
}

