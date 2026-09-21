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
        Title = 'Azeroth Travel Tracker - WoW: Forever (beta)'
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

function Get-ValidatedAddonFiles {
    param([string]$AddonRoot)

    if (-not (Test-Path -LiteralPath $AddonRoot -PathType Container)) {
        throw "Addon directory does not exist: $AddonRoot"
    }

    $root = Get-Item -LiteralPath $AddonRoot -Force
    if (($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Addon source contains a reparse point: $($root.FullName)"
    }

    $rootPath = $root.FullName.TrimEnd('\')
    $directories = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $files = [System.Collections.Generic.List[object]]::new()
    $directories.Push($root)

    while ($directories.Count -gt 0) {
        $directory = $directories.Pop()
        foreach ($item in $directory.EnumerateFileSystemInfos()) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Addon source contains a reparse point: $($item.FullName)"
            }

            if (($item.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                $directories.Push([System.IO.DirectoryInfo]$item)
                continue
            }

            $relativePath = $item.FullName.Substring($rootPath.Length + 1)
            $files.Add([pscustomobject]@{
                FullPath = $item.FullName
                RelativePath = $relativePath
            })
        }
    }

    return @($files | Sort-Object -Property RelativePath)
}

function Invoke-GitText {
    param(
        [string]$RepoRoot,
        [string]$Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.Arguments = $Arguments
    $startInfo.WorkingDirectory = $RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Could not start Git.'
    }

    try {
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Git failed with exit code $($process.ExitCode): $($stderr.Trim())"
        }

        return $stdout
    }
    finally {
        $process.Dispose()
    }
}

function Get-HeadCommit {
    param([string]$RepoRoot)

    $commit = (Invoke-GitText -RepoRoot $RepoRoot -Arguments 'rev-parse --verify HEAD').Trim()
    if ($commit -notmatch '^[0-9a-f]{40,64}$') {
        throw "Git returned an invalid HEAD object ID: $commit"
    }

    return $commit
}

function Assert-CleanAddonWorktree {
    param([string]$RepoRoot)

    $status = Invoke-GitText `
        -RepoRoot $RepoRoot `
        -Arguments 'status --porcelain=v1 -z --untracked-files=all -- AzerothTravelTracker'
    if ($status.Length -ne 0) {
        $details = ($status -replace "`0", ', ').Trim(' ', ',')
        throw "Addon working tree must be clean before packaging: $details"
    }
}

function Get-TrackedAddonFilesAtHead {
    param(
        [string]$RepoRoot,
        [string]$Commit = (Get-HeadCommit -RepoRoot $RepoRoot)
    )

    $tree = Invoke-GitText `
        -RepoRoot $RepoRoot `
        -Arguments "ls-tree -r -z $Commit -- AzerothTravelTracker"
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($record in $tree.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        if ($record -notmatch '^(\d{6}) (blob|tree|commit) ([0-9a-f]+)\t(.+)$') {
            throw "Git returned an invalid addon tree entry: $record"
        }

        $mode = $Matches[1]
        $type = $Matches[2]
        $path = $Matches[4]
        if ($type -cne 'blob' -or $mode -notin @('100644', '100755')) {
            throw "Tracked addon entry is not a regular file: $path"
        }
        if (-not $path.StartsWith(
            'AzerothTravelTracker/',
            [System.StringComparison]::Ordinal
        )) {
            throw "Tracked addon entry is outside the addon directory: $path"
        }

        $files.Add($path.Substring('AzerothTravelTracker/'.Length))
    }

    if ($files.Count -eq 0) {
        throw 'HEAD does not contain any tracked addon files.'
    }

    return @($files | Sort-Object)
}

function New-GitAddonSnapshot {
    param(
        [string]$RepoRoot,
        [string]$SnapshotZipPath,
        [string]$Commit = (Get-HeadCommit -RepoRoot $RepoRoot)
    )

    & git `
        -c core.autocrlf=false `
        -C $RepoRoot `
        archive `
        --format=zip `
        "--output=$SnapshotZipPath" `
        $Commit `
        AzerothTravelTracker
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create addon snapshot from Git commit $Commit."
    }
}

function Assert-ZipLayout {
    param(
        [string]$ZipPath,
        [string]$ExpectedTopLevelDirectory,
        [string[]]$ExpectedFilePaths
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

        $actualFilePaths = [System.Collections.Generic.List[string]]::new()
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

            if (-not $isDirectoryMarker) {
                $actualFilePaths.Add(($parts[1..($parts.Count - 1)] -join '/'))
            }
        }

        if ($null -ne $ExpectedFilePaths) {
            $expected = @($ExpectedFilePaths | ForEach-Object { $_ -replace '\\', '/' })
            $actual = @($actualFilePaths)
            [System.Array]::Sort($expected, [System.StringComparer]::Ordinal)
            [System.Array]::Sort($actual, [System.StringComparer]::Ordinal)

            if (
                $expected.Count -ne $actual.Count -or
                [string]::Join("`n", $expected) -cne [string]::Join("`n", $actual)
            ) {
                throw (
                    "Package archive file set does not match the validated addon source. " +
                    "Expected: [$([string]::Join(', ', $expected))]. " +
                    "Actual: [$([string]::Join(', ', $actual))]."
                )
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Assert-IconAssetArchiveEntries {
    param([string[]]$EntryNames)

    $normalizedEntries = @(
        $EntryNames |
            ForEach-Object { $_ -replace '\\', '/' } |
            Where-Object { -not $_.EndsWith('/') }
    )
    $requiredTextures = @(
        'AzerothTravelTracker/Media/ATTLogo.tga',
        'AzerothTravelTracker/Media/ByLevel.tga',
        'AzerothTravelTracker/Media/Overview.tga'
    )
    $actualTextures = @(
        $normalizedEntries |
            Where-Object {
                $_ -match '\AAzerothTravelTracker/Media/[^/]+\.tga\z'
            }
    )
    [System.Array]::Sort($requiredTextures, [System.StringComparer]::Ordinal)
    [System.Array]::Sort($actualTextures, [System.StringComparer]::Ordinal)

    if (
        $requiredTextures.Count -ne $actualTextures.Count -or
        [string]::Join("`n", $requiredTextures) -cne
            [string]::Join("`n", $actualTextures)
    ) {
        throw (
            'Package must include exactly the required runtime TGA entries: ' +
            "$([string]::Join(', ', $requiredTextures))."
        )
    }
    if ($normalizedEntries | Where-Object { $_ -match '(?i)tab_iconography' }) {
        throw 'Package must not include a tab_iconography reference entry.'
    }
    if ($normalizedEntries | Where-Object { $_ -match '(?i)\.(jpg|jpeg)\z' }) {
        throw 'Package must not include a source JPG or JPEG entry.'
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
$testsPath = Join-Path $repoRoot 'tests\run.lua'
$artifactsRoot = Join-Path $repoRoot 'artifacts'
$stagingPath = Join-Path $artifactsRoot 'AzerothTravelTracker'
$zipPath = Join-Path $artifactsRoot "AzerothTravelTracker-$Version.zip"
$snapshotZipPath = Join-Path $artifactsRoot '.AzerothTravelTracker-head.zip'

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

Get-ValidatedAddonFiles -AddonRoot $addonRoot | Out-Null
Assert-CleanAddonWorktree -RepoRoot $repoRoot
$headCommit = Get-HeadCommit -RepoRoot $repoRoot
$trackedFiles = @(
    Get-TrackedAddonFilesAtHead -RepoRoot $repoRoot -Commit $headCommit
)

New-Item -ItemType Directory -Path $artifactsRoot -Force | Out-Null

$resolvedStagingPath = Assert-SafeStagingPath `
    -RepoRoot $repoRoot `
    -ArtifactsRoot $artifactsRoot `
    -StagingPath $stagingPath

if (Test-Path -LiteralPath $resolvedStagingPath) {
    Remove-Item -LiteralPath $resolvedStagingPath -Recurse -Force
}

try {
    if (Test-Path -LiteralPath $snapshotZipPath) {
        Remove-Item -LiteralPath $snapshotZipPath -Force
    }
    New-GitAddonSnapshot `
        -RepoRoot $repoRoot `
        -SnapshotZipPath $snapshotZipPath `
        -Commit $headCommit
    Assert-ZipLayout `
        -ZipPath $snapshotZipPath `
        -ExpectedTopLevelDirectory 'AzerothTravelTracker' `
        -ExpectedFilePaths $trackedFiles
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $snapshotArchive = [System.IO.Compression.ZipFile]::OpenRead($snapshotZipPath)
    try {
        Assert-IconAssetArchiveEntries -EntryNames @(
            $snapshotArchive.Entries | ForEach-Object { $_.FullName }
        )
    }
    finally {
        $snapshotArchive.Dispose()
    }

    [System.IO.Compression.ZipFile]::ExtractToDirectory(
        $snapshotZipPath,
        $artifactsRoot
    )
    $interface = Assert-AddonManifest `
        -TocPath (Join-Path $resolvedStagingPath 'AzerothTravelTracker.toc') `
        -AddonRoot $resolvedStagingPath `
        -ExpectedVersion $Version
    Write-Output "Validated addon manifest for Interface $interface."

    Assert-CleanAddonWorktree -RepoRoot $repoRoot
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Move-Item -LiteralPath $snapshotZipPath -Destination $zipPath
}
finally {
    if (Test-Path -LiteralPath $snapshotZipPath) {
        Remove-Item -LiteralPath $snapshotZipPath -Force
    }
}

Write-Output ([System.IO.Path]::GetFullPath($zipPath))
