$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageScript = Join-Path $repoRoot 'tools\Package-Addon.ps1'

if (-not (Test-Path -LiteralPath $packageScript -PathType Leaf)) {
    throw "Package script does not exist: $packageScript"
}

$env:ATM_PACKAGE_VALIDATION_ONLY = '1'
. $packageScript
Remove-Item Env:\ATM_PACKAGE_VALIDATION_ONLY

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

    $fixtureAddonRoot = Join-Path $Path 'AzerothTravelMetrics'
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
    $fixtureMediaRoot = Join-Path $fixtureAddonRoot 'Media'
    New-Item -ItemType Directory -Path $fixtureMediaRoot -Force | Out-Null
    foreach ($textureName in @('ATMLogo.tga', 'Overview.tga', 'ByLevel.tga')) {
        [System.IO.File]::WriteAllBytes(
            (Join-Path $fixtureMediaRoot $textureName),
            [byte[]](0, 1, 2, 3)
        )
    }
    @'
## Interface: 16001
## Title: Azeroth Travel Metrics - WoW: Forever (beta)
## Version: 1.0.0-beta
## SavedVariables: AzerothTravelMetricsDB

Present.lua
'@ | Set-Content -LiteralPath (Join-Path $fixtureAddonRoot 'AzerothTravelMetrics.toc')

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
    param(
        [string]$RepoRoot,
        [string]$HostExecutable = (Get-Process -Id $PID).Path
    )

    $output = & $HostExecutable `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $RepoRoot 'tools\Package-Addon.ps1') 2>&1 |
        Out-String

    return @{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'AzerothTravelMetrics-package-tests-' + [guid]::NewGuid().ToString('N')
)

try {
    $addonRoot = Join-Path $fixtureRoot 'AzerothTravelMetrics'
    New-Item -ItemType Directory -Path $addonRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $addonRoot 'Present.lua') -Value '-- fixture'

    $missingFileToc = Join-Path $addonRoot 'MissingFile.toc'
    @'
## Interface: 16001
## Title: Azeroth Travel Metrics - WoW: Forever (beta)
## Version: 1.0.0-beta
## SavedVariables: AzerothTravelMetricsDB

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
## Title: Azeroth Travel Metrics - WoW: Forever (beta)
## Version: 1.0.0-beta
## SavedVariables: AzerothTravelMetricsDB

Present.lua
'@ | Set-Content -LiteralPath $nonnumericToc

    Test-Throws `
        -Name 'manifest rejects a nonnumeric Interface' `
        -MessagePattern 'numeric Interface' `
        -Action { Assert-AddonManifest -TocPath $nonnumericToc -AddonRoot $addonRoot }

    $oldTitleToc = Join-Path $addonRoot 'OldTitle.toc'
    @'
## Interface: 16001
## Title: Azeroth Travel Metrics
## Version: 1.0.0-beta
## SavedVariables: AzerothTravelMetricsDB

Present.lua
'@ | Set-Content -LiteralPath $oldTitleToc

    Test-Throws `
        -Name 'manifest rejects the ambiguous pre-Forever title' `
        -MessagePattern (
            '\A' + [regex]::Escape(
                "Addon TOC Title must be 'Azeroth Travel Metrics - WoW: Forever (beta)', found 'Azeroth Travel Metrics'."
            ) + '\z'
        ) `
        -Action {
            Assert-AddonManifest `
                -TocPath $oldTitleToc `
                -AddonRoot $addonRoot
        }

    $duplicateMetadataToc = Join-Path $addonRoot 'DuplicateMetadata.toc'
    @'
## Interface: 16001
## Title: Azeroth Travel Metrics - WoW: Forever (beta)
## Version: 1.0.0-beta
## Version: conflicting
## SavedVariables: AzerothTravelMetricsDB

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
        -Action { Assert-ZipLayout -ZipPath $badZip -ExpectedTopLevelDirectory 'AzerothTravelMetrics' }

    $validZip = Join-Path $fixtureRoot 'valid-layout.zip'
    New-ZipFixture -Path $validZip -EntryNames @(
        'AzerothTravelMetrics/',
        'AzerothTravelMetrics/Present.lua',
        'AzerothTravelMetrics\Nested\Present.lua'
    )
    Test-DoesNotThrow `
        -Name 'zip validation accepts normal entries and directory markers' `
        -Action { Assert-ZipLayout -ZipPath $validZip -ExpectedTopLevelDirectory 'AzerothTravelMetrics' }

    Test-Throws `
        -Name 'zip validation rejects an omitted regular source file' `
        -MessagePattern 'archive file set does not match' `
        -Action {
            Assert-ZipLayout `
                -ZipPath $validZip `
                -ExpectedTopLevelDirectory 'AzerothTravelMetrics' `
                -ExpectedFilePaths @('Present.lua', 'Nested/Present.lua', 'Missing.lua')
        }

    $requiredTextures = @(
        'AzerothTravelMetrics/Media/ATMLogo.tga',
        'AzerothTravelMetrics/Media/Overview.tga',
        'AzerothTravelMetrics/Media/ByLevel.tga'
    )
    Test-DoesNotThrow `
        -Name 'icon archive accepts exactly the three runtime TGA entries' `
        -Action {
            Assert-IconAssetArchiveEntries -EntryNames $requiredTextures
        }
    Test-Throws `
        -Name 'icon archive rejects a missing runtime TGA entry' `
        -MessagePattern 'exactly the required runtime TGA entries' `
        -Action {
            Assert-IconAssetArchiveEntries -EntryNames $requiredTextures[0..1]
        }
    Test-Throws `
        -Name 'icon archive rejects source JPG and JPEG entries' `
        -MessagePattern 'source JPG or JPEG' `
        -Action {
            Assert-IconAssetArchiveEntries -EntryNames (
                $requiredTextures + @(
                    'AzerothTravelMetrics\artwork\source\overview_icon.jpg',
                    'AzerothTravelMetrics/source.jpeg'
                )
            )
        }
    Test-Throws `
        -Name 'icon archive rejects the tab iconography reference' `
        -MessagePattern 'tab_iconography' `
        -Action {
            Assert-IconAssetArchiveEntries -EntryNames (
                $requiredTextures + @(
                    'AzerothTravelMetrics\Media\tab_iconography.jpg'
                )
            )
        }

    $invalidZipEntries = @(
        'AzerothTravelMetrics/../escaped.lua',
        'AzerothTravelMetrics/./Present.lua',
        'AzerothTravelMetrics//Present.lua',
        'AzerothTravelMetrics\..\escaped.lua',
        'AzerothTravelMetrics\.\Present.lua',
        'AzerothTravelMetrics\\Present.lua',
        '/AzerothTravelMetrics/Present.lua',
        '\AzerothTravelMetrics\Present.lua',
        'C:/AzerothTravelMetrics/Present.lua',
        'C:\AzerothTravelMetrics\Present.lua',
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
                    -ExpectedTopLevelDirectory 'AzerothTravelMetrics'
            }
    }

    $failedPackageRoot = Join-Path $fixtureRoot 'failed-package'
    $failedPackageSource = Join-Path $failedPackageRoot 'AzerothTravelMetrics'
    $failedPackageOutput = Join-Path $failedPackageRoot 'output'
    New-Item -ItemType Directory -Path $failedPackageSource -Force | Out-Null
    New-Item -ItemType Directory -Path $failedPackageOutput -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $failedPackageSource 'A.lua') -Value '-- first'
    $lockedPackageSource = Join-Path $failedPackageSource 'B.lua'
    Set-Content -LiteralPath $lockedPackageSource -Value '-- locked'
    $failedPackagePath = Join-Path $failedPackageOutput 'release.zip'

    Test-Throws `
        -Name 'package write failure does not publish a new destination' `
        -MessagePattern 'being used by another process|cannot access the file' `
        -Action {
            $lockedStream = [System.IO.File]::Open(
                $lockedPackageSource,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            try {
                New-DeterministicAddonPackage `
                    -AddonRoot $failedPackageSource `
                    -ZipPath $failedPackagePath
            }
            finally {
                $lockedStream.Dispose()
            }
        }
    Test-DoesNotThrow `
        -Name 'failed package write leaves no destination or temporary file' `
        -Action {
            $remainingFiles = @(Get-ChildItem -LiteralPath $failedPackageOutput -File -Force)
            if ($remainingFiles.Count -ne 0) {
                throw "Packaging failure left output files: $($remainingFiles.Name -join ', ')"
            }
        }

    $existingPackagePath = Join-Path $failedPackageOutput 'existing-release.zip'
    New-ZipFixture `
        -Path $existingPackagePath `
        -EntryNames @('AzerothTravelMetrics/Previous.lua')
    $existingPackageHash = (
        Get-FileHash -LiteralPath $existingPackagePath -Algorithm SHA256
    ).Hash

    Test-Throws `
        -Name 'package write failure preserves a pre-existing destination' `
        -MessagePattern 'being used by another process|cannot access the file' `
        -Action {
            $lockedStream = [System.IO.File]::Open(
                $lockedPackageSource,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            try {
                New-DeterministicAddonPackage `
                    -AddonRoot $failedPackageSource `
                    -ZipPath $existingPackagePath
            }
            finally {
                $lockedStream.Dispose()
            }
        }
    Test-DoesNotThrow `
        -Name 'failed replacement leaves the existing destination unchanged and no temp file' `
        -Action {
            $actualHash = (
                Get-FileHash -LiteralPath $existingPackagePath -Algorithm SHA256
            ).Hash
            if ($actualHash -cne $existingPackageHash) {
                throw 'Packaging failure changed the pre-existing destination.'
            }

            $remainingFiles = @(Get-ChildItem -LiteralPath $failedPackageOutput -File -Force)
            if (
                $remainingFiles.Count -ne 1 -or
                $remainingFiles[0].FullName -cne $existingPackagePath
            ) {
                throw "Packaging failure left unexpected files: $($remainingFiles.Name -join ', ')"
            }
        }

    $successfulPackageRoot = Join-Path $fixtureRoot 'successful-package'
    $successfulPackageSource = Join-Path $successfulPackageRoot 'AzerothTravelMetrics'
    $successfulPackageOutput = Join-Path $successfulPackageRoot 'output'
    New-Item -ItemType Directory -Path $successfulPackageSource -Force | Out-Null
    New-Item -ItemType Directory -Path $successfulPackageOutput -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $successfulPackageSource 'Current.lua') -Value '-- current'
    $successfulPackagePath = Join-Path $successfulPackageOutput 'release.zip'
    New-ZipFixture `
        -Path $successfulPackagePath `
        -EntryNames @('AzerothTravelMetrics/Previous.lua')
    $previousPackageHash = (
        Get-FileHash -LiteralPath $successfulPackagePath -Algorithm SHA256
    ).Hash

    Test-DoesNotThrow `
        -Name 'successful package atomically replaces a pre-existing destination' `
        -Action {
            New-DeterministicAddonPackage `
                -AddonRoot $successfulPackageSource `
                -ZipPath $successfulPackagePath
            Assert-ZipLayout `
                -ZipPath $successfulPackagePath `
                -ExpectedTopLevelDirectory 'AzerothTravelMetrics' `
                -ExpectedFilePaths @('Current.lua')

            $currentPackageHash = (
                Get-FileHash -LiteralPath $successfulPackagePath -Algorithm SHA256
            ).Hash
            if ($currentPackageHash -ceq $previousPackageHash) {
                throw 'Successful packaging did not replace the previous destination.'
            }

            $remainingFiles = @(Get-ChildItem -LiteralPath $successfulPackageOutput -File -Force)
            if (
                $remainingFiles.Count -ne 1 -or
                $remainingFiles[0].FullName -cne $successfulPackagePath
            ) {
                throw "Successful packaging left unexpected files: $($remainingFiles.Name -join ', ')"
            }
        }

    $culturePackageRoot = Join-Path $fixtureRoot 'culture-package'
    $cultureAddonRoot = Join-Path $culturePackageRoot 'AzerothTravelMetrics'
    New-Item -ItemType Directory -Path $cultureAddonRoot -Force | Out-Null
    $unicodeName = ([char]0x00E4) + '.lua'
    foreach ($name in @('a.lua', 'z.lua', $unicodeName)) {
        Set-Content -LiteralPath (Join-Path $cultureAddonRoot $name) -Value "-- $name"
    }
    $culturePackages = @{}
    $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
    $originalUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture

    Test-DoesNotThrow `
        -Name 'Unicode package order and hash are ordinal across cultures' `
        -Action {
            try {
                foreach ($cultureName in @('en-US', 'sv-SE')) {
                    $culture = [System.Globalization.CultureInfo]::GetCultureInfo(
                        $cultureName
                    )
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
                    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture
                    $packagePath = Join-Path $culturePackageRoot "$cultureName.zip"
                    New-DeterministicAddonPackage `
                        -AddonRoot $cultureAddonRoot `
                        -ZipPath $packagePath
                    $culturePackages[$cultureName] = $packagePath
                }
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = $originalUiCulture
            }

            $expectedOrder = @('a.lua', 'z.lua', $unicodeName)
            [System.Array]::Sort(
                $expectedOrder,
                [System.StringComparer]::Ordinal
            )
            foreach ($cultureName in @('en-US', 'sv-SE')) {
                $archive = [System.IO.Compression.ZipFile]::OpenRead(
                    $culturePackages[$cultureName]
                )
                try {
                    $actualOrder = @(
                        $archive.Entries |
                            ForEach-Object {
                                $_.FullName.Substring('AzerothTravelMetrics/'.Length)
                            }
                    )
                }
                finally {
                    $archive.Dispose()
                }

                if (
                    [string]::Join("`n", $actualOrder) -cne
                        [string]::Join("`n", $expectedOrder)
                ) {
                    throw (
                        "$cultureName package order was not ordinal. " +
                        "Expected [$([string]::Join(', ', $expectedOrder))], " +
                        "actual [$([string]::Join(', ', $actualOrder))]."
                    )
                }
            }

            $enHash = (
                Get-FileHash -LiteralPath $culturePackages['en-US'] -Algorithm SHA256
            ).Hash
            $svHash = (
                Get-FileHash -LiteralPath $culturePackages['sv-SE'] -Algorithm SHA256
            ).Hash
            if ($enHash -cne $svHash) {
                throw "Culture changed package bytes: $enHash != $svHash"
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
                -StagingPath (Join-Path $artifactsJunction 'AzerothTravelMetrics')
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
    $repeatedSnapshotZip = Join-Path $snapshotRepo 'snapshot-repeat.zip'
    Assert-CleanAddonWorktree -RepoRoot $snapshotRepo
    $trackedSnapshotFiles = @(Get-TrackedAddonFilesAtHead -RepoRoot $snapshotRepo)
    if ($trackedSnapshotFiles -contains '') {
        throw 'Tracked addon files must not include a trailing empty Git record.'
    }
    & git -C $snapshotRepo config core.autocrlf true

    Test-DoesNotThrow `
        -Name 'git snapshot is byte-reproducible for the same commit' `
        -Action {
            New-GitAddonSnapshot `
                -RepoRoot $snapshotRepo `
                -SnapshotZipPath $snapshotZip
            Start-Sleep -Seconds 2
            New-GitAddonSnapshot `
                -RepoRoot $snapshotRepo `
                -SnapshotZipPath $repeatedSnapshotZip

            $firstHash = (
                Get-FileHash -LiteralPath $snapshotZip -Algorithm SHA256
            ).Hash
            $secondHash = (
                Get-FileHash -LiteralPath $repeatedSnapshotZip -Algorithm SHA256
            ).Hash
            if ($firstHash -cne $secondHash) {
                throw 'Git snapshots from the same commit were not identical.'
            }
        }

    $crossCommitRepo = Join-Path $fixtureRoot 'cross-commit-reproducibility-repo'
    New-PackageRepoFixture -Path $crossCommitRepo | Out-Null
    $firstAddonTree = (
        Invoke-GitText `
            -RepoRoot $crossCommitRepo `
            -Arguments 'rev-parse HEAD:AzerothTravelMetrics'
    ).Trim()
    $firstPackage = Join-Path $fixtureRoot 'first-cross-commit-package.zip'

    Test-DoesNotThrow `
        -Name 'packages are byte-reproducible across commits with the same addon tree' `
        -Action {
            $firstResult = Invoke-PackageFixture -RepoRoot $crossCommitRepo
            if ($firstResult.ExitCode -ne 0) {
                throw $firstResult.Output
            }
            Copy-Item `
                -LiteralPath (
                    Join-Path $crossCommitRepo `
                        'artifacts\AzerothTravelMetrics-1.0.0-beta.zip'
                ) `
                -Destination $firstPackage

            Set-Content `
                -LiteralPath (Join-Path $crossCommitRepo 'unrelated-root-file.txt') `
                -Value 'changes the enclosing commit without changing addon bytes'
            $env:GIT_AUTHOR_DATE = '2040-01-02T03:04:06+00:00'
            $env:GIT_COMMITTER_DATE = '2040-01-02T03:04:06+00:00'
            try {
                & git -C $crossCommitRepo add -- unrelated-root-file.txt
                & git -C $crossCommitRepo commit --quiet -m 'unrelated root change'
                if ($LASTEXITCODE -ne 0) {
                    throw 'Could not create the unrelated fixture commit.'
                }
            }
            finally {
                Remove-Item Env:\GIT_AUTHOR_DATE -ErrorAction SilentlyContinue
                Remove-Item Env:\GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
            }

            $secondAddonTree = (
                Invoke-GitText `
                    -RepoRoot $crossCommitRepo `
                    -Arguments 'rev-parse HEAD:AzerothTravelMetrics'
            ).Trim()
            if ($firstAddonTree -cne $secondAddonTree) {
                throw 'The unrelated fixture commit changed the addon tree.'
            }

            $secondResult = Invoke-PackageFixture -RepoRoot $crossCommitRepo
            if ($secondResult.ExitCode -ne 0) {
                throw $secondResult.Output
            }

            $firstHash = (
                Get-FileHash -LiteralPath $firstPackage -Algorithm SHA256
            ).Hash
            $secondHash = (
                Get-FileHash `
                    -LiteralPath (
                        Join-Path $crossCommitRepo `
                            'artifacts\AzerothTravelMetrics-1.0.0-beta.zip'
                    ) `
                    -Algorithm SHA256
            ).Hash
            if ($firstHash -cne $secondHash) {
                throw (
                    'Packages from identical addon trees were not identical: ' +
                    "$firstHash != $secondHash"
                )
            }
        }

    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    $powerShell = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $windowsPowerShell -or $null -eq $powerShell) {
        $missingRuntimes = @(
            if ($null -eq $windowsPowerShell) {
                'powershell.exe'
            }
            if ($null -eq $powerShell) {
                'pwsh'
            }
        )
        Write-Output (
            'SKIP packages are byte-reproducible across PowerShell runtimes ' +
            "(missing: $([string]::Join(', ', $missingRuntimes)))"
        )
        $skipped++
    }
    else {
        $crossRuntimeRepo = Join-Path $fixtureRoot 'cross-runtime-reproducibility-repo'
        New-PackageRepoFixture -Path $crossRuntimeRepo | Out-Null
        $windowsPowerShellPackage = Join-Path $fixtureRoot 'windows-powershell-package.zip'

        Test-DoesNotThrow `
            -Name 'packages are byte-reproducible across PowerShell runtimes' `
            -Action {
                $windowsPowerShellResult = Invoke-PackageFixture `
                    -RepoRoot $crossRuntimeRepo `
                    -HostExecutable $windowsPowerShell.Source
                if ($windowsPowerShellResult.ExitCode -ne 0) {
                    throw $windowsPowerShellResult.Output
                }
                Copy-Item `
                    -LiteralPath (
                        Join-Path $crossRuntimeRepo `
                            'artifacts\AzerothTravelMetrics-1.0.0-beta.zip'
                    ) `
                    -Destination $windowsPowerShellPackage

                $powerShellResult = Invoke-PackageFixture `
                    -RepoRoot $crossRuntimeRepo `
                    -HostExecutable $powerShell.Source
                if ($powerShellResult.ExitCode -ne 0) {
                    throw $powerShellResult.Output
                }

                $windowsPowerShellHash = (
                    Get-FileHash `
                        -LiteralPath $windowsPowerShellPackage `
                        -Algorithm SHA256
                ).Hash
                $powerShellHash = (
                    Get-FileHash `
                        -LiteralPath (
                            Join-Path $crossRuntimeRepo `
                                'artifacts\AzerothTravelMetrics-1.0.0-beta.zip'
                        ) `
                        -Algorithm SHA256
                ).Hash
                if ($windowsPowerShellHash -cne $powerShellHash) {
                    throw (
                        'Packages from different PowerShell runtimes were not identical: ' +
                        "$windowsPowerShellHash != $powerShellHash"
                    )
                }
            }
    }

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
                -ExpectedTopLevelDirectory 'AzerothTravelMetrics' `
                -ExpectedFilePaths $trackedSnapshotFiles

            $archive = [System.IO.Compression.ZipFile]::OpenRead($snapshotZip)
            try {
                $entry = $archive.GetEntry('AzerothTravelMetrics/Present.lua')
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
                Join-Path $normalRepo 'artifacts\AzerothTravelMetrics-1.0.0-beta.zip'
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
