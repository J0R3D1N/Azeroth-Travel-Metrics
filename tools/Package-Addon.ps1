param([string]$Version = '0.1.0-beta')

$ErrorActionPreference = 'Stop'

function Get-TocMetadata {
    param(
        [string[]]$Lines,
        [string]$Name
    )

    $pattern = '^##\s*' + [regex]::Escape($Name) + ':\s*(.*?)\s*$'
    $matches = @($Lines | Select-String -Pattern $pattern)
    if ($matches.Count -ne 1) {
        throw "Addon TOC must contain exactly one $Name metadata line."
    }

    return $matches[0].Matches[0].Groups[1].Value
}

function Assert-AddonManifest {
    param(
        [string]$TocPath,
        [string]$AddonRoot,
        [string]$ExpectedVersion = '0.1.0-beta'
    )

    if (-not (Test-Path -LiteralPath $TocPath -PathType Leaf)) {
        throw "Addon TOC does not exist: $TocPath"
    }
    if (-not (Test-Path -LiteralPath $AddonRoot -PathType Container)) {
        throw "Addon directory does not exist: $AddonRoot"
    }

    $lines = Get-Content -LiteralPath $TocPath
    $interface = Get-TocMetadata -Lines $lines -Name 'Interface'
    if ($interface -notmatch '^\d+$') {
        throw "Addon TOC must contain a numeric Interface value: $TocPath"
    }

    $expectedMetadata = @{
        Title = 'Azeroth Travel Tracker'
        Version = $ExpectedVersion
        SavedVariables = 'AzerothTravelTrackerDB'
    }
    foreach ($name in $expectedMetadata.Keys) {
        $actual = Get-TocMetadata -Lines $lines -Name $name
        if ($actual -cne $expectedMetadata[$name]) {
            throw "Addon TOC $name must be '$($expectedMetadata[$name])', found '$actual'."
        }
    }

    $resolvedAddonRoot = [System.IO.Path]::GetFullPath($AddonRoot).TrimEnd('\')
    foreach ($line in $lines) {
        $entry = $line.Trim()
        if ($entry -eq '' -or $entry.StartsWith('#')) {
            continue
        }

        $entryPath = $entry -replace '/', '\'
        $fullEntryPath = [System.IO.Path]::GetFullPath(
            (Join-Path $resolvedAddonRoot $entryPath)
        )
        if (-not $fullEntryPath.StartsWith(
            $resolvedAddonRoot + '\',
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Addon TOC file entry escapes the addon directory: $entry"
        }
        if (-not (Test-Path -LiteralPath $fullEntryPath -PathType Leaf)) {
            throw "Addon TOC file entry does not exist: $entry"
        }
    }

    return [int]$interface
}

function Assert-ZipLayout {
    param(
        [string]$ZipPath,
        [string]$ExpectedTopLevelDirectory
    )

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "Package zip does not exist: $ZipPath"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        if ($archive.Entries.Count -eq 0) {
            throw "Package zip is empty: $ZipPath"
        }

        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if (
                $name.StartsWith('/') -or
                $name -match '^[A-Za-z]:'
            ) {
                throw "Zip entry has an invalid path: $name"
            }

            $parts = @($name.Split(
                [char]'/', [System.StringSplitOptions]::None
            ))
            $isDirectoryMarker = $name.EndsWith('/')
            if ($isDirectoryMarker) {
                $parts = @($parts[0..($parts.Count - 2)])
            }

            if (
                $parts.Count -eq 0 -or
                $parts -contains '' -or
                $parts -contains '.' -or
                $parts -contains '..'
            ) {
                throw "Zip entry has an invalid path: $name"
            }

            if (
                $parts[0] -cne $ExpectedTopLevelDirectory -or
                ($parts.Count -lt 2 -and -not $isDirectoryMarker)
            ) {
                throw "Every zip entry must be under exactly one top-level directory named '$ExpectedTopLevelDirectory': $name"
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Assert-SafeStagingPath {
    param(
        [string]$RepoRoot,
        [string]$ArtifactsRoot,
        [string]$StagingPath
    )

    $resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $resolvedArtifactsRoot = [System.IO.Path]::GetFullPath($ArtifactsRoot).TrimEnd('\')
    $resolvedStagingPath = [System.IO.Path]::GetFullPath($StagingPath).TrimEnd('\')
    $expectedArtifactsRoot = Join-Path $resolvedRepoRoot 'artifacts'
    $expectedStagingPath = Join-Path $expectedArtifactsRoot 'AzerothTravelTracker'

    if ($resolvedArtifactsRoot -cne $expectedArtifactsRoot) {
        throw "Refusing to use unexpected artifacts path: $resolvedArtifactsRoot"
    }
    if ($resolvedStagingPath -cne $expectedStagingPath) {
        throw "Refusing to use unexpected staging path: $resolvedStagingPath"
    }
    if (-not $resolvedStagingPath.StartsWith(
        $resolvedArtifactsRoot + '\',
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove staging outside artifacts: $resolvedStagingPath"
    }

    foreach ($path in @($resolvedArtifactsRoot, $resolvedStagingPath)) {
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to use a reparse point for package staging: $path"
            }
        }
    }

    return $resolvedStagingPath
}

if ($env:ATT_PACKAGE_VALIDATION_ONLY -eq '1') {
    return
}

if ($Version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Version contains characters that are unsafe for a package filename: $Version"
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$addonRoot = Join-Path $repoRoot 'AzerothTravelTracker'
$tocPath = Join-Path $addonRoot 'AzerothTravelTracker.toc'
$testsPath = Join-Path $repoRoot 'tests\run.lua'
$artifactsRoot = Join-Path $repoRoot 'artifacts'
$stagingPath = Join-Path $artifactsRoot 'AzerothTravelTracker'
$zipPath = Join-Path $artifactsRoot "AzerothTravelTracker-$Version.zip"

$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') `
    + ';' `
    + [System.Environment]::GetEnvironmentVariable('Path', 'User')
$lua = Get-Command lua, luajit -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $lua) {
    throw 'Neither lua nor luajit was found on PATH.'
}

& $lua.Source $testsPath
if ($LASTEXITCODE -ne 0) {
    throw "Lua tests failed with exit code $LASTEXITCODE."
}

$interface = Assert-AddonManifest `
    -TocPath $tocPath `
    -AddonRoot $addonRoot `
    -ExpectedVersion $Version
Write-Output "Validated addon manifest for Interface $interface."

New-Item -ItemType Directory -Path $artifactsRoot -Force | Out-Null

$resolvedStagingPath = Assert-SafeStagingPath `
    -RepoRoot $repoRoot `
    -ArtifactsRoot $artifactsRoot `
    -StagingPath $stagingPath

if (Test-Path -LiteralPath $resolvedStagingPath) {
    Remove-Item -LiteralPath $resolvedStagingPath -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedStagingPath | Out-Null

Get-ChildItem -LiteralPath $addonRoot | Copy-Item `
    -Destination $resolvedStagingPath `
    -Recurse `
    -Force

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -LiteralPath $resolvedStagingPath -DestinationPath $zipPath
Assert-ZipLayout `
    -ZipPath $zipPath `
    -ExpectedTopLevelDirectory 'AzerothTravelTracker'

Write-Output ([System.IO.Path]::GetFullPath($zipPath))
