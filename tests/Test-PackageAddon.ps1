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
$skipped = 0

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

function Test-DoesNotThrow {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        & $Action
        Write-Output "PASS $Name"
        $script:passed++
    }
    catch {
        Write-Output "FAIL $Name"
        Write-Output "  Unexpected error: $($_.Exception.Message)"
        $script:failed++
    }
}

function New-ZipFixture {
    param(
        [string]$Path,
        [string[]]$EntryNames
    )

    $archive = [System.IO.Compression.ZipFile]::Open(
        $Path,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        foreach ($entryName in $EntryNames) {
            $entry = $archive.CreateEntry($entryName)
            if (-not $entryName.EndsWith('/') -and -not $entryName.EndsWith('\')) {
                $writer = [System.IO.StreamWriter]::new($entry.Open())
                try {
                    $writer.Write('-- fixture')
                }
                finally {
                    $writer.Dispose()
                }
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function New-PackageRepoFixture {
    param([string]$Path)

    $fixtureAddonRoot = Join-Path $Path 'AzerothTravelTracker'
    New-Item -ItemType Directory -Path (Join-Path $Path 'tools') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Path 'tests') -Force | Out-Null
    New-Item -ItemType Directory -Path $fixtureAddonRoot -Force | Out-Null
    Copy-Item -LiteralPath $packageScript -Destination (Join-Path $Path 'tools\Package-Addon.ps1')
    Set-Content -LiteralPath (Join-Path $Path 'tests\run.lua') -Value "print('fixture Lua tests passed')"
    [System.IO.File]::WriteAllText(
        (Join-Path $fixtureAddonRoot 'Present.lua'),
        "-- fixture`n-- second line`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    @'
## Interface: 16001
## Title: Azeroth Travel Tracker - WoW: Forever (beta)
## Version: 0.1.0-beta
## SavedVariables: AzerothTravelTrackerDB

Present.lua
'@ | Set-Content -LiteralPath (Join-Path $fixtureAddonRoot 'AzerothTravelTracker.toc')

    & git -C $Path init --quiet
    & git -C $Path config user.name 'Package Fixture'
    & git -C $Path config user.email 'package-fixture@example.invalid'
    & git -C $Path config core.autocrlf false
    & git -C $Path add --all
    & git -C $Path commit --quiet -m 'fixture'
    if ($LASTEXITCODE -ne 0) {
        throw "Could not initialize package fixture repository: $Path"
    }

    return $fixtureAddonRoot
}

function Save-PackageRepoFixture {
    param([string]$Path)

    & git -C $Path add --all
    & git -C $Path commit --quiet -m 'update fixture'
    if ($LASTEXITCODE -ne 0) {
        throw "Could not update package fixture repository: $Path"
    }
}

function Invoke-PackageFixture {
    param([string]$RepoRoot)

    $hostExecutable = (Get-Process -Id $PID).Path
    $output = & $hostExecutable `
        -NoProfile `
        -File (Join-Path $RepoRoot 'tools\Package-Addon.ps1') 2>&1 |
        Out-String

    return @{
        ExitCode = $LASTEXITCODE
        Output = $output
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
## Title: Azeroth Travel Tracker - WoW: Forever (beta)
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
## Title: Azeroth Travel Tracker - WoW: Forever (beta)
## Version: 0.1.0-beta
## SavedVariables: AzerothTravelTrackerDB

Present.lua
'@ | Set-Content -LiteralPath $nonnumericToc

    Test-Throws `
        -Name 'manifest rejects a nonnumeric Interface' `
        -MessagePattern 'numeric Interface' `
        -Action { Assert-AddonManifest -TocPath $nonnumericToc -AddonRoot $addonRoot }

    $oldTitleToc = Join-Path $addonRoot 'OldTitle.toc'
    @'
## Interface: 16001
## Title: Azeroth Travel Tracker
## Version: 0.1.0-beta
## SavedVariables: AzerothTravelTrackerDB

Present.lua
'@ | Set-Content -LiteralPath $oldTitleToc

    Test-Throws `
        -Name 'manifest rejects the ambiguous pre-Forever title' `
        -MessagePattern 'WoW: Forever \(beta\)' `
        -Action {
            Assert-AddonManifest `
                -TocPath $oldTitleToc `
                -AddonRoot $addonRoot
        }

    $duplicateMetadataToc = Join-Path $addonRoot 'DuplicateMetadata.toc'
    @'
## Interface: 16001
## Title: Azeroth Travel Tracker - WoW: Forever (beta)
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

    $validZip = Join-Path $fixtureRoot 'valid-layout.zip'
    New-ZipFixture -Path $validZip -EntryNames @(
        'AzerothTravelTracker/',
        'AzerothTravelTracker/Present.lua',
        'AzerothTravelTracker\Nested\Present.lua'
    )
    Test-DoesNotThrow `
        -Name 'zip validation accepts normal entries and directory markers' `
        -Action { Assert-ZipLayout -ZipPath $validZip -ExpectedTopLevelDirectory 'AzerothTravelTracker' }

    Test-Throws `
        -Name 'zip validation rejects an omitted regular source file' `
        -MessagePattern 'archive file set does not match' `
        -Action {
            Assert-ZipLayout `
                -ZipPath $validZip `
                -ExpectedTopLevelDirectory 'AzerothTravelTracker' `
                -ExpectedFilePaths @('Present.lua', 'Nested/Present.lua', 'Missing.lua')
        }

    $invalidZipEntries = @(
        'AzerothTravelTracker/../escaped.lua',
        'AzerothTravelTracker/./Present.lua',
        'AzerothTravelTracker//Present.lua',
        'AzerothTravelTracker\..\escaped.lua',
        'AzerothTravelTracker\.\Present.lua',
        'AzerothTravelTracker\\Present.lua',
        '/AzerothTravelTracker/Present.lua',
        '\AzerothTravelTracker\Present.lua',
        'C:/AzerothTravelTracker/Present.lua',
        'C:\AzerothTravelTracker\Present.lua',
        'OtherAddon/Present.lua'
    )
    foreach ($invalidEntryName in $invalidZipEntries) {
        $invalidZip = Join-Path $fixtureRoot (
            'invalid-layout-' + [guid]::NewGuid().ToString('N') + '.zip'
        )
        New-ZipFixture -Path $invalidZip -EntryNames @($invalidEntryName)

        Test-Throws `
            -Name "zip validation rejects '$invalidEntryName'" `
            -MessagePattern 'top-level directory|invalid path' `
            -Action {
                Assert-ZipLayout `
                    -ZipPath $invalidZip `
                    -ExpectedTopLevelDirectory 'AzerothTravelTracker'
            }
    }

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

    $junctionRepo = Join-Path $fixtureRoot 'junction-source-repo'
    $junctionAddonRoot = New-PackageRepoFixture -Path $junctionRepo
    $externalJunctionTarget = Join-Path $fixtureRoot 'external-junction-target'
    New-Item -ItemType Directory -Path $externalJunctionTarget | Out-Null
    Set-Content `
        -LiteralPath (Join-Path $externalJunctionTarget 'External.lua') `
        -Value '-- must not be packaged'
    New-Item `
        -ItemType Junction `
        -Path (Join-Path $junctionAddonRoot 'LinkedExternal') `
        -Target $externalJunctionTarget | Out-Null

    Test-Throws `
        -Name 'package rejects a source junction before staging' `
        -MessagePattern 'reparse point' `
        -Action {
            $result = Invoke-PackageFixture -RepoRoot $junctionRepo
            if ($result.ExitCode -ne 0) {
                throw $result.Output
            }
        }
    Test-DoesNotThrow `
        -Name 'source junction failure leaves no staging or package output' `
        -Action {
            if (Test-Path -LiteralPath (Join-Path $junctionRepo 'artifacts')) {
                throw 'Artifacts were created before the source junction was rejected.'
            }
        }

    $rootJunctionRepo = Join-Path $fixtureRoot 'root-junction-source-repo'
    $rootJunctionAddon = New-PackageRepoFixture -Path $rootJunctionRepo
    $externalRootTarget = Join-Path $fixtureRoot 'external-addon-root'
    Move-Item -LiteralPath $rootJunctionAddon -Destination $externalRootTarget
    New-Item `
        -ItemType Junction `
        -Path $rootJunctionAddon `
        -Target $externalRootTarget | Out-Null

    Test-Throws `
        -Name 'package rejects a source root junction before staging' `
        -MessagePattern 'reparse point' `
        -Action {
            $result = Invoke-PackageFixture -RepoRoot $rootJunctionRepo
            if ($result.ExitCode -ne 0) {
                throw $result.Output
            }
        }
    Test-DoesNotThrow `
        -Name 'source root junction failure leaves no staging or package output' `
        -Action {
            if (Test-Path -LiteralPath (Join-Path $rootJunctionRepo 'artifacts')) {
                throw 'Artifacts were created before the source root junction was rejected.'
            }
        }

    $symlinkRepo = Join-Path $fixtureRoot 'symlink-source-repo'
    $symlinkAddonRoot = New-PackageRepoFixture -Path $symlinkRepo
    $externalSymlinkTarget = Join-Path $fixtureRoot 'external-symlink-target.lua'
    Set-Content -LiteralPath $externalSymlinkTarget -Value '-- must not be packaged'
    $symlinkCreated = $false
    try {
        New-Item `
            -ItemType SymbolicLink `
            -Path (Join-Path $symlinkAddonRoot 'LinkedExternal.lua') `
            -Target $externalSymlinkTarget `
            -ErrorAction Stop | Out-Null
        $symlinkCreated = $true
    }
    catch {
        Write-Output "SKIP package rejects a source file symbolic link ($($_.Exception.Message))"
        $skipped++
    }

    if ($symlinkCreated) {
        Test-Throws `
            -Name 'package rejects a source file symbolic link before staging' `
            -MessagePattern 'reparse point' `
            -Action {
                $result = Invoke-PackageFixture -RepoRoot $symlinkRepo
                if ($result.ExitCode -ne 0) {
                    throw $result.Output
                }
            }
        Test-DoesNotThrow `
            -Name 'source file symlink failure leaves no staging or package output' `
            -Action {
                if (Test-Path -LiteralPath (Join-Path $symlinkRepo 'artifacts')) {
                    throw 'Artifacts were created before the source file symlink was rejected.'
                }
            }
    }

    $snapshotRepo = Join-Path $fixtureRoot 'immutable-snapshot-repo'
    $snapshotAddonRoot = New-PackageRepoFixture -Path $snapshotRepo
    $snapshotZip = Join-Path $snapshotRepo 'snapshot.zip'
    Assert-CleanAddonWorktree -RepoRoot $snapshotRepo
    $trackedSnapshotFiles = @(Get-TrackedAddonFilesAtHead -RepoRoot $snapshotRepo)
    & git -C $snapshotRepo config core.autocrlf true

    $replacedAddonRoot = Join-Path $fixtureRoot 'validated-addon-root'
    Move-Item -LiteralPath $snapshotAddonRoot -Destination $replacedAddonRoot
    $maliciousAddonRoot = Join-Path $fixtureRoot 'malicious-addon-root'
    New-Item -ItemType Directory -Path $maliciousAddonRoot | Out-Null
    Set-Content `
        -LiteralPath (Join-Path $maliciousAddonRoot 'Present.lua') `
        -Value '-- malicious replacement'
    New-Item `
        -ItemType Junction `
        -Path $snapshotAddonRoot `
        -Target $maliciousAddonRoot | Out-Null

    Test-DoesNotThrow `
        -Name 'git snapshot ignores a post-validation addon junction swap' `
        -Action {
            New-GitAddonSnapshot `
                -RepoRoot $snapshotRepo `
                -SnapshotZipPath $snapshotZip
            Assert-ZipLayout `
                -ZipPath $snapshotZip `
                -ExpectedTopLevelDirectory 'AzerothTravelTracker' `
                -ExpectedFilePaths $trackedSnapshotFiles

            $archive = [System.IO.Compression.ZipFile]::OpenRead($snapshotZip)
            try {
                $entry = $archive.GetEntry('AzerothTravelTracker/Present.lua')
                if ($null -eq $entry) {
                    throw 'The immutable snapshot omitted Present.lua.'
                }

                $entryStream = $entry.Open()
                try {
                    $memory = [System.IO.MemoryStream]::new()
                    $entryStream.CopyTo($memory)
                    $content = $memory.ToArray()
                }
                finally {
                    $entryStream.Dispose()
                }

                $expected = [System.Text.Encoding]::UTF8.GetBytes(
                    "-- fixture`n-- second line`n"
                )
                if (
                    $content.Length -ne $expected.Length -or
                    [System.BitConverter]::ToString($content) -cne
                        [System.BitConverter]::ToString($expected)
                ) {
                    throw 'The immutable snapshot did not preserve exact HEAD blob bytes.'
                }
            }
            finally {
                $archive.Dispose()
            }
        }

    $dirtyTrackedRepo = Join-Path $fixtureRoot 'dirty-tracked-repo'
    $dirtyTrackedAddonRoot = New-PackageRepoFixture -Path $dirtyTrackedRepo
    Set-Content `
        -LiteralPath (Join-Path $dirtyTrackedAddonRoot 'Present.lua') `
        -Value '-- dirty tracked file'

    Test-Throws `
        -Name 'package rejects dirty tracked addon files' `
        -MessagePattern 'working tree must be clean.*Present.lua' `
        -Action {
            $result = Invoke-PackageFixture -RepoRoot $dirtyTrackedRepo
            if ($result.ExitCode -ne 0) {
                throw $result.Output
            }
        }

    $untrackedRepo = Join-Path $fixtureRoot 'untracked-addon-repo'
    $untrackedAddonRoot = New-PackageRepoFixture -Path $untrackedRepo
    Set-Content `
        -LiteralPath (Join-Path $untrackedAddonRoot 'Untracked.lua') `
        -Value '-- untracked addon file'

    Test-Throws `
        -Name 'package rejects untracked addon files' `
        -MessagePattern 'working tree must be clean.*Untracked.lua' `
        -Action {
            $result = Invoke-PackageFixture -RepoRoot $untrackedRepo
            if ($result.ExitCode -ne 0) {
                throw $result.Output
            }
        }

    $normalRepo = Join-Path $fixtureRoot 'normal-source-repo'
    $normalAddonRoot = New-PackageRepoFixture -Path $normalRepo
    New-Item -ItemType Directory -Path (Join-Path $normalAddonRoot 'Nested') | Out-Null
    Set-Content `
        -LiteralPath (Join-Path $normalAddonRoot 'Nested\Normal.lua') `
        -Value '-- nested fixture'
    Save-PackageRepoFixture -Path $normalRepo

    Test-DoesNotThrow `
        -Name 'normal clean repository packages successfully' `
        -Action {
            $result = Invoke-PackageFixture -RepoRoot $normalRepo
            if ($result.ExitCode -ne 0) {
                throw $result.Output
            }
            if (-not (Test-Path -LiteralPath (
                Join-Path $normalRepo 'artifacts\AzerothTravelTracker-0.1.0-beta.zip'
            ) -PathType Leaf)) {
                throw 'Expected package zip was not created.'
            }
        }
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

Write-Output "$passed passed, $failed failed, $skipped skipped"
if ($failed -gt 0) {
    exit 1
}
