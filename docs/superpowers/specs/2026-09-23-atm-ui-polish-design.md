# ATM UI Polish Design

## Goal

Polish the deployed hybrid ATM window without changing travel tracking,
SavedVariables, model behavior, or the accepted portrait-frame identity.

The pass addresses four visible issues from the September 23 in-game
screenshot:

1. Settings must become a third right-side tab.
2. The compact HUD Restore control must match the HUD Close control.
3. The working main-window Minimize control must become visible.
4. The unused vertical space above the footer must be removed.

## Selected Approach

Make a surgical layout pass inside the current hybrid architecture:

- preserve the `PortraitFrameTemplate`, circular pocket-watch portrait, thin
  title bar, native Close control, and classic non-parchment center;
- shorten the shell rather than stretching content into empty space;
- convert Settings from a footer popup into a normal center panel selected by
  a third native side tab;
- keep Reset Session in the compact footer;
- retain Blizzard red-button artwork for title and HUD controls.

Keeping the existing `420 x 470` shell and expanding the center would preserve
unnecessary space. Moving Reset Session into Settings would change behavior
that the user did not request.

## Main Window Geometry

Keep the width at `420` pixels and reduce the height to `414` pixels:

- the content begins at the current top inset;
- Overview remains `320` pixels tall;
- By Level remains fully visible at its current `310`-pixel height;
- the footer begins within a small visual gap below the content;
- Reset Session, the Settings-free footer, and the version label remain inside
  the bottom border without overlap.

Reduce the generic content and error-panel heights to match the compact shell.
No blank block comparable to the screenshot's red box may remain.

## Navigation and Settings

Navigation contains three vertically stacked
`LargeSideTabButtonTemplate` controls:

1. Overview, using `inv_misc_spyglass_02`;
2. By Level, using `inv_misc_book_09`;
3. Settings, using `INV_Misc_Gear_01`.

Settings uses the same tab size, icon fill, spacing, selected texture, tooltip,
and fallback behavior as Overview and By Level.

`activeTab` accepts `overview`, `levels`, and `settings`. Selecting Settings:

- synchronizes persisted controls before displaying the panel;
- hides Overview, By Level, and any stale error surface;
- displays a full center panel at the same origin and width as the other views.

The Settings center uses the established character-stat visual language:

- native character-info header and row atlases;
- gold labels and white values/controls;
- compact rows for distance units, minimap visibility, and diagnostics;
- a `Diagnostic Rejections` section beneath the controls that shows the
  scrollable reason/count output when diagnostics are enabled;
- no parchment and no floating popup.

Diagnostic output no longer extends the Overview panel. Overview remains a
fixed `320`-pixel surface whether diagnostics are enabled or disabled.

The footer Settings gear is removed. Reset Session remains in the footer and
retains its confirmation and storage behavior.

## Main Minimize Control

The main Minimize click target already works, so preserve its behavior and
24-pixel parity with the native Close button.

Continue using `UIPanelHideButtonNoScripts`, but explicitly ensure its normal,
pushed, disabled, and highlight textures use Forever's native red-button
atlases:

- `RedButton-MiniCondense`;
- `RedButton-MiniCondense-pressed`;
- `RedButton-MiniCondense-disabled`;
- `RedButton-Highlight`.

Anchor the control at a fixed title-bar position immediately left of Close and
keep it at frame level 510. If native texture setup is unavailable, retain a
visible compact fallback rather than an invisible working target.

## Compact HUD Controls

Keep the HUD Close control at `20 x 20`. Reduce Restore from `24 x 24` to
`20 x 20`, including its containing control and clickable child. Preserve:

- hover-only visibility;
- Restore behavior;
- tooltip composition;
- close behavior;
- drag behavior and persisted HUD position.

## Error and State Behavior

Errors continue to replace Overview or By Level content. Settings remains
usable as a local configuration surface even when statistics have an error;
selecting Settings hides the error panel. Returning to Overview or By Level
shows the pending error until the next successful refresh clears it.

Tab selection must remain synchronized in native and fallback-template paths.

## Testing

Automated tests must prove:

- the shell is compact and footer controls remain inside its bounds;
- no large gap remains between Overview content and the footer;
- Settings is the third matching right-side tab;
- the footer gear and floating Settings popup are gone;
- Settings synchronizes and persists all existing controls;
- diagnostic reason/count output is parented to Settings and never changes
  Overview height;
- error visibility follows the selected content tab;
- main Minimize uses the native template, native red-button atlases, fixed
  title-bar placement, and a visible fallback;
- HUD Restore and Close are both `20 x 20`;
- existing Overview, By Level, reset, HUD, fallback, combat, packaging, and
  identity behavior remains green.

The in-game acceptance gate is:

1. Overview, By Level, and Settings appear as matching right-side tabs.
2. Settings opens as center content with no footer popup.
3. Main Minimize and Close are both visible and work.
4. HUD Restore and Close appear the same size.
5. The footer sits directly below the content with no red-box dead space.
