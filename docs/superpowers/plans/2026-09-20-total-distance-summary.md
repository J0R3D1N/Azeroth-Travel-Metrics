# Total Distance Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a derived Total Distance footer to lifetime, session, current-level, and By Level statistics while keeping the main window at 420 x 430 pixels.

**Architecture:** Extend the pure `UIModel` summary with raw and formatted combined distance, then pass that value through the existing ordered summary-row contract. Extend `UITheme.CreateSection` with an optional footer-row index so the total can receive gold emphasis and a separator without coupling the theme to travel-statistic field names. Rebalance shared section geometry to fit five rows plus optional diagnostics inside the existing frame.

**Tech Stack:** World of Warcraft addon Lua, Blizzard frame APIs, dependency-free Lua test harness, PowerShell packaging scripts.

---

## File Map

| File | Responsibility |
|---|---|
| `AzerothTravelTracker\UIModel.lua` | Derive `totalYards` and the unit-formatted `total` value. |
| `AzerothTravelTracker\UITheme.lua` | Render an optional emphasized footer row and compact five-row section geometry. |
| `AzerothTravelTracker\UI.lua` | Add Total Distance to ordered summary rows and size Overview/By Level sections without enlarging the shell. |
| `tests\test_ui_model.lua` | Verify sums, unit formatting, level totals, and unchanged step semantics. |
| `tests\test_ui_theme.lua` | Verify footer separator, colors, row count, and compact section dimensions. |
| `tests\test_core.lua` | Verify Overview and By Level wiring and non-overlapping geometry. |
| `docs\BETA-SMOKE-TESTS.md` | Add in-client checks for total values and compact layout at supported UI scales. |

### Task 0: Preserve the Completed Screenshot Fixes

**Files:**
- Modify: `AzerothTravelTracker\UI.lua`
- Modify: `AzerothTravelTracker\Minimap.lua`
- Modify: `tests\test_core.lua`
- Modify: `tests\test_minimap.lua`
- Modify: `docs\BETA-SMOKE-TESTS.md`
- Modify: `docs\superpowers\plans\2026-09-20-character-panel-ui.md`
- Modify: `docs\superpowers\specs\2026-09-20-character-panel-ui-design.md`

- [ ] **Step 1: Verify the existing screenshot fixes**

Run:

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
lua tests\run.lua
git --no-pager diff --check
```

Expected: `192 passed, 0 failed` before total-distance tests are added, and no
whitespace errors.

- [ ] **Step 2: Commit the screenshot fixes as their own change**

```powershell
git add AzerothTravelTracker\UI.lua AzerothTravelTracker\Minimap.lua `
  tests\test_core.lua tests\test_minimap.lua `
  docs\BETA-SMOKE-TESTS.md `
  docs\superpowers\plans\2026-09-20-character-panel-ui.md `
  docs\superpowers\specs\2026-09-20-character-panel-ui-design.md
git commit -m "fix: polish tracker panel geometry" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

### Task 1: Derive Total Distance in the Presentation Model

**Files:**
- Modify: `tests\test_ui_model.lua`
- Modify: `AzerothTravelTracker\UIModel.lua`

- [ ] **Step 1: Add failing overview total tests**

Extend `ui overview includes raw and metric formatted category values`:

```lua
testlib.equal(overview.lifetime.totalYards, 3860)
testlib.equal(overview.lifetime.total, "3.53 km")
testlib.equal(overview.session.totalYards, 1030)
testlib.equal(overview.session.total, "941.8 m")
testlib.equal(overview.currentLevel.totalYards, 603)
testlib.equal(overview.currentLevel.total, "551.4 m")
```

Extend `ui overview uses imperial only when explicitly selected`:

```lua
testlib.equal(imperial.lifetime.total, "2.19 mi")
testlib.equal(unknown.lifetime.total, "3.53 km")
```

Extend `changing overview units changes strings only` inside the group loop:

```lua
testlib.equal(metricGroup.totalYards, imperialGroup.totalYards)
testlib.truthy(metricGroup.total ~= imperialGroup.total)
```

- [ ] **Step 2: Add a failing By Level total assertion**

Extend `ui level rows preserve timestamps and represent every category`:

```lua
testlib.equal(row.totalYards, 603)
testlib.equal(row.total, "603 yd")
```

- [ ] **Step 3: Run the presentation-model tests and verify RED**

Run:

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
lua tests\run.lua
```

Expected: failures report missing `totalYards` and `total` values; existing validation tests continue to execute without Lua errors.

- [ ] **Step 4: Implement the derived total**

In `buildSummary`, calculate the total once from validated components:

```lua
local function buildSummary(totals, raceFile, units)
    local rawSteps = ATT.Stride.EstimateSteps(totals.onFoot, raceFile)
    local totalYards = totals.onFoot + totals.swimming + totals.taxi

    return {
        rawSteps = rawSteps,
        steps = ATT.Distance.FormatNumber(rawSteps),
        onFootYards = totals.onFoot,
        swimmingYards = totals.swimming,
        taxiYards = totals.taxi,
        totalYards = totalYards,
        onFoot = ATT.Distance.Format(totals.onFoot, units),
        swimming = ATT.Distance.Format(totals.swimming, units),
        taxi = ATT.Distance.Format(totals.taxi, units),
        total = ATT.Distance.Format(totalYards, units),
    }
end
```

Do not add a stored total or alter `Storage.lua`.

- [ ] **Step 5: Run the presentation-model tests and verify GREEN**

Run:

```powershell
lua tests\run.lua
```

Expected: all tests pass, including exact raw and formatted total assertions.

- [ ] **Step 6: Commit the model change**

```powershell
git add AzerothTravelTracker\UIModel.lua tests\test_ui_model.lua
git commit -m "feat: derive total travel distance" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

### Task 2: Add a Reusable Emphasized Section Footer

**Files:**
- Modify: `tests\test_ui_theme.lua`
- Modify: `AzerothTravelTracker\UITheme.lua`

- [ ] **Step 1: Write a failing footer-style test**

Change the character-section test to create five rows with the fifth identified
as the footer:

```lua
local section = addon.UITheme.CreateSection(parent, "Lifetime", 5, {
    footerIndex = 5,
})

testlib.equal(section.frame.height, 100)
testlib.equal(section.header.height, 20)
testlib.equal(#section.rows, 5)
testlib.equal(section.rows[1].frame.height, 16)
testlib.equal(section.footer, section.rows[5])
testlib.equal(section.footer.separator.shown, true)
testlib.equal(section.footer.label.textColor[1], 1)
testlib.equal(section.footer.label.textColor[2], 0.82)
testlib.equal(section.footer.value.textColor[1], 1)
testlib.equal(section.footer.value.textColor[2], 0.82)
```

Pass five values to `SetSectionValues` and assert:

```lua
testlib.equal(section.rows[5].label.text, "Total Distance")
testlib.equal(section.rows[5].value.text, "3.53 km")
```

Update the fallback two-row section expectation from `60` to `52`, reflecting
the compact `20 + (2 * 16)` geometry.

- [ ] **Step 2: Run the theme tests and verify RED**

Run:

```powershell
lua tests\run.lua
```

Expected: the current section is 114 pixels for five rows, accepts no footer
options, and exposes no footer separator.

- [ ] **Step 3: Implement compact section geometry and footer styling**

In `UITheme.lua`, change the geometry constants:

```lua
local SECTION_HEADER_HEIGHT = 20
local SECTION_ROW_HEIGHT = 16
```

Extend the constructor signature and normalize options:

```lua
function Theme.CreateSection(parent, title, rowCount, options)
    rowCount = rowCount or 4
    options = options or {}
```

When creating each row, identify the footer and add its separator:

```lua
local isFooter = index == options.footerIndex
local row = {
    frame = rowFrame,
    background = background,
    label = label,
    value = value,
}

if isFooter then
    label:SetTextColor(1, 0.82, 0, 1)
    value:SetTextColor(1, 0.82, 0, 1)

    row.separator = rowFrame:CreateTexture(nil, "OVERLAY")
    row.separator:SetColorTexture(0.72, 0.43, 0.16, 0.95)
    row.separator:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 4, 0)
    row.separator:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -4, 0)
    row.separator:SetHeight(1)
    section.footer = row
end

table.insert(section.rows, row)
```

Non-footer rows retain their current label and value colors. A section without
`footerIndex` remains valid and has no `section.footer`.

- [ ] **Step 4: Run the theme tests and verify GREEN**

Run:

```powershell
lua tests\run.lua
```

Expected: all theme and prior tests pass with 20-pixel headers, 16-pixel rows,
and a gold fifth-row footer.

- [ ] **Step 5: Commit the theme change**

```powershell
git add AzerothTravelTracker\UITheme.lua tests\test_ui_theme.lua
git commit -m "feat: add emphasized statistic footers" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

### Task 3: Wire Total Distance into Overview and By Level

**Files:**
- Modify: `tests\test_core.lua`
- Modify: `AzerothTravelTracker\UI.lua`

- [ ] **Step 1: Add failing regular-panel assertions**

In `ui creation is lazy idempotent and uses requested native structure`, change
the expected labels and dimensions:

```lua
local expectedLabels = {
    "Estimated Steps",
    "On Foot",
    "Swimming",
    "Flight Path",
    "Total Distance",
}

testlib.equal(#section.rows, 5)
testlib.equal(section.frame.height, 100)
testlib.equal(section.footer, section.rows[5])
testlib.equal(section.footer.separator.shown, true)
```

Also assert the unchanged shell and fitted overview geometry:

```lua
testlib.equal(first.width, 420)
testlib.equal(first.height, 430)
testlib.equal(harness.addon.UI.overviewPanel.height, 306)
testlib.equal(
    harness.addon.UI.diagnosticsScrollFrame.point[5],
    -310
)
```

- [ ] **Step 2: Add failing refresh assertions**

In the UI refresh test, make the fake overview summaries include:

```lua
total = "3.53 km"
```

Make each fake level row include:

```lua
total = "603 yd"
```

Then assert:

```lua
testlib.equal(
    harness.addon.UI.summarySections[1].footer.value:GetText(),
    "3.53 km"
)
testlib.equal(
    harness.addon.UI.levelRows[1].footer.value:GetText(),
    "603 yd"
)
```

- [ ] **Step 3: Run the UI tests and verify RED**

Run:

```powershell
lua tests\run.lua
```

Expected: failures show only four rows, no footer, and the old section geometry.

- [ ] **Step 4: Add Total Distance to the ordered UI contract**

Append the footer definition:

```lua
local SUMMARY_ROWS = {
    { key = "steps", label = "Estimated Steps" },
    { key = "onFoot", label = "On Foot" },
    { key = "swimming", label = "Swimming" },
    { key = "taxi", label = "Flight Path" },
    { key = "total", label = "Total Distance", footer = true },
}
```

Rebalance the constants without changing the outer frame:

```lua
local SECTION_HEIGHT = 100
local SECTION_GAP = 3
local SUMMARY_CONTENT_HEIGHT = (SECTION_HEIGHT * 3) + (SECTION_GAP * 2)
local LEVEL_CARD_HEIGHT = 104
```

Pass footer options for both Overview and level cards:

```lua
local section = ATT.UITheme.CreateSection(
    UI.overviewPanel,
    definition.title,
    #SUMMARY_ROWS,
    { footerIndex = #SUMMARY_ROWS }
)
```

```lua
local card = ATT.UITheme.CreateSection(
    UI.levelScrollChild,
    "",
    #SUMMARY_ROWS,
    { footerIndex = #SUMMARY_ROWS }
)
```

Keep the top-level frame size exactly `420, 430` and leave the HUD rows
unchanged.

- [ ] **Step 5: Run all Lua tests and verify GREEN**

Run:

```powershell
lua tests\run.lua
```

Expected: all tests pass; Overview and every level card expose five rows with a
gold Total Distance footer.

- [ ] **Step 6: Commit the UI wiring**

```powershell
git add AzerothTravelTracker\UI.lua tests\test_core.lua
git commit -m "feat: show total distance in statistics" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

### Task 4: Document, Validate, Package, and Install

**Files:**
- Modify: `docs\BETA-SMOKE-TESTS.md`

- [ ] **Step 1: Add the manual validation row**

Add:

```markdown
| Total distance summaries | Compare each Lifetime, This Session, Current Level, and By Level total against the visible On Foot + Swimming + Flight Path values in metric and imperial modes. | Every Total Distance footer equals the three component distances, changes units with the setting, remains gold-accented and readable, and does not clip or enlarge the 420 x 430 panel at 80%, 100%, or 120% UI scale. | PENDING | PENDING |
```

- [ ] **Step 2: Run final automated validation**

Run:

```powershell
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
```

Expected: all Lua tests pass; all packaging tests pass except the documented
Windows symlink privilege skip.

- [ ] **Step 3: Commit the smoke-test documentation**

```powershell
git add docs\BETA-SMOKE-TESTS.md
git commit -m "docs: add total distance smoke test" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

- [ ] **Step 4: Package from a clean tracked addon tree**

Run:

```powershell
.\tools\Package-Addon.ps1 -Version '0.1.0-beta'
```

Expected:

```text
Created ...\artifacts\AzerothTravelTracker-0.1.0-beta.zip
```

- [ ] **Step 5: Install the exact packaged snapshot**

Expand the archive to a temporary directory, replace only the named installed
addon directory, and copy the packaged folder:

```powershell
$root = 'D:\_projects\wow-forever-step-tracker'
$zip = Join-Path $root 'artifacts\AzerothTravelTracker-0.1.0-beta.zip'
$temp = Join-Path $root 'artifacts\install-0.1.0-beta'
$destination = 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelTracker'

if (Test-Path -LiteralPath $temp) {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
Expand-Archive -LiteralPath $zip -DestinationPath $temp
if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $temp 'AzerothTravelTracker') `
    -Destination $destination -Recurse
Remove-Item -LiteralPath $temp -Recurse -Force
```

- [ ] **Step 6: Verify source, package, and install parity**

Extract the immutable release to a specifically named verification directory,
compare every packaged file directly to the installed copy by SHA-256, and then
compare each packaged file's unfiltered Git object ID to the blob committed at
`HEAD`:

```powershell
$root = & git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) {
    throw 'Could not resolve the repository root.'
}
$root = $root.Trim()
$zip = Join-Path $root 'artifacts\AzerothTravelTracker-0.1.0-beta.zip'
$temp = Join-Path $root 'artifacts\verify-0.1.0-beta'
$package = Join-Path $temp 'AzerothTravelTracker'
$installed = 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelTracker'

if (Test-Path -LiteralPath $temp) {
    Remove-Item -LiteralPath $temp -Recurse -Force
}

try {
    Expand-Archive -LiteralPath $zip -DestinationPath $temp

    $packageHashes = Get-ChildItem -LiteralPath $package -File -Recurse |
        ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName.Substring($package.Length + 1)
                Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }
    $installedHashes = Get-ChildItem -LiteralPath $installed -File -Recurse |
        ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName.Substring($installed.Length + 1)
                Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }

    $parityDifferences = Compare-Object $packageHashes $installedHashes `
        -Property Path, Hash
    if ($parityDifferences) {
        $parityDifferences | Format-Table -AutoSize
        throw 'Installed addon differs from the packaged release.'
    }

    $headMismatches = Get-ChildItem -LiteralPath $package -File -Recurse |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($package.Length + 1)
            $gitPath = 'AzerothTravelTracker/' + ($relativePath -replace '\\', '/')
            $packageObject = & git -C $root hash-object --no-filters -- $_.FullName
            if ($LASTEXITCODE -ne 0) {
                throw "Could not hash packaged file: $relativePath"
            }
            $packageObject = $packageObject.Trim()
            $headObject = & git -C $root rev-parse --verify "HEAD:$gitPath"
            if ($LASTEXITCODE -ne 0) {
                throw "Could not resolve committed file: $gitPath"
            }
            $headObject = $headObject.Trim()
            if ($packageObject -ne $headObject) {
                [pscustomobject]@{
                    Path = $relativePath
                    PackageObject = $packageObject
                    HeadObject = $headObject
                }
            }
        }
    if ($headMismatches) {
        $headMismatches | Format-Table -AutoSize
        throw 'Packaged release differs from committed HEAD content.'
    }

    'Package, install, and committed HEAD content match.'
}
finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
```

Expected: no difference or mismatch tables, followed by
`Package, install, and committed HEAD content match.` The exact
`artifacts\verify-0.1.0-beta` temporary directory is removed even if a
verification fails.

- [ ] **Step 7: Perform the in-client check**

In the Forever beta:

1. Run `/reload`.
2. Open Overview and confirm all three totals.
3. Open By Level and confirm each card total.
4. Switch metric/imperial and verify every total changes units.
5. Inspect at 80%, 100%, and 120% UI scale for clipping or overlap.

Expected: each total equals On Foot + Swimming + Flight Path, all prior
screenshot fixes remain correct, and no Lua errors occur.
