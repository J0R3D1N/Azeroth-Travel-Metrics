# ATM UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a matching third Settings side tab, compact the main window, make main Minimize visibly native, and size compact Restore to match Close.

**Architecture:** Keep the existing portrait-shell and classic statistic panels. Extend the existing side-tab state machine with a center Settings panel, parameterize the shared window-size control for HUD sizing, and add a small native-atlas helper so the main minimize button cannot remain an invisible click target.

**Tech Stack:** WoW Forever Lua, Blizzard XML templates and atlases, repository Lua test harness, PowerShell packaging, ForeverSVFix.

---

## File Map

- Modify `AzerothTravelMetrics/UI.lua`
  - main-shell height and footer geometry;
  - three-tab state machine;
  - center Settings panel;
  - main Minimize placement and native artwork;
  - compact HUD Restore size.
- Modify `AzerothTravelMetrics/UITheme.lua`
  - native title-button atlas helper;
  - optional size for `CreateWindowSizeControl`.
- Modify `tests/test_core.lua`
  - shell bounds, Settings navigation, error behavior, main Minimize, and HUD parity.
- Modify `tests/test_ui_theme.lua`
  - atlas helper and optional window-size-control sizing.
- Modify `README.md`
  - third Settings tab and compact shell description.
- Modify `docs/BETA-SMOKE-TESTS.md`
  - in-game checks for all four screenshot callouts.

### Task 1: Parameterize compact HUD Restore sizing

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua:696-739`
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua:576-590`

- [ ] **Step 1: Write the failing theme test**

Add a test that calls:

```lua
local control, button = addon.UITheme.CreateWindowSizeControl(
    parent,
    "restore",
    "Restore",
    20
)

testlib.equal(control.width, 20)
testlib.equal(control.height, 20)
testlib.equal(button.width, 20)
testlib.equal(button.height, 20)
```

Keep the existing default-size test and assert it still produces `24 x 24`.

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: the new custom-size assertion fails because
`CreateWindowSizeControl` ignores its fourth argument.

- [ ] **Step 3: Add the optional size contract**

Change the signature and setup:

```lua
function Theme.CreateWindowSizeControl(parent, mode, tooltip, size)
    if mode ~= "minimize" and mode ~= "restore" then
        error("unsupported window size control: " .. tostring(mode))
    end

    size = size or 24
```

Use `size` for the container, native child buttons, and fallback:

```lua
control:SetSize(size, size)
control.MaximizeButton:SetSize(size, size)
control.MinimizeButton:SetSize(size, size)
```

```lua
local button = Theme.CreateTitleControl(parent, mode, tooltip, size)
```

- [ ] **Step 4: Request 20 pixels from the compact HUD**

Change the HUD creation call to:

```lua
local restoreControl, restoreButton =
    ATM.UITheme.CreateWindowSizeControl(
        frame,
        "restore",
        "Restore",
        20
    )
```

Update the core HUD test to assert Restore and Close are both `20 x 20`.

- [ ] **Step 5: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add -- AzerothTravelMetrics\UI.lua AzerothTravelMetrics\UITheme.lua tests\test_core.lua tests\test_ui_theme.lua
git commit -m "fix: match compact restore to close"
```

### Task 2: Guarantee visible native Minimize artwork

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua:926-964`

- [ ] **Step 1: Write failing atlas-helper tests**

Extend the texture harness with `SetAtlas` recording and button texture accessors.
Add a test for:

```lua
local applied = addon.UITheme.ApplyButtonAtlases(button, {
    normal = "RedButton-MiniCondense",
    pushed = "RedButton-MiniCondense-pressed",
    disabled = "RedButton-MiniCondense-disabled",
    highlight = "RedButton-Highlight",
})

testlib.equal(applied, true)
testlib.equal(button.normalTexture.atlas, "RedButton-MiniCondense")
testlib.equal(
    button.pushedTexture.atlas,
    "RedButton-MiniCondense-pressed"
)
testlib.equal(
    button.disabledTexture.atlas,
    "RedButton-MiniCondense-disabled"
)
testlib.equal(button.highlightTexture.atlas, "RedButton-Highlight")
```

Add a fallback case where texture getters are unavailable and assert `false`
without an exception.

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: failure because `ApplyButtonAtlases` does not exist.

- [ ] **Step 3: Implement the focused atlas helper**

Add:

```lua
function Theme.ApplyButtonAtlases(button, atlases)
    local getters = {
        normal = "GetNormalTexture",
        pushed = "GetPushedTexture",
        disabled = "GetDisabledTexture",
        highlight = "GetHighlightTexture",
    }
    local applied = false

    for state, getterName in pairs(getters) do
        local getter = button and button[getterName]
        local atlas = atlases and atlases[state]
        if type(getter) == "function" and atlas then
            local texture = getter(button)
            if texture and type(texture.SetAtlas) == "function" then
                local succeeded, accepted =
                    pcall(texture.SetAtlas, texture, atlas)
                applied = (succeeded and accepted ~= false) or applied
            end
        end
    end

    return applied
end
```

Do not add generic skinning behavior beyond the four native title-button
texture states.

- [ ] **Step 4: Apply native art and fixed placement**

After creating the main `UIPanelHideButtonNoScripts` button:

```lua
ATM.UITheme.ApplyButtonAtlases(UI.minimizeButton, {
    normal = "RedButton-MiniCondense",
    pushed = "RedButton-MiniCondense-pressed",
    disabled = "RedButton-MiniCondense-disabled",
    highlight = "RedButton-Highlight",
})
UI.minimizeButton:ClearAllPoints()
UI.minimizeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, 0)
UI.minimizeButton:SetFrameLevel(510)
```

Keep the existing click handler and `24 x 24` size. Update the harness and core
test to assert the exact atlases, fixed anchor, visibility, and frame level.
If `ApplyButtonAtlases` returns `false`, add a centered
`GameFontHighlightSmall` `"-"` font string to the button so the fallback click
target remains visible.

- [ ] **Step 5: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add -- AzerothTravelMetrics\UI.lua AzerothTravelMetrics\UITheme.lua tests\test_core.lua tests\test_ui_theme.lua
git commit -m "fix: restore visible minimize artwork"
```

### Task 3: Replace the Settings popup with a matching third side tab

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua:207-230,966-1152`

- [ ] **Step 1: Replace popup expectations with failing tab expectations**

Replace `ui settings gear toggles a synchronized popup` with tests that assert:

```lua
testlib.equal(UI.settingsButton, nil)
testlib.equal(UI.settingsTab.template, "LargeSideTabButtonTemplate")
testlib.equal(UI.settingsTab.Icon.texture, UITheme.Icons.SETTINGS)
testlib.equal(UI.settingsTab.point[2], UI.levelTab)
testlib.equal(UI.settingsTab.point[3], "BOTTOM")
testlib.equal(UI.settingsPanel.parent, UI.frame)
testlib.equal(UI.settingsPanel:IsShown(), false)
```

Click `settingsTab` and assert Overview and By Level hide, Settings shows,
selection moves to Settings, and persisted controls synchronize.

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: failures because Settings is still a footer gear and popup.

- [ ] **Step 3: Extend panel visibility**

Update `setPanelVisibility` so:

```lua
local showingSettings = activeTab == "settings"
local showingLevels = activeTab == "levels"

UI.settingsPanel:SetShown(showingSettings)
UI.overviewPanel:SetShown(not hasError and not showingLevels and not showingSettings)
UI.levelPanel:SetShown(not hasError and showingLevels)
UI.errorPanel:SetShown(hasError and not showingSettings)

ATM.UITheme.SetSideTabSelected(UI.overviewTab, activeTab == "overview")
ATM.UITheme.SetSideTabSelected(UI.levelTab, showingLevels)
ATM.UITheme.SetSideTabSelected(UI.settingsTab, showingSettings)
```

Use explicit `Show`/`Hide` branches if `SetShown` is unavailable in the test
harness. Call `syncSettingsControls()` before showing Settings.

- [ ] **Step 4: Create the third native side tab**

Create:

```lua
UI.settingsTab = ATM.UITheme.CreateSideTab(
    "AzerothTravelMetricsFrameSettingsTab",
    frame,
    {
        icon = ATM.UITheme.Icons.SETTINGS,
        tooltip = "Settings",
    }
)
UI.settingsTab:SetPoint("TOP", UI.levelTab, "BOTTOM", 0, -2)
UI.settingsTab:SetScript("OnClick", function()
    activeTab = "settings"
    syncSettingsControls()
    setPanelVisibility()
end)
```

Remove `UI.settingsButton` and its popup toggle script.

- [ ] **Step 5: Convert Settings into center content**

Create the Settings panel at the shared panel origin:

```lua
UI.settingsPanel = CreateFrame("Frame", nil, frame)
UI.settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -54)
UI.settingsPanel:SetSize(376, 320)
```

Use `ATM.UITheme.CreateSection` to create a character-stat-style Settings
section:

```lua
UI.settingsSection = ATM.UITheme.CreateSection(
    UI.settingsPanel,
    "Settings",
    3
)
UI.settingsSection.frame:SetPoint(
    "TOPLEFT",
    UI.settingsPanel,
    "TOPLEFT",
    0,
    0
)
UI.settingsSection.frame:SetWidth(376)
ATM.UITheme.SetSectionValues(UI.settingsSection, {
    { label = "Distance Units", value = "" },
    { label = "Minimap Button", value = "" },
    { label = "Diagnostics", value = "" },
})
```

Create the controls in those row frames:

```lua
UI.metricCheck = createCheckButton(
    UI.settingsSection.rows[1].frame,
    "Metric"
)
UI.metricCheck:SetSize(20, 20)
UI.metricCheck:SetPoint(
    "RIGHT",
    UI.settingsSection.rows[1].frame,
    "RIGHT",
    -98,
    0
)

UI.imperialCheck = createCheckButton(
    UI.settingsSection.rows[1].frame,
    "Imperial"
)
UI.imperialCheck:SetSize(20, 20)
UI.imperialCheck:SetPoint(
    "RIGHT",
    UI.settingsSection.rows[1].frame,
    "RIGHT",
    -34,
    0
)

UI.minimapCheck = createCheckButton(
    UI.settingsSection.rows[2].frame,
    "Show"
)
UI.minimapCheck:SetSize(20, 20)
UI.minimapCheck:SetPoint(
    "RIGHT",
    UI.settingsSection.rows[2].frame,
    "RIGHT",
    -42,
    0
)

UI.diagnosticsCheck = createCheckButton(
    UI.settingsSection.rows[3].frame,
    "Show"
)
UI.diagnosticsCheck:SetSize(20, 20)
UI.diagnosticsCheck:SetPoint(
    "RIGHT",
    UI.settingsSection.rows[3].frame,
    "RIGHT",
    -42,
    0
)
```

Preserve the current click handlers and database mutations exactly.

Move the diagnostic output below the Settings controls:

```lua
UI.diagnosticsHeadingSection = ATM.UITheme.CreateSection(
    UI.settingsPanel,
    "Diagnostic Rejections",
    0
)
UI.diagnosticsHeadingSection.frame:SetPoint(
    "TOPLEFT",
    UI.settingsPanel,
    "TOPLEFT",
    0,
    -84
)
UI.diagnosticsHeadingSection.frame:SetWidth(376)
```

Parent the diagnostics scroll frame to `UI.settingsPanel`, anchor it 14 pixels
inside and 8 pixels below the diagnostic heading, and size it `348 x 190`.
Remove both dynamic `UI.overviewPanel:SetHeight` calls so Overview remains
`320` pixels tall.

- [ ] **Step 6: Cover pending-error behavior**

Add a test:

```lua
UI.ShowError("Statistics unavailable")
UI.settingsTab.scripts.OnClick()
testlib.equal(UI.settingsPanel:IsShown(), true)
testlib.equal(UI.errorPanel:IsShown(), false)

UI.overviewTab.scripts.OnClick()
testlib.equal(UI.settingsPanel:IsShown(), false)
testlib.equal(UI.errorPanel:IsShown(), true)
```

- [ ] **Step 7: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```powershell
git add -- AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "feat: add settings side tab"
```

### Task 4: Remove main-window dead space

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua:827-831,996-1037,1154-1173`

- [ ] **Step 1: Write failing compact-shell bounds tests**

Assert:

```lua
testlib.equal(UI.frame.width, 420)
testlib.equal(UI.frame.height, 414)
testlib.equal(UI.contentFrame.height, 320)
testlib.equal(UI.errorPanel.height, 312)
testlib.equal(UI.resetButton.point[1], "BOTTOMLEFT")
testlib.equal(UI.resetButton.point[5], 12)
```

Calculate the Overview bottom and footer top from known offsets and assert the
gap is no more than 8 pixels.

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: failures showing the current `470`, `350`, and `342` heights.

- [ ] **Step 3: Apply exact compact geometry**

Change:

```lua
frame:SetSize(420, 414)
UI.contentFrame:SetSize(388, 320)
UI.errorPanel:SetSize(376, 312)
```

Keep Overview at `320`, By Level at `310`, Reset at bottom-left `(18, 12)`,
and version at bottom-right `(-18, 13)`. The footer then begins six pixels
below Overview's bottom edge.

- [ ] **Step 4: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass and the bounds assertion reports a six-pixel gap.

- [ ] **Step 5: Commit**

```powershell
git add -- AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: compact ATM main window"
```

### Task 5: Update user-facing documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/BETA-SMOKE-TESTS.md`

- [ ] **Step 1: Update README UI description**

Describe:

- three right-side tabs: Overview, By Level, Settings;
- center Settings content;
- compact footer with Reset Session and version;
- compact HUD controls with equal Restore/Close sizing.

- [ ] **Step 2: Update the beta smoke checklist**

Add explicit checks:

```text
- Overview, By Level, and Settings use matching right-side tab art.
- Main Minimize is visible immediately left of Close and both work.
- HUD Restore and Close appear the same size.
- The footer follows the center content without a large blank region.
- Settings controls persist units, minimap visibility, and diagnostics.
```

- [ ] **Step 3: Commit**

```powershell
git add -- README.md docs\BETA-SMOKE-TESTS.md
git commit -m "docs: describe compact settings tab UI"
```

### Task 6: Review, validate, package, and deploy

**Files:**
- Verify all committed changes from `cc5d4ae` through HEAD.

- [ ] **Step 1: Request focused code review**

Review:

- three-tab visibility and pending-error behavior;
- Settings control persistence;
- exact `420 x 414` bounds;
- main Minimize texture fallback and frame layering;
- HUD hover/Restore composition;
- native and rejected-template fallback paths.

Fix all Critical and Important findings with a failing regression test first.

- [ ] **Step 2: Run complete validation**

Run:

```powershell
lua .\tests\run.lua
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PackageAddon.ps1
$size = $Host.UI.RawUI.BufferSize
$size.Width = 500
$Host.UI.RawUI.BufferSize = $size
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
```

Expected: zero failures.

- [ ] **Step 3: Validate the TOC**

Validate `AzerothTravelMetrics.toc` inline for Interface `16001`.

Expected: no issues.

- [ ] **Step 4: Confirm a clean committed worktree**

Run:

```powershell
git status --short
```

Expected: no output.

- [ ] **Step 5: Build the package**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Package-Addon.ps1
```

Expected:

```text
Validated addon manifest for Interface 16001.
...\artifacts\AzerothTravelMetrics-1.0.0-beta.zip
```

- [ ] **Step 6: Deploy safely**

Confirm `WowB` is not running. Move the current installed folder to:

```text
D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics_backup_YYYYMMDD_HHMMSS
```

Copy:

```text
artifacts\AzerothTravelMetrics
```

to:

```text
D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics
```

- [ ] **Step 7: Reapply ForeverSVFix**

Run:

```powershell
Set-Location D:\_projects\ForeverSVFix
python .\forever_sv_fix.py --wow 'D:\Games\World of Warcraft\_classic_beta_' --account '50347838#1' repair
python .\forever_sv_fix.py --wow 'D:\Games\World of Warcraft\_classic_beta_' --account '50347838#1' doctor
```

Expected:

```text
Active installation checks: OK
No repair needed.
```

- [ ] **Step 8: Compare deployed runtime bytes**

Compare every deployed file against
`artifacts\AzerothTravelMetrics`, excluding
`AzerothTravelMetrics.toc` because ForeverSVFix patches it.

Expected: no differences.

- [ ] **Step 9: Preserve the feature branch**

Keep `feature/spellbook-window` and
`D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window` for the next
in-game screenshot and approval. Do not merge.
