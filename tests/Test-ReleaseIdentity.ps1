$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$addonRoot = Join-Path $repoRoot 'AzerothTravelMetrics'
$activeRoots = @(
    $addonRoot,
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
$ignoredDirectoryNames = @(
    '.git',
    '.mypy_cache',
    '.pytest_cache',
    '.ruff_cache',
    '__pycache__',
    'artifacts',
    'node_modules'
)

function Get-NormalizedFullPath {
    param([string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [char[]]@('\', '/')
    )
}

function Test-PathWithinRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    return (
        $Path.Equals(
            $Root,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $Path.StartsWith(
            $Root + '\',
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $Path.StartsWith(
            $Root + '/',
            [System.StringComparison]::OrdinalIgnoreCase
        )
    )
}

function Get-RelativePathWithinRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    if (-not (Test-PathWithinRoot -Path $Path -Root $Root)) {
        throw "Path is outside expected root '$Root': $Path"
    }

    if (
        $Path.Equals(
            $Root,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        return ''
    }

    return $Path.Substring($Root.Length).TrimStart([char[]]@('\', '/'))
}

$resolvedRepoRoot = Get-NormalizedFullPath -Path $repoRoot
$resolvedAddonRoot = Get-NormalizedFullPath -Path $addonRoot

function Test-IgnoredPath {
    param([string]$Path)

    $resolvedPath = Get-NormalizedFullPath -Path $Path
    if (Test-PathWithinRoot -Path $resolvedPath -Root $resolvedAddonRoot) {
        return $false
    }

    $relativePath = Get-RelativePathWithinRoot `
        -Path $resolvedPath `
        -Root $resolvedRepoRoot
    $segments = @($relativePath -split '[\\/]')
    return @($segments | Where-Object { $_ -in $ignoredDirectoryNames }).Count -gt 0
}

$activeItems = @(
    foreach ($root in $activeRoots) {
        if (Test-Path -LiteralPath $root) {
            Get-Item -LiteralPath $root
            Get-ChildItem -LiteralPath $root -Force -Recurse
        }
    }
    foreach ($path in $activeFiles) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Get-Item -LiteralPath $path
        }
    }
) | Where-Object {
    $_.FullName -notin $allowedLegacyFiles -and
        -not (Test-IgnoredPath -Path $_.FullName)
}

$nameViolations = @(
    $activeItems |
        Where-Object { $_.Name -match $legacyPattern } |
        ForEach-Object { "$($_.FullName): legacy identity in active name" }
)

$contentViolations = @(
    $activeItems |
        Where-Object {
            -not $_.PSIsContainer -and
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0
        } |
        Select-String -Pattern $legacyPattern
) |
        ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }

$violations = @($nameViolations) + @($contentViolations)
if ($violations.Count -gt 0) {
    throw "Legacy ATT identity remains in active release surfaces:`n$($violations -join "`n")"
}

Write-Output 'PASS active release surfaces use only the ATM identity'
