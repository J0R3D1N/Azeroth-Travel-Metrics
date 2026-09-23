# ATM Native Minimize Style Design

## Goal

Make the now-visible main-window Minimize control match Blizzard's native red
Close button without regressing visibility or compact-HUD behavior.

## Selected Approach

Use `UIPanelHideButtonNoScripts` as the preferred main Minimize control:

- native `24 x 24` red button artwork;
- anchored immediately left of the native Close button;
- raised above Close and the portrait title chrome;
- explicit Forever minimize atlases applied to all button states;
- existing `UI.Minimize()` behavior and tooltip preserved.

The previous native attempt used a fixed top-right frame anchor and frame level
510. In the live portrait shell that artwork did not render, even though the
button remained clickable. The current ATM control proves that anchoring
relative to Close and rendering above the title chrome is reliable. This pass
combines the native red artwork with that proven placement and layering.

## Fallback Behavior

Native template or atlas failure must never restore an invisible click target.

Creation therefore uses two paths:

1. create the native `UIPanelHideButtonNoScripts` candidate and explicitly
   apply `RedButton-MiniCondense`, its pushed and disabled variants, and
   `RedButton-Highlight`;
2. if the native textures cannot be obtained or assigned, hide the candidate
   and use the current visible ATM `CreateTitleControl` minimize button.

Only the native path is expected in WoW Forever. The ATM path is defensive and
may retain its current `20 x 20` brown/gold appearance because it is used only
when native red artwork is unavailable.

## Placement and Layering

The selected Minimize button:

- is parented to the main frame;
- anchors `RIGHT` to Close's `LEFT` at `(-1, 0)`;
- uses a frame level greater than Close and at least `511`;
- remains immediately adjacent to Close with no overlap;
- does not change the title, portrait, side tabs, or frame dimensions.

The native button uses its template size of `24 x 24`, matching Close.

## Testing

Test-driven implementation must prove:

- the normal portrait path selects `UIPanelHideButtonNoScripts`;
- native normal, pushed, disabled, and highlight textures receive the exact
  red minimize atlases;
- the button is `24 x 24`, adjacent to Close, above Close, shown, and calls
  `UI.Minimize()`;
- the fallback shell can also use the native red path;
- missing/rejected native textures select the visible ATM title control;
- the fallback has visible background, highlight, and glyph textures;
- Close, compact HUD Restore/Close, Settings-only Reset, Settings geometry,
  diagnostics, tracking warnings, and all other behavior remain unchanged.

## In-Game Acceptance

1. Minimize and Close appear as a matching pair of native red title buttons.
2. Minimize remains immediately left of Close and opens the compact HUD.
3. Neither control overlaps the title bar or each other.
4. All previously accepted final-refinement behavior remains unchanged.
