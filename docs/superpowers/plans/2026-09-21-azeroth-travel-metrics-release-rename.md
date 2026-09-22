# Azeroth Travel Metrics Release Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Atomically rename the unreleased addon to Azeroth Travel Metrics `1.0.0-beta`, preserve the developer's local test data, and produce a clean CurseForge-ready package with `/atm` as its only slash command.

**Architecture:** Rename the repository, addon root, TOC, namespace, SavedVariables, frames, runtime media, package identity, tests, and active documentation as one coordinated release change. Keep legacy ATT handling out of the distributed addon; a separate fail-closed PowerShell migration tool preserves only the current local beta data before the new ATM package is installed and ForeverSVFix is reapplied.

**Tech Stack:** World of Warcraft Lua and TOC metadata, SavedVariables, dependency-free Lua tests, PowerShell validation and migration tests, Python/Pillow icon generation, Git, ForeverSVFix.

**Approved design:** `docs/superpowers/specs/2026-09-21-azeroth-travel-metrics-release-rename-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `AzerothTravelMetrics/AzerothTravelMetrics.toc` | New addon identity, version, SavedVariables declaration, icon, and load order. |
| `AzerothTravelMetrics/*.lua` | Runtime namespace and all named UI/runtime identities changed from ATT to ATM without behavioral changes. |
| `AzerothTravelMetrics/Media/ATMLogo.tga` | Renamed title/minimap runtime badge. |
| `tests/test_*.lua` | Load the renamed addon files and assert ATM globals, frames, messages, media, version, and sole slash command. |
| `tests/test_icon_assets.py` | Assert the icon builder targets `AzerothTravelMetrics/Media/ATMLogo.tga`. |
| `tests/Test-PackageAddon.ps1` | Assert the new TOC metadata, archive root, runtime assets, and package filename. |
| `tests/Test-ReleaseIdentity.ps1` | Reject legacy ATT identity from active release surfaces except the explicit local migration files. |
| `tests/Test-MigrateLocalATTData.ps1` | Exercise successful and fail-closed local SavedVariables migration in temporary fixtures. |
| `tools/Build-IconAssets.py` | Write generated textures under the renamed addon folder and target `ATMLogo.tga`. |
| `tools/Set-InterfaceVersion.ps1` | Update `AzerothTravelMetrics/AzerothTravelMetrics.toc`. |
| `tools/Package-Addon.ps1` | Validate and package `AzerothTravelMetrics-<version>.zip`. |
| `tools/Migrate-LocalATTData.ps1` | One-time local migration from the developer's ATT SavedVariables file to ATM. Never included in the addon archive. |
| `README.md` | ATM installation, commands, data name, package commands, and release version. |
| `docs/BETA-SMOKE-TESTS.md` | Active ATM smoke checklist and final observed rename results. |

## Task 1: Lock the New Release Identity in Tests

**Files:**
- Modify: `tests/test_namespace.lua`
- Modify: `tests/test_core.lua`
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_minimap.lua`
- Create: `tests/Test-ReleaseIdentity.ps1`
- Modify: `tests/Test-PackageAddon.ps1`

- [ ] **Step 1: Change Lua identity expectations before production files**

Update addon paths in every Lua test from:

```lua
"AzerothTravelTracker\\Namespace.lua"
```

to:

```lua
"AzerothTravelMetrics\\Namespace.lua"
```

Apply the same directory change to every loaded module. In
`tests/test_namespace.lua`, require the loader to receive the new addon name:

```lua
local addon = testlib.loadAddon(
    "AzerothTravelMetrics\\Namespace.lua",
    {},
    "AzerothTravelMetrics"
)
testlib.equal(addon.name, "AzerothTravelMetrics")
```

Extend `tests/testlib.lua` with a third optional parameter:

```lua
function testlib.loadAddon(files, globals, addonName)
    if type(files) == "string" then
        files = { files }
    end

    local environment = globals or {}
    if getmetatable(environment) == nil then
        setmetatable(environment, { __index = _G })
    end
    environment._G = environment

    local addon = {}
    for _, path in ipairs(files) do
        local chunk = loadChunk(path, environment)
        chunk(addonName or "AzerothTravelMetrics", addon)
    end

    return addon, environment
end
```

- [ ] **Step 2: Require the new runtime globals and sole slash command**

In `tests/test_core.lua`, rename fixture globals and assertions:

```lua
globals.AzerothTravelMetricsDB = options.savedDB

testlib.equal(
    harness.environment.SLASH_AZEROTHTRAVELMETRICS1,
    "/atm"
)
testlib.equal(
    harness.environment.SLASH_AZEROTHTRAVELMETRICS2,
    nil
)
testlib.equal(
    type(harness.environment.SlashCmdList.AZEROTHTRAVELMETRICS),
    "function"
)
testlib.equal(
    harness.environment.SlashCmdList.AZEROTHTRAVELTRACKER,
    nil
)
```

Change expected frame and popup identifiers to:

```lua
"AzerothTravelMetricsFrame"
"AzerothTravelMetricsFrameOverviewTab"
"AzerothTravelMetricsFrameLevelTab"
"AzerothTravelMetricsHUD"
"AZEROTH_TRAVEL_METRICS_RESET_SESSION"
```

Change expected text/media to:

```lua
"[Azeroth Travel Metrics] "
"ATM v1.0.0-beta"
"Interface\\AddOns\\AzerothTravelMetrics\\Media\\ATMLogo"
"Interface\\AddOns\\AzerothTravelMetrics\\Media\\Overview"
"Interface\\AddOns\\AzerothTravelMetrics\\Media\\ByLevel"
```

- [ ] **Step 3: Add an active-release legacy identity guard**

Create `tests/Test-ReleaseIdentity.ps1`:

```powershell
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
    $_.FullName -notin $allowedLegacyFiles
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
```

- [ ] **Step 4: Update package-test expectations**

In `tests/Test-PackageAddon.ps1`, change fixture metadata and archive paths to:

```powershell
## Title: Azeroth Travel Metrics - WoW: Forever (beta)
## Version: 1.0.0-beta
## SavedVariables: AzerothTravelMetricsDB
```

Use these runtime archive entries:

```powershell
'AzerothTravelMetrics/Media/ATMLogo.tga'
'AzerothTravelMetrics/Media/ByLevel.tga'
'AzerothTravelMetrics/Media/Overview.tga'
```

Change all fixture addon roots and expected top-level directories from
`AzerothTravelTracker` to `AzerothTravelMetrics`.

- [ ] **Step 5: Run the identity tests and verify RED**

Run:

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') +
    ';' +
    [System.Environment]::GetEnvironmentVariable('Path','User')
lua .\tests\run.lua
.\tests\Test-PackageAddon.ps1
.\tests\Test-ReleaseIdentity.ps1
```

Expected: failures because the addon directory, namespace, runtime globals,
media, TOC metadata, and package root still use ATT.

## Task 2: Rename the Repository, Addon Tree, and Runtime Identity

**Files:**
- Move: `D:\_projects\wow-forever-step-tracker` to `D:\_projects\azeroth-travel-metrics`
- Move: `AzerothTravelTracker` to `AzerothTravelMetrics`
- Move: `AzerothTravelMetrics/AzerothTravelTracker.toc` to `AzerothTravelMetrics/AzerothTravelMetrics.toc`
- Move: `AzerothTravelMetrics/Media/ATTLogo.tga` to `AzerothTravelMetrics/Media/ATMLogo.tga`
- Modify: `AzerothTravelMetrics/*.lua`
- Modify: `tests/testlib.lua`
- Modify: `tests/test_*.lua`

- [ ] **Step 1: Move the repository and addon paths with Git**

Run from `D:\_projects` while no process uses the old repository directory:

```powershell
Set-Location 'D:\_projects'
Move-Item -LiteralPath '.\wow-forever-step-tracker' `
    -Destination '.\azeroth-travel-metrics'
Set-Location '.\azeroth-travel-metrics'
git mv '.\AzerothTravelTracker' '.\AzerothTravelMetrics'
git mv '.\AzerothTravelMetrics\AzerothTravelTracker.toc' `
    '.\AzerothTravelMetrics\AzerothTravelMetrics.toc'
git mv '.\AzerothTravelMetrics\Media\ATTLogo.tga' `
    '.\AzerothTravelMetrics\Media\ATMLogo.tga'
```

Expected: Git records directory/file renames and preserves history. The
existing dirty `docs/BETA-SMOKE-TESTS.md` remains intact.

- [ ] **Step 2: Rename the Lua namespace without changing behavior**

In every `AzerothTravelMetrics/*.lua` file, change:

```lua
local addonName, ATT = ...
```

to:

```lua
local addonName, ATM = ...
```

Change all namespace references from `ATT` to `ATM`, including module
registration, constants, callbacks, and cross-module calls. Do not rename
ordinary words that merely contain the letters `att`.

In `Namespace.lua`, preserve all values and callbacks while assigning:

```lua
ATM.name = addonName
ATM.VERSION_FALLBACK = "1.0.0-beta"
```

- [ ] **Step 3: Rename SavedVariables and user-visible runtime identity**

In `Core.lua`, use:

```lua
local savedDB = AzerothTravelMetricsDB
...
AzerothTravelMetricsDB = db
```

Register only:

```lua
SLASH_AZEROTHTRAVELMETRICS1 = "/atm"

SlashCmdList.AZEROTHTRAVELMETRICS = function(message)
    -- existing command behavior unchanged
end
```

Change the chat prefix to:

```lua
"[Azeroth Travel Metrics] "
```

In `UI.lua`, rename the popup key and named frames:

```lua
local RESET_DIALOG_KEY = "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
"AzerothTravelMetricsFrame"
"AzerothTravelMetricsFrameOverviewTab"
"AzerothTravelMetricsFrameLevelTab"
"AzerothTravelMetricsHUD"
```

Change the title/footer to:

```lua
"Azeroth Travel Metrics"
"ATM v" .. getVersion()
```

In `UITheme.lua`, use:

```lua
TITLE = "Interface\\AddOns\\AzerothTravelMetrics\\Media\\ATMLogo"
OVERVIEW = "Interface\\AddOns\\AzerothTravelMetrics\\Media\\Overview"
LEVELS = "Interface\\AddOns\\AzerothTravelMetrics\\Media\\ByLevel"
```

- [ ] **Step 4: Write the new TOC identity**

`AzerothTravelMetrics/AzerothTravelMetrics.toc` must begin:

```text
## Interface: 16001
## Title: Azeroth Travel Metrics - WoW: Forever (beta)
## Notes: Tracks estimated steps and travel distance.
## Author: Jason Parker
## Version: 1.0.0-beta
## IconTexture: Interface\Icons\Ability_Rogue_Sprint
## SavedVariables: AzerothTravelMetricsDB
```

Keep the existing Lua load order unchanged.

- [ ] **Step 5: Run Lua tests**

Run:

```powershell
Set-Location 'D:\_projects\azeroth-travel-metrics'
lua .\tests\run.lua
```

Expected: all Lua tests pass. Package and identity tests may still fail until
Task 3 updates tooling and documentation.

- [ ] **Step 6: Commit runtime rename**

```powershell
git add AzerothTravelMetrics tests
git commit -m "refactor: rename addon runtime to Azeroth Travel Metrics" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 3: Rename Build, Package, Media, and Active Documentation

**Files:**
- Modify: `tools/Build-IconAssets.py`
- Modify: `tools/Set-InterfaceVersion.ps1`
- Modify: `tools/Package-Addon.ps1`
- Modify: `tests/test_icon_assets.py`
- Modify: `tests/Test-PackageAddon.ps1`
- Validate: `tests/Test-ReleaseIdentityContent.ps1`
- Modify: `tests/Test-ReleaseIdentity.ps1`
- Modify: `README.md`
- Modify: `docs/BETA-SMOKE-TESTS.md`

- [ ] **Step 1: Point icon generation at ATM media**

In `tools/Build-IconAssets.py`, use:

```python
TARGET = ROOT / "AzerothTravelMetrics" / "Media"
ASSET_NAMES = ("ATMLogo.tga", "Overview.tga", "ByLevel.tga")
```

Change the badge target:

```python
"azeroth_travel_metrics.jpg": {
    "target": "ATMLogo.tga",
    "mask": "circle",
    "isolate": "boot",
    "crop": (
        540 / 2048,
        810 / 2048,
        880 / 2048,
        1150 / 2048,
    ),
},
```

Make the same expected-name changes in `tests/test_icon_assets.py`.

- [ ] **Step 2: Rename interface-version tooling**

In `tools/Set-InterfaceVersion.ps1`, set:

```powershell
$addonTocPath = Join-Path $PSScriptRoot `
    '..\AzerothTravelMetrics\AzerothTravelMetrics.toc'
```

Keep interface discovery and replacement behavior unchanged.

- [ ] **Step 3: Rename package constants and validation**

In `tools/Package-Addon.ps1`, use these exact identities:

```powershell
param([string]$Version = '1.0.0-beta')

$addonDirectoryName = 'AzerothTravelMetrics'
$expectedTitle = 'Azeroth Travel Metrics - WoW: Forever (beta)'
$expectedSavedVariables = 'AzerothTravelMetricsDB'
$expectedLogo = 'AzerothTravelMetrics/Media/ATMLogo.tga'
```

Derive paths from `$addonDirectoryName` instead of repeating literal folder
names:

```powershell
$addonRoot = Join-Path $repoRoot $addonDirectoryName
$stagingPath = Join-Path $artifactsRoot $addonDirectoryName
$zipPath = Join-Path $artifactsRoot "$addonDirectoryName-$Version.zip"
$snapshotZipPath = Join-Path $artifactsRoot ".$addonDirectoryName-head.zip"
```

Update tracked-tree prefix validation, archive root validation, required
textures, and status messages to use `AzerothTravelMetrics`.

- [ ] **Step 4: Rewrite active documentation**

Update `README.md` and `docs/BETA-SMOKE-TESTS.md` to use:

```text
Azeroth Travel Metrics
AzerothTravelMetrics
AzerothTravelMetrics.toc
AzerothTravelMetricsDB
/atm
ATM v1.0.0-beta
AzerothTravelMetrics-1.0.0-beta.zip
```

Document only `/atm`; remove `/azerothtraveltracker` and `/att`. Update the
package command example:

```powershell
.\tools\Package-Addon.ps1 -Version '1.0.0-beta'
```

Do not rewrite completed historical specs or plans solely to remove ATT names.

- [ ] **Step 5: Run all rename and packaging tests**

Run:

```powershell
python -m pytest -q .\tests\test_icon_assets.py
lua .\tests\run.lua
.\tests\Test-PackageAddon.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
```

Expected:

```text
7 passed
all Lua tests passed, 0 failed
32 passed, 0 failed, 1 skipped
Release identity content tests: 7 passed, 0 failed
PASS active release surfaces use only the ATM identity
```

- [ ] **Step 6: Commit release-surface rename**

```powershell
git add README.md docs\BETA-SMOKE-TESTS.md tools tests `
  AzerothTravelMetrics\Media
git commit -m "build: rename release artifacts to Azeroth Travel Metrics" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 4: Add Fail-Closed Local SavedVariables Migration

**Files:**
- Create: `tools/Migrate-LocalATTData.ps1`
- Create: `tests/Test-MigrateLocalATTData.ps1`

- [ ] **Step 1: Write migration failure and success fixtures**

Create `tests/Test-MigrateLocalATTData.ps1`. Dot-source the migration script
with `ATM_MIGRATION_FUNCTIONS_ONLY=1`, then test temporary files for:

1. missing old file;
2. existing destination refusal;
3. zero legacy root assignments;
4. duplicate legacy root assignments;
5. exact successful replacement;
6. unchanged bytes before and after the equal-length root token;
7. backup creation with filename format `YYYYMMDD_HHMMSS`;
8. byte-identical backup content;
9. no source mutation;
10. UTF-8 BOM preservation;
11. UTF-8 without a BOM preservation;
12. invalid UTF-8 refusal before backup or destination creation.

Representative success assertion:

```powershell
$sourceBytes = [System.Text.Encoding]::UTF8.GetBytes(
    "AzerothTravelTrackerDB = {`n  characters = { ['Éowyn'] = {} },`n}`n"
)
[System.IO.File]::WriteAllBytes($oldPath, $sourceBytes)

$result = Invoke-LocalSavedVariablesMigration `
    -OldSavedVariablesPath $oldPath `
    -NewSavedVariablesPath $newPath `
    -BackupDirectory $backupRoot `
    -WowProcessName ('NoSuchProcess-' + [guid]::NewGuid().ToString('N'))

$newBytes = [System.IO.File]::ReadAllBytes($newPath)
$restored = [System.Text.Encoding]::UTF8.GetString($newBytes) `
    -replace 'AzerothTravelMetricsDB', 'AzerothTravelTrackerDB'

if ($restored -cne [System.Text.Encoding]::UTF8.GetString($sourceBytes)) {
    throw 'Migration changed data outside the SavedVariables root name.'
}
```

- [ ] **Step 2: Run migration tests and verify RED**

Run:

```powershell
.\tests\Test-MigrateLocalATTData.ps1
```

Expected: failure because `tools/Migrate-LocalATTData.ps1` does not exist.

- [ ] **Step 3: Implement the migration function**

Create `tools/Migrate-LocalATTData.ps1` with:

```powershell
param(
    [string]$OldSavedVariablesPath = (
        'D:\Games\World of Warcraft\_classic_beta_\WTF\Account\' +
        '50347838#1\SavedVariables\AzerothTravelTracker.lua'
    ),
    [string]$NewSavedVariablesPath = (
        'D:\Games\World of Warcraft\_classic_beta_\WTF\Account\' +
        '50347838#1\SavedVariables\AzerothTravelMetrics.lua'
    ),
    [string]$BackupDirectory = (
        'D:\Games\World of Warcraft\_classic_beta_\WTF\ForeverSVFix\' +
        'migration-backups'
    ),
    [string]$WowProcessName = 'WowB'
)

$ErrorActionPreference = 'Stop'

function Invoke-LocalSavedVariablesMigration {
    param(
        [Parameter(Mandatory)][string]$OldSavedVariablesPath,
        [Parameter(Mandatory)][string]$NewSavedVariablesPath,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [string]$WowProcessName = 'WowB'
    )

    if (Get-Process -Name $WowProcessName -ErrorAction SilentlyContinue) {
        throw 'WoW must be closed before migrating SavedVariables.'
    }
    if (-not (Test-Path -LiteralPath $OldSavedVariablesPath -PathType Leaf)) {
        throw "Legacy SavedVariables file does not exist: $OldSavedVariablesPath"
    }
    if (Test-Path -LiteralPath $NewSavedVariablesPath) {
        throw "ATM SavedVariables destination already exists: $NewSavedVariablesPath"
    }

    $bytes = [System.IO.File]::ReadAllBytes($OldSavedVariablesPath)
    $hasBom = $bytes.Length -ge 3 `
        -and $bytes[0] -eq 0xEF `
        -and $bytes[1] -eq 0xBB `
        -and $bytes[2] -eq 0xBF
    $bodyOffset = 0
    if ($hasBom) {
        $bodyOffset = 3
    }
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $encoding.GetString(
        $bytes,
        $bodyOffset,
        $bytes.Length - $bodyOffset
    )
    $pattern = '(?m)^AzerothTravelTrackerDB([ \t]*)='
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one legacy SavedVariables root, found $($matches.Count)."
    }

    $updated = [regex]::Replace(
        $text,
        $pattern,
        'AzerothTravelMetricsDB$1=',
        1
    )
    $roundTrip = [regex]::Replace(
        $updated,
        '(?m)^AzerothTravelMetricsDB([ \t]*)=',
        'AzerothTravelTrackerDB$1=',
        1
    )
    if ($roundTrip -cne $text) {
        throw 'Migration changed content outside the SavedVariables root.'
    }

    $updatedBody = $encoding.GetBytes($updated)
    if ($hasBom) {
        $updatedBytes = [byte[]]::new($updatedBody.Length + 3)
        $updatedBytes[0] = 0xEF
        $updatedBytes[1] = 0xBB
        $updatedBytes[2] = 0xBF
        [System.Array]::Copy(
            $updatedBody,
            0,
            $updatedBytes,
            3,
            $updatedBody.Length
        )
    }
    else {
        $updatedBytes = $updatedBody
    }

    $roundTripBody = $encoding.GetBytes($roundTrip)
    if ($hasBom) {
        $roundTripBytes = [byte[]]::new($roundTripBody.Length + 3)
        $roundTripBytes[0] = 0xEF
        $roundTripBytes[1] = 0xBB
        $roundTripBytes[2] = 0xBF
        [System.Array]::Copy(
            $roundTripBody,
            0,
            $roundTripBytes,
            3,
            $roundTripBody.Length
        )
    }
    else {
        $roundTripBytes = $roundTripBody
    }
    $bytesEqual = $bytes.Length -eq $roundTripBytes.Length
    if ($bytesEqual) {
        for ($index = 0; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -ne $roundTripBytes[$index]) {
                $bytesEqual = $false
                break
            }
        }
    }
    if (-not $bytesEqual) {
        throw 'Migration byte verification failed.'
    }

    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupPath = Join-Path $BackupDirectory (
        "AzerothTravelTracker_$stamp.lua"
    )
    if (Test-Path -LiteralPath $backupPath) {
        throw "Migration backup already exists: $backupPath"
    }
    Copy-Item -LiteralPath $OldSavedVariablesPath -Destination $backupPath
    [System.IO.File]::WriteAllBytes(
        $NewSavedVariablesPath,
        $updatedBytes
    )

    return [pscustomobject]@{
        BackupPath = $backupPath
        OldHash = (Get-FileHash -LiteralPath $OldSavedVariablesPath -Algorithm SHA256).Hash
        NewHash = (Get-FileHash -LiteralPath $NewSavedVariablesPath -Algorithm SHA256).Hash
    }
}

if ($env:ATM_MIGRATION_FUNCTIONS_ONLY -ne '1') {
    Invoke-LocalSavedVariablesMigration `
        -OldSavedVariablesPath $OldSavedVariablesPath `
        -NewSavedVariablesPath $NewSavedVariablesPath `
        -BackupDirectory $BackupDirectory `
        -WowProcessName $WowProcessName
}
```

Add both BOM and no-BOM UTF-8 fixtures. Invalid UTF-8 must fail before a
destination or backup is created.

- [ ] **Step 4: Run migration and identity tests**

Run:

```powershell
.\tests\Test-MigrateLocalATTData.ps1
.\tests\Test-ReleaseIdentity.ps1
```

Expected: all migration fixtures pass, and the identity guard permits legacy
names only in the two explicit migration files and in historical docs.

- [ ] **Step 5: Commit migration tooling**

```powershell
git add tools\Migrate-LocalATTData.ps1 `
  tests\Test-MigrateLocalATTData.ps1 `
  tests\Test-ReleaseIdentity.ps1
git commit -m "build: add local ATT to ATM data migration" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 5: Build, Migrate, Install, and Verify ATM

**Files:**
- Build: `artifacts/AzerothTravelMetrics-1.0.0-beta.zip`
- Install: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics`
- Preserve: current ATT and new ATM SavedVariables until smoke approval

- [ ] **Step 1: Run complete automated validation**

Run:

```powershell
Set-Location 'D:\_projects\azeroth-travel-metrics'
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') +
    ';' +
    [System.Environment]::GetEnvironmentVariable('Path','User')
python -m pytest -q .\tests\test_icon_assets.py
lua .\tests\run.lua
.\tests\Test-PackageAddon.ps1
.\tests\Test-MigrateLocalATTData.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
.\tools\Package-Addon.ps1 -Version '1.0.0-beta'
Get-FileHash `
  -LiteralPath '.\artifacts\AzerothTravelMetrics-1.0.0-beta.zip' `
  -Algorithm SHA256
```

Require zero failures, seven passing release identity regression cases, only
the existing privilege-dependent package skip, one `AzerothTravelMetrics`
archive root, exactly three TGA assets, and no source artwork or ForeverSVFix
artifacts.

- [ ] **Step 2: Stop if WoW is running**

Run:

```powershell
if (Get-Process -Name WowB -ErrorAction SilentlyContinue) {
    throw 'WoW must be closed before migrating or installing ATM.'
}
```

Never terminate the client automatically.

- [ ] **Step 3: Migrate the local SavedVariables**

Run:

```powershell
.\tools\Migrate-LocalATTData.ps1
```

Record the old file hash, new file hash, and migration backup path. Confirm the
old active file remains untouched.

- [ ] **Step 4: Replace only the exact installed addon folders**

Use exact paths and no wildcards:

```powershell
$wow = 'D:\Games\World of Warcraft\_classic_beta_'
$installRoot = Join-Path $wow 'Interface\AddOns'
$oldInstalled = Join-Path $installRoot 'AzerothTravelTracker'
$newInstalled = Join-Path $installRoot 'AzerothTravelMetrics'
$zip = 'D:\_projects\azeroth-travel-metrics\artifacts\AzerothTravelMetrics-1.0.0-beta.zip'
$staging = Join-Path $env:TEMP 'AzerothTravelMetrics-install'

if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Path $staging | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force
$stagedEntries = @(Get-ChildItem -LiteralPath $staging)
$stagedAddon = Join-Path $staging 'AzerothTravelMetrics'
$stagedToc = Join-Path $stagedAddon 'AzerothTravelMetrics.toc'
if (
    $stagedEntries.Count -ne 1 `
    -or $stagedEntries[0].Name -ne 'AzerothTravelMetrics' `
    -or -not (Test-Path -LiteralPath $stagedToc -PathType Leaf)
) {
    throw 'Package does not contain the expected single ATM addon root.'
}
if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) {
    throw "Unexpected AddOns install path: $installRoot"
}

if (Test-Path -LiteralPath $newInstalled) {
    Remove-Item -LiteralPath $newInstalled -Recurse -Force
}
Move-Item `
    -LiteralPath (Join-Path $staging 'AzerothTravelMetrics') `
    -Destination $newInstalled

if (Test-Path -LiteralPath $oldInstalled) {
    Remove-Item -LiteralPath $oldInstalled -Recurse -Force
}
Remove-Item -LiteralPath $staging -Recurse -Force
```

- [ ] **Step 5: Reapply ForeverSVFix**

Run:

```powershell
python D:\_projects\ForeverSVFix\forever_sv_fix.py `
  --wow 'D:\Games\World of Warcraft\_classic_beta_' `
  --account '50347838#1' repair

python D:\_projects\ForeverSVFix\forever_sv_fix.py `
  --wow 'D:\Games\World of Warcraft\_classic_beta_' `
  --account '50347838#1' doctor
```

Require:

```text
Active installation checks: OK
No repair needed.
```

- [ ] **Step 6: Verify installed identity and data**

Confirm:

```powershell
$installed = 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics'
$saved = 'D:\Games\World of Warcraft\_classic_beta_\WTF\Account\50347838#1\SavedVariables\AzerothTravelMetrics.lua'
$linked = Join-Path $installed 'ForeverSVFixData\AzerothTravelMetrics.lua'

Get-FileHash -LiteralPath $saved -Algorithm SHA256
Get-FileHash -LiteralPath $linked -Algorithm SHA256
Get-Content -LiteralPath (Join-Path $installed 'AzerothTravelMetrics.toc')
```

The active and linked ATM hashes must match. The generated restore entry must
follow `Core.lua`. The installed addon must contain no ATT-named files or
directories.

## Task 6: Smoke Test, Archive Legacy Data, and Prepare Release

**Files:**
- Modify: `docs/BETA-SMOKE-TESTS.md`
- Archive after approval: old active `AzerothTravelTracker.lua`

- [ ] **Step 1: Perform focused in-game acceptance**

Launch the Forever beta and verify:

1. AddOns lists **Azeroth Travel Metrics - WoW: Forever (beta)** version
   `1.0.0-beta`.
2. Existing lifetime, session, and By Level data are intact.
3. `/atm` opens the window and all subcommands work.
4. `/att` and `/azerothtraveltracker` are not registered.
5. The title reads **Azeroth Travel Metrics** and the footer reads
   `ATM v1.0.0-beta`.
6. The title/minimap badge, native Condense/Expand controls, Settings footer,
   10-pixel gaps, layering, scrollbar, and minimap rim placement still pass.
7. Closing/reopening and `/reload` preserve the migrated data.
8. No Lua errors or legacy ATT chat prefixes appear.

- [ ] **Step 2: Record only observed evidence**

Update only rename, launch, reload, persistence, controls, and package identity
rows in `docs/BETA-SMOKE-TESTS.md`. Do not mark unrelated movement scenarios
complete.

- [ ] **Step 3: Archive the old active SavedVariables file**

Only after Step 1 confirms ATM loaded the migrated data:

```powershell
$oldSaved = 'D:\Games\World of Warcraft\_classic_beta_\WTF\Account\50347838#1\SavedVariables\AzerothTravelTracker.lua'
$archiveRoot = 'D:\Games\World of Warcraft\_classic_beta_\WTF\ForeverSVFix\migration-backups'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$archivePath = Join-Path $archiveRoot "AzerothTravelTracker_retired_$stamp.lua"

if (Test-Path -LiteralPath $oldSaved -PathType Leaf) {
    Move-Item -LiteralPath $oldSaved -Destination $archivePath
}
```

Re-run ForeverSVFix `doctor` and confirm ATM remains healthy.

- [ ] **Step 4: Commit smoke evidence**

```powershell
git add docs\BETA-SMOKE-TESTS.md
git commit -m "docs: record Azeroth Travel Metrics beta release smoke test" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

- [ ] **Step 5: Final release verification**

Run:

```powershell
python -m pytest -q .\tests\test_icon_assets.py
lua .\tests\run.lua
.\tests\Test-PackageAddon.ps1
.\tests\Test-MigrateLocalATTData.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
.\tools\Package-Addon.ps1 -Version '1.0.0-beta'
git --no-pager status --short
```

Expected: all tests pass, including all seven release identity regression
cases and the standalone identity guard; the package is reproducible, and the
only working tree changes are intentional release artifacts ignored by Git.

## Completion Criteria

1. The repository and addon roots are named `azeroth-travel-metrics` and
   `AzerothTravelMetrics`.
2. Active runtime, test, tooling, package, install, and documentation surfaces
   use ATM identity exclusively except the explicit local migration files.
3. The distributed addon declares only `AzerothTravelMetricsDB` and registers
   only `/atm`.
4. The package is `AzerothTravelMetrics-1.0.0-beta.zip` with one matching
   top-level directory.
5. Existing local test data is preserved and loads under the ATM identity.
6. ForeverSVFix doctor reports healthy after the renamed installation.
7. Focused in-game launch, reload, UI, and persistence checks pass.
8. The old SavedVariables file is archived only after successful ATM smoke
   confirmation.
