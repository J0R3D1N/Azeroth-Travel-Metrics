# Spellbook Window Visual Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a second ATM spellbook-window candidate with left-justified filled icon tabs, a Settings page, guaranteed title controls, an unobscured reset action, and parchment-native sections.

**Architecture:** Keep the existing `PortraitFrameTemplate` shell, shared parchment content frame, data models, and HUD. Extend the current tab state to a third `settings` panel, move existing settings controls into that panel, create explicit title-overlay controls, and revise `UITheme` section rendering so headings and rows sit naturally on parchment.

**Tech Stack:** World of Warcraft Lua, Forever Blizzard XML templates/atlases, repository Lua test harness, PowerShell packaging and identity tests, ForeverSVFix.

---

## File map

- `AzerothTravelMetrics/UITheme.lua`
  - Own top-tab dimensions/icon crop/selection, parchment section visuals, and safe control styling.
- `AzerothTravelMetrics/UI.lua`
  - Own shell layout, three-panel visibility, explicit close/minimize controls, Settings page, reset placement, and footer.
- `tests/test_ui_theme.lua`
  - Verify filled tabs and parchment-native section/fallback behavior.
- `tests/test_core.lua`
  - Verify three-tab layout, control visibility, Settings behavior, Reset placement, panel switching, and unchanged UI lifecycle behavior.
- `README.md`
  - Describe the final three-tab spellbook UI and Settings-page reset.
- `docs/BETA-SMOKE-TESTS.md`
  - Add focused checks for all five screenshot findings.

### Task 1: Fill and left-align the horizontal tabs

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing theme tests for filled tab icons**

Update the `CreateTopTab` test to require a larger icon and tighter crop:

```lua
testlib.equal(tab.width, 44)
testlib.equal(tab.height, 38)
testlib.equal(tab.Icon.width, 34)
testlib.equal(tab.Icon.height, 34)
testlib.equal(tab.Icon.texCoord[1], 0.12)
testlib.equal(tab.Icon.texCoord[2], 0.88)
testlib.equal(tab.Icon.texCoord[3], 0.12)
testlib.equal(tab.Icon.texCoord[4], 0.88)
```

- [ ] **Step 2: Write failing core tests for a left-justified three-tab row**

Extend the spellbook layout test:

```lua
testlib.equal(UI.overviewTab.point[1], "TOPLEFT")
testlib.equal(UI.overviewTab.point[2], frame)
testlib.equal(UI.overviewTab.point[3], "TOPLEFT")
testlib.truthy(UI.overviewTab.point[4] < 100)

testlib.equal(UI.levelTab.point[1], "LEFT")
testlib.equal(UI.levelTab.point[2], UI.overviewTab)
testlib.equal(UI.settingsTab.point[1], "LEFT")
testlib.equal(UI.settingsTab.point[2], UI.levelTab)
testlib.equal(UI.settingsTab.Icon.texture, UITheme.Icons.SETTINGS)
```

- [ ] **Step 3: Run the Lua suite and confirm the new assertions fail**

Run:

```powershell
Set-Location D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window
lua .\tests\run.lua
```

Expected: failures showing the icon is still `26 x 26`, the first tab is still centered around x=152, and `settingsTab` is absent.

- [ ] **Step 4: Enlarge/crop tab artwork and create the third tab**

In `UITheme.lua`, change `CreateTopTab`:

```lua
tab.Icon:SetSize(34, 34)
tab.Icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
tab.Icon:SetTexture(options.icon)
tab.Icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
```

In `UI.lua`, anchor the strip near the left edge while clearing the portrait:

```lua
UI.overviewTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 72, -36)
UI.levelTab:SetPoint("LEFT", UI.overviewTab, "RIGHT", 6, 0)

UI.settingsTab = ATM.UITheme.CreateTopTab(
    "AzerothTravelMetricsFrameSettingsTab",
    frame,
    {
        icon = ATM.UITheme.Icons.SETTINGS,
        tooltip = "Settings",
    }
)
UI.settingsTab:SetPoint("LEFT", UI.levelTab, "RIGHT", 6, 0)
UI.settingsTab:Show()
```

Do not wire the Settings click behavior until Task 2.

- [ ] **Step 5: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all existing tests and the new tab layout tests pass.

- [ ] **Step 6: Commit**

```powershell
git add AzerothTravelMetrics\UITheme.lua AzerothTravelMetrics\UI.lua tests\test_ui_theme.lua tests\test_core.lua
git commit -m "fix: align and fill spellbook tabs" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 2: Convert Settings into the third parchment page

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing panel-selection tests**

Add a test that clicks all three tabs:

```lua
UI.settingsTab.scripts.OnClick()
testlib.equal(UI.overviewPanel:IsShown(), false)
testlib.equal(UI.levelPanel:IsShown(), false)
testlib.equal(UI.settingsPanel:IsShown(), true)
testlib.equal(UI.settingsTab.selected, true)
testlib.equal(UI.overviewTab.selected, false)
testlib.equal(UI.levelTab.selected, false)

UI.overviewTab.scripts.OnClick()
testlib.equal(UI.overviewPanel:IsShown(), true)
testlib.equal(UI.settingsPanel:IsShown(), false)
```

Also assert Settings is parented to the shared content frame:

```lua
testlib.equal(UI.settingsPanel.parent, UI.contentFrame)
testlib.equal(UI.settingsButton, nil)
```

- [ ] **Step 2: Write failing synchronization tests**

Set persisted values, click Settings, and assert controls synchronize:

```lua
harness.db.settings.units = "imperial"
harness.db.settings.showMinimap = false
harness.db.settings.showDiagnostics = true
UI.settingsTab.scripts.OnClick()
testlib.equal(UI.metricCheck:GetChecked(), false)
testlib.equal(UI.imperialCheck:GetChecked(), true)
testlib.equal(UI.minimapCheck:GetChecked(), false)
testlib.equal(UI.diagnosticsCheck:GetChecked(), true)
```

- [ ] **Step 3: Run the Lua suite and confirm failure**

Run:

```powershell
lua .\tests\run.lua
```

Expected: `settingsTab` has no click behavior and the current Settings panel is still a floating footer popup.

- [ ] **Step 4: Extend active panel visibility**

Update `setPanelVisibility` to select one of three panels:

```lua
if hasError then
    UI.overviewPanel:Hide()
    UI.levelPanel:Hide()
    UI.settingsPanel:Hide()
elseif activeTab == "levels" then
    UI.overviewPanel:Hide()
    UI.settingsPanel:Hide()
    UI.levelPanel:Show()
elseif activeTab == "settings" then
    UI.overviewPanel:Hide()
    UI.levelPanel:Hide()
    UI.settingsPanel:Show()
else
    UI.levelPanel:Hide()
    UI.settingsPanel:Hide()
    UI.overviewPanel:Show()
end

ATM.UITheme.SetTopTabSelected(UI.overviewTab, activeTab == "overview")
ATM.UITheme.SetTopTabSelected(UI.levelTab, activeTab == "levels")
ATM.UITheme.SetTopTabSelected(UI.settingsTab, activeTab == "settings")
```

- [ ] **Step 5: Rebuild Settings as a content panel**

Remove the footer `settingsButton` and popup toggle script. Create `settingsPanel` after `contentFrame`:

```lua
UI.settingsPanel = CreateFrame("Frame", nil, UI.contentFrame)
UI.settingsPanel:SetPoint("TOPLEFT", UI.contentFrame, "TOPLEFT", 18, -18)
UI.settingsPanel:SetPoint("BOTTOMRIGHT", UI.contentFrame, "BOTTOMRIGHT", -18, 18)
```

Keep the existing check buttons and callbacks, but parent them to
`UI.settingsPanel`. Add the Settings tab click:

```lua
UI.settingsTab:SetScript("OnClick", function()
    activeTab = "settings"
    syncSettingsControls()
    setPanelVisibility()
end)
```

- [ ] **Step 6: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: the three-panel selection and synchronization tests pass; existing units/minimap/diagnostics tests remain green.

- [ ] **Step 7: Commit**

```powershell
git add AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "feat: add spellbook settings page" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 3: Guarantee visible close and minimize controls

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Correct the native-template harness and write failing overlay tests**

Keep `PortraitFrameTemplate` children accurate, but require ATM-owned overlay
controls:

```lua
testlib.equal(UI.closeButton.parent, UI.titleRegion)
testlib.equal(UI.closeButton.point[1], "RIGHT")
testlib.equal(UI.minimizeControl.parent, UI.titleRegion)
testlib.equal(UI.minimizeControl.point[2], UI.closeButton)
testlib.truthy(UI.closeButton:GetFrameLevel() > frame:GetFrameLevel())
testlib.truthy(UI.minimizeControl:GetFrameLevel() > frame:GetFrameLevel())
```

Retain click tests proving Close hides the main frame and Minimize shows the
existing HUD.

- [ ] **Step 2: Run the Lua suite and confirm failure**

Run:

```powershell
lua .\tests\run.lua
```

Expected: failure because the native close button is currently reused rather than explicitly created in `titleRegion`.

- [ ] **Step 3: Always create ATM-owned title controls**

Do not assign `frame.CloseButton` to `UI.closeButton`. Create the safe close
button unconditionally:

```lua
UI.closeButton = createSafeButton(
    UI.titleRegion,
    "UIPanelCloseButton",
    24,
    24,
    nil,
    "x"
)
UI.closeButton:SetPoint("RIGHT", UI.titleRegion, "RIGHT", -2, 0)
raiseAboveParent(UI.closeButton, UI.titleRegion, 3)
```

If `frame.CloseButton` exists, hide it with a guarded call so duplicate chrome
does not appear:

```lua
if frame.CloseButton and frame.CloseButton ~= UI.closeButton then
    pcall(frame.CloseButton.Hide, frame.CloseButton)
end
```

Continue creating `CreateWindowSizeControl` in `titleRegion`, anchored left of
the explicit close button.

- [ ] **Step 4: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: title-control visibility, close, minimize, restore, HUD, Escape, and fallback tests pass.

- [ ] **Step 5: Commit**

```powershell
git add AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: guarantee spellbook title controls" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 4: Move Reset Session into a Settings danger zone

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing placement and behavior tests**

Assert Reset is no longer a frame-footer child:

```lua
testlib.equal(UI.resetButton.parent, UI.settingsPanel)
testlib.equal(UI.resetButton.point[1], "BOTTOMLEFT")
testlib.equal(UI.resetButton:GetText(), "Reset Current Session")
testlib.truthy(UI.resetWarning ~= nil)
testlib.equal(UI.resetWarning.parent, UI.settingsPanel)
```

Retain the existing confirmation test:

```lua
UI.resetButton.scripts.OnClick()
testlib.equal(
    harness.environment.shownPopup,
    "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
)
```

- [ ] **Step 2: Run the Lua suite and confirm failure**

Run:

```powershell
lua .\tests\run.lua
```

Expected: Reset is still parented to the outer frame and still reads `Reset Session`.

- [ ] **Step 3: Add the Settings danger-zone section**

Create a divider, heading, warning, and button near the Settings panel bottom:

```lua
UI.resetDivider = ATM.UITheme.CreateDivider(UI.settingsPanel)
UI.resetDivider:SetPoint(
    "BOTTOMLEFT",
    UI.settingsPanel,
    "BOTTOMLEFT",
    0,
    76
)
UI.resetDivider:SetPoint(
    "BOTTOMRIGHT",
    UI.settingsPanel,
    "BOTTOMRIGHT",
    0,
    76
)

UI.resetHeading = createLabel(
    UI.settingsPanel,
    "Session",
    "GameFontNormal"
)
UI.resetHeading:SetPoint("BOTTOMLEFT", UI.resetDivider, "TOPLEFT", 0, 6)

UI.resetWarning = createLabel(
    UI.settingsPanel,
    "Resets only this character's current travel session.",
    "GameFontDisableSmall"
)
UI.resetWarning:SetPoint("BOTTOMLEFT", UI.settingsPanel, "BOTTOMLEFT", 0, 38)

UI.resetButton = createSafeButton(
    UI.settingsPanel,
    "UIPanelButtonTemplate",
    156,
    24,
    "Reset Current Session"
)
UI.resetButton:SetPoint("BOTTOMLEFT", UI.settingsPanel, "BOTTOMLEFT", 0, 6)
```

Keep the existing confirmation callback unchanged.

- [ ] **Step 4: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: reset placement and all reset success/error/baseline tests pass.

- [ ] **Step 5: Commit**

```powershell
git add AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: move session reset into settings" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 5: Replace dark section bars with parchment-native sections

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing theme tests for parchment sections**

Change section assertions to require:

```lua
testlib.equal(section.header.atlas, nil)
testlib.equal(section.title.justifyH, "LEFT")
testlib.equal(section.title.textColor[1], 0.26)
testlib.equal(section.divider.atlas, addon.UITheme.Atlases.DIVIDER)
testlib.truthy(section.rows[1].background.color ~= nil)
testlib.equal(section.rows[1].label.textColor[1], 0.32)
testlib.equal(section.rows[1].value.textColor[1], 0.12)
```

Add a rejected-atlas case proving the divider still becomes a visible
one-pixel brown line.

- [ ] **Step 2: Write failing layout tests for the Lifetime top gap**

Require deliberate top padding:

```lua
testlib.equal(UI.overviewPanel.point[5], -18)
testlib.equal(UI.summarySections[1].frame.point[5], 0)
testlib.truthy(UI.summarySections[1].divider ~= nil)
```

Also assert By Level cards use the same section treatment.

- [ ] **Step 3: Run the Lua suite and confirm failure**

Run:

```powershell
lua .\tests\run.lua
```

Expected: current sections still use `UI-Character-Info-Title` and row atlases with centered gold/light text.

- [ ] **Step 4: Implement parchment-native section rendering**

In `CreateSection`:

```lua
local header = CreateFrame("Frame", nil, frame)
header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
header:SetHeight(SECTION_HEADER_HEIGHT)

titleText:SetPoint("LEFT", header, "LEFT", 8, 0)
titleText:SetPoint("RIGHT", header, "RIGHT", -8, 0)
titleText:SetJustifyH("LEFT")
titleText:SetTextColor(0.26, 0.13, 0.05, 1)
```

Replace row atlases with subtle parchment colors:

```lua
background:SetColorTexture(
    0.36,
    0.22,
    0.09,
    index % 2 == 0 and 0.08 or 0.03
)
label:SetTextColor(0.32, 0.16, 0.06, 1)
value:SetTextColor(0.12, 0.07, 0.03, 1)
```

Keep the divider and Total Distance emphasis, but use dark brown rather than
bright yellow/white.

- [ ] **Step 5: Add page-top spacing**

Move Overview and By Level panels down inside `contentFrame`:

```lua
UI.overviewPanel:SetPoint("TOPLEFT", UI.contentFrame, "TOPLEFT", 6, -18)
UI.levelPanel:SetPoint("TOPLEFT", UI.contentFrame, "TOPLEFT", 6, -18)
```

Adjust view heights only if required to retain all content inside the existing
`420 x 470` frame. Do not increase the frame unless a failing bounds test
proves it is necessary.

- [ ] **Step 6: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: parchment section tests, content-bound tests, level scrolling, diagnostics, and error-panel tests pass.

- [ ] **Step 7: Commit**

```powershell
git add AzerothTravelMetrics\UITheme.lua AzerothTravelMetrics\UI.lua tests\test_ui_theme.lua tests\test_core.lua
git commit -m "fix: finish parchment section styling" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 6: Update documentation and beta smoke coverage

**Files:**
- Modify: `README.md`
- Modify: `docs/BETA-SMOKE-TESTS.md`

- [ ] **Step 1: Update README**

Document:

- left-justified horizontal Overview/By Level/Settings tabs;
- Settings as a parchment page rather than a popup;
- Reset Current Session inside Settings;
- explicit close/minimize controls;
- parchment-native headings and dividers.

- [ ] **Step 2: Update the smoke checklist**

Replace the first-candidate visual rows with checks for:

```text
Tab strip: horizontal, left-justified, icons fill buttons, order is Overview / By Level / Settings.
Title controls: minimize and close both render and work at 80%, 100%, and 120%.
Settings page: controls synchronize and persist; Reset Current Session is fully visible.
Parchment: no seam above Lifetime; headings/dividers match across Overview and By Level.
Footer: version remains unobscured and no Settings/Reset controls overlap the frame border.
```

Leave these rows `PENDING` until the user observes them in game.

- [ ] **Step 3: Commit**

```powershell
git add README.md docs\BETA-SMOKE-TESTS.md
git commit -m "docs: add spellbook correction smoke checks" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 7: Validate, review, package, and deploy the second candidate

**Files:**
- Verify: all changed files
- Build: `artifacts/AzerothTravelMetrics-1.0.0-beta.zip`
- Deploy: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics`

- [ ] **Step 1: Run the full Lua suite**

```powershell
Set-Location D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window
lua .\tests\run.lua
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Run packaging tests**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PackageAddon.ps1
```

Expected: 40 pass, zero fail, with only the administrator-only symlink test optionally skipped.

- [ ] **Step 3: Run release identity checks**

Use a wide PowerShell buffer so expected fixture paths do not wrap:

```powershell
$size = $Host.UI.RawUI.BufferSize
$size.Width = 500
$Host.UI.RawUI.BufferSize = $size
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
```

Expected: 7 content tests pass and the standalone identity check passes.

- [ ] **Step 4: Validate the TOC**

Run the WoW MCP `wow_toc_validate` tool against
`AzerothTravelMetrics/AzerothTravelMetrics.toc`.

Expected: Interface `16001`, Forever target, no issues.

- [ ] **Step 5: Request focused code review**

Review the complete range from `b7314cc` to the new HEAD. Require the reviewer
to check:

- three-panel selection/error restoration;
- title-control frame levels and native/fallback behavior;
- settings persistence;
- reset confirmation/baseline behavior;
- parchment content bounds and level scrolling;
- WoW Forever template/atlas assumptions.

Fix every Critical or Important issue and rerun affected tests.

- [ ] **Step 6: Build from clean committed HEAD**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Package-Addon.ps1
```

Expected:

```text
Validated addon manifest for Interface 16001.
...\artifacts\AzerothTravelMetrics-1.0.0-beta.zip
```

- [ ] **Step 7: Confirm WoW is closed**

```powershell
$process = Get-Process -Name WowB -ErrorAction SilentlyContinue
if ($process) { throw "Close WoW beta before deployment." }
```

- [ ] **Step 8: Back up and deploy the package**

Use timestamp format `yyyyMMdd_HHmmss`:

```powershell
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$installed = 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics'
$backup = "D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window\artifacts\installed-backups\AzerothTravelMetrics_$stamp"
Copy-Item -LiteralPath $installed -Destination $backup -Recurse -Force
Remove-Item -LiteralPath $installed -Recurse -Force
Expand-Archive -LiteralPath .\artifacts\AzerothTravelMetrics-1.0.0-beta.zip -DestinationPath 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns' -Force
```

- [ ] **Step 9: Refresh and verify ForeverSVFix**

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

- [ ] **Step 10: Preserve the branch for in-game testing**

Keep:

- branch: `feature/spellbook-window`
- worktree: `D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window`

Do not merge until the user confirms the second candidate in game.
