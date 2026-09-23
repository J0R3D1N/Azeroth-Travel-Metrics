# Spellbook-Style ATM Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle ATM's main window with a native circular pocket-watch portrait, thin Blizzard title bar, top icon tabs, parchment pages, and spellbook dividers while preserving all existing behavior.

**Architecture:** Keep ATM's existing data models, panels, controls, and lifecycle. Replace only the main-window presentation layer with a guarded `PortraitFrameTemplateMinimizable` shell and small reusable theme helpers for parchment, top tabs, and section dividers. Every native template or atlas keeps a visible fallback.

**Tech Stack:** WoW Forever Lua 5.1, Blizzard XML templates and atlases, repository Lua test harness, PowerShell packaging tests, ForeverSVFix deployment workflow.

---

## File map

| File | Responsibility |
|---|---|
| `AzerothTravelMetrics/UITheme.lua` | Native icon contract, portrait-shell setup, top icon tabs, parchment backgrounds, section/divider styling, fallbacks. |
| `AzerothTravelMetrics/UI.lua` | Main-frame creation, top-tab placement, content-page placement, title/control wiring, unchanged panel behavior. |
| `AzerothTravelMetrics/AzerothTravelMetrics.toc` | Pocket-watch addon-listing icon. |
| `tests/test_ui_theme.lua` | Theme helper behavior and fallback coverage. |
| `tests/test_core.lua` | Integrated main-window layout, behavior, and TOC identity. |
| `tests/test_minimap.lua` | Pocket-watch minimap icon regression coverage. |
| `README.md` | Native icon and spellbook-style UI documentation. |
| `docs/BETA-SMOKE-TESTS.md` | In-game visual and interaction checks. |

### Task 1: Adopt the pocket-watch identity

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_core.lua`
- Modify: `tests/test_minimap.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`
- Modify: `AzerothTravelMetrics/AzerothTravelMetrics.toc`

- [ ] **Step 1: Write failing icon expectations**

Change every main-icon expectation to:

```lua
"Interface\\Icons\\inv_misc_pocketwatch_01"
```

Cover `UITheme.Icons.TITLE`, the main portrait, minimized HUD Steps cell,
minimap icon, and TOC `IconTexture`.

- [ ] **Step 2: Run the Lua suite and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: failures showing `ability_mount_jungletiger` where the pocket-watch
path is expected.

- [ ] **Step 3: Implement the icon change**

In `UITheme.lua`:

```lua
TITLE = "Interface\\Icons\\inv_misc_pocketwatch_01",
```

In `AzerothTravelMetrics.toc`:

```text
## IconTexture: Interface\Icons\inv_misc_pocketwatch_01
```

Keep `UI.lua` and `Minimap.lua` consuming `ATM.UITheme.Icons.TITLE`; do not
introduce duplicate paths.

- [ ] **Step 4: Run the Lua suite and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add AzerothTravelMetrics\UITheme.lua `
  AzerothTravelMetrics\AzerothTravelMetrics.toc `
  tests\test_ui_theme.lua tests\test_core.lua tests\test_minimap.lua
git commit -m "refactor: use pocket watch identity"
```

### Task 2: Add guarded portrait-shell creation

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Add failing theme tests**

Add tests for this API:

```lua
local shell = addon.UITheme.CreateWindowShell(
    "AzerothTravelMetricsFrame",
    UIParent,
    addon.UITheme.Icons.TITLE
)
```

Require:

```lua
testlib.equal(shell.nativePortrait, true)
testlib.equal(shell.frame.template, "PortraitFrameTemplateMinimizable")
testlib.equal(shell.frame.PortraitContainer.portrait.texture,
    addon.UITheme.Icons.TITLE)
testlib.equal(shell.frame.TitleContainer.TitleText:GetText(),
    "Azeroth Travel Metrics")
testlib.equal(shell.closeButton, shell.frame.CloseButton)
testlib.equal(shell.minimizeButton, shell.frame.MinimizeButton)
```

Add a rejected-template case requiring `nativePortrait == false`, a visible
fallback portrait, close button, and minimize button.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: failure because `CreateWindowShell` does not exist.

- [ ] **Step 3: Implement the shell helper**

Add to `UITheme.lua`:

```lua
function Theme.CreateWindowShell(name, parent, portraitTexture)
    local created, frame = pcall(
        CreateFrame,
        "Frame",
        name,
        parent,
        "PortraitFrameTemplateMinimizable"
    )

    if created and frame
        and frame.PortraitContainer
        and frame.PortraitContainer.portrait
        and frame.TitleContainer
        and frame.TitleContainer.TitleText
        and frame.CloseButton
    then
        frame.PortraitContainer.portrait:SetTexture(portraitTexture)
        frame.PortraitContainer.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        frame.TitleContainer.TitleText:SetText("Azeroth Travel Metrics")
        return {
            frame = frame,
            nativePortrait = true,
            portrait = frame.PortraitContainer.portrait,
            title = frame.TitleContainer.TitleText,
            closeButton = frame.CloseButton,
            minimizeButton = frame.MinimizeButton,
        }
    end

    if created and frame and type(frame.Hide) == "function" then
        frame:Hide()
    end

    local fallback = CreateFrame("Frame", name, parent, "BackdropTemplate")
    local portraitFrame, portrait = Theme.CreateCircularPortrait(
        fallback,
        portraitTexture,
        54
    )
    return {
        frame = fallback,
        nativePortrait = false,
        portraitFrame = portraitFrame,
        portrait = portrait,
        title = nil,
        closeButton = Theme.CreateFallbackCloseButton(fallback),
        minimizeButton = Theme.CreateFallbackMinimizeButton(fallback),
    }
end
```

Extract the existing safe close/minimize and framed-icon logic instead of
duplicating it. The fallback circular portrait must use a circular mask atlas
when available and the existing cropped square icon when it is not.

- [ ] **Step 4: Wire `UI.Create` to the shell result**

Replace `createMainFrame()` plus the custom 44-pixel title region with:

```lua
UI.windowShell = ATM.UITheme.CreateWindowShell(
    "AzerothTravelMetricsFrame",
    UIParent,
    ATM.UITheme.Icons.TITLE
)
local frame = UI.windowShell.frame
UI.frame = frame
UI.title = UI.windowShell.title
UI.titleIcon = UI.windowShell.portrait
UI.closeButton = UI.windowShell.closeButton
UI.minimizeButton = UI.windowShell.minimizeButton
```

Retain frame size, position, strata, movement, Escape registration, click
handlers, and fallback controls.

- [ ] **Step 5: Run tests and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add AzerothTravelMetrics\UITheme.lua AzerothTravelMetrics\UI.lua `
  tests\test_ui_theme.lua tests\test_core.lua
git commit -m "feat: add native portrait window shell"
```

### Task 3: Replace side tabs with top interior icon tabs

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing top-tab tests**

Define the wished-for helper:

```lua
local tab = addon.UITheme.CreateTopTab(
    "TestTab",
    parent,
    {
        icon = addon.UITheme.Icons.OVERVIEW,
        tooltip = "Overview",
    }
)
```

Require a `40 x 40` button, cropped icon, highlight region, selected border,
tooltip scripts, and `Theme.SetTopTabSelected(tab, true/false)`.

In integrated UI tests require:

```lua
testlib.equal(UI.overviewTab.point[1], "TOPLEFT")
testlib.equal(UI.overviewTab.point[2], UI.contentPage)
testlib.equal(UI.levelTab.point[1], "LEFT")
testlib.equal(UI.levelTab.point[2], UI.overviewTab)
testlib.equal(UI.overviewTab.Icon.texture, UITheme.Icons.OVERVIEW)
testlib.equal(UI.levelTab.Icon.texture, UITheme.Icons.LEVELS)
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: missing `CreateTopTab` and old right-side anchors.

- [ ] **Step 3: Implement top tabs**

Add:

```lua
function Theme.CreateTopTab(name, parent, options)
    local tab = CreateFrame("Button", name, parent)
    tab:SetSize(40, 40)
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Icon:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, -4)
    tab.Icon:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 4)
    tab.Icon:SetTexture(options.icon)
    tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tab.HighlightTexture = createColorTexture(
        tab, "HIGHLIGHT", 1, 0.82, 0.25, 0.22
    )
    tab.SelectedTexture = createSelectedBorder(tab, 40)
    setTooltip(tab, options.tooltip or "")
    return tab
end

function Theme.SetTopTabSelected(tab, selected)
    tab.selected = selected == true
    tab.SelectedTexture:SetShown(tab.selected)
end
```

Generalize `createSelectedBorder` to accept the requested size.

- [ ] **Step 4: Re-anchor tabs inside the frame**

Place Overview at the parchment page's upper-left edge and By Level
immediately to its right. Update `setPanelVisibility()` to call
`SetTopTabSelected`.

- [ ] **Step 5: Run tests and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add AzerothTravelMetrics\UITheme.lua AzerothTravelMetrics\UI.lua `
  tests\test_ui_theme.lua tests\test_core.lua
git commit -m "feat: move navigation tabs into window"
```

### Task 4: Add parchment page and spellbook section styling

**Files:**
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_core.lua`
- Modify: `AzerothTravelMetrics/UITheme.lua`
- Modify: `AzerothTravelMetrics/UI.lua`

- [ ] **Step 1: Write failing parchment tests**

Extend `Theme.Atlases` expectations:

```lua
PARCHMENT = "spellbook-page-condensed-c60",
DIVIDER = "spellbook-divider",
```

Test:

```lua
local page = addon.UITheme.CreateParchmentPage(parent)
testlib.equal(page.atlas, "spellbook-page-condensed-c60")
testlib.equal(page.useAtlasSize, false)
```

Add an atlas-rejection case requiring:

```lua
testlib.equal(page.color[1], 0.72)
testlib.equal(page.color[2], 0.52)
testlib.equal(page.color[3], 0.28)
```

Update section tests to require a divider atlas beneath each heading and dark
text suitable for parchment.

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
lua .\tests\run.lua
```

Expected: missing parchment/divider APIs and old dark-row colors.

- [ ] **Step 3: Implement parchment helpers**

Add:

```lua
function Theme.CreateParchmentPage(parent)
    local page = parent:CreateTexture(nil, "BACKGROUND")
    page:SetAllPoints(parent)
    Theme.SetAtlasOrColor(
        page,
        Theme.Atlases.PARCHMENT,
        0.72, 0.52, 0.28, 1,
        false
    )
    return page
end
```

Extend `SetAtlasOrColor` with an optional `useAtlasSize` argument that defaults
to `true`; parchment passes `false`.

In `CreateSection`:

```lua
titleText:SetTextColor(0.20, 0.10, 0.04, 1)

local divider = frame:CreateTexture(nil, "ARTWORK")
divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 2)
divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 2)
divider:SetHeight(7)
Theme.SetAtlasOrColor(
    divider,
    Theme.Atlases.DIVIDER,
    0.36, 0.18, 0.07, 0.85,
    false
)
section.divider = divider
```

Use transparent or low-alpha warm row backgrounds and dark label/value text.
Keep the Total Distance separator and emphasis.

- [ ] **Step 4: Create and anchor the shared content page**

In `UI.Create`:

```lua
UI.contentPage = CreateFrame("Frame", nil, frame)
UI.contentPage:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -62)
UI.contentPage:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 42)
UI.parchment = ATM.UITheme.CreateParchmentPage(UI.contentPage)
```

Parent Overview and By Level panels to `UI.contentPage`, not directly to the
outer frame. Preserve their dimensions, scroll calculations, and error panel.

- [ ] **Step 5: Run tests and verify GREEN**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add AzerothTravelMetrics\UITheme.lua AzerothTravelMetrics\UI.lua `
  tests\test_ui_theme.lua tests\test_core.lua
git commit -m "feat: add spellbook parchment pages"
```

### Task 5: Update active documentation and smoke coverage

**Files:**
- Modify: `README.md`
- Modify: `docs/BETA-SMOKE-TESTS.md`

- [ ] **Step 1: Update README**

Document the pocket-watch identity and the native resources:

```text
PortraitFrameTemplateMinimizable
spellbook-page-condensed-c60
spellbook-divider
```

State that no custom image assets are packaged.

- [ ] **Step 2: Update beta smoke tests**

Add or revise rows covering:

- circular portrait and thin title bar;
- pocket-watch icon in title, minimap, addon listing, and HUD;
- top Overview/By Level icon tabs;
- parchment coverage without seams;
- divider alignment and dark-text contrast;
- 80%, 100%, and 120% UI scale;
- settings/reset/minimize/close interaction;
- Overview and By Level scrolling and selection.

- [ ] **Step 3: Check documentation diff**

Run:

```powershell
git diff --check
```

Expected: no output.

- [ ] **Step 4: Commit**

```powershell
git add README.md docs\BETA-SMOKE-TESTS.md
git commit -m "docs: add spellbook window smoke checks"
```

### Task 6: Complete automated validation and review

**Files:**
- Review all changed files.

- [ ] **Step 1: Run Lua tests**

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 2: Run packaging tests**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Test-PackageAddon.ps1
```

Expected: 40 passed, 0 failed, administrator-only symlink case may skip.

- [ ] **Step 3: Run release identity tests**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Test-ReleaseIdentity.ps1
```

Expected: seven content tests and standalone identity check pass.

- [ ] **Step 4: Validate the TOC**

Run the WoW MCP TOC validator against inline
`AzerothTravelMetrics/AzerothTravelMetrics.toc` contents for Forever.

Expected: no issues.

- [ ] **Step 5: Request focused code review**

Review the branch diff from `1567f0f` through `HEAD` for:

- template-child assumptions;
- fallback visibility;
- frame levels and mouse interaction;
- tab selection behavior;
- parchment scaling;
- regressions in scrolling, settings, reset, minimize, and Escape handling.

- [ ] **Step 6: Fix Critical or Important review findings**

Add a failing regression test before each fix, then rerun the focused and full
test suites.

### Task 7: Build and deploy the in-game test candidate

**Files:**
- Generated: `artifacts/AzerothTravelMetrics-1.0.0-beta.zip`
- Installed test copy: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics`

- [ ] **Step 1: Build the committed package**

The packaging script requires a clean committed addon tree:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Package-Addon.ps1
```

Expected: package path printed with exit code zero.

- [ ] **Step 2: Verify WoW is closed**

```powershell
Get-Process WowB -ErrorAction SilentlyContinue
```

Expected: no process.

- [ ] **Step 3: Back up and deploy the packaged folder**

Move the current installed addon to a timestamped directory under:

```text
artifacts\installed-backups\
```

Copy `artifacts\AzerothTravelMetrics` into the Forever AddOns directory.

- [ ] **Step 4: Reapply ForeverSVFix and run doctor**

```powershell
Set-Location D:\_projects\ForeverSVFix
python .\forever_sv_fix.py `
  --wow "D:\Games\World of Warcraft\_classic_beta_" install
python .\forever_sv_fix.py `
  --wow "D:\Games\World of Warcraft\_classic_beta_" doctor
```

Expected:

```text
Active installation checks: OK
No repair needed.
```

- [ ] **Step 5: Perform the in-game smoke test**

Use `docs/BETA-SMOKE-TESTS.md` and record factual results for the redesigned
window. Do not merge the branch until the circular portrait, title bar, tabs,
parchment, dividers, controls, scaling, and SavedVariables persistence pass.

- [ ] **Step 6: Keep the feature branch isolated**

Leave `feature/spellbook-window` and its worktree intact for corrections found
during gameplay. Merge only after explicit user approval.
