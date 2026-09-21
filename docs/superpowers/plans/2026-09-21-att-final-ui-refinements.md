# ATT Final UI Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the remaining screenshot-verified title, control, footer, spacing, and small-logo issues without regressing the validated layering, scrollbar, minimap placement, or SavedVariables behavior.

**Architecture:** Reuse Blizzard's native `MaximizeMinimizeButtonFrameTemplate` for the exact World Map Condense/Expand iconography, retaining ATT's custom control only as a compatibility fallback. Update existing layout constants and anchors rather than restructuring the window. Regenerate the ATT runtime badge from a tight crop of the custom boot in the new pixel-art source, with an explicit circular alpha mask suitable for 20-32 pixel rendering.

**Tech Stack:** World of Warcraft Lua UI APIs, Blizzard SharedXML templates and atlases, Lua test harness, Python 3 with Pillow, PowerShell package tests, Git.

**Approved design:** `docs/superpowers/specs/2026-09-21-att-ui-parity-polish-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `artwork/source/azeroth_travel_metrics.jpg` | New source for the small ATT title/minimap badge. |
| `tools/Build-IconAssets.py` | Converts the badge with a circular alpha mask and retains the tab-icon conversion. |
| `AzerothTravelTracker/Media/ATTLogo.tga` | Regenerated small-display ATT badge. |
| `AzerothTravelTracker/UITheme.lua` | Native maximize/minimize control factory and full-width title tint. |
| `AzerothTravelTracker/UI.lua` | Native control composition, footer Settings placement, and 10-pixel section spacing. |
| `tests/test_icon_assets.py` | Validates the real ATT badge alpha and deterministic generation. |
| `tests/test_ui_theme.lua` | Validates native Condense/Expand controls and fallback behavior. |
| `tests/test_core.lua` | Validates title edges, footer anchoring, native control composition, and 10-pixel gaps. |
| `tests/Test-PackageAddon.ps1` | Confirms the replacement source JPG remains outside the package. |
| `README.md` | Updates the source asset name. |

## Task 1: Replace the Small ATT Badge Source

**Files:**
- Create: `artwork/source/azeroth_travel_metrics.jpg`
- Delete: `artwork/source/att_logo_400x400.jpg`
- Modify: `tools/Build-IconAssets.py`
- Modify: `AzerothTravelTracker/Media/ATTLogo.tga`
- Modify: `tests/test_icon_assets.py`
- Modify: `README.md`

- [ ] **Step 1: Preserve the new source artwork**

Run:

```powershell
Copy-Item -LiteralPath `
  'D:\_projects\wow-forever-step-tracker\artifacts\AzerothTravelTracker\azeroth_travel_metrics.jpg' `
  -Destination 'D:\_projects\wow-forever-step-tracker\artwork\source\azeroth_travel_metrics.jpg'
```

Remove only the tracked superseded source:

```powershell
Remove-Item -LiteralPath `
  'D:\_projects\wow-forever-step-tracker\artwork\source\att_logo_400x400.jpg'
```

Do not delete either file from `artifacts\AzerothTravelTracker`.

- [ ] **Step 2: Write failing badge-generation tests**

In `tests/test_icon_assets.py`, require the builder's source mapping to use
`azeroth_travel_metrics.jpg` with the normalized boot crop
`(500 / 2048, 1340 / 2048, 960 / 2048, 1800 / 2048)`, then validate the
generated `ATTLogo.tga`:

```python
def test_att_logo_uses_circular_alpha_mask(self):
    image = Image.open(self.media / "ATTLogo.tga").convert("RGBA")
    self.assertEqual(image.size, (64, 64))
    self.assertEqual(image.getpixel((0, 0))[3], 0)
    self.assertEqual(image.getpixel((63, 0))[3], 0)
    self.assertEqual(image.getpixel((0, 63))[3], 0)
    self.assertEqual(image.getpixel((63, 63))[3], 0)
    self.assertEqual(image.getpixel((32, 32))[3], 255)

    transparent = sum(
        1 for pixel in image.getdata() if pixel[3] == 0
    )
    self.assertGreater(transparent, 400)
```

Keep the deterministic rebuild and no-white-fringe assertions.

- [ ] **Step 3: Run the asset test and verify it fails**

Run:

```powershell
python -m unittest tests.test_icon_assets
```

Expected: failure because the builder still maps `ATTLogo.tga` from
the full badge rather than the approved boot crop.

- [ ] **Step 4: Add an explicit circular badge mask**

In `tools/Build-IconAssets.py`, define per-asset configuration:

```python
ASSETS = {
    "azeroth_travel_metrics.jpg": {
        "target": "ATTLogo.tga",
        "mask": "circle",
        "crop": (500 / 2048, 1340 / 2048, 960 / 2048, 1800 / 2048),
    },
    "overview_icon.jpg": {
        "target": "Overview.tga",
        "mask": "rounded",
    },
    "by_level_icon.jpg": {
        "target": "ByLevel.tga",
        "mask": "rounded",
    },
}
```

Add a supersampled circular mask for the ATT badge:

```python
def circular_mask(size: int, scale: int = 4) -> Image.Image:
    large = Image.new("L", (size * scale, size * scale), 0)
    draw = ImageDraw.Draw(large)
    inset = 2 * scale
    draw.ellipse(
        (inset, inset, size * scale - inset - 1, size * scale - inset - 1),
        fill=255,
    )
    return large.resize((size, size), Image.Resampling.LANCZOS)
```

Crop the new source to the normalized boot rectangle, resize with premultiplied
alpha, and multiply the circular mask into its alpha channel. The crop retains
the brown boot and nearby map colors while excluding the title, metric values,
fish, and most of the baked checkerboard. Do not globally color-key the source.
Retain the existing centered crop and rounded mask for the two tab icons.

- [ ] **Step 5: Regenerate and verify the runtime badge**

Run:

```powershell
python .\tools\Build-IconAssets.py
python -m unittest tests.test_icon_assets
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
```

Expected: asset and Lua tests pass; package tests pass with only the existing
privilege-dependent skip. The package contains `ATTLogo.tga` but neither
source JPG.

- [ ] **Step 6: Update documentation and commit**

Change the README source name from `att_logo_400x400.jpg` to
`azeroth_travel_metrics.jpg`.

Commit:

```powershell
git add artwork\source tools\Build-IconAssets.py `
  AzerothTravelTracker\Media\ATTLogo.tga tests\test_icon_assets.py README.md
git commit -m "fix: optimize the ATT badge for small icons" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 2: Use Native Window Controls and Correct Remaining Layout

**Files:**
- Modify: `AzerothTravelTracker/UITheme.lua`
- Modify: `AzerothTravelTracker/UI.lua`
- Modify: `tests/test_ui_theme.lua`
- Modify: `tests/test_core.lua`

- [ ] **Step 1: Extend the test harness for Blizzard's native template**

When the fake `CreateFrame` receives
`MaximizeMinimizeButtonFrameTemplate`, construct:

```lua
frame.MaximizeButton = newFrame("Button", nil, frame, nil, options)
frame.MinimizeButton = newFrame("Button", nil, frame, nil, options)
frame.MaximizeButton:Hide()
frame.MinimizeButton:Show()

function frame:SetMinimizedLook()
    self.MaximizeButton:Hide()
    self.MinimizeButton:Show()
end

function frame:SetMaximizedLook()
    self.MaximizeButton:Show()
    self.MinimizeButton:Hide()
end
```

Allow the template to be rejected so fallback behavior remains testable.

- [ ] **Step 2: Write failing native-control tests**

In `tests/test_ui_theme.lua`, require a new helper:

```lua
local control, button = addon.UITheme.CreateWindowSizeControl(
    parent,
    "minimize",
    "Minimize"
)
testlib.equal(control.template, "MaximizeMinimizeButtonFrameTemplate")
testlib.equal(control.width, 24)
testlib.equal(control.height, 24)
testlib.equal(button, control.MinimizeButton)
testlib.equal(control.MinimizeButton:IsShown(), true)
testlib.equal(control.MaximizeButton:IsShown(), false)
```

Add the corresponding `"restore"` case:

```lua
testlib.equal(button, control.MaximizeButton)
testlib.equal(control.MaximizeButton:IsShown(), true)
testlib.equal(control.MinimizeButton:IsShown(), false)
```

Add template-rejection cases that return a nonfatal fallback button with the
correct `controlKind`, click target, and three-line down-left/up-right arrow
geometry rather than the obsolete underscore.

- [ ] **Step 3: Write failing composition and layout tests**

In `tests/test_core.lua`, assert:

```lua
testlib.equal(UI.minimizeControl.width, 24)
testlib.equal(UI.minimizeControl.point[2], UI.closeButton)
testlib.equal(UI.minimizeButton, UI.minimizeControl.MinimizeButton)
testlib.equal(UI.hud.restoreControl.width, 24)
testlib.equal(UI.hud.restoreButton, UI.hud.restoreControl.MaximizeButton)
```

Preserve and extend hover tests so the HUD's native maximize child and Close
remain hidden at rest and visible while the HUD or either button is hovered.

Assert the title tint reaches the inner shell edges:

```lua
testlib.equal(UI.shell.topGlow.points[1][4], 7)
testlib.equal(UI.shell.topGlow.points[2][4], -7)
testlib.equal(UI.shell.topGlow.height, 44)
```

Assert Settings occupies the footer immediately left of the version:

```lua
testlib.equal(UI.settingsButton.point[1], "RIGHT")
testlib.equal(UI.settingsButton.point[2], UI.versionLabel)
testlib.equal(UI.settingsButton.point[3], "LEFT")
testlib.equal(UI.settingsButton.point[4], -8)
testlib.equal(UI.settingsButton.point[5], 0)
```

Assert 10-pixel spacing:

```lua
testlib.equal(UI.summarySections[2].frame.point[5], -10)
testlib.equal(UI.summarySections[3].frame.point[5], -10)
testlib.equal(UI.overviewPanel.height, 320)
testlib.equal(UI.levelRows[2].frame.point[5], -114)
testlib.equal(UI.levelRows[3].frame.point[5], -228)
testlib.equal(UI.levelScrollChild.height, 332)
```

- [ ] **Step 4: Run the Lua suite and verify it fails**

Run:

```powershell
lua tests\run.lua
```

Expected: failures identify custom glyph controls, inset title tint, old
Settings anchor, and 8-pixel spacing.

- [ ] **Step 5: Implement the native control helper**

In `AzerothTravelTracker/UITheme.lua`, add:

```lua
function Theme.CreateWindowSizeControl(parent, mode, tooltip)
    local created, control = pcall(
        CreateFrame,
        "Frame",
        nil,
        parent,
        "MaximizeMinimizeButtonFrameTemplate"
    )
    if created
        and control
        and control.MaximizeButton
        and control.MinimizeButton
    then
        control:SetSize(24, 24)
        if mode == "minimize" then
            control:SetMinimizedLook()
            setTooltip(control.MinimizeButton, tooltip or "Minimize")
            return control, control.MinimizeButton
        elseif mode == "restore" then
            control:SetMaximizedLook()
            setTooltip(control.MaximizeButton, tooltip or "Restore")
            return control, control.MaximizeButton
        end
        error("unsupported window size control: " .. tostring(mode))
    end

    local fallbackKind = mode == "restore" and "restore" or "minimize"
    local button = Theme.CreateTitleControl(
        parent,
        fallbackKind,
        tooltip,
        24
    )
    return button, button
end
```

Validate `mode` before attempting frame creation so unsupported modes always
fail clearly. Call `SetMinimizedLook`/`SetMaximizedLook` defensively; if the
template is incomplete or rejects setup, discard it and use the fallback.
Update `Theme.CreateTitleControl` so its `"minimize"` fallback is a three-line
down-left Condense arrow and its `"restore"` fallback is a three-line up-right
Expand arrow. Use axis-aligned fallback geometry if line rotation is
unavailable, preserving the existing no-throw compatibility behavior.

- [ ] **Step 6: Compose main and HUD controls**

In `AzerothTravelTracker/UI.lua`, replace the main custom minimize button:

```lua
UI.minimizeControl, UI.minimizeButton =
    ATT.UITheme.CreateWindowSizeControl(
        UI.titleRegion,
        "minimize",
        "Minimize"
    )
UI.minimizeControl:SetPoint(
    "RIGHT",
    UI.closeButton,
    "LEFT",
    -1,
    0
)
raiseAboveParent(UI.minimizeControl, UI.titleRegion, 3)
UI.minimizeButton:SetScript("OnClick", function()
    UI.Minimize()
end)
```

In the HUD, create `restoreControl` with mode `"restore"`, anchor it left of
Close, and retain `restoreButton` as the visible native child. Apply hover
composition to `restoreButton`; hide/show `restoreControl` as the unit so the
entire native control remains contained and visible.

- [ ] **Step 7: Correct title tint, Settings, and spacing**

In `UITheme.lua`, anchor the glow:

```lua
shell.topGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -8)
shell.topGlow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -8)
```

In `UI.lua`, create/anchor the version label before finalizing Settings, then:

```lua
UI.settingsButton:ClearAllPoints()
UI.settingsButton:SetPoint(
    "RIGHT",
    UI.versionLabel,
    "LEFT",
    -8,
    0
)
```

Use:

```lua
local SECTION_GAP = 10
local LEVEL_CARD_GAP = 10
```

The existing formulas then yield `SUMMARY_CONTENT_HEIGHT = 320` and
three-card level content height `332`. Keep gap-free final-item calculations
and update the scrollbar after assigning the final height.

- [ ] **Step 8: Run tests and commit**

Run:

```powershell
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
```

Expected: zero failures; only the existing privilege-dependent package skip
may remain.

Commit:

```powershell
git add AzerothTravelTracker\UITheme.lua AzerothTravelTracker\UI.lua `
  tests\test_ui_theme.lua tests\test_core.lua
git commit -m "fix: match native window controls and layout" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 3: Validate, Deploy, and Record Focused Evidence

**Files:**
- Preserve until user validation: `docs/BETA-SMOKE-TESTS.md`
- Build artifact: `artifacts/AzerothTravelTracker-0.1.0-beta.zip`
- Install target: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelTracker`

- [ ] **Step 1: Validate and package**

Run from the repository root:

```powershell
python -m unittest tests.test_icon_assets
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
.\tools\Package-Addon.ps1 -Version '0.1.0-beta'
Get-FileHash `
  -LiteralPath '.\artifacts\AzerothTravelTracker-0.1.0-beta.zip' `
  -Algorithm SHA256
```

Require zero failures, one allowed privilege skip, exactly three runtime TGAs,
no source JPG/reference/ForeverSVFix artifacts, and the exact approved title.

- [ ] **Step 2: Install only while WoW is closed**

If `WowB` is running, stop and ask the user to close it. Never terminate it.
Hash the active ATT SavedVariables, replace only the exact installed ATT
folder through an exact temporary staging directory, and never modify account
data.

- [ ] **Step 3: Reapply ForeverSVFix and verify integrity**

Run:

```powershell
python D:\_projects\ForeverSVFix\forever_sv_fix.py `
  --wow 'D:\Games\World of Warcraft\_classic_beta_' `
  --account '50347838#1' repair
python D:\_projects\ForeverSVFix\forever_sv_fix.py `
  --wow 'D:\Games\World of Warcraft\_classic_beta_' `
  --account '50347838#1' doctor
```

Require healthy doctor output, unchanged active/linked SavedVariables hashes,
restore load after `Core.lua`, and the exact junction target.

- [ ] **Step 4: Focused in-game acceptance**

At 100%, 80%, and 120% UI scale, verify:

1. The custom boot crop is recognizable in the 32-pixel title icon and
   20-pixel minimap icon, with no checkerboard.
2. The title tint reaches both inner border edges.
3. The main Condense button points down-left and the HUD Expand button points
   up-right, matching the World Map; both are fully visible.
4. HUD controls remain hover-only and all click behavior works.
5. Settings sits in the footer left of the version and does not overlap the
   Current Level total.
6. Overview and By Level gaps are exactly 10 pixels visually.
7. Previously passing layering, scrollbar, minimap rim-kiss, startup, and
   persistence checks remain passing.

- [ ] **Step 5: Record only verified smoke results**

Update only corresponding rows in `docs/BETA-SMOKE-TESTS.md`, then commit:

```powershell
git add docs\BETA-SMOKE-TESTS.md
git commit -m "docs: record final ATT UI smoke results" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Completion Criteria

1. The custom boot crop is legible at title and minimap sizes without a checkerboard.
2. The title tint reaches the shell's inner left and right edges.
3. Main/HUD controls use Blizzard's native Condense/Expand visuals.
4. Settings cannot overlap data rows.
5. Overview and By Level gaps are 10 pixels with no trailing gap.
6. All automated suites pass.
7. Clean deployment, ForeverSVFix doctor, and SavedVariables integrity pass.
8. Focused in-game evidence is recorded without claiming unrelated smoke coverage.
