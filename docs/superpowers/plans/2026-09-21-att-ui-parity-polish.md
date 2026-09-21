# ATT UI Parity Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Azeroth Travel Tracker match Azeroth Public Library's warm translucency and panel hierarchy while fixing scrollbar, minimap, window-control, and AddOns-menu identity defects.

**Architecture:** Keep ATT's compact window architecture and move reusable visual behavior into `UITheme.lua`. `UI.lua` remains responsible for window composition and scroll-state updates, while `Minimap.lua` remains responsible for shape-aware launcher geometry. Every behavior change begins with a failing Lua or PowerShell regression test, and the clean package is installed before ForeverSVFix is reapplied and verified.

**Tech Stack:** World of Warcraft addon Lua, Blizzard frame/texture APIs, dependency-free Lua test harness, PowerShell packaging tests, ForeverSVFix v1.0.2, Git.

**Approved design:** `docs/superpowers/specs/2026-09-21-att-ui-parity-polish-design.md`

---

## File Map

| File | Responsibility in this change |
|---|---|
| `AzerothTravelTracker/UITheme.lua` | Own APL-derived shell alpha values, fallback shell, title separator, and reusable minimize/restore title controls. |
| `AzerothTravelTracker/UI.lua` | Select correct strata, compose main/HUD controls, reserve the internal scrollbar gutter, and toggle scrollbar chrome only on overflow. |
| `AzerothTravelTracker/Minimap.lua` | Center launcher artwork and calculate rim-kiss offsets from the launcher's decorative radius. |
| `AzerothTravelTracker/AzerothTravelTracker.toc` | Expose the exact Forever-beta AddOns-menu title. |
| `tests/test_core.lua` | Frame-harness and UI regressions for opacity, strata, controls, and scrollbar behavior. |
| `tests/test_ui_theme.lua` | Focused title-control construction and fallback tests. |
| `tests/test_minimap.lua` | Rim-kiss geometry, border centering, shape, dimension, and frame-level tests. |
| `tools/Package-Addon.ps1` | Validate the new exact TOC title in release packages. |
| `tests/Test-PackageAddon.ps1` | Prove package validation accepts only the new exact title. |
| `README.md` | Document the visible Forever-beta identity and the mandatory post-install ForeverSVFix workflow. |
| `docs/BETA-SMOKE-TESTS.md` | Record manual comparison and interaction results after installation. |

The existing uncommitted smoke-test observation in `docs/BETA-SMOKE-TESTS.md`
must remain intact. Do not stage it in implementation commits until the final
manual-validation task explicitly updates that file.

## Task 1: Match APL Shell Translucency and Layer Hierarchy

**Files:**
- Modify: `tests/test_core.lua:2139-2354`
- Modify: `tests/test_core.lua:2517-2570`
- Modify: `tests/test_core.lua:2632-2703`
- Modify: `AzerothTravelTracker/UITheme.lua:18-163`
- Modify: `AzerothTravelTracker/UI.lua:49-64`
- Modify: `AzerothTravelTracker/UI.lua:650-800`

- [ ] **Step 1: Change shell and strata assertions to the approved values**

In `tests/test_core.lua`, update the custom-shell test so it requires the APL
layer values and `MEDIUM` strata:

```lua
testlib.equal(first.strata, "MEDIUM")
testlib.near(harness.addon.UI.shell.darkTexture.vertexColor[1], 0.86, 0.001)
testlib.near(harness.addon.UI.shell.darkTexture.vertexColor[2], 0.64, 0.001)
testlib.near(harness.addon.UI.shell.darkTexture.vertexColor[3], 0.20, 0.001)
testlib.near(harness.addon.UI.shell.darkTexture.vertexColor[4], 0.26, 0.001)
testlib.near(harness.addon.UI.shell.goldTexture.vertexColor[1], 0.80, 0.001)
testlib.near(harness.addon.UI.shell.goldTexture.vertexColor[2], 0.58, 0.001)
testlib.near(harness.addon.UI.shell.goldTexture.vertexColor[3], 0.18, 0.001)
testlib.near(harness.addon.UI.shell.goldTexture.vertexColor[4], 0.08, 0.001)
testlib.equal(harness.addon.UI.shell.topGlow.height, 28)
testlib.truthy(harness.addon.UI.shell.titleSeparator ~= nil)
testlib.near(harness.addon.UI.shell.titleSeparator.color[4], 0.22, 0.001)
```

Update the gradient fallback assertion from `0.42` to `0.16`.

Replace the strata cases with the new order:

```lua
local cases = {
    {
        rejected = {},
        expected = "MEDIUM",
        attempts = { "MEDIUM" },
    },
    {
        rejected = { MEDIUM = true },
        expected = "HIGH",
        attempts = { "MEDIUM", "HIGH" },
    },
    {
        rejected = { MEDIUM = true, HIGH = true },
        expected = "DIALOG",
        attempts = { "MEDIUM", "HIGH", "DIALOG" },
    },
    {
        rejected = { MEDIUM = true, HIGH = true, DIALOG = true },
        expected = nil,
        attempts = { "MEDIUM", "HIGH", "DIALOG" },
    },
}
```

For each case, assert both the main frame and HUD attempt exactly that sequence.
Also assert:

```lua
testlib.equal(harness.addon.UI.settingsPanel.strata, "DIALOG")
testlib.truthy(
    harness.addon.UI.settingsPanel:GetFrameLevel()
        > harness.addon.UI.frame:GetFrameLevel()
)
```

- [ ] **Step 2: Run the Lua suite and verify the new tests fail**

Run:

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
lua tests\run.lua
```

Expected: failures show the current 0.88 dark overlay, 0.16 gold overlay,
0.42 fallback vignette, missing separator, `DIALOG` default strata, and missing
settings-panel strata.

- [ ] **Step 3: Apply APL's shell layer values**

In `UITheme.lua`, keep `SHELL_BACKDROP`, but make the accepted backdrop set both
colors:

```lua
frame:SetBackdropColor(0.08, 0.06, 0.035, 0.95)
if type(frame.SetBackdropBorderColor) == "function" then
    pcall(
        frame.SetBackdropBorderColor,
        frame,
        0.67,
        0.53,
        0.27,
        0.96
    )
end
```

Replace the shell layer construction with these values:

```lua
shell.darkTexture = frame:CreateTexture(nil, "BACKGROUND")
shell.darkTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -7)
shell.darkTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7, 7)
shell.darkTexture:SetTexture(
    "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
)
shell.darkTexture:SetVertexColor(0.86, 0.64, 0.20, 0.26)

shell.goldTexture = frame:CreateTexture(nil, "BACKGROUND")
shell.goldTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
shell.goldTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
shell.goldTexture:SetTexture(
    "Interface\\DialogFrame\\UI-DialogBox-Gold-Background"
)
shell.goldTexture:SetVertexColor(0.80, 0.58, 0.18, 0.08)

shell.vignette = frame:CreateTexture(nil, "BORDER")
shell.vignette:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
shell.vignette:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
local gradientApplied = false
if type(shell.vignette.SetGradientAlpha) == "function" then
    local ok, accepted = pcall(
        shell.vignette.SetGradientAlpha,
        shell.vignette,
        "VERTICAL",
        0.02, 0.01, 0.00, 0.16,
        0.00, 0.00, 0.00, 0.03
    )
    gradientApplied = ok and accepted ~= false
end
if not gradientApplied then
    shell.vignette:SetColorTexture(0.02, 0.01, 0.00, 0.16)
end

shell.topGlow = frame:CreateTexture(nil, "BORDER")
shell.topGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
shell.topGlow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -8)
shell.topGlow:SetHeight(28)
shell.topGlow:SetColorTexture(0.95, 0.72, 0.22, 0.14)

shell.titleSeparator = frame:CreateTexture(nil, "BORDER")
shell.titleSeparator:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -52)
shell.titleSeparator:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -52)
shell.titleSeparator:SetHeight(1)
shell.titleSeparator:SetColorTexture(0.88, 0.69, 0.24, 0.22)
```

Change the bare-shell fallback background to
`(0.08, 0.06, 0.035, 0.95)` and fallback border to
`(0.67, 0.53, 0.27, 0.96)`.

- [ ] **Step 4: Change main/HUD and overlay strata**

In `UI.lua`, replace the strata order with:

```lua
local strataOptions = {
    "MEDIUM",
    "HIGH",
    "DIALOG",
}
```

After creating `settingsPanel`, set its overlay strata defensively:

```lua
if type(settingsPanel.SetFrameStrata) == "function" then
    pcall(settingsPanel.SetFrameStrata, settingsPanel, "DIALOG")
end
if type(settingsPanel.SetFrameLevel) == "function"
    and type(frame.GetFrameLevel) == "function"
then
    settingsPanel:SetFrameLevel(frame:GetFrameLevel() + 100)
end
```

- [ ] **Step 5: Extend the frame harness for border-color assertions**

Add this method beside `SetBackdropColor` in `tests/test_core.lua`:

```lua
function frame:SetBackdropBorderColor(...)
    self.backdropBorderColor = { ... }
end
```

Assert the four border components match `(0.67, 0.53, 0.27, 0.96)`.

- [ ] **Step 6: Run the Lua suite and verify it passes**

Run:

```powershell
lua tests\run.lua
```

Expected: zero failed tests.

- [ ] **Step 7: Commit the shell and hierarchy change**

```powershell
git add AzerothTravelTracker\UITheme.lua AzerothTravelTracker\UI.lua tests\test_core.lua
git commit -m "fix: match APL shell and panel hierarchy" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 2: Replace Text Controls with Compact Title Glyph Controls

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_core.lua:2426-2437`
- Modify: `tests/test_core.lua:3036-3174`
- Modify: `AzerothTravelTracker/UITheme.lua`
- Modify: `AzerothTravelTracker/UI.lua:290-598`
- Modify: `AzerothTravelTracker/UI.lua:685-724`

- [ ] **Step 1: Write failing UI theme tests for minimize and restore glyphs**

In `tests/test_ui_theme.lua`, extend its fake frame/texture support with
`SetRotation`:

```lua
function region:SetRotation(radians)
    self.rotation = radians
end
```

Add:

```lua
testlib.case("title controls expose compact minimize and restore glyphs", function()
    local addon, parent = newHarness()

    local minimize = addon.UITheme.CreateTitleControl(
        parent,
        "minimize",
        "Minimize",
        24
    )
    local restore = addon.UITheme.CreateTitleControl(
        parent,
        "restore",
        "Restore",
        20
    )

    testlib.equal(minimize.width, 24)
    testlib.equal(minimize.height, 24)
    testlib.equal(minimize.controlKind, "minimize")
    testlib.equal(#minimize.GlyphTextures, 1)
    testlib.equal(minimize.GlyphTextures[1].width, 9)
    testlib.equal(minimize.GlyphTextures[1].height, 2)

    testlib.equal(restore.controlKind, "restore")
    testlib.equal(#restore.GlyphTextures, 3)
    testlib.near(restore.GlyphTextures[1].rotation, math.rad(45), 0.001)
end)
```

- [ ] **Step 2: Write failing composition assertions**

Update the main-window test in `tests/test_core.lua`:

```lua
testlib.equal(UI.minimizeButton.controlKind, "minimize")
testlib.equal(UI.minimizeButton.width, 24)
testlib.equal(UI.minimizeButton.height, 24)
testlib.equal(UI.minimizeButton.point[2], UI.closeButton)
```

Update the HUD tests:

```lua
testlib.equal(UI.hud.restoreButton.controlKind, "restore")
testlib.equal(UI.hud.restoreButton.width, 20)
testlib.equal(UI.hud.restoreButton.height, 20)
testlib.equal(UI.hud.restoreButton:GetText(), nil)
testlib.equal(UI.hud.restoreButton.point[2], UI.hud.closeButton)
testlib.equal(UI.hud.restoreButton.point[3], "LEFT")
```

Keep the existing assertions that both HUD controls are hidden at rest, shown
on hover, and remain shown while either control is hovered.

- [ ] **Step 3: Run the Lua suite and verify the new tests fail**

Run:

```powershell
lua tests\run.lua
```

Expected: `CreateTitleControl` is missing and the HUD still exposes a 54-pixel
text `Restore` button.

- [ ] **Step 4: Implement `Theme.CreateTitleControl`**

Add to `UITheme.lua`:

```lua
local function addGlyphLine(button, width, height, x, y, rotation)
    local line = button:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0.18, 1)
    line:SetSize(width, height)
    line:SetPoint("CENTER", button, "CENTER", x, y)
    if rotation and type(line.SetRotation) == "function" then
        pcall(line.SetRotation, line, rotation)
    end
    table.insert(button.GlyphTextures, line)
    return line
end

function Theme.CreateTitleControl(parent, kind, tooltip, size)
    local button = CreateFrame("Button", nil, parent)
    size = size or 20
    button:SetSize(size, size)
    button.controlKind = kind
    button.GlyphTextures = {}

    button.Background = createColorTexture(
        button,
        "BACKGROUND",
        0.18,
        0.10,
        0.04,
        0.88
    )
    button.HighlightTexture = createColorTexture(
        button,
        "HIGHLIGHT",
        0.95,
        0.72,
        0.22,
        0.24
    )

    if kind == "minimize" then
        addGlyphLine(button, 9, 2, 0, -4, nil)
    elseif kind == "restore" then
        addGlyphLine(button, 10, 2, -1, 0, math.rad(45))
        addGlyphLine(button, 5, 2, 3, 4, 0)
        addGlyphLine(button, 5, 2, 5, 2, math.rad(90))
    else
        error("unsupported title control: " .. tostring(kind))
    end

    setTooltip(button, tooltip or "")
    return button
end
```

If the beta rejects `SetRotation`, keep the three visible line textures in
their fallback positions; the helper must not throw.

- [ ] **Step 5: Use the helper in the main window and HUD**

Remove `createMinimizeButton` from `UI.lua`.

Create the main minimize button with:

```lua
UI.minimizeButton = ATT.UITheme.CreateTitleControl(
    UI.titleRegion,
    "minimize",
    "Minimize",
    24
)
```

Replace the HUD text button with:

```lua
local restoreButton = ATT.UITheme.CreateTitleControl(
    frame,
    "restore",
    "Restore",
    20
)
restoreButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
```

Create `closeButton` first, anchored at `TOPRIGHT, -2, -2`, so restore can be
positioned relative to it. Preserve all existing click and hover scripts.

- [ ] **Step 6: Run the Lua suite and verify it passes**

Run:

```powershell
lua tests\run.lua
```

Expected: zero failed tests.

- [ ] **Step 7: Commit the control change**

```powershell
git add AzerothTravelTracker\UITheme.lua AzerothTravelTracker\UI.lua tests\test_ui_theme.lua tests\test_core.lua
git commit -m "fix: use compact minimize and restore controls" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 3: Keep the By Level Scrollbar Inside an Overflow-Only Gutter

**Files:**
- Modify: `tests/test_core.lua:1470-1925`
- Modify: `tests/test_core.lua:3248-3333`
- Modify: `AzerothTravelTracker/UI.lua:12-20`
- Modify: `AzerothTravelTracker/UI.lua:1028-1086`
- Modify: `AzerothTravelTracker/UI.lua:1210-1280`

- [ ] **Step 1: Extend the test harness with native scrollbar chrome**

In `newUIHarness`'s `CreateFrame`, add:

```lua
if template == "UIPanelScrollFrameTemplate" then
    frame.ScrollBar = newFrame("Slider", nil, frame, nil, options)
    frame.ScrollBar.ScrollUpButton =
        newFrame("Button", nil, frame.ScrollBar, nil, options)
    frame.ScrollBar.ScrollDownButton =
        newFrame("Button", nil, frame.ScrollBar, nil, options)
    frame.ScrollBar.ThumbTexture =
        newFrame("Texture", nil, frame.ScrollBar, nil, options)
end
```

- [ ] **Step 2: Write failing gutter and overflow assertions**

Add a one-row case:

```lua
testlib.case("ui hides level scrollbar chrome when content fits", function()
    local harness = newUIHarness({
        levelRows = {
            {
                level = 5,
                steps = "5",
                onFoot = "5 m",
                swimming = "0 m",
                taxi = "0 m",
            },
        },
    })
    local UI = harness.addon.UI
    UI.Create()
    UI.Refresh()

    testlib.equal(UI.levelScrollFrame.width, 348)
    testlib.equal(UI.levelScrollChild.width, 348)
    testlib.equal(UI.levelRows[1].frame.width, 348)
    testlib.equal(UI.levelScrollFrame.ScrollBar:IsShown(), false)
end)
```

Extend the 16-row overflow case:

```lua
testlib.equal(UI.levelScrollFrame.width, 348)
testlib.equal(UI.levelScrollFrame.ScrollBar:IsShown(), true)
testlib.equal(UI.levelScrollFrame.ScrollBar.points[1][1], "TOPLEFT")
testlib.equal(
    UI.levelScrollFrame.ScrollBar.points[1][2],
    UI.levelScrollFrame
)
testlib.equal(UI.levelScrollFrame.ScrollBar.points[1][3], "TOPRIGHT")
testlib.truthy(UI.levelScrollFrame.ScrollBar.points[1][4] >= 2)
testlib.equal(UI.levelScrollFrame.ScrollBar.points[2][1], "BOTTOMLEFT")
```

Add a fallback case with `UIPanelScrollFrameTemplate` rejected and assert
creation and refresh succeed without `ScrollBar`.

- [ ] **Step 3: Run the Lua suite and verify the new tests fail**

Run:

```powershell
lua tests\run.lua
```

Expected: the viewport remains 376 pixels wide, scrollbar chrome is unmanaged,
and cards do not explicitly reserve the gutter.

- [ ] **Step 4: Add scrollbar chrome helpers**

Near the top of `UI.lua`, define:

```lua
local LEVEL_PANEL_WIDTH = 376
local LEVEL_CONTENT_WIDTH = 348
local LEVEL_SCROLLBAR_GAP = 4
```

Add:

```lua
local function setRegionShown(region, shown)
    if not region then
        return
    end
    if shown and type(region.Show) == "function" then
        region:Show()
    elseif not shown and type(region.Hide) == "function" then
        region:Hide()
    end
end

local function updateLevelScrollbar()
    local scrollFrame = UI.levelScrollFrame
    if not scrollFrame then
        return
    end

    local scrollRange = 0
    if type(scrollFrame.GetVerticalScrollRange) == "function" then
        local ok, value = pcall(
            scrollFrame.GetVerticalScrollRange,
            scrollFrame
        )
        if ok and type(value) == "number" and value > 0 then
            scrollRange = value
        end
    end

    setRegionShown(scrollFrame.ScrollBar, scrollRange > 0)
end
```

- [ ] **Step 5: Reserve and anchor the internal gutter**

Set:

```lua
UI.levelPanel:SetSize(LEVEL_PANEL_WIDTH, 310)
levelScrollFrame:SetSize(LEVEL_CONTENT_WIDTH, LEVEL_VIEW_HEIGHT)
UI.levelScrollChild:SetSize(LEVEL_CONTENT_WIDTH, LEVEL_VIEW_HEIGHT)
```

When `levelScrollFrame.ScrollBar` exists:

```lua
levelScrollFrame.ScrollBar:ClearAllPoints()
levelScrollFrame.ScrollBar:SetPoint(
    "TOPLEFT",
    levelScrollFrame,
    "TOPRIGHT",
    LEVEL_SCROLLBAR_GAP,
    -14
)
levelScrollFrame.ScrollBar:SetPoint(
    "BOTTOMLEFT",
    levelScrollFrame,
    "BOTTOMRIGHT",
    LEVEL_SCROLLBAR_GAP,
    14
)
```

Keep every level card width at `LEVEL_CONTENT_WIDTH`.

Call `updateLevelScrollbar()` after setting the final scroll-child height in
`UI.Refresh()`. Reset vertical scroll to zero only when rows shrink below the
current offset.

- [ ] **Step 6: Run the Lua suite and verify it passes**

Run:

```powershell
lua tests\run.lua
```

Expected: zero failed tests.

- [ ] **Step 7: Commit the scrollbar change**

```powershell
git add AzerothTravelTracker\UI.lua tests\test_core.lua
git commit -m "fix: contain the level scrollbar inside ATT" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 4: Attach the Minimap Launcher with Rim-Kiss Geometry

**Files:**
- Modify: `tests/test_minimap.lua:1-180`
- Modify: `tests/test_minimap.lua:297-470`
- Modify: `AzerothTravelTracker/Minimap.lua:5-21`
- Modify: `AzerothTravelTracker/Minimap.lua:64-186`
- Modify: `AzerothTravelTracker/Minimap.lua:258-296`

- [ ] **Step 1: Write failing rim-kiss geometry tests**

Add constants in the test:

```lua
local LAUNCHER_OUTER_RADIUS = 27
```

Update default-padding expectations:

```lua
local x, y = addon.Minimap.CalculateMinimapOffset(0, 200, 160)
testlib.near(x, 127, 0.0001)
testlib.near(y, 0, 0.0001)
```

For a 140 x 140 round minimap at 45 degrees:

```lua
local expected = (70 + LAUNCHER_OUTER_RADIUS) / math.sqrt(2)
testlib.near(x, expected, 0.0001)
testlib.near(y, expected, 0.0001)
```

Extend launcher creation assertions:

```lua
testlib.equal(harness.addon.Minimap.border.point[1], "CENTER")
testlib.equal(harness.addon.Minimap.border.point[2], button)
testlib.equal(harness.addon.Minimap.border.point[3], "CENTER")
testlib.near(button.point[4], 127, 0.0001)
testlib.truthy(button.frameLevel > harness.environment.Minimap:GetFrameLevel())
```

Keep explicit-padding tests at `5`; they continue proving the reusable geometry
function independently of the launcher's default radius.

Update fallback-dimension expectations:

```lua
local x, y = addon.Minimap.CalculateMinimapOffset(0, nil, nil)
testlib.near(x, 102, 0.0001)
testlib.near(y, 0, 0.0001)
```

- [ ] **Step 2: Run minimap tests and verify they fail**

Run:

```powershell
lua tests\run.lua
```

Expected: default placement still uses `18`, the border is anchored from
`TOPLEFT`, and the default offsets are too close or visually displaced.

- [ ] **Step 3: Derive launcher placement from its decorative radius**

Replace the minimap constants with:

```lua
local BUTTON_SIZE = 32
local BORDER_SIZE = 54
local BUTTON_OUTER_RADIUS = BORDER_SIZE / 2
local DEFAULT_MINIMAP_DIAMETER = 150
```

Keep `CalculateMinimapOffset`'s `padding` parameter, but default it to
`BUTTON_OUTER_RADIUS`.

In `positionButton`, call:

```lua
local x, y = MinimapLauncher.CalculateMinimapOffset(
    angle,
    width,
    height,
    BUTTON_OUTER_RADIUS,
    getMinimapShape()
)
```

Use `BUTTON_SIZE` in `button:SetSize`.

- [ ] **Step 4: Center the decorative border**

Replace:

```lua
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
```

with:

```lua
border:SetSize(BORDER_SIZE, BORDER_SIZE)
border:SetPoint("CENTER", button, "CENTER", 0, 0)
```

Preserve the current relative frame-level elevation over `Minimap`.

- [ ] **Step 5: Run the Lua suite and verify it passes**

Run:

```powershell
lua tests\run.lua
```

Expected: zero failed tests across all shapes, dimensions, drag behavior, and
visibility behavior.

- [ ] **Step 6: Commit the minimap change**

```powershell
git add AzerothTravelTracker\Minimap.lua tests\test_minimap.lua
git commit -m "fix: attach the launcher to the minimap rim" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 5: Identify the Package as WoW Forever Beta

**Files:**
- Modify: `tests/Test-PackageAddon.ps1`
- Modify: `tools/Package-Addon.ps1:35-50`
- Modify: `AzerothTravelTracker/AzerothTravelTracker.toc:1-7`
- Modify: `README.md:1-22`

- [ ] **Step 1: Change package fixtures to require the exact approved title**

In every valid fixture in `tests/Test-PackageAddon.ps1`, replace:

```text
## Title: Azeroth Travel Tracker
```

with:

```text
## Title: Azeroth Travel Tracker - WoW: Forever (beta)
```

Add a rejection test:

```powershell
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
```

- [ ] **Step 2: Run package tests and verify they fail**

Run:

```powershell
.\tests\Test-PackageAddon.ps1
```

Expected: valid fixtures fail because `Package-Addon.ps1` still requires the
old title, or the new rejection test does not reject the old title.

- [ ] **Step 3: Update manifest validation and the source TOC**

In `tools/Package-Addon.ps1`:

```powershell
$expectedMetadata = @{
    Title = 'Azeroth Travel Tracker - WoW: Forever (beta)'
    Version = $ExpectedVersion
    SavedVariables = 'AzerothTravelTrackerDB'
}
```

In `AzerothTravelTracker.toc`:

```text
## Title: Azeroth Travel Tracker - WoW: Forever (beta)
```

Keep the in-window title unchanged.

- [ ] **Step 4: Document package identity and ForeverSVFix deployment**

Add near the top of `README.md`:

```markdown
The WoW AddOns menu lists this build as
**Azeroth Travel Tracker - WoW: Forever (beta)** so it cannot be confused with
a release for another client.
```

Add under installation/development:

```markdown
After replacing the installed addon folder or TOC, keep WoW closed and reapply
ForeverSVFix, then run its `doctor` command. The packaged addon intentionally
does not contain ForeverSVFix markers, generated files, or account-specific
junctions.
```

- [ ] **Step 5: Run package and Lua tests**

Run:

```powershell
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
```

Expected: both suites report zero failures.

- [ ] **Step 6: Commit the package identity change**

```powershell
git add AzerothTravelTracker\AzerothTravelTracker.toc tools\Package-Addon.ps1 tests\Test-PackageAddon.ps1 README.md
git commit -m "chore: identify ATT as a Forever beta addon" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 6: Validate, Package, Install, and Reapply ForeverSVFix

**Files:**
- Modify after manual validation: `docs/BETA-SMOKE-TESTS.md`
- Build artifact: `artifacts/AzerothTravelTracker-0.1.0-beta.zip`
- Install target: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelTracker`

- [ ] **Step 1: Confirm only the existing smoke observation is dirty**

Run:

```powershell
git --no-pager status --short
```

Expected before packaging:

```text
 M docs/BETA-SMOKE-TESTS.md
```

The addon directory itself must be clean because packaging rejects dirty addon
files.

- [ ] **Step 2: Run final automated validation**

Run:

```powershell
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
```

Expected: zero failures. The PowerShell suite may retain its existing
privilege-dependent skip.

- [ ] **Step 3: Build the clean package from committed HEAD**

Run:

```powershell
.\tools\Package-Addon.ps1 -Version '0.1.0-beta'
```

Expected:

```text
Validated addon manifest for Interface 16001.
D:\_projects\wow-forever-step-tracker\artifacts\AzerothTravelTracker-0.1.0-beta.zip
```

- [ ] **Step 4: Record the package hash and inspect its file set**

Run:

```powershell
Get-FileHash `
  -LiteralPath '.\artifacts\AzerothTravelTracker-0.1.0-beta.zip' `
  -Algorithm SHA256
```

Open the archive through `System.IO.Compression.ZipFile` and verify:

- one top-level `AzerothTravelTracker` folder;
- no `ForeverSVFixData`;
- no generated ForeverSVFix files;
- the TOC contains no `X-ForeverSVFix` marker;
- the TOC title is the approved Forever-beta title.

- [ ] **Step 5: Verify WoW is closed and preserve the active data hash**

Run:

```powershell
$wow = 'D:\Games\World of Warcraft\_classic_beta_'
$saved = Join-Path $wow 'WTF\Account\50347838#1\SavedVariables\AzerothTravelTracker.lua'

if (Get-Process -Name 'WowB' -ErrorAction SilentlyContinue) {
    throw 'WoW must be closed before installing ATT.'
}

$savedHashBefore = (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
$savedHashBefore
```

Expected: no WoW process and a valid 64-character SHA-256 hash.

- [ ] **Step 6: Replace only the installed ATT folder from the clean package**

Resolve and inspect these exact paths before deletion:

```powershell
$installed = Join-Path $wow 'Interface\AddOns\AzerothTravelTracker'
$staging = Join-Path $env:TEMP 'AzerothTravelTracker-install'

Get-Item -LiteralPath $installed -Force
```

Remove only that exact addon folder and exact staging folder, extract the zip
to staging, then move the extracted `AzerothTravelTracker` folder into
`Interface\AddOns`. Do not remove or modify the account SavedVariables
directory.

- [ ] **Step 7: Reapply and verify ForeverSVFix**

Run:

```powershell
python D:\_projects\ForeverSVFix\forever_sv_fix.py `
  --wow 'D:\Games\World of Warcraft\_classic_beta_' `
  --account '50347838#1' `
  repair

python D:\_projects\ForeverSVFix\forever_sv_fix.py `
  --wow 'D:\Games\World of Warcraft\_classic_beta_' `
  --account '50347838#1' `
  doctor
```

Expected:

```text
Active installation checks: OK
No repair needed.
```

- [ ] **Step 8: Verify SavedVariables integrity and generated load order**

Run:

```powershell
$savedHashAfter = (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
if ($savedHashAfter -ne $savedHashBefore) {
    throw 'ATT SavedVariables changed during deployment.'
}

$toc = Join-Path $installed 'AzerothTravelTracker.toc'
$lines = Get-Content -LiteralPath $toc
$coreIndex = [Array]::IndexOf($lines, 'Core.lua')
$restoreIndex = [Array]::IndexOf(
    $lines,
    'ForeverSVFixData\AzerothTravelTracker.lua'
)
if ($restoreIndex -le $coreIndex) {
    throw 'ForeverSVFix restore file is not after ATT code.'
}
```

Also confirm `ForeverSVFixData` is a reparse point targeting:

```text
D:\Games\World of Warcraft\_classic_beta_\WTF\Account\50347838#1\SavedVariables
```

- [ ] **Step 9: Perform in-game visual acceptance**

Launch WoW and compare ATT beside APL at 100% UI scale first:

1. ATT background/title warmth is comparably translucent rather than solid.
2. ATT main window sits behind World Map and Character panel.
3. ATT remains above ordinary world/HUD content.
4. ATT settings or confirmation overlays sit above ATT.
5. Tooltips sit above ATT.
6. By Level scrollbar is fully inside the right edge and hidden when content
   does not overflow.
7. The minimap launcher ring kisses the minimap rim without covering content.
8. Main `_` and `X` controls align and work.
9. HUD restore arrow and `X` appear only on hover and remain inside the border.

Repeat geometry checks at 80% and 120% UI scale.

- [ ] **Step 10: Record observed evidence**

Update only the relevant rows in `docs/BETA-SMOKE-TESTS.md` with the observed
date, UI scales, APL comparison, layering, scrollbar, launcher, and controls.
Do not mark unrelated movement or persistence scenarios as passed.

- [ ] **Step 11: Commit the smoke evidence**

```powershell
git add docs\BETA-SMOKE-TESTS.md
git commit -m "docs: record ATT UI parity smoke results" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Completion Criteria

1. Lua tests pass with zero failures.
2. Package tests pass with zero failures, excluding only the existing
   privilege-dependent skip.
3. ATT uses APL-derived translucent layer values without a near-opaque full
   interior texture.
4. The regular window and HUD default to `MEDIUM`; ATT overlays use `DIALOG`.
5. The By Level scrollbar remains inside its gutter and appears only on
   overflow.
6. The minimap launcher's decorative ring touches the minimap rim at all tested
   shapes, dimensions, angles, and UI scales.
7. Main minimize and HUD restore controls use the approved glyphs and geometry.
8. WoW's AddOns menu shows
   `Azeroth Travel Tracker - WoW: Forever (beta)`.
9. The clean package excludes all ForeverSVFix artifacts.
10. ForeverSVFix is reapplied after installation, `doctor` reports healthy,
    and the active SavedVariables hash is unchanged.
11. Manual APL side-by-side results are recorded without marking unrelated
    smoke scenarios complete.
