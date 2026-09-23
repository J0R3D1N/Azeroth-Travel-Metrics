# Spellbook Window Runtime Visual Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the exposed rock-texture band, make parchment text readable, and place minimize/close controls fully inside the native title bar.

**Architecture:** Keep ATM's content and footer geometry unchanged, but host the parchment atlas on a separate art frame that extends upward behind the tabs. Reuse the portrait template's native close button and place the minimize control at the native chrome frame level; retain ATM-owned controls only for the fallback shell. Apply Blizzard's spellbook text treatment by using regular game fonts with shadows disabled.

**Tech Stack:** WoW Forever Lua 5.1 UI API, Blizzard virtual templates and atlases, repository Lua test harness, PowerShell packaging tests.

---

## File Map

| File | Responsibility |
|---|---|
| `AzerothTravelMetrics/UI.lua` | Main-window geometry, native/fallback title-control ownership, panel placement. |
| `AzerothTravelMetrics/UITheme.lua` | Parchment page creation and section typography. |
| `tests/test_core.lua` | Integrated page-art geometry and native/fallback title-control behavior. |
| `tests/test_ui_theme.lua` | Font-object and shadow-removal behavior. |
| `docs/BETA-SMOKE-TESTS.md` | Runtime checks for the screenshot regressions. |

### Task 1: Separate parchment art from panel geometry

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write the failing integrated geometry assertions**

In `ui uses portrait chrome top tabs and a parchment page`, replace the direct
page-parent assumption with:

```lua
testlib.equal(UI.pageArtFrame.parent, frame)
testlib.equal(UI.pageArtFrame.point[1], "TOPLEFT")
testlib.equal(UI.pageArtFrame.point[2], UI.contentFrame)
testlib.equal(UI.pageArtFrame.point[3], "TOPLEFT")
testlib.equal(UI.pageArtFrame.point[4], 0)
testlib.equal(UI.pageArtFrame.point[5], 34)
testlib.equal(UI.pageArtFrame.width, 388)
testlib.equal(UI.pageArtFrame.height, 398)
testlib.equal(UI.parchmentPage.parent, UI.pageArtFrame)
testlib.equal(UI.contentFrame.height, 364)
testlib.equal(UI.overviewPanel.point[5], -18)
```

Also require the art frame and content frame to share the same bottom:

```lua
testlib.equal(
    UI.pageArtFrame.point[5] - UI.pageArtFrame.height,
    -UI.contentFrame.height
)
```

- [ ] **Step 2: Run the suite and verify the new assertions fail**

```powershell
Set-Location D:\_projects\azeroth-travel-metrics\.worktrees\spellbook-window
lua .\tests\run.lua
```

Expected: failure because `UI.pageArtFrame` does not exist.

- [ ] **Step 3: Add the dedicated page-art frame**

In `UI.Create`, immediately before creating `UI.contentFrame`, add:

```lua
UI.pageArtFrame = CreateFrame("Frame", nil, frame)
UI.pageArtFrame:SetPoint(
    "TOPLEFT",
    UI.contentFrame,
    "TOPLEFT",
    0,
    34
)
UI.pageArtFrame:SetSize(388, 398)
UI.parchmentPage = ATM.UITheme.CreateParchmentPage(UI.pageArtFrame)
```

Because this references `UI.contentFrame`, first create and size
`UI.contentFrame`, then create `UI.pageArtFrame`; remove the old
`CreateParchmentPage(UI.contentFrame)` call. Do not change content-frame,
panel, or footer coordinates.

- [ ] **Step 4: Run the suite and verify it passes**

```powershell
lua .\tests\run.lua
```

Expected: all Lua tests pass.

- [ ] **Step 5: Commit**

```powershell
git add AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: extend parchment art behind tabs" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 2: Make parchment typography readable

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`

- [ ] **Step 1: Add shadow support to the theme harness**

Add this method to `newRegion` in `tests/test_ui_theme.lua`:

```lua
function region:SetShadowOffset(x, y)
    self.shadowOffset = { x, y }
end
```

- [ ] **Step 2: Write failing typography assertions**

In the section-rendering test, require:

```lua
testlib.equal(section.title.template, "GameFontNormal")
testlib.equal(section.title.shadowOffset[1], 0)
testlib.equal(section.title.shadowOffset[2], 0)
testlib.equal(section.rows[1].label.template, "GameFontNormal")
testlib.equal(section.rows[1].label.shadowOffset[1], 0)
testlib.equal(section.rows[1].label.shadowOffset[2], 0)
testlib.equal(section.rows[1].value.template, "GameFontHighlight")
testlib.equal(section.rows[1].value.shadowOffset[1], 0)
testlib.equal(section.rows[1].value.shadowOffset[2], 0)
```

Keep the existing dark-brown color and divider assertions.

- [ ] **Step 3: Run the suite and verify the assertions fail**

```powershell
lua .\tests\run.lua
```

Expected: failures showing the current `*Small` templates and missing shadow
offsets.

- [ ] **Step 4: Apply the regular fonts and remove shadows**

In `Theme.CreateSection`, create the title with `GameFontNormal`, labels with
`GameFontNormal`, and values with `GameFontHighlight`. Immediately after setting
each font string's color, add:

```lua
if type(fontString.SetShadowOffset) == "function" then
    fontString:SetShadowOffset(0, 0)
end
```

Use the actual local names `titleText`, `label`, and `value`; do not introduce a
new helper for three calls.

- [ ] **Step 5: Run the suite and verify it passes**

```powershell
lua .\tests\run.lua
```

Expected: all Lua tests pass without changing section dimensions.

- [ ] **Step 6: Commit**

```powershell
git add AzerothTravelMetrics\UITheme.lua tests\test_ui_theme.lua
git commit -m "fix: improve parchment text readability" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 3: Use native title-control layering

**Files:**
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Replace the native-control assertions**

Update `ui uses portrait chrome top tabs and a parchment page` to require:

```lua
testlib.equal(UI.closeButton, frame.CloseButton)
testlib.equal(frame.CloseButton:IsShown(), true)
testlib.equal(UI.minimizeControl.parent, frame)
testlib.equal(UI.minimizeControl.point[1], "RIGHT")
testlib.equal(UI.minimizeControl.point[2], frame.CloseButton)
testlib.equal(UI.minimizeControl.point[3], "LEFT")
testlib.truthy(UI.minimizeControl.frameLevel >= 510)
```

Update `ui creates a safe close button when portrait chrome omits one` to
require that the fallback close button is parented to `UI.titleRegion`.

- [ ] **Step 2: Run the suite and verify the assertions fail**

```powershell
lua .\tests\run.lua
```

Expected: failures because the native close button is hidden and both controls
currently belong to `UI.titleRegion`.

- [ ] **Step 3: Reuse native close and raise native minimize**

In `UI.Create`:

```lua
if nativePortrait and frame.CloseButton then
    UI.closeButton = frame.CloseButton
    UI.closeButton:Show()
else
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
end
UI.closeButton:SetScript("OnClick", function()
    frame:Hide()
end)
```

Create the minimize control with `frame` as parent on the native path and
`UI.titleRegion` on the fallback path:

```lua
local titleControlParent = nativePortrait and frame or UI.titleRegion
UI.minimizeControl, UI.minimizeButton =
    ATM.UITheme.CreateWindowSizeControl(
        titleControlParent,
        "minimize",
        "Minimize"
    )
UI.minimizeControl:SetPoint("RIGHT", UI.closeButton, "LEFT", -1, 0)
if nativePortrait then
    UI.minimizeControl:SetFrameLevel(510)
else
    raiseAboveParent(UI.minimizeControl, UI.titleRegion, 3)
end
```

Remove the code that hides `frame.CloseButton`. Preserve existing click
handlers and fallback behavior.

- [ ] **Step 4: Run the suite and verify it passes**

```powershell
lua .\tests\run.lua
```

Expected: all Lua tests pass.

- [ ] **Step 5: Commit**

```powershell
git add AzerothTravelMetrics\UI.lua tests\test_core.lua
git commit -m "fix: place controls in native title chrome" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 4: Document, validate, package, and deploy

**Files:**
- Modify: `docs/BETA-SMOKE-TESTS.md`
- Build: `artifacts/AzerothTravelMetrics-1.0.0-beta.zip`
- Deploy: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics`

- [ ] **Step 1: Update the pending smoke gate**

Add explicit pending checks:

```text
No native rock-texture strip appears between the tabs and parchment.
Lifetime is fully visible and all section text is readable without dark shadows.
Minimize and close are fully inside the title bar and both controls work.
The parchment bottom and version footer remain unchanged and unobscured.
```

- [ ] **Step 2: Run the full Lua suite**

```powershell
lua .\tests\run.lua
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Run packaging and release identity tests**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PackageAddon.ps1
$size = $Host.UI.RawUI.BufferSize
$size.Width = 500
$Host.UI.RawUI.BufferSize = $size
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
```

Expected: packaging tests pass with only the administrator-only symlink test
optionally skipped; 7 identity-content tests and the standalone identity check
pass.

- [ ] **Step 4: Validate the TOC and request focused review**

Validate `AzerothTravelMetrics/AzerothTravelMetrics.toc` for Forever Interface
`16001`, then review only the branch changes since `a210db0`. Resolve all
Critical and Important findings before packaging.

- [ ] **Step 5: Commit documentation**

```powershell
git add docs\BETA-SMOKE-TESTS.md
git commit -m "docs: add runtime visual smoke checks" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

- [ ] **Step 6: Build the clean committed package**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Package-Addon.ps1
```

Expected: `artifacts\AzerothTravelMetrics-1.0.0-beta.zip` is rebuilt from clean
HEAD.

- [ ] **Step 7: Deploy while WoW is closed**

Confirm `WowB` is not running, back up the installed addon using
`yyyyMMdd_HHmmss`, replace it with the package, then run:

```powershell
Set-Location D:\_projects\ForeverSVFix
python .\forever_sv_fix.py --wow 'D:\Games\World of Warcraft\_classic_beta_' --account '50347838#1' repair
python .\forever_sv_fix.py --wow 'D:\Games\World of Warcraft\_classic_beta_' --account '50347838#1' doctor
```

Expected: `Active installation checks: OK` and `No repair needed.`

- [ ] **Step 8: Verify deployed files**

Compare installed runtime files with
`artifacts\AzerothTravelMetrics`, excluding the TOC because ForeverSVFix patches
it. Preserve `feature/spellbook-window` and its worktree for in-game review.
