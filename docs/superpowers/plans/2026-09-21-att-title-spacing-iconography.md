# ATT Title, Spacing, and Iconography Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish ATT's MVP visual polish by fitting all title controls inside the colored header, adding consistent 8-pixel section spacing, and replacing placeholder WoW icons with the approved custom artwork.

**Architecture:** Keep the existing frame hierarchy and corrected minimap geometry. Add three optimized runtime textures under the addon, reference them through `UITheme.Icons`, and adjust only the existing title/section layout constants. Preserve the user-provided source art outside the packaged addon and generate deterministic 64 x 64 TGA assets with a small build tool.

**Tech Stack:** World of Warcraft Lua UI APIs, Lua test harness, Python 3 with Pillow for deterministic texture conversion, PowerShell package tests, Git.

**Approved design:** `docs/superpowers/specs/2026-09-21-att-ui-parity-polish-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `artwork/source/att_logo_400x400.jpg` | Preserved source for the ATT title/minimap logo. |
| `artwork/source/overview_icon.jpg` | Preserved source for the Overview tab icon. |
| `artwork/source/by_level_icon.jpg` | Preserved source for the By Level tab icon. |
| `tools/Build-IconAssets.py` | Deterministically center-crops, removes edge-connected white canvas, resizes, and writes WoW-compatible TGA textures. |
| `AzerothTravelTracker/Media/ATTLogo.tga` | Runtime title and minimap texture. |
| `AzerothTravelTracker/Media/Overview.tga` | Runtime Overview-tab texture. |
| `AzerothTravelTracker/Media/ByLevel.tga` | Runtime By Level-tab texture. |
| `AzerothTravelTracker/UITheme.lua` | Runtime texture paths and 44-pixel title glow. |
| `AzerothTravelTracker/UI.lua` | 32-pixel title icon and consistent 8-pixel Overview/By Level spacing. |
| `AzerothTravelTracker/Minimap.lua` | Uses the ATT logo at 20 x 20 without changing the validated rim geometry. |
| `tests/test_core.lua` | Title chrome, custom tab icon, and section-spacing regressions. |
| `tests/test_minimap.lua` | Custom minimap texture and size regression. |
| `tests/Test-PackageAddon.ps1` | Runtime texture inclusion and source-art exclusion checks. |
| `README.md` | Documents custom icon source/build workflow. |

## Task 1: Generate and Wire the Custom Runtime Textures

**Files:**
- Create: `artwork/source/att_logo_400x400.jpg`
- Create: `artwork/source/overview_icon.jpg`
- Create: `artwork/source/by_level_icon.jpg`
- Create: `tools/Build-IconAssets.py`
- Create: `AzerothTravelTracker/Media/ATTLogo.tga`
- Create: `AzerothTravelTracker/Media/Overview.tga`
- Create: `AzerothTravelTracker/Media/ByLevel.tga`
- Modify: `AzerothTravelTracker/UITheme.lua`
- Modify: `AzerothTravelTracker/Minimap.lua`
- Modify: `tests/test_core.lua`
- Modify: `tests/test_minimap.lua`
- Modify: `tests/Test-PackageAddon.ps1`
- Modify: `README.md`

- [ ] **Step 1: Copy the three approved source images into the repository**

Copy, without deleting the originals:

```powershell
New-Item -ItemType Directory -Force `
  'D:\_projects\wow-forever-step-tracker\artwork\source' | Out-Null

Copy-Item -LiteralPath `
  'D:\_projects\wow-forever-step-tracker\artifacts\AzerothTravelTracker\att_logo_400x400.jpg' `
  -Destination 'D:\_projects\wow-forever-step-tracker\artwork\source\att_logo_400x400.jpg'
Copy-Item -LiteralPath `
  'D:\_projects\wow-forever-step-tracker\artifacts\AzerothTravelTracker\overview_icon.jpg' `
  -Destination 'D:\_projects\wow-forever-step-tracker\artwork\source\overview_icon.jpg'
Copy-Item -LiteralPath `
  'D:\_projects\wow-forever-step-tracker\artifacts\AzerothTravelTracker\by_level_icon.jpg' `
  -Destination 'D:\_projects\wow-forever-step-tracker\artwork\source\by_level_icon.jpg'
```

Do not copy `tab_iconography.jpg`; it is a reference sheet, not a runtime or source asset.

- [ ] **Step 2: Write failing texture-path and package tests**

In `tests/test_core.lua`, replace the placeholder-icon expectations with:

```lua
testlib.equal(
    harness.addon.UITheme.Icons.TITLE,
    "Interface\\AddOns\\AzerothTravelTracker\\Media\\ATTLogo"
)
testlib.equal(
    harness.addon.UITheme.Icons.OVERVIEW,
    "Interface\\AddOns\\AzerothTravelTracker\\Media\\Overview"
)
testlib.equal(
    harness.addon.UITheme.Icons.LEVELS,
    "Interface\\AddOns\\AzerothTravelTracker\\Media\\ByLevel"
)
testlib.equal(harness.addon.UI.overviewTab.Icon.texture,
    harness.addon.UITheme.Icons.OVERVIEW)
testlib.equal(harness.addon.UI.levelTab.Icon.texture,
    harness.addon.UITheme.Icons.LEVELS)
```

In `tests/test_minimap.lua`, assert:

```lua
testlib.equal(
    harness.addon.Minimap.icon.texture,
    "Interface\\AddOns\\AzerothTravelTracker\\Media\\ATTLogo"
)
testlib.equal(harness.addon.Minimap.icon.width, 20)
testlib.equal(harness.addon.Minimap.icon.height, 20)
```

In `tests/Test-PackageAddon.ps1`, add archive assertions for exactly these runtime entries:

```powershell
$requiredTextures = @(
    'AzerothTravelTracker/Media/ATTLogo.tga',
    'AzerothTravelTracker/Media/Overview.tga',
    'AzerothTravelTracker/Media/ByLevel.tga'
)
foreach ($texture in $requiredTextures) {
    Test-True "package includes $texture" ($zipEntries -contains $texture)
}
Test-True 'package excludes source JPGs' (
    -not ($zipEntries | Where-Object { $_ -match '\.(jpg|jpeg)$' })
)
Test-True 'package excludes tab iconography reference' (
    -not ($zipEntries | Where-Object { $_ -match 'tab_iconography' })
)
```

- [ ] **Step 3: Run tests and verify the new assertions fail**

Run:

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') +
  ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
```

Expected: Lua tests report the old Blizzard texture paths, and package tests report the three missing TGA entries.

- [ ] **Step 4: Add the deterministic texture builder**

Create `tools/Build-IconAssets.py`:

```python
from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artwork" / "source"
TARGET = ROOT / "AzerothTravelTracker" / "Media"
ASSETS = {
    "att_logo_400x400.jpg": "ATTLogo.tga",
    "overview_icon.jpg": "Overview.tga",
    "by_level_icon.jpg": "ByLevel.tga",
}
SIZE = 64


def center_crop(image: Image.Image) -> Image.Image:
    edge = min(image.size)
    left = (image.width - edge) // 2
    top = (image.height - edge) // 2
    return image.crop((left, top, left + edge, top + edge))


def clear_edge_white(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    queue = deque()
    seen = set()

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if (x, y) in seen:
            continue
        seen.add((x, y))
        red, green, blue, alpha = pixels[x, y]
        if min(red, green, blue) < 235 or max(red, green, blue) - min(
            red, green, blue
        ) > 24:
            continue
        pixels[x, y] = (red, green, blue, 0)
        if x > 0:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y > 0:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))

    return rgba


def build(source_name: str, target_name: str) -> None:
    with Image.open(SOURCE / source_name) as original:
        cropped = center_crop(original)
        transparent = clear_edge_white(cropped)
        resized = transparent.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        TARGET.mkdir(parents=True, exist_ok=True)
        resized.save(TARGET / target_name, format="TGA", compression=None)


def main() -> None:
    for source_name, target_name in ASSETS.items():
        build(source_name, target_name)


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Generate and validate the TGA files**

Run:

```powershell
python .\tools\Build-IconAssets.py
python -c "from pathlib import Path; from PIL import Image; root=Path(r'AzerothTravelTracker\Media'); names=['ATTLogo.tga','Overview.tga','ByLevel.tga']; [(lambda im,n: print(n, im.size, im.mode, im.getpixel((0,0))[3]))(Image.open(root/n).convert('RGBA'),n) for n in names]"
```

Expected: all three images report `(64, 64) RGBA`; `ATTLogo.tga` reports a transparent corner alpha of `0`.

- [ ] **Step 6: Wire the custom texture paths**

In `AzerothTravelTracker/UITheme.lua`, set:

```lua
Icons = {
    PORTRAIT = "Interface\\Icons\\INV_Misc_Map_01",
    TITLE = "Interface\\AddOns\\AzerothTravelTracker\\Media\\ATTLogo",
    OVERVIEW = "Interface\\AddOns\\AzerothTravelTracker\\Media\\Overview",
    LEVELS = "Interface\\AddOns\\AzerothTravelTracker\\Media\\ByLevel",
    SETTINGS = "Interface\\Icons\\INV_Misc_Gear_01",
},
```

In `AzerothTravelTracker/Minimap.lua`, replace the hard-coded sprint texture with:

```lua
icon:SetTexture(ATT.UITheme.Icons.TITLE)
icon:SetSize(20, 20)
icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
```

Keep the validated tracking-border alignment and rim-clearance calculation unchanged.

- [ ] **Step 7: Document the asset workflow**

Add a development subsection to `README.md`:

```markdown
### Icon assets

The editable source JPGs live in `artwork/source/`. Regenerate the three
64 x 64 WoW runtime textures with:

```powershell
python .\tools\Build-IconAssets.py
```

The distribution package includes only `AzerothTravelTracker/Media/*.tga`;
source JPGs and the comparison sheet are not packaged.
```

- [ ] **Step 8: Run both suites and commit**

Run:

```powershell
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
```

Expected: zero failures; only the existing privilege-dependent package test may skip.

Commit:

```powershell
git add artwork\source tools\Build-IconAssets.py `
  AzerothTravelTracker\Media AzerothTravelTracker\UITheme.lua `
  AzerothTravelTracker\Minimap.lua tests\test_core.lua `
  tests\test_minimap.lua tests\Test-PackageAddon.ps1 README.md
git commit -m "feat: add custom ATT iconography" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 2: Fit the Title Chrome and Add Section Spacing

**Files:**
- Modify: `AzerothTravelTracker/UITheme.lua`
- Modify: `AzerothTravelTracker/UI.lua`
- Modify: `tests/test_core.lua`

- [ ] **Step 1: Write failing title-layout assertions**

In the main-window test in `tests/test_core.lua`, assert:

```lua
testlib.equal(UI.shell.topGlow.height, 44)
testlib.equal(UI.titleRegion.height, 44)
testlib.equal(UI.titleIconFrame.width, 32)
testlib.equal(UI.titleIconFrame.height, 32)
testlib.equal(UI.titleIconFrame.point[1], "LEFT")
testlib.equal(UI.titleIconFrame.point[4], 4)
testlib.equal(UI.closeButton.width, 24)
testlib.equal(UI.minimizeButton.width, 24)
```

Keep the existing vertical-center assertions for title text and controls. The 32-pixel icon inside the 44-pixel region provides six pixels of vertical margin.

- [ ] **Step 2: Write failing spacing assertions**

For Overview:

```lua
testlib.equal(UI.summarySections[2].frame.point[5], -8)
testlib.equal(UI.summarySections[3].frame.point[5], -8)
testlib.equal(UI.overviewPanel.height, 316)
```

For three By Level cards:

```lua
testlib.equal(UI.levelRows[1].frame.point[5], 0)
testlib.equal(UI.levelRows[2].frame.point[5], -112)
testlib.equal(UI.levelRows[3].frame.point[5], -224)
testlib.equal(UI.levelScrollChild.height, 328)
```

The three-card content height is `104 + 8 + 104 + 8 + 104 = 328`; there is no
trailing gap. One- and two-card views still retain the 282-pixel minimum
viewport height.

- [ ] **Step 3: Run the Lua suite and verify the tests fail**

Run:

```powershell
lua tests\run.lua
```

Expected: failures show the 28-pixel glow, 36-pixel title icon, 3-pixel Overview gap, 104-pixel level stride, and old content-height calculation.

- [ ] **Step 4: Implement title-bar containment**

In `AzerothTravelTracker/UITheme.lua`, set:

```lua
shell.topGlow:SetHeight(44)
```

In `AzerothTravelTracker/UI.lua`, create the title icon at 32 pixels:

```lua
UI.titleIconFrame,
    UI.titleIcon,
    UI.titleIconBackground,
    UI.titleIconBorder = ATT.UITheme.CreateFramedIcon(
        UI.titleRegion,
        ATT.UITheme.Icons.TITLE,
        32
    )
```

Do not change the 44-pixel title region, title font, 24-pixel controls, separator position, tabs, or content origin.

- [ ] **Step 5: Implement exact 8-pixel inter-section spacing**

At the top of `AzerothTravelTracker/UI.lua`, use:

```lua
local SECTION_HEIGHT = 100
local SECTION_GAP = 8
local SUMMARY_CONTENT_HEIGHT = (SECTION_HEIGHT * 3) + (SECTION_GAP * 2)
local LEVEL_CARD_HEIGHT = 104
local LEVEL_CARD_GAP = 8
```

Position level cards with:

```lua
local topOffset = (index - 1) * (LEVEL_CARD_HEIGHT + LEVEL_CARD_GAP)
card.frame:SetPoint(
    "TOPLEFT",
    UI.levelScrollChild,
    "TOPLEFT",
    0,
    -topOffset
)
```

Set the scroll-child height without a trailing gap:

```lua
local levelContentHeight = 0
if #levelRows > 0 then
    levelContentHeight = (#levelRows * LEVEL_CARD_HEIGHT)
        + ((#levelRows - 1) * LEVEL_CARD_GAP)
end
UI.levelScrollChild:SetHeight(math.max(
    LEVEL_VIEW_HEIGHT,
    levelContentHeight
))
```

Keep the overflow-only scrollbar update after the final height assignment.

- [ ] **Step 6: Run the Lua suite and commit**

Run:

```powershell
lua tests\run.lua
```

Expected: zero failures.

Commit:

```powershell
git add AzerothTravelTracker\UITheme.lua AzerothTravelTracker\UI.lua `
  tests\test_core.lua
git commit -m "fix: refine ATT title and section spacing" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 3: Validate, Package, Install, and Reapply ForeverSVFix

**Files:**
- Preserve until manual validation: `docs/BETA-SMOKE-TESTS.md`
- Build artifact: `artifacts/AzerothTravelTracker-0.1.0-beta.zip`
- Install target: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelTracker`

- [ ] **Step 1: Verify repository state and automated tests**

Run:

```powershell
git --no-pager status --short
lua tests\run.lua
.\tests\Test-PackageAddon.ps1
```

Expected: only `docs/BETA-SMOKE-TESTS.md` is dirty; both suites have zero failures, with only the existing privilege-dependent package skip allowed.

- [ ] **Step 2: Build and inspect the clean package**

Run:

```powershell
.\tools\Package-Addon.ps1 -Version '0.1.0-beta'
Get-FileHash `
  -LiteralPath '.\artifacts\AzerothTravelTracker-0.1.0-beta.zip' `
  -Algorithm SHA256
```

Inspect the ZIP through `System.IO.Compression.ZipFile` and require:

- one top-level `AzerothTravelTracker` directory;
- the three `Media/*.tga` files;
- no JPG source files or `tab_iconography` reference;
- no `ForeverSVFixData`, generated helper file, or `X-ForeverSVFix` marker;
- the exact approved Forever-beta TOC title.

- [ ] **Step 3: Stop if WoW is running and preserve data integrity**

Run:

```powershell
$wow = 'D:\Games\World of Warcraft\_classic_beta_'
$saved = Join-Path $wow `
  'WTF\Account\50347838#1\SavedVariables\AzerothTravelTracker.lua'
if (Get-Process -Name 'WowB' -ErrorAction SilentlyContinue) {
    throw 'WoW must be closed before installing ATT.'
}
$savedHashBefore = (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
```

Never terminate WoW automatically and never modify the account SavedVariables directory.

- [ ] **Step 4: Replace only the installed ATT folder**

Inspect and resolve:

```powershell
$installed = Join-Path $wow 'Interface\AddOns\AzerothTravelTracker'
$staging = Join-Path $env:TEMP 'AzerothTravelTracker-install'
Get-Item -LiteralPath $installed -Force
```

Remove only those exact installed/staging paths, extract the validated ZIP, and move its single `AzerothTravelTracker` folder into the AddOns directory. Do not use wildcards.

- [ ] **Step 5: Reapply ForeverSVFix and verify**

Run:

```powershell
python D:\_projects\ForeverSVFix\forever_sv_fix.py `
  --wow 'D:\Games\World of Warcraft\_classic_beta_' `
  --account '50347838#1' repair

python D:\_projects\ForeverSVFix\forever_sv_fix.py `
  --wow 'D:\Games\World of Warcraft\_classic_beta_' `
  --account '50347838#1' doctor
```

Require `Active installation checks: OK` and `No repair needed.` Verify:

- SavedVariables before/after/linked hashes are identical;
- the installed TOC restore entry follows `Core.lua`;
- `ForeverSVFixData` targets the exact account SavedVariables directory;
- source and package remain free of generated ForeverSVFix artifacts.

- [ ] **Step 6: Perform focused in-game acceptance**

At 100%, then 80% and 120% UI scale, verify:

1. The title color fills the 44-pixel title region.
2. The 32-pixel ATT title logo, title text, minimize, and Close controls are fully contained and vertically centered.
3. The minimap ATT logo fills the visible native ring without changing rim-kiss placement.
4. Overview has an 8-pixel gap after Lifetime and This Session.
5. Every By Level card has an 8-pixel gap before the next level heading.
6. Layering, scrollbar behavior, persistence, and controls remain passing.

- [ ] **Step 7: Record only observed smoke evidence**

Update only the corresponding rows in `docs/BETA-SMOKE-TESTS.md`. Do not mark unrelated movement scenarios complete.

Commit:

```powershell
git add docs\BETA-SMOKE-TESTS.md
git commit -m "docs: record ATT UI refinement smoke results" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Completion Criteria

1. Custom title, minimap, Overview, and By Level textures render from committed 64 x 64 TGA assets.
2. No source JPG or reference sheet enters the addon package.
3. The complete 44-pixel title region is colored and all title elements fit within it.
4. Overview and By Level use exact 8-pixel gaps only between sections/cards.
5. Minimap rim tangency and the validated frame hierarchy remain unchanged.
6. Lua and package suites have zero failures.
7. Clean installation, ForeverSVFix doctor, and SavedVariables integrity checks pass.
8. Focused in-game results are recorded without claiming unrelated smoke coverage.
