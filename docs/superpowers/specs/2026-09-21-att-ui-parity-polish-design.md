# ATT UI Parity Polish Design

## Goal

Correct the remaining Azeroth Travel Tracker visual and interaction defects
without changing tracking, persistence, session, or aggregation behavior.

The regular window and minimized HUD should use the same restrained,
translucent visual hierarchy as Azeroth Public Library while preserving ATT's
compact layout and dependency-free implementation.

## Scope

This pass addresses:

- main-window and title-region opacity;
- frame strata and frame-level hierarchy;
- By Level scrollbar placement and visibility;
- minimap launcher attachment to the minimap rim;
- main-window minimize and minimized-HUD restore controls;
- the title shown for ATT in WoW's AddOns menu.

It does not change movement sampling, distance calculations, SavedVariables
schema, character lookup, session lifecycle, or statistics content.

## Reference and Approach

Use the installed Azeroth Public Library implementation as the visual
reference, but do not add a runtime dependency or copy its full window
architecture.

The selected approach is surgical parity:

- keep ATT's 420 x 430 regular window and 220 x 96 HUD;
- keep the existing Overview and By Level content structures;
- centralize visual corrections in `UITheme.lua`;
- make focused geometry and control changes in `UI.lua` and `Minimap.lua`;
- retain safe fallbacks for beta-client template or atlas failures.

A native-template rebuild is rejected because the Forever beta has already
demonstrated incompatible or deprecated Blizzard templates. A broad APL shell
port is rejected because it would add unnecessary structure and coupling.

## Window Shell and Opacity

ATT currently combines a 0.95-alpha tooltip backdrop with additional dark,
gold, vignette, and glow layers whose cumulative opacity makes the window
appear effectively solid.

Retain the tooltip backdrop assets and base color:

```text
background: (0.08, 0.06, 0.035, 0.95)
border:     (0.67, 0.53, 0.27, 0.96)
```

Match APL's lighter layered treatment:

- `UI-DialogBox-Background-Dark` receives the APL window warmth tint near
  `(0.86, 0.64, 0.20, 0.26)`;
- `UI-DialogBox-Gold-Background` uses a subtle tint near
  `(0.80, 0.58, 0.18, 0.08)`;
- the vertical vignette fades from 0.16 alpha to 0.03 alpha;
- the top glow fills the 44-pixel title area and fades from 0.14 alpha to
  0.01 alpha;
- no additional near-opaque texture covers the complete interior.

The 44-pixel title area remains part of this unified shell. It uses the subtle
top glow plus a one-pixel warm-gold separator at its lower edge with 0.22
alpha, and does not introduce an independent solid title bar. The glow extends
to the shell's inner left and right border edges without visible end gaps.

The existing fallback path remains visible if `BackdropTemplate`, gradient
APIs, or textures are unavailable. Its colors should approximate the same
warm translucency rather than reverting to a solid black panel.

## Layer Hierarchy

The main window and minimized HUD use `MEDIUM` strata, matching APL's normal
panel behavior:

- above world content and ordinary HUD elements;
- behind the World Map, Character panel, and higher-priority dialogs;
- below native tooltips.

ATT-owned settings or confirmation overlays use `DIALOG` strata and a frame
level above their owning window. Child controls use frame levels only to order
themselves above ATT shell textures; they do not raise the entire window to a
higher strata.

The strata fallback order begins at `MEDIUM` and falls back only when the beta
client rejects it. The main window and HUD share this policy.

## Title Controls

The regular window has two always-visible controls inside its upper-right
title region:

- minimize, using Blizzard's native 24 x 24
  `MaximizeMinimizeButtonFrameTemplate` Condense control;
- close, represented by `X`.

The minimize control sits immediately left of Close and uses the same native
red-button family as the World Map. If the template is unavailable, ATT keeps
a nonfatal fallback control with the same direction and click behavior.

The 44-pixel title region keeps the existing title font and 24 x 24 controls.
Its framed ATT logo is 32 x 32, vertically centered with six pixels of margin
above and below. The title glow fills the complete title region so the icon,
text, minimize control, and Close control all sit within the colored strip
without moving the tabs or content below it.

## Section Spacing

Overview summary sections use a 10-pixel vertical gap after Lifetime and This
Session. By Level cards use the same 10-pixel gap before the next level
heading.
Section and card heights remain unchanged. Layout and scroll-height
calculations include gaps only between items, never after the final item.

The minimized HUD keeps its controls hidden at rest and reveals them while the
HUD or either control is hovered:

- restore uses the native 24 x 24 Expand control from
  `MaximizeMinimizeButtonFrameTemplate`;
- close uses `X`;
- both controls fit entirely within the HUD border;
- neither control overlaps the title or statistic cells;
- moving between the HUD and its controls does not prematurely hide them.

The existing hover alpha transition remains, but control visibility and
geometry are independent from the HUD's statistic content.

## By Level Scrollbar

The By Level view reserves a dedicated scrollbar gutter entirely inside the
main window's right border.

The scroll frame and cards use separate widths:

- the scroll frame fills the available panel area;
- level cards end before the scrollbar gutter;
- the native scrollbar, arrow buttons, and thumb remain inside the gutter;
- the scrollbar does not overlap the window border or appear outside it.

Scrollbar chrome is visible only when
`levelScrollFrame:GetVerticalScrollRange() > 0`. When the content fits, all
scrollbar pieces are hidden while mouse-wheel behavior remains harmless.

The implementation must account for client differences where the template
exposes scrollbar chrome through `ScrollBar`, named child regions, or direct
children. ATT should collect the relevant chrome once and update it through a
single visibility helper.

## Minimap Launcher Geometry

The selected placement is **rim-kiss**:

- the launcher's decorative outer ring touches the outer minimap rim;
- the icon and clickable content remain outside the map's content surface;
- there is no floating gap;
- the launcher does not sink below or behind the minimap border.

Use Blizzard's Forever/classic tracking-border layout: the asymmetric 54 x 54
texture is anchored from the 32 x 32 button's top-left corner so the texture's
visible circular ring is centered on the button and its icon.

Placement uses the visible ring radius of 16 pixels rather than the full
texture bounds. `CalculateMinimapOffset` continues to find the shape-aware
minimap perimeter for round, square, side, corner, and tri-corner shapes, then
adds the Euclidean clearance required for tangency between the minimap rim and
visible launcher ring.

Dragging continues to persist only the polar angle. Repositioning at another
UI scale or minimap size recomputes the tangent position from current
dimensions.

The launcher remains above the minimap border through a small relative frame
level increase without using a globally elevated strata.

The native tracking-border artwork keeps its Forever/classic alignment. The
ATT logo artwork is 20 x 20 inside the visible ring, matching the 20 x 20
background, while the corrected ring alignment and rim tangency remain
unchanged.

## Custom Icon Assets

Three user-provided source images become optimized 64 x 64 TGA textures under
`AzerothTravelTracker\Media\`:

- a tight crop of the custom boot in `azeroth_travel_metrics` is used by the
  title and minimap launcher;
- `overview_icon` is used by the Overview side tab;
- `by_level_icon` is used by the By Level side tab.

The conversion uses square crops and transparent outside corners so no white
or checkerboard JPEG canvas appears in WoW. The package contains only the
optimized runtime textures, not the multi-megabyte source JPGs or the
`tab_iconography` reference sheet.

The Settings gear lives in the bottom-right footer immediately left of the
version label. It never overlaps Overview values or By Level content.

## AddOns Menu Identity

Change the `.toc` title to exactly:

```text
Azeroth Travel Tracker - WoW: Forever (beta)
```

The in-window title remains:

```text
Azeroth Travel Tracker
```

This clearly identifies the supported game version in WoW's AddOns menu
without making the compact title region unnecessarily long.

## Error Handling and Compatibility

- If backdrop gradients are unavailable, use equivalent low-alpha color
  textures.
- If the preferred title-control asset is unavailable, render the required
  glyph with an ATT-owned font string or line texture.
- If `UIPanelScrollFrameTemplate` is unavailable, retain the existing basic
  scroll frame and mouse-wheel behavior; do not show nonfunctional chrome.
- If scrollbar fields differ across beta builds, ignore missing pieces and
  manage only the discovered regions.
- Invalid minimap dimensions continue to use the established safe defaults.
- No UI fallback may prevent addon initialization or tracking.

## Automated Testing

Follow test-driven development for every behavior change.

Add or update tests that first reproduce:

- the shell's cumulative near-opaque layer values;
- main-window and HUD selection of `DIALOG` instead of `MEDIUM`;
- a scrollbar viewport that consumes the full panel width and places native
  chrome outside the intended gutter;
- scrollbar visibility when no scrolling is required;
- the minimap border being offset from the button center;
- fixed minimap padding rather than tangent launcher geometry;
- a text `Restore` button instead of the diagonal-arrow control;
- a minimize control that does not match the Close control geometry;
- the old ambiguous AddOns menu title.

Passing assertions must cover:

- APL-derived shell colors and alpha values;
- `MEDIUM` strata for the main window and HUD;
- `DIALOG` and elevated frame level for ATT-owned overlays;
- internal scrollbar gutter geometry and overflow-only visibility;
- card widths that clear the gutter;
- centered minimap border and rim-kiss offsets on round and non-round shapes;
- scale- and dimension-independent minimap angle preservation;
- `_`, diagonal restore arrow, and `X` control roles and hover behavior;
- the exact `.toc` title;
- no regression in existing Overview, By Level, HUD, minimap, persistence,
  lifecycle, or packaging tests.

## Manual Beta Validation

At the same scene and UI scale, place ATT beside Azeroth Public Library and
verify:

- comparable warm translucency in the shell and title region;
- world detail remains subtly visible through both windows;
- ATT sits behind the World Map and Character panel but above ordinary world
  HUD content;
- settings and confirmation overlays appear above ATT;
- native tooltips appear above all ATT surfaces;
- the By Level scrollbar is fully inside the right border and appears only
  when levels overflow;
- the minimap launcher ring touches the minimap rim without covering map
  content at several angles;
- the main `_` and `X` controls are aligned and readable;
- HUD controls appear on hover, remain inside the border, and use the diagonal
  restore arrow plus `X`;
- all geometry remains correct at 80%, 100%, and 120% UI scale.

## Packaging and ForeverSVFix

The distribution package remains clean and must not contain:

- `## X-ForeverSVFix`;
- `ForeverSVFixData`;
- account-specific links or generated workaround files.

After installing or replacing the packaged addon:

1. keep WoW fully closed;
2. reapply ForeverSVFix from the pinned reviewed source;
3. run ForeverSVFix `doctor`;
4. launch WoW only after the doctor reports a healthy installation.

The deployment verification must confirm that the active
`AzerothTravelTracker.lua` SavedVariables file is unchanged and reachable
through the regenerated junction before launching the client.
