# ATM UI Final Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Minimize visibly reliable in WoW Forever, restrict Reset Session to Settings, contain the Distance Units controls, and suppress the misleading `unsupportedState` tracking warning.

**Architecture:** Preserve the accepted compact portrait shell and three-tab content model. Replace only the main-window native minimize artwork with the existing ATM-owned title-control primitive, let the tab visibility function own Reset Session visibility, explicitly bound checkbox labels inside the Settings row, and distinguish normal movement rejections from genuine runtime availability failures in Core.

**Tech Stack:** WoW Forever Lua, Blizzard frame APIs, ATM UITheme primitives, repository Lua test harness, PowerShell packaging, WoW TOC validation, ForeverSVFix.

---

## File Map

- Modify `AzerothTravelMetrics/UI.lua`
  - create the main Minimize button with `UITheme.CreateTitleControl`;
  - show Reset Session only for the Settings tab;
  - explicitly anchor and size Distance Units checkbox labels.
- Modify `AzerothTravelMetrics/Core.lua`
  - stop announcing normal `unsupportedState` movement rejections.
- Modify `tests/test_core.lua`
  - regress main Minimize visibility and placement;
  - regress Reset Session tab visibility;
  - regress Settings control bounds;
  - regress normal rejection versus genuine capability warning behavior.
- Modify `README.md`
  - document Settings-only Reset Session and non-fatal diagnostic rejections.
- Modify `docs/BETA-SMOKE-TESTS.md`
  - add exact in-game checks for the four reported findings.

All implementation work occurs in:

```text
D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window
```

Do not merge `feature/spellbook-window`; this remains an in-game candidate.

### Task 1: Replace main Minimize with deterministic ATM artwork

**Files:**
- Modify: `tests/test_core.lua:2675-2760`
- Modify: `AzerothTravelMetrics/UI.lua:937-997`

- [ ] **Step 1: Replace the native-template assertions with a failing title-control regression**

In `ui keeps portrait chrome with right tabs and classic center`, replace the
current Minimize assertions with:

```lua
testlib.equal(UI.minimizeButton.parent, frame)
testlib.equal(UI.minimizeButton.template, nil)
testlib.equal(UI.minimizeButton.controlKind, "minimize")
testlib.equal(UI.minimizeButton.width, 20)
testlib.equal(UI.minimizeButton.height, 20)
testlib.equal(UI.minimizeButton.point[1], "RIGHT")
testlib.equal(UI.minimizeButton.point[2], UI.closeButton)
testlib.equal(UI.minimizeButton.point[3], "LEFT")
testlib.equal(UI.minimizeButton.point[4], -1)
testlib.equal(UI.minimizeButton.point[5], 0)
testlib.truthy(UI.minimizeButton.Background.color ~= nil)
testlib.truthy(UI.minimizeButton.HighlightTexture.color ~= nil)
testlib.equal(#UI.minimizeButton.GlyphTextures, 3)
testlib.truthy(
    UI.minimizeButton.frameLevel > UI.closeButton.frameLevel
)
```

Replace `ui main minimize keeps a visible atlas fallback` with:

```lua
testlib.case("ui main minimize uses visible ATM artwork", function()
    local harness = newUIHarness({
        missingHideButtonTextures = true,
    })
    local UI = harness.addon.UI
    UI.Create()

    testlib.equal(UI.minimizeButton.controlKind, "minimize")
    testlib.equal(UI.minimizeButton.template, nil)
    testlib.equal(#UI.minimizeButton.GlyphTextures, 3)
    for _, texture in ipairs(UI.minimizeButton.GlyphTextures) do
        testlib.equal(texture:IsShown(), true)
    end
end)
```

Update the fallback-shell test to expect the same ATM title control rather
than `UIPanelHideButtonNoScripts`.

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
Set-Location D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window
lua .\tests\run.lua
```

Expected: Minimize tests fail because the main window still creates a
`24 x 24` `UIPanelHideButtonNoScripts` button.

- [ ] **Step 3: Replace the main Minimize construction**

Replace the native template, atlas application, and fallback-label block in
`UI.Create` with:

```lua
UI.minimizeButton = ATM.UITheme.CreateTitleControl(
    frame,
    "minimize",
    "Minimize",
    20
)
UI.minimizeControl = UI.minimizeButton
UI.minimizeButton:SetPoint(
    "RIGHT",
    UI.closeButton,
    "LEFT",
    -1,
    0
)
UI.minimizeButton:SetFrameLevel(
    math.max(UI.closeButton:GetFrameLevel() + 1, 511)
)
UI.minimizeButton:Show()
UI.minimizeButton:SetScript("OnClick", function()
    UI.Minimize()
end)
```

Delete the main-window use of:

```lua
"UIPanelHideButtonNoScripts"
ATM.UITheme.ApplyButtonAtlases(...)
UI.minimizeFallbackText
```

Do not remove `ApplyButtonAtlases` from `UITheme.lua`; it remains tested and
may be useful to other native controls. Do not change compact HUD controls.

- [ ] **Step 4: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit the Minimize fix**

```powershell
git add -- AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: render a reliable ATM minimize control" -m "Replace the invisible Forever native minimize artwork with ATM's tested title-control glyph while preserving the compact HUD behavior." -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 2: Show Reset Session only on Settings

**Files:**
- Modify: `tests/test_core.lua:2600-2680,3090-3270`
- Modify: `AzerothTravelMetrics/UI.lua:202-241`

- [ ] **Step 1: Write failing tab-visibility assertions**

In `ui settings side tab opens synchronized center content`, add:

```lua
testlib.equal(UI.resetButton:IsShown(), true)

UI.overviewTab.scripts.OnClick()
testlib.equal(UI.resetButton:IsShown(), false)

UI.levelTab.scripts.OnClick()
testlib.equal(UI.resetButton:IsShown(), false)

UI.settingsTab.scripts.OnClick()
testlib.equal(UI.resetButton:IsShown(), true)
```

In `ui settings tab temporarily hides pending statistic errors`, assert that
Reset Session remains hidden on the error surface and becomes visible only
after selecting Settings:

```lua
testlib.equal(UI.resetButton:IsShown(), false)
UI.settingsTab.scripts.OnClick()
testlib.equal(UI.resetButton:IsShown(), true)
```

Update `ui action buttons remain visible and interactive without panel
templates` to select Settings before asserting and clicking Reset Session:

```lua
testlib.equal(UI.resetButton:IsShown(), false)
UI.settingsTab.scripts.OnClick()
testlib.equal(UI.resetButton:IsShown(), true)
UI.resetButton.scripts.OnClick()
```

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: Reset visibility assertions fail because the button is currently
shown independently of `activeTab`.

- [ ] **Step 3: Make panel visibility own Reset visibility**

At the end of `setPanelVisibility`, before side-tab selected-state updates,
add:

```lua
if UI.resetButton then
    if showingSettings then
        UI.resetButton:Show()
    else
        UI.resetButton:Hide()
    end
end
```

Do not reparent or move the button. Preserve its existing footer anchor,
confirmation popup, storage reset, tracker baseline reset, and error handling.

- [ ] **Step 4: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit the Settings-only Reset behavior**

```powershell
git add -- AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: limit session reset to settings" -m "Hide the destructive session action on Overview, By Level, and error surfaces while preserving its Settings footer behavior." -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 3: Contain Distance Units inside the Settings row

**Files:**
- Modify: `tests/test_core.lua:2640-2680`
- Modify: `AzerothTravelMetrics/UI.lua:1098-1130`

- [ ] **Step 1: Write failing geometry assertions**

Extend `ui settings side tab opens synchronized center content` with:

```lua
testlib.equal(UI.metricCheck.point[1], "LEFT")
testlib.equal(UI.metricCheck.point[2], UI.settingsSection.rows[1].frame)
testlib.equal(UI.metricCheck.point[3], "LEFT")
testlib.equal(UI.metricCheck.point[4], 218)
testlib.equal(UI.metricCheck.label.point[1], "LEFT")
testlib.equal(UI.metricCheck.label.point[2], UI.metricCheck)
testlib.equal(UI.metricCheck.label.point[3], "RIGHT")
testlib.equal(UI.metricCheck.label.point[4], 2)
testlib.equal(UI.metricCheck.label.width, 48)

testlib.equal(UI.imperialCheck.point[1], "LEFT")
testlib.equal(UI.imperialCheck.point[2], UI.settingsSection.rows[1].frame)
testlib.equal(UI.imperialCheck.point[3], "LEFT")
testlib.equal(UI.imperialCheck.point[4], 294)
testlib.equal(UI.imperialCheck.label.point[1], "LEFT")
testlib.equal(UI.imperialCheck.label.point[2], UI.imperialCheck)
testlib.equal(UI.imperialCheck.label.point[3], "RIGHT")
testlib.equal(UI.imperialCheck.label.point[4], 2)
testlib.equal(UI.imperialCheck.label.width, 56)

local metricRight = 218 + 16 + 2 + 48
local imperialRight = 294 + 16 + 2 + 56
testlib.truthy(metricRight < 294)
testlib.truthy(imperialRight <= 376 - 8)
```

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: assertions fail because both controls use right anchors and native
checkbox label geometry is unbounded.

- [ ] **Step 3: Apply explicit checkbox and label bounds**

Replace the Metric anchor with:

```lua
UI.metricCheck:SetPoint(
    "LEFT",
    UI.settingsSection.rows[1].frame,
    "LEFT",
    218,
    0
)
UI.metricCheck.label:ClearAllPoints()
UI.metricCheck.label:SetPoint(
    "LEFT",
    UI.metricCheck,
    "RIGHT",
    2,
    0
)
UI.metricCheck.label:SetWidth(48)
UI.metricCheck.label:SetJustifyH("LEFT")
```

Replace the Imperial anchor with:

```lua
UI.imperialCheck:SetPoint(
    "LEFT",
    UI.settingsSection.rows[1].frame,
    "LEFT",
    294,
    0
)
UI.imperialCheck.label:ClearAllPoints()
UI.imperialCheck.label:SetPoint(
    "LEFT",
    UI.imperialCheck,
    "RIGHT",
    2,
    0
)
UI.imperialCheck.label:SetWidth(56)
UI.imperialCheck.label:SetJustifyH("LEFT")
```

Keep both checkbox click targets at `16 x 16`. Do not change Minimap Button or
Diagnostics row geometry.

- [ ] **Step 4: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit the Settings geometry fix**

```powershell
git add -- AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: contain settings unit controls" -m "Give Metric and Imperial explicit checkbox and label bounds so the Distance Units row stays inside the compact Settings frame." -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 4: Treat unsupported movement states as diagnostics, not outages

**Files:**
- Modify: `tests/test_core.lua:1370-1400`
- Modify: `AzerothTravelMetrics/Core.lua:25-36`

- [ ] **Step 1: Write the failing warning-policy test**

Replace `ticker reports only explicit capability reasons once` with:

```lua
testlib.case("ticker reports capability failures but not normal movement rejections", function()
    local harness = newCoreHarness({
        sampleResults = {
            { reason = "positionUnavailable" },
            { reason = "positionUnavailable" },
            { reason = "stationary" },
            { reason = "unsupportedState" },
            { reason = "notAnApprovedCapabilityReason" },
        },
    })
    makeReady(harness)

    for _ = 1, 5 do
        harness.calls.tickers[1].callback()
    end

    testlib.equal(#harness.calls.prints, 1)
    testlib.truthy(contains(
        harness.calls.prints[1],
        "positionUnavailable"
    ))
    testlib.truthy(not contains(
        harness.calls.prints[1],
        "unsupportedState"
    ))
end)
```

Do not alter tracker diagnostic tests. They must continue to prove that
`character.diagnostics.unsupportedState` increments.

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: the warning-policy test fails with two chat messages because
`unsupportedState` is still reportable.

- [ ] **Step 3: Remove only the normal rejection from chat reporting**

Delete this entry from `REPORTABLE_REASONS`:

```lua
unsupportedState = true,
```

Do not change `Movement.Classify`, `Movement.BuildSegment`, Tracker rejection
handling, diagnostic counters, or other reportable reasons.

- [ ] **Step 4: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass with zero failures, including existing
`unsupportedState` diagnostic tests.

- [ ] **Step 5: Commit the warning-policy fix**

```powershell
git add -- AzerothTravelMetrics\Core.lua tests\test_core.lua
git commit -m "fix: silence normal unsupported-state warnings" -m "Keep unsupported movement states in diagnostics without presenting mounted, airborne, or transitional samples as tracking outages." -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 5: Update user-facing documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/BETA-SMOKE-TESTS.md`

- [ ] **Step 1: Update the README UI description**

In the compact-window description, state:

```markdown
Reset Session is available only from Settings. Normal unsupported movement
states, such as mounted or airborne samples, remain visible in diagnostic
rejection counts but do not produce tracking-unavailable chat warnings.
```

Describe the main Minimize control as an ATM-rendered title control rather
than native red-button artwork.

- [ ] **Step 2: Update the beta smoke tests**

Add these exact acceptance checks:

```markdown
- Main Minimize is visibly rendered immediately left of Close.
- Reset Session is hidden on Overview and By Level and visible on Settings.
- Metric and Imperial are fully contained inside the Distance Units row.
- Login and ordinary mounted/airborne transitions do not print
  `Tracking unavailable: unsupportedState`.
```

Retain the existing checks for compact shell geometry, three side tabs,
diagnostics, HUD parity, reset confirmation, and travel totals.

- [ ] **Step 3: Review the documentation diff**

Run:

```powershell
git --no-pager diff --check
git --no-pager diff -- README.md docs\BETA-SMOKE-TESTS.md
```

Expected: no whitespace errors and only the focused acceptance/documentation
changes.

- [ ] **Step 4: Commit the documentation**

```powershell
git add -- README.md docs\BETA-SMOKE-TESTS.md
git commit -m "docs: describe final ATM UI refinements" -m "Document the Settings-only reset action, reliable title control, contained unit controls, and non-fatal unsupported-state diagnostics." -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 6: Validate, package, deploy, and verify

**Files:**
- Verify: `AzerothTravelMetrics/AzerothTravelMetrics.toc`
- Generate: `artifacts/AzerothTravelMetrics-1.0.0-beta.zip`
- Deploy: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics`

- [ ] **Step 1: Run the complete Lua suite**

```powershell
Set-Location D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window
lua .\tests\run.lua
```

Expected: every test passes with zero failures.

- [ ] **Step 2: Run package and release validation**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PackageAddon.ps1
$size = $Host.UI.RawUI.BufferSize
$size.Width = 500
$Host.UI.RawUI.BufferSize = $size
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
```

Expected: package tests and both release-identity checks pass. The
Administrator-only symbolic-link test may skip.

- [ ] **Step 3: Validate the TOC**

Validate `AzerothTravelMetrics/AzerothTravelMetrics.toc` inline with the WoW
TOC validator when the configured addon root differs from the worktree.

Expected:

```text
interface: WoW Forever (Camelot)
No issues found.
```

- [ ] **Step 4: Confirm a clean worktree and build the package**

```powershell
git --no-pager status --short
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Package-Addon.ps1
git --no-pager status --short
```

Expected: the worktree is clean before and after packaging, the Lua suite
passes inside the packager, Interface `16001` validates, and the beta zip is
produced.

- [ ] **Step 5: Confirm WoW beta is closed**

```powershell
$wow = Get-Process -Name WowB -ErrorAction SilentlyContinue
if ($wow) {
    throw "WowB is running; deployment aborted."
}
```

Expected: no `WowB` process.

- [ ] **Step 6: Back up and deploy the packaged addon**

Use exact resolved paths and timestamp format `yyyyMMdd_HHmmss`:

```powershell
$source = 'D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window\artifacts\AzerothTravelMetrics'
$addons = 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns'
$dest = Join-Path $addons 'AzerothTravelMetrics'
$backup = Join-Path $addons (
    'AzerothTravelMetrics_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
)

Move-Item -LiteralPath $dest -Destination $backup
Copy-Item -LiteralPath $source -Destination $dest -Recurse
```

Expected: the previous candidate is preserved in the timestamped backup and
the new package is installed at the active addon path.

- [ ] **Step 7: Reapply ForeverSVFix**

```powershell
Set-Location D:\_projects\ForeverSVFix
python .\forever_sv_fix.py --wow 'D:\Games\World of Warcraft\_classic_beta_' --account '50347838#1' repair
python .\forever_sv_fix.py --wow 'D:\Games\World of Warcraft\_classic_beta_' --account '50347838#1' doctor
```

Expected: repair completes and doctor reports:

```text
Active installation checks: OK
No repair needed.
```

- [ ] **Step 8: Compare packaged and deployed runtime files**

Compare SHA-256 hashes for every non-TOC file under:

```text
D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window\artifacts\AzerothTravelMetrics
D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics
```

Exclude `.toc` because ForeverSVFix intentionally patches release identity.

Expected: identical relative file lists and hashes for every non-TOC runtime
file.

- [ ] **Step 9: Report the in-game acceptance checklist**

Ask the user to verify:

1. visible Minimize immediately left of Close;
2. Reset Session only on Settings;
3. no `unsupportedState` login warning;
4. contained Metric and Imperial controls;
5. unchanged tabs, HUD, diagnostics, and travel totals.
