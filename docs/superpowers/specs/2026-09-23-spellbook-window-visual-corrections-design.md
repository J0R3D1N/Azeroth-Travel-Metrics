# Spellbook Window Visual Corrections Design

## Goal

Correct the first in-game spellbook-window candidate without changing ATM's
tracking, storage, statistics, HUD, or command behavior.

The second candidate must:

- left-align the horizontal icon tabs;
- make the tab artwork fill each button;
- add Settings as a third tab;
- guarantee visible minimize and close controls;
- remove Reset Session from the crowded footer;
- eliminate the visual seam above the Lifetime section; and
- finish the intended parchment-native section treatment.

## Window structure

Retain the native `PortraitFrameTemplate` shell, circular pocket-watch
portrait, `420 x 470` frame size, movable behavior, Escape handling, and
existing frame strata.

Create explicit minimize and close controls in ATM's title overlay rather than
depending on inherited template children for presentation. Anchor close at the
upper-right and minimize immediately to its left. Raise both controls above
the native title and border artwork. The close action hides only the regular
window; minimize continues to open the existing HUD.

If a native button template is unavailable, use the existing safe fallback
button construction. Missing native chrome must never silently remove either
action.

## Horizontal tab strip

Keep the tabs horizontal. Anchor the strip near the left side below the title,
leaving enough clearance for the circular portrait:

1. Overview
2. By Level
3. Settings

The row is left-justified, not centered. Each tab remains icon-only with a
tooltip and clear selected state.

Increase the visible icon size within each tab and crop the icon texture
coordinates so the artwork fills the button without touching its border.
Retain:

- Overview: `Interface\Icons\inv_misc_spyglass_02`
- By Level: `Interface\Icons\inv_misc_book_09`
- Settings: `Interface\Icons\INV_Misc_Gear_01`

All three tabs use the same dimensions, icon treatment, hover behavior, and
selection treatment.

## Settings page

Replace the floating settings popup and footer gear button with a dedicated
Settings content panel inside the shared parchment page.

The Settings tab contains:

- Metric and Imperial unit controls;
- Show minimap button;
- Show diagnostics;
- a separated Reset Current Session action.

Existing setting persistence and focused update behavior remain unchanged.
Switching to Settings synchronizes the controls before showing the page.

## Reset Session placement

Remove Reset Session from the frame footer.

Place a full-width or comfortably sized **Reset Current Session** button near
the bottom of the Settings page beneath a divider and a concise warning that
the action resets only the current character's active session. Treat this as a
danger-zone section through spacing and muted red/brown emphasis rather than
bright custom artwork.

The existing confirmation dialog, storage operation, baseline reset, error
reporting, and successful refresh behavior remain unchanged.

This placement is preferred over repositioning the footer button because it
does not compete with the frame border, version label, parchment page, or UI
scale changes.

## Parchment and sections

Use `spellbook-page-condensed-c60` as the shared page background for Overview,
By Level, Settings, and error states.

Remove the dark character-stat header and row atlases from the parchment
content. Each section uses:

- extra top padding before the first section;
- a left-aligned dark-brown heading directly on parchment;
- `spellbook-divider` beneath the heading;
- dark-brown labels and near-black values;
- a subtle alternating parchment tint only where row separation is needed;
- a restrained emphasized Total Distance row.

The Lifetime heading must begin below the page's decorated top edge so no dark
rectangle or transparent seam appears between the header and parchment.

Apply the same section treatment to This Session, Current Level, and By Level
cards so the pages read as one visual system.

## Footer

Keep only the version label in the footer. It must remain unobscured and must
not overlap the parchment page or frame border at 80%, 100%, or 120% UI scale.

Settings and Reset Session no longer occupy footer space.

## Panel behavior

Extend active panel state from two values to three:

- `overview`
- `levels`
- `settings`

Only the selected content panel is visible. Error state continues to replace
normal content and does not alter the selected tab. Returning from an error
restores the selected panel.

Overview and By Level retain their existing model construction, scrolling,
row reuse, diagnostics, and refresh behavior. Settings uses existing database
references and callbacks rather than introducing new SavedVariables.

## Fallbacks

Preserve guarded behavior:

- rejected portrait template falls back to the safe bare shell;
- rejected button templates fall back to visible ATM controls;
- rejected parchment atlas falls back to a warm parchment color;
- rejected divider atlas falls back to a one-pixel brown line;
- unavailable gear, spyglass, or book textures do not remove the clickable
  tab frames.

The fallback shell must retain the same three-tab layout and all actions.

## Testing

Automated tests will verify:

- the tab row is horizontal, ordered, and left-justified;
- all tab icons use enlarged dimensions and cropped texture coordinates;
- Settings is the third selected panel and replaces the floating popup;
- units, minimap visibility, and diagnostics still persist correctly;
- Reset Session exists only on the Settings page and retains confirmation;
- explicit close and minimize controls are visible and interactive with native
  and fallback shell paths;
- section headings use parchment-native treatment and dividers;
- the first section has deliberate page-top spacing;
- Overview, By Level, error, Settings, HUD, Escape, and combat-safe behavior
  remain intact.

The beta smoke checklist will verify the five screenshot findings at 80%,
100%, and 120% UI scale and confirm there are no new overlaps or Lua errors.

## Non-goals

- Changing travel calculations or classification.
- Changing SavedVariables schema.
- Restyling the minimized HUD.
- Adding additional settings.
- Reproducing full spellbook paging, bookmarks, or animations.
