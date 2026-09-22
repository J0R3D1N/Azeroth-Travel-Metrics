$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$activeRoots = @(
    (Join-Path $repoRoot 'AzerothTravelMetrics'),
    (Join-Path $repoRoot 'tests'),
    (Join-Path $repoRoot 'tools')
)
$activeFiles = @(
    (Join-Path $repoRoot 'README.md'),
    (Join-Path $repoRoot 'docs\BETA-SMOKE-TESTS.md')
)
$allowedLegacyFiles = @(
    (Join-Path $repoRoot 'tools\Migrate-LocalATTData.ps1'),
    (Join-Path $repoRoot 'tests\Test-MigrateLocalATTData.ps1'),
    (Join-Path $repoRoot 'tests\Test-ReleaseIdentity.ps1')
)
$legacyPattern =
    'Azeroth Travel Tracker|AzerothTravelTracker|AZEROTHTRAVELTRACKER|ATTLogo|(?<![A-Za-z0-9_])ATT(?![A-Za-z0-9_])|(?<![A-Za-z0-9])/att(?![A-Za-z0-9])'

$files = @(
    foreach ($root in $activeRoots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -File -Recurse
        }
    }
    foreach ($path in $activeFiles) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Get-Item -LiteralPath $path
        }
    }
) | Where-Object {
    $_.FullName -notin $allowedLegacyFiles -and
        $_.Extension -in @('.lua', '.ps1', '.py', '.md', '.toc')
}

$violations = @(
    $files | Select-String -Pattern $legacyPattern
)
if ($violations.Count -gt 0) {
    $details = $violations |
        ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
    throw "Legacy ATT identity remains in active release surfaces:`n$($details -join "`n")"
}

Write-Output 'PASS active release surfaces use only the ATM identity'
