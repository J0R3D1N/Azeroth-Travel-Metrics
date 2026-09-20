$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageScript = Join-Path $repoRoot 'tools\Package-Addon.ps1'

if (-not (Test-Path -LiteralPath $packageScript -PathType Leaf)) {
    throw "Package script does not exist: $packageScript"
}

$env:ATT_PACKAGE_VALIDATION_ONLY = '1'
. $packageScript
Remove-Item Env:\ATT_PACKAGE_VALIDATION_ONLY

$passed = 0
$failed = 0

function Test-Throws {
    param(
        [string]$Name,
        [scriptblock]$Action,
        [string]$MessagePattern
    )

    try {
        & $Action
        Write-Output "FAIL $Name"
        Write-Output '  Expected an exception.'
        $script:failed++
    }
    catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            Write-Output "FAIL $Name"
            Write-Output "  Unexpected error: $($_.Exception.Message)"
            $script:failed++
            return
        }

        Write-Output "PASS $Name"
        $script:passed++
    }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'AzerothTravelTracker-package-tests-' + [guid]::NewGuid().ToString('N')
)

try {
    $addonRoot = Join-Path $fixtureRoot 'AzerothTravelTracker'
    New-Item -ItemType Directory -Path $addonRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $addonRoot 'Present.lua') -Value '-- fixture'

    $missingFileToc = Join-Path $addonRoot 'MissingFile.toc'
    @'
## Interface: 16001
## Title: Azeroth Travel Tracker
## Version: 0.1.0-beta
## SavedVariables: AzerothTravelTrackerDB

Present.lua
Missing.lua
'@ | Set-Content -LiteralPath $missingFileToc

    Test-Throws `
        -Name 'manifest rejects a missing file entry' `
        -MessagePattern 'does not exist' `
        -Action { Assert-AddonManifest -TocPath $missingFileToc -AddonRoot $addonRoot }

    $nonnumericToc = Join-Path $addonRoot 'Nonnumeric.toc'
    @'
## Interface: beta
## Title: Azeroth Travel Tracker
## Version: 0.1.0-beta
## SavedVariables: AzerothTravelTrackerDB

Present.lua
'@ | Set-Content -LiteralPath $nonnumericToc

    Test-Throws `
        -Name 'manifest rejects a nonnumeric Interface' `
        -MessagePattern 'numeric Interface' `
        -Action { Assert-AddonManifest -TocPath $nonnumericToc -AddonRoot $addonRoot }

    $duplicateMetadataToc = Join-Path $addonRoot 'DuplicateMetadata.toc'
    @'
## Interface: 16001
## Title: Azeroth Travel Tracker
## Version: 0.1.0-beta
## Version: conflicting
## SavedVariables: AzerothTravelTrackerDB

Present.lua
'@ | Set-Content -LiteralPath $duplicateMetadataToc

    Test-Throws `
        -Name 'manifest rejects duplicate required metadata' `
        -MessagePattern 'exactly one Version' `
        -Action { Assert-AddonManifest -TocPath $duplicateMetadataToc -AddonRoot $addonRoot }

    $badZipSource = Join-Path $fixtureRoot 'bad-zip-source'
    New-Item -ItemType Directory -Path $badZipSource | Out-Null
    Set-Content -LiteralPath (Join-Path $badZipSource 'root-file.txt') -Value 'bad'
    $badZip = Join-Path $fixtureRoot 'bad-layout.zip'
    Compress-Archive -LiteralPath (Join-Path $badZipSource 'root-file.txt') -DestinationPath $badZip

    Test-Throws `
        -Name 'zip validation rejects files at archive root' `
        -MessagePattern 'top-level directory' `
        -Action { Assert-ZipLayout -ZipPath $badZip -ExpectedTopLevelDirectory 'AzerothTravelTracker' }

    $fixtureRepo = Join-Path $fixtureRoot 'repo'
    $redirectedArtifacts = Join-Path $fixtureRoot 'redirected-artifacts'
    $artifactsJunction = Join-Path $fixtureRepo 'artifacts'
    New-Item -ItemType Directory -Path $fixtureRepo | Out-Null
    New-Item -ItemType Directory -Path $redirectedArtifacts | Out-Null
    New-Item -ItemType Junction `
        -Path $artifactsJunction `
        -Target $redirectedArtifacts | Out-Null

    Test-Throws `
        -Name 'staging safety rejects an artifacts junction' `
        -MessagePattern 'reparse point' `
        -Action {
            Assert-SafeStagingPath `
                -RepoRoot $fixtureRepo `
                -ArtifactsRoot $artifactsJunction `
                -StagingPath (Join-Path $artifactsJunction 'AzerothTravelTracker')
        }
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

Write-Output "$passed passed, $failed failed"
if ($failed -gt 0) {
    exit 1
}
