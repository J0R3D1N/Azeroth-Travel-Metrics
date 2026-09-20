# Character Panel UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Azeroth Travel Tracker's flat black window with a compact, movable World of Warcraft: Forever character-panel shell using native portrait, stat-row, side-tab, and minimap assets.

**Architecture:** Add a focused `UITheme` module that owns native asset names, protected atlas/texture application, icon-tab construction, section construction, and visible fallbacks. Keep `UI.lua` responsible for interaction and model binding while changing its layout from top tabs and text blobs to right-side icon tabs and reusable stat sections. Preserve all tracking, storage, settings, reset, strata, and minimap-position behavior.

**Tech Stack:** World of Warcraft Interface 16001 Lua, Blizzard frame templates and atlases, dependency-free Lua test harness, PowerShell packaging tests.

**Design:** `docs/superpowers/specs/2026-09-20-character-panel-ui-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `AzerothTravelTracker\UITheme.lua` | Native icon/atlas constants, safe asset fallbacks, character-stat sections and rows, and side-tab construction/selection. |
| `AzerothTravelTracker\UI.lua` | Main portrait-frame shell, right-side navigation, stacked Overview and By Level views, settings footer, reset action, and model binding. |
| `AzerothTravelTracker\Minimap.lua` | Minimap launcher's built-in sprint icon. |
| `AzerothTravelTracker\AzerothTravelTracker.toc` | Loads `UITheme.lua` before `UI.lua`. |
| `tests\test_ui_theme.lua` | Isolated tests for native assets, side-tab fallbacks, section construction, and selected state. |
| `tests\test_core.lua` | End-to-end frame layout, native/fallback shell, overview rows, level rows, settings, movability, and strata tests. |
| `tests\test_minimap.lua` | Exact minimap icon regression. |
| `tests\run.lua` | Registers the new theme tests. |
| `docs\BETA-SMOKE-TESTS.md` | Adds concrete in-client checks for the redesigned shell and login warning. |

### Task 1: Add the Character-Panel Theme Boundary

**Files:**
- Create: `AzerothTravelTracker\UITheme.lua`
- Create: `tests\test_ui_theme.lua`
- Modify: `tests\run.lua`
- Modify: `AzerothTravelTracker\AzerothTravelTracker.toc`

- [ ] **Step 1: Register the new test module**

Add `"test_ui_theme"` immediately before `"test_core"` in `tests\run.lua`.

- [ ] **Step 2: Write failing tests for the asset contract**

Create `tests\test_ui_theme.lua` and load:

```lua
local testlib = require("testlib")

local FILES = {
    "AzerothTravelTracker\\Namespace.lua",
    "AzerothTravelTracker\\UITheme.lua",
}

testlib.case("ui theme exposes approved native icons and atlases", function()
    local addon = testlib.loadAddon(FILES)
    testlib.equal(addon.UITheme.Icons.PORTRAIT, "Interface\\Icons\\INV_Misc_Map_01")
    testlib.equal(addon.UITheme.Icons.OVERVIEW, "Interface\\Icons\\INV_Misc_Map_01")
    testlib.equal(addon.UITheme.Icons.LEVELS, "Interface\\Icons\\INV_Misc_Book_09")
    testlib.equal(addon.UITheme.Icons.SETTINGS, "Interface\\Icons\\INV_Misc_Gear_01")
    testlib.equal(addon.UITheme.Atlases.SECTION, "UI-Character-Info-Title")
    testlib.equal(addon.UITheme.Atlases.ROW, "UI-Character-Info-Line-Bounce")
end)
```

Add tests with a fake frame factory proving:

```lua
local tab = addon.UITheme.CreateSideTab("TestTab", parent, {
    icon = addon.UITheme.Icons.OVERVIEW,
    tooltip = "Overview",
})
testlib.equal(calls.templates[1], "LargeSideTabButtonTemplate")
testlib.equal(tab.Icon.texture, addon.UITheme.Icons.OVERVIEW)
tab.scripts.OnEnter(tab)
testlib.equal(calls.tooltipText, "Overview")
addon.UITheme.SetSideTabSelected(tab, true)
testlib.equal(tab.SelectedTexture.shown, true)
```

Repeat with `LargeSideTabButtonTemplate` rejected and assert the bare button still has:

```lua
testlib.truthy(tab.Icon)
testlib.truthy(tab.Background)
testlib.truthy(tab.SelectedTexture)
testlib.equal(tab.width, 50)
testlib.equal(tab.height, 50)
```

Add section tests proving `CreateSection(parent, "Lifetime", 4)` produces one `UI-Character-Info-Title` heading, four `UI-Character-Info-Line-Bounce` rows, yellow labels, white values, and fallback color textures when `SetAtlas` throws.

- [ ] **Step 3: Run the theme tests and verify failure**

Run:

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
lua tests\run.lua
```

Expected: failure loading `AzerothTravelTracker\UITheme.lua`.

- [ ] **Step 4: Implement `UITheme.lua`**

Define the stable public contract:

```lua
local _, ATT = ...
local Theme = {
    Icons = {
        PORTRAIT = "Interface\\Icons\\INV_Misc_Map_01",
        OVERVIEW = "Interface\\Icons\\INV_Misc_Map_01",
        LEVELS = "Interface\\Icons\\INV_Misc_Book_09",
        SETTINGS = "Interface\\Icons\\INV_Misc_Gear_01",
    },
    Atlases = {
        SECTION = "UI-Character-Info-Title",
        ROW = "UI-Character-Info-Line-Bounce",
        ROW_ALTERNATE = "UI-Character-Info-Line-Bounce2",
        INSET = "common-insideframe",
    },
}
ATT.UITheme = Theme
```

Implement:

```lua
Theme.SetAtlasOrColor(texture, atlas, red, green, blue, alpha)
Theme.CreateInset(parent)
Theme.CreateSideTab(name, parent, options)
Theme.SetSideTabSelected(tab, selected)
Theme.CreateSection(parent, title, rowCount)
Theme.SetSectionValues(section, values)
Theme.CreateIconButton(parent, icon, tooltip)
```

`SetAtlasOrColor` must `pcall(texture.SetAtlas, texture, atlas, true)` and call `SetColorTexture` with the supplied fallback when the atlas call is missing or rejected.

`CreateSideTab` must first `pcall(CreateFrame, "Button", name, parent, "LargeSideTabButtonTemplate")`. Its fallback creates a 50-by-50 bare button with brown background, icon, gold selected border, highlight texture, and tooltip scripts. Do not reference `PanelTemplates_*` or deprecated character tab templates.

`CreateSection` must return:

```lua
{
    frame = frame,
    header = headerTexture,
    title = titleFontString,
    rows = {
        { frame = rowFrame, background = rowTexture, label = label, value = value },
    },
}
```

Use yellow `(1, 0.82, 0)` labels, white `(1, 1, 1)` values, 22-pixel rows, and a 30-pixel section header.

- [ ] **Step 5: Load the module before `UI.lua`**

Insert:

```text
UITheme.lua
UI.lua
```

in `AzerothTravelTracker\AzerothTravelTracker.toc`.

- [ ] **Step 6: Run tests**

Run:

```powershell
lua tests\run.lua
```

Expected: all theme tests pass and all existing tests remain green.

- [ ] **Step 7: Commit**

```powershell
git add AzerothTravelTracker\UITheme.lua AzerothTravelTracker\AzerothTravelTracker.toc tests\test_ui_theme.lua tests\run.lua
git commit -m "feat: add character panel UI theme" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

### Task 2: Rebuild the Window Shell and Navigation

**Files:**
- Modify: `AzerothTravelTracker\UI.lua`
- Modify: `tests\test_core.lua`

- [ ] **Step 1: Update the UI test harness for textures and portrait helpers**

Extend the fake region/frame objects in `tests\test_core.lua` with:

```lua
function region:SetAtlas(atlas, useAtlasSize)
    if options.rejectAtlases and options.rejectAtlases[atlas] then
        error("atlas unavailable")
    end
    self.atlas = atlas
    self.useAtlasSize = useAtlasSize
end

function region:SetColorTexture(red, green, blue, alpha)
    self.color = { red, green, blue, alpha }
end

function region:SetTextColor(red, green, blue, alpha)
    self.textColor = { red, green, blue, alpha }
end
```

Provide `SetPortraitToTexture(frame, texture)` in the fake globals and record the texture.

- [ ] **Step 2: Replace old-layout assertions with failing shell assertions**

Update the lazy-creation test to require:

```lua
testlib.equal(first.template, "PortraitFrameBaseTemplate")
testlib.equal(first.strata, "FULLSCREEN_DIALOG")
testlib.equal(first.movable, true)
testlib.equal(first.portraitTexture, harness.addon.UITheme.Icons.PORTRAIT)
testlib.equal(harness.addon.UI.overviewTab.template, "LargeSideTabButtonTemplate")
testlib.equal(harness.addon.UI.overviewTab.point[1], "TOPLEFT")
testlib.equal(harness.addon.UI.overviewTab.point[3], "TOPRIGHT")
testlib.equal(harness.addon.UI.levelTab.point[1], "TOP")
testlib.equal(harness.addon.UI.levelTab.point[2], harness.addon.UI.overviewTab)
testlib.equal(#harness.addon.UI.summarySections, 3)
testlib.equal(harness.addon.UI.settingsPanel:IsShown(), false)
```

Assert the requested templates do not include `CharacterFrameTabButtonTemplate` or `PanelTabButtonTemplate`.

Add a fallback test rejecting `PortraitFrameBaseTemplate`, `LargeSideTabButtonTemplate`, and all character atlases. Assert the frame, two visible icon tabs, inset, settings icon, reset action, and stat labels are still created without throwing.

- [ ] **Step 3: Run the focused tests and verify failure**

Run:

```powershell
lua tests\run.lua
```

Expected: UI tests fail because the current frame uses `BasicFrameTemplateWithInset`, top text tabs, and `summaryGroups`.

- [ ] **Step 4: Replace the main shell**

Change `createMainFrame()` to try:

```lua
local templates = {
    "PortraitFrameBaseTemplate",
    "BasicFrameTemplateWithInset",
}
```

then fall back to a bare frame. Set the frame to approximately `470 x 480`, preserve drag scripts and strata order, and set the portrait through:

```lua
if type(SetPortraitToTexture) == "function" then
    pcall(SetPortraitToTexture, frame, ATT.UITheme.Icons.PORTRAIT)
elseif frame.PortraitContainer and frame.PortraitContainer.portrait then
    frame.PortraitContainer.portrait:SetTexture(ATT.UITheme.Icons.PORTRAIT)
end
```

Use native title text when exposed by the template; otherwise create the existing `GameFontNormalLarge` fallback.

- [ ] **Step 5: Replace top tabs with right-side icon tabs**

Delete `createTab`, `setFallbackTabColor`, all `PanelTemplates_*` integration, and text-tab sizing.

Create:

```lua
UI.overviewTab = ATT.UITheme.CreateSideTab(
    "AzerothTravelTrackerFrameOverviewTab",
    frame,
    { icon = ATT.UITheme.Icons.OVERVIEW, tooltip = "Overview" }
)
UI.overviewTab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -4, -34)

UI.levelTab = ATT.UITheme.CreateSideTab(
    "AzerothTravelTrackerFrameLevelTab",
    frame,
    { icon = ATT.UITheme.Icons.LEVELS, tooltip = "By Level" }
)
UI.levelTab:SetPoint("TOP", UI.overviewTab, "BOTTOM", 0, -2)
```

Change `setPanelVisibility()` to call `ATT.UITheme.SetSideTabSelected`.

- [ ] **Step 6: Move utility controls into the footer**

Create a 28-by-28 gear button with `ATT.UITheme.CreateIconButton`, anchor it at the bottom-right inside the frame, and preserve the settings-panel toggle behavior.

Keep Reset Session as a small `UIPanelButtonTemplate` anchored bottom-left. Do not color it red.

Anchor the settings inset above the footer, keep it hidden by default, and preserve all existing setting mutations.

- [ ] **Step 7: Run tests**

Run:

```powershell
lua tests\run.lua
```

Expected: native and fallback shell/navigation tests pass; tracking and settings tests remain green.

- [ ] **Step 8: Commit**

```powershell
git add AzerothTravelTracker\UI.lua tests\test_core.lua
git commit -m "feat: use character panel shell and side tabs" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

### Task 3: Restyle Overview and By Level Statistics

**Files:**
- Modify: `AzerothTravelTracker\UI.lua`
- Modify: `tests\test_core.lua`

- [ ] **Step 1: Write failing overview-section tests**

Assert each of the three sections has exactly four rows and these labels:

```lua
local expected = {
    "Estimated Steps",
    "On Foot",
    "Swimming",
    "Flight Path",
}
for _, section in ipairs(harness.addon.UI.summarySections) do
    testlib.equal(#section.rows, 4)
    for index, label in ipairs(expected) do
        testlib.equal(section.rows[index].label:GetText(), label)
    end
end
```

After `UI.Refresh()`, assert the Lifetime values are separately bound:

```lua
testlib.equal(UI.summarySections[1].rows[1].value:GetText(), "100")
testlib.equal(UI.summarySections[1].rows[2].value:GetText(), "100 m")
testlib.equal(UI.summarySections[1].rows[3].value:GetText(), "20 m")
testlib.equal(UI.summarySections[1].rows[4].value:GetText(), "70 m")
```

- [ ] **Step 2: Write failing By Level tests**

For two model rows, assert:

```lua
testlib.equal(#UI.levelRows, 2)
testlib.equal(UI.levelRows[1].title:GetText(), "Level 42")
testlib.equal(UI.levelRows[1].rows[1].value:GetText(), "420")
testlib.equal(UI.levelRows[1].rows[4].value:GetText(), "42 m")
testlib.equal(UI.levelRows[2].title:GetText(), "Level 41")
```

Retain the existing 15-level scroll test and assert the child height exceeds the viewport.

- [ ] **Step 3: Run tests and verify failure**

Run:

```powershell
lua tests\run.lua
```

Expected: failure because Overview uses multiline text blobs and By Level uses one pipe-delimited label per level.

- [ ] **Step 4: Build stacked Overview sections**

Replace `summaryText` and `summaryGroups` with:

```lua
local SUMMARY_ROWS = {
    { key = "steps", label = "Estimated Steps" },
    { key = "onFoot", label = "On Foot" },
    { key = "swimming", label = "Swimming" },
    { key = "taxi", label = "Flight Path" },
}
```

Create `UI.summarySections` through `ATT.UITheme.CreateSection`. Stack Lifetime, This Session, and Current Level with 8-pixel gaps. Keep diagnostics below the third section and only show text when diagnostics are enabled.

In `UI.Refresh()`, bind each model field to its individual right-aligned value:

```lua
for sectionIndex, definition in ipairs(summaryDefinitions) do
    local summary = overview[definition.key]
    local values = {}
    for rowIndex, rowDefinition in ipairs(SUMMARY_ROWS) do
        values[rowIndex] = tostring(summary[rowDefinition.key])
    end
    ATT.UITheme.SetSectionValues(UI.summarySections[sectionIndex], values)
end
```

- [ ] **Step 5: Build character-style level cards**

Change `ensureLevelRows` so each model row owns a compact four-row section titled `Level <n>`. Reuse existing frames when refreshing. Set each card height to 118 pixels and update `UI.levelScrollChild` height from the card count.

Bind steps, on-foot, swimming, and taxi values separately. Keep highest-level-first ordering supplied by `UIModel`.

- [ ] **Step 6: Run tests**

Run:

```powershell
lua tests\run.lua
```

Expected: all overview, level-scroll, error, settings, reset, and lifecycle tests pass.

- [ ] **Step 7: Commit**

```powershell
git add AzerothTravelTracker\UI.lua tests\test_core.lua
git commit -m "feat: restyle travel statistics panels" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

### Task 4: Update the Minimap Icon and Beta Validation

**Files:**
- Modify: `AzerothTravelTracker\Minimap.lua`
- Modify: `tests\test_minimap.lua`
- Modify: `docs\BETA-SMOKE-TESTS.md`

- [ ] **Step 1: Tighten the minimap icon regression**

Replace the broad icon-path assertion with:

```lua
testlib.equal(
    first.textures[2].texture,
    "Interface\\Icons\\Ability_Rogue_Sprint"
)
```

- [ ] **Step 2: Run the minimap tests and verify failure**

Run:

```powershell
lua tests\run.lua
```

Expected: failure showing `Ability_Mount_RidingHorse`.

- [ ] **Step 3: Change the minimap icon**

In `Minimap.lua`, set:

```lua
icon:SetTexture("Interface\\Icons\\Ability_Rogue_Sprint")
```

- [ ] **Step 4: Update manual beta checks**

Add or update rows in `docs\BETA-SMOKE-TESTS.md` for:

- login or `/reload` does not print `Tracking unavailable: unsupported state`;
- portrait frame, bronze trim, and brown inset visually match the character panel;
- Overview and By Level are right-side icon tabs with correct tooltips and selected state;
- all three Overview sections and all four rows are readable at 80%, 100%, and 120% UI scale;
- By Level scrolling exposes every level;
- settings starts collapsed and the footer controls do not overlap content;
- sprint minimap icon renders and retains click/drag behavior;
- no Lua errors occur when opening, moving, tabbing, changing settings, or resetting.

Leave `Observed` and `Result` as `PENDING` until verified in the client.

- [ ] **Step 5: Run complete automated validation**

Run:

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
.\tools\Package-Addon.ps1 -Version '0.1.0-beta'
```

Expected:

- all Lua tests pass;
- all available packaging fixtures pass;
- the symlink fixture may skip only when Windows lacks symlink privilege;
- `artifacts\AzerothTravelTracker-0.1.0-beta.zip` is recreated.

- [ ] **Step 6: Install changed files into the Forever beta**

Copy the packaged addon snapshot into:

```text
D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelTracker
```

Verify the installed folder contains `UITheme.lua` and that its `.toc` lists `UITheme.lua` before `UI.lua`.

- [ ] **Step 7: Commit**

```powershell
git add AzerothTravelTracker\Minimap.lua tests\test_minimap.lua docs\BETA-SMOKE-TESTS.md
git commit -m "feat: finish character panel visual refresh" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Completion Criteria

1. The frame uses native portrait chrome when available and remains fully visible with fallbacks.
2. Overview and By Level are right-side `LargeSideTabButtonTemplate` icon tabs.
3. Overview contains three stacked sections with four independently aligned stat rows each.
4. By Level uses scrollable level sections and exposes every model row.
5. Settings remains collapsed and Reset Session remains confirmed.
6. The minimap icon is `Ability_Rogue_Sprint`.
7. Movability and strata fallback behavior are unchanged.
8. Login does not report unsupported state solely because false WoW predicates returned nil.
9. All Lua and packaging tests pass.
10. The packaged snapshot is installed in the Forever beta AddOns folder and is ready for `/reload`.
