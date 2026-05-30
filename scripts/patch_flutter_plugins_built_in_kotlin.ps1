param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$depsPath = Join-Path $RepoRoot ".flutter-plugins-dependencies"
if (-not (Test-Path -LiteralPath $depsPath)) {
    throw "Missing .flutter-plugins-dependencies. Run flutter pub get first."
}

$dependencies = Get-Content -LiteralPath $depsPath -Raw | ConvertFrom-Json
$androidPlugins = @($dependencies.plugins.android)
$patched = New-Object System.Collections.Generic.List[string]

$patterns = @(
    @{
        Pattern = "(?m)^([ `t]*)apply plugin: ['""]kotlin-android['""][ `t]*$"
        Replacement = '$1// Built-in Kotlin migration: KGP application removed by scripts/patch_flutter_plugins_built_in_kotlin.ps1'
    },
    @{
        Pattern = "(?m)^([ `t]*)apply plugin: ['""]org\.jetbrains\.kotlin\.android['""][ `t]*$"
        Replacement = '$1// Built-in Kotlin migration: KGP application removed by scripts/patch_flutter_plugins_built_in_kotlin.ps1'
    },
    @{
        Pattern = "(?m)^([ `t]*)id\(['""]kotlin-android['""]\)[ `t]*$"
        Replacement = '$1// Built-in Kotlin migration: KGP application removed by scripts/patch_flutter_plugins_built_in_kotlin.ps1'
    },
    @{
        Pattern = "(?m)^([ `t]*)id\(['""]org\.jetbrains\.kotlin\.android['""]\)[ `t]*$"
        Replacement = '$1// Built-in Kotlin migration: KGP application removed by scripts/patch_flutter_plugins_built_in_kotlin.ps1'
    },
    @{
        Pattern = "(?m)^([ `t]*)apply\(plugin = ['""]org\.jetbrains\.kotlin\.android['""]\)[ `t]*$"
        Replacement = '$1// Built-in Kotlin migration: KGP application removed by scripts/patch_flutter_plugins_built_in_kotlin.ps1'
    },
    @{
        Pattern = "(?ms)\r?\n[ `t]*if \(shouldApplyKotlinAndroidPlugin\) \{[ `t\r\n]*withGroovyBuilder \{[ `t\r\n]*""kotlinOptions"" \{[ `t\r\n]*setProperty\(""jvmTarget"", JavaVersion\.VERSION_17\.toString\(\)\)[ `t\r\n]*\}[ `t\r\n]*\}[ `t\r\n]*\}"
        Replacement = ''
    },
    @{
        Pattern = "(?ms)\r?\n[ `t]*kotlinOptions[ `t]*\{[ `t\r\n]*jvmTarget[ `t]*=[ `t]*JavaVersion\.VERSION_17\.toString\(\)[ `t\r\n]*\}"
        Replacement = ''
    },
    @{
        Pattern = "(?ms)\r?\n[ `t]*kotlinOptions[ `t]*\{[ `t\r\n]*jvmTarget[ `t]*=[ `t]*['""][^'""]+['""][ `t\r\n]*\}"
        Replacement = ''
    }
)

foreach ($plugin in $androidPlugins) {
    $pluginPath = $plugin.path
    if ([string]::IsNullOrWhiteSpace($pluginPath)) {
        continue
    }

    $androidPath = Join-Path $pluginPath "android"
    if (-not (Test-Path -LiteralPath $androidPath)) {
        continue
    }

    $gradleFiles = Get-ChildItem -LiteralPath $androidPath -File -Recurse |
        Where-Object { $_.Name -eq "build.gradle" -or $_.Name -eq "build.gradle.kts" }
    foreach ($gradleFile in $gradleFiles) {
        $original = [System.IO.File]::ReadAllText($gradleFile.FullName)
        $updated = $original

        foreach ($entry in $patterns) {
            $updated = [regex]::Replace($updated, $entry.Pattern, $entry.Replacement)
        }

        if ($updated -ne $original) {
            $backupPath = "$($gradleFile.FullName).pre-built-in-kotlin"
            if (-not (Test-Path -LiteralPath $backupPath)) {
                [System.IO.File]::WriteAllText($backupPath, $original, [System.Text.UTF8Encoding]::new($false))
            }
            [System.IO.File]::WriteAllText($gradleFile.FullName, $updated, [System.Text.UTF8Encoding]::new($false))
            $patched.Add("$($plugin.name): $($gradleFile.FullName)") | Out-Null
        }
    }
}

if ($patched.Count -eq 0) {
    Write-Output "No Flutter plugin KGP applications needed patching."
} else {
    Write-Output "Patched Flutter plugin KGP applications:"
    $patched | ForEach-Object { Write-Output "  $_" }
}
