# Hybrid Window Rollback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore ATM's last-known-good right-tab, non-parchment center UI while retaining the portrait frame, thin title bar, pocket-watch identity, and current behavior.

**Architecture:** Selectively restore navigation, center layout, section styling, Settings popup, and footer controls from commit `1567f0f` instead of reverting the branch. Keep current portrait-frame creation and data/HUD logic. Replace the unreliable main-window max/min frame with a direct `UIPanelHideButtonNoScripts` minimize button.

**Tech Stack:** WoW Forever Lua 5.1 UI API, Blizzard virtual templates and atlases, repository Lua harness, PowerShell packaging tests.

---

## File Map

| File | Responsibility |
|---|---|
| `AzerothTravelMetrics/UI.lua` | Portrait shell, title controls, right-side navigation, content geometry, Settings popup, footer controls. |
| `AzerothTravelMetrics/UITheme.lua` | Side-tab and character-stat section rendering. |
| `tests/test_core.lua` | Integrated shell, navigation, Settings, Reset, and panel geometry behavior. |
| `tests/test_ui_theme.lua` | Native/fallback side tabs and restored section styling. |
| `README.md` | User-visible UI description. |
| `docs/BETA-SMOKE-TESTS.md` | In-game acceptance checks for the rollback candidate. |

### Task 1: Restore right-side navigation and reliable title controls

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing shell/navigation assertions**

Replace the current top-tab assertions with:

```lua
testlib.equal(frame.template, "PortraitFrameTemplate")
testlib.equal(UI.closeButton, frame.CloseButton)
testlib.equal(UI.closeButton:IsShown(), true)
testlib.equal(UI.minimizeButton.parent, frame)
testlib.equal(UI.minimizeButton.template, "UIPanelHideButtonNoScripts")
testlib.equal(UI.minimizeButton.point[1], "RIGHT")
testlib.equal(UI.minimizeButton.point[2], UI.closeButton)
testlib.equal(UI.minimizeButton.point[3], "LEFT")
testlib.truthy(UI.minimizeButton.frameLevel >= 510)
testlib.equal(UI.overviewTab.point[1], "TOPLEFT")
testlib.equal(UI.overviewTab.point[2], frame)
testlib.equal(UI.overviewTab.point[3], "TOPRIGHT")
testlib.equal(UI.levelTab.point[1], "TOP")
testlib.equal(UI.levelTab.point[2], UI.overviewTab)
testlib.equal(UI.levelTab.point[3], "BOTTOM")
testlib.equal(UI.settingsTab, nil)
```

Update panel-switch tests so only `overview` and `levels` are valid active tabs
and selection uses `SetSideTabSelected`.

- [ ] **Step 2: Run the suite and verify failure**

```powershell
Set-Location D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window
lua .\tests\run.lua
```

Expected: failures because the window still has horizontal top tabs, a Settings
tab, and `MaximizeMinimizeButtonFrameTemplate`.

- [ ] **Step 3: Restore right-side tabs and direct minimize button**

In `UI.Create`, preserve the portrait and native close setup. Replace the main
minimize creation with:

```lua
UI.minimizeButton = createSafeButton(
    frame,
    "UIPanelHideButtonNoScripts",
    24,
    24,
    nil,
    "-"
)
UI.minimizeControl = UI.minimizeButton
UI.minimizeButton:SetPoint("RIGHT", UI.closeButton, "LEFT", -1, 0)
UI.minimizeButton:SetFrameLevel(510)
UI.minimizeButton:Show()
UI.minimizeButton:SetScript("OnClick", function()
    UI.Minimize()
end)
```

Replace the three `CreateTopTab` calls with the two `CreateSideTab` calls and
anchors from `1567f0f`:

```lua
UI.overviewTab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -4, -34)
UI.levelTab:SetPoint("TOP", UI.overviewTab, "BOTTOM", 0, -2)
```

Remove `UI.settingsTab` and the `settings` branch from `setPanelVisibility`.
Use `Theme.SetSideTabSelected` for Overview and By Level.

- [ ] **Step 4: Run the suite and verify the navigation passes**

```powershell
lua .\tests\run.lua
```

Expected: the new shell/navigation assertions pass; remaining failures are
limited to center styling and Settings/footer expectations.

- [ ] **Step 5: Commit**

```powershell
git add AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: restore right-side window navigation" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 2: Restore the last-known-good non-parchment center

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing theme assertions**

Require `Theme.CreateSection` to produce:

```lua
testlib.equal(section.header.atlas, addon.UITheme.Atlases.SECTION)
testlib.equal(section.title.fontTemplate, "GameFontNormalSmall")
testlib.equal(section.title.justifyH, "CENTER")
testlib.equal(section.title.points[1][4], 13)
testlib.equal(section.title.points[2][4], -13)
testlib.equal(section.rows[1].background.atlas, addon.UITheme.Atlases.ROW)
testlib.equal(section.rows[1].label.textColor[1], 1)
testlib.equal(section.rows[1].label.textColor[2], 0.82)
testlib.equal(section.rows[1].value.textColor[1], 1)
testlib.equal(section.rows[1].value.textColor[2], 1)
```

Remove parchment-divider and zero-shadow assertions.

- [ ] **Step 2: Write failing center-geometry assertions**

In `tests/test_core.lua`, require:

```lua
testlib.equal(UI.parchmentPage, nil)
testlib.equal(UI.pageArtFrame, nil)
testlib.equal(UI.contentFrame.point[4], 16)
testlib.equal(UI.contentFrame.point[5], -50)
testlib.equal(UI.contentFrame.width, 388)
testlib.equal(UI.contentFrame.height, 350)
testlib.equal(UI.errorInset.parent, UI.errorPanel)
testlib.equal(UI.overviewPanel.point[5], -8)
testlib.equal(UI.levelPanel.parent, frame)
testlib.equal(UI.levelPanel.point[4], 22)
testlib.equal(UI.levelPanel.point[5], -54)
```

- [ ] **Step 3: Run the suite and verify failure**

```powershell
lua .\tests\run.lua
```

Expected: failures from parchment geometry and parchment-native section styling.

- [ ] **Step 4: Restore `CreateSection` from `1567f0f`**

Use:

```powershell
git show 1567f0f:AzerothTravelMetrics/UITheme.lua
```

Restore only the `CreateSection` implementation: character-info header atlas,
centered small heading, character-stat row atlas, gold labels, white values, and
existing footer separator. Keep current icon constants and unrelated helpers.

- [ ] **Step 5: Restore center geometry from `1567f0f`**

Remove `UI.pageArtFrame` and `UI.parchmentPage`. Restore:

```lua
UI.contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -50)
UI.contentFrame:SetSize(388, 350)
UI.errorPanel:SetPoint("TOPLEFT", UI.contentFrame, "TOPLEFT", 6, -8)
UI.errorPanel:SetSize(376, 342)
UI.errorInset = ATM.UITheme.CreateInset(UI.errorPanel)
UI.overviewPanel:SetPoint("TOPLEFT", UI.contentFrame, "TOPLEFT", 6, -8)
UI.levelPanel = CreateFrame("Frame", nil, frame)
UI.levelPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -54)
```

Restore the remaining Overview and By Level placement constants exactly from
`1567f0f`; do not alter model refresh or scrolling logic.

- [ ] **Step 6: Run the suite and verify it passes this task**

```powershell
lua .\tests\run.lua
```

Expected: restored theme and geometry tests pass; Settings/footer tests may still
fail until Task 3.

- [ ] **Step 7: Commit**

```powershell
git add AzerothTravelMetrics\UITheme.lua AzerothTravelMetrics\UI.lua tests\test_ui_theme.lua tests\test_core.lua
git commit -m "fix: restore non-parchment metric panels" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 3: Restore Settings popup and footer Reset

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing Settings/footer assertions**

Require:

```lua
testlib.equal(UI.settingsButton.parent, frame)
testlib.equal(UI.settingsTab, nil)
testlib.equal(UI.settingsPanel.parent, frame)
testlib.equal(UI.settingsPanel.template, "InsetFrameTemplate3")
testlib.equal(UI.settingsPanel.width, 205)
testlib.equal(UI.settingsPanel.height, 128)
testlib.equal(UI.resetButton.parent, frame)
testlib.equal(UI.resetButton:GetText(), "Reset Session")
testlib.equal(UI.resetButton.point[1], "BOTTOMLEFT")
testlib.equal(UI.resetWarning, nil)
testlib.equal(UI.resetDivider, nil)
testlib.equal(UI.resetHeading, nil)
```

Exercise `UI.settingsButton.scripts.OnClick()` twice and assert the panel shows
then hides while controls remain synchronized.

- [ ] **Step 2: Run the suite and verify failure**

```powershell
lua .\tests\run.lua
```

Expected: failures because Settings and Reset still live on the parchment page.

- [ ] **Step 3: Restore footer and popup code from `1567f0f`**

Use:

```powershell
git show 1567f0f:AzerothTravelMetrics/UI.lua
```

Restore the `Reset Session` footer button, Settings icon button, compact
`InsetFrameTemplate3` panel, checkbox anchors, synchronization, and toggle
handler. Remove `resetDivider`, `resetHeading`, and `resetWarning`.

Keep the current reset confirmation/storage functions unchanged.

- [ ] **Step 4: Run the suite and verify it passes**

```powershell
lua .\tests\run.lua
```

Expected: all Lua tests pass.

- [ ] **Step 5: Commit**

```powershell
git add AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: restore footer settings and reset controls" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 4: Document, review, package, and deploy

**Files:**
- Modify: `README.md`
- Modify: `docs/BETA-SMOKE-TESTS.md`
- Build: `artifacts/AzerothTravelMetrics-1.0.0-beta.zip`
- Deploy: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics`

- [ ] **Step 1: Update documentation**

Document:

- portrait frame and thin title bar retained;
- Overview and By Level restored as right-side tabs;
- non-parchment character-stat center restored;
- Settings restored to footer gear/popup;
- Reset Session restored to footer;
- native close and direct native minimize controls.

- [ ] **Step 2: Run all validation**

```powershell
lua .\tests\run.lua
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PackageAddon.ps1
$size = $Host.UI.RawUI.BufferSize
$size.Width = 500
$Host.UI.RawUI.BufferSize = $size
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
```

Expected: all Lua tests pass; packaging tests pass with only the administrator
symlink test optionally skipped; all identity checks pass.

- [ ] **Step 3: Validate TOC and request focused review**

Validate Interface `16001` and review changes since `b91d153`. Resolve all
Critical and Important findings.

- [ ] **Step 4: Commit documentation**

```powershell
git add README.md docs\BETA-SMOKE-TESTS.md
git commit -m "docs: describe hybrid window rollback" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

- [ ] **Step 5: Build and deploy**

Build from clean committed HEAD:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Package-Addon.ps1
```

Confirm `WowB` is not running, back up the installed addon using
`yyyyMMdd_HHmmss`, deploy the package, and run:

```powershell
Set-Location D:\_projects\ForeverSVFix
python .\forever_sv_fix.py --wow 'D:\Games\World of Warcraft\_classic_beta_' --account '50347838#1' repair
python .\forever_sv_fix.py --wow 'D:\Games\World of Warcraft\_classic_beta_' --account '50347838#1' doctor
```

Expected: `Active installation checks: OK` and `No repair needed.`

- [ ] **Step 6: Verify deployment and preserve branch**

Compare installed files with `artifacts\AzerothTravelMetrics`, excluding the
ForeverSVFix-patched TOC. Keep `feature/spellbook-window` and its worktree for
in-game approval.
