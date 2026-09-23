# Hybrid Window Rollback Design

## Goal

Restore ATM's last-known-good non-parchment content layout and right-side tabs
while retaining the successful parts of the newer shell:

- circular pocket-watch portrait;
- thin native title bar;
- native close control;
- current ATM identity and travel behavior.

The screenshot from the third spellbook candidate is the rejection baseline.
The center parchment treatment and horizontal tabs must be removed.

## Source of Truth

Commit `1567f0f` is the last-known-good center layout and interaction design:

- Overview and By Level use vertical right-side icon tabs;
- sections use `UI-Character-Info-Title` headers and character-stat row atlases;
- Settings opens from the bottom-right gear button as a compact popup;
- Reset Session is a footer button;
- the center content has no parchment page.

Current HEAD remains the source of truth for the portrait frame, title,
pocket-watch identity, data model, travel fixes, packaging, and SavedVariables
behavior.

## Considered Approaches

### 1. Revert all spellbook commits

This would restore the old UI quickly, but it would also discard the accepted
portrait frame, thin title bar, identity work, tests, and later unrelated fixes.

### 2. Keep the current structure and restyle it

This would preserve more recent code, but it would continue iterating on the
rejected three-tab parchment architecture rather than returning to the known
good design.

### 3. Selectively restore the prior center UI

Restore the relevant layout and theme behavior from `1567f0f` inside the current
portrait shell. This keeps accepted chrome and current behavior while returning
the center of the window to a proven state.

This is the selected approach.

## Window Shell

Continue creating the main window with `PortraitFrameTemplate`. Keep:

- frame size `420 x 470`;
- circular portrait using `inv_misc_pocketwatch_01`;
- native `TitleContainer.TitleText`;
- native `frame.CloseButton`;
- current movable-frame and escape behavior.

No parchment texture or page-art frame remains.

## Minimize Control

Do not use `MaximizeMinimizeButtonFrameTemplate` for the regular window. In the
Forever client this control has repeatedly failed to produce a visible minimize
button in the title bar.

Create the main minimize button from `UIPanelHideButtonNoScripts`, which supplies
Blizzard's native red condense artwork at frame level 510. Parent it directly to
the main frame and anchor it immediately left of the native close button. Its
click handler continues to call `UI.Minimize()`.

The minimized HUD's Restore behavior remains unchanged.

## Navigation

Restore two `LargeSideTabButtonTemplate` controls:

1. Overview
2. By Level

Anchor Overview to the upper-right outside edge of the main frame and By Level
below it. Use the existing spyglass and book icons. Remove the horizontal tab
row and remove Settings from `activeTab`.

## Center Content

Restore the non-parchment center layout from `1567f0f`:

- content frame at `TOPLEFT (16, -50)`, size `388 x 350`;
- Overview panel and its three centered character-stat sections;
- By Level panel and level cards using the same section style;
- error inset using the prior inset treatment;
- original section spacing and scroll geometry.

Restore `Theme.CreateSection` to:

- use `UI-Character-Info-Title` for headers;
- center `GameFontNormalSmall` headings;
- use character-stat row atlases;
- use gold labels and white values;
- retain the Total Distance separator and emphasis.

## Settings and Footer

Restore the bottom-right Settings gear button and compact
`InsetFrameTemplate3` popup from `1567f0f`. The popup continues to synchronize
and persist units, minimap visibility, and diagnostics.

Restore `Reset Session` to the bottom-left footer. Preserve its current
confirmation and storage behavior. Keep the version label at bottom-right.

## Preserved Behavior

The rollback must not change:

- travel classification or totals;
- Overview/By Level data generation;
- SavedVariables schema or ForeverSVFix requirements;
- minimize-to-HUD behavior;
- reset confirmation semantics;
- addon identity, icon paths, version, or package structure.

## Testing

Automated tests will prove:

- the portrait template and native title remain;
- the native close button remains visible;
- the main minimize control uses `UIPanelHideButtonNoScripts`, is parented to
  the main frame, and sits beside close at frame level 510;
- only two right-side tabs exist and switch Overview/By Level;
- no parchment page, page-art frame, horizontal top tab, or Settings tab exists;
- section headers and rows use the prior character-stat atlases and colors;
- Settings is again a gear-triggered popup;
- Reset Session is again in the footer;
- existing model, HUD, reset, packaging, and identity tests remain green.

The in-game gate is:

1. portrait frame and thin title bar remain;
2. minimize and close are both visible and work;
3. Overview and By Level tabs appear on the right;
4. the center matches the last-known-good non-parchment layout;
5. Settings opens from the footer gear;
6. no parchment artwork remains.
