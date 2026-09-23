# Spellbook-Style ATM Window Design

## Goal

Restyle the Azeroth Travel Metrics main window to resemble the supplied
Forever spellbook reference while preserving ATM's behavior and compact
single-page footprint.

The redesign emphasizes:

- a circular pocket-watch portrait at the upper-left;
- a thinner native Blizzard title bar;
- Overview and By Level icon tabs inside the window along the top;
- parchment page backgrounds;
- spellbook-style section headings and dividers.

## Native assets

Use Forever-native UI resources verified in build `1.60.1.69913`:

- outer frame: `PortraitFrameTemplateMinimizable`;
- page background: `spellbook-page-condensed-c60`;
- section separator: `spellbook-divider`;
- main portrait: `Interface\Icons\inv_misc_pocketwatch_01`;
- Overview tab: `Interface\Icons\inv_misc_spyglass_02`;
- By Level tab: `Interface\Icons\inv_misc_book_09`.

The pocket watch also becomes the addon-listing, title, minimap, and session
Steps icon so ATM has one consistent identity.

## Architecture

Use a hybrid native shell rather than inheriting `SpellBookFrameTemplate`.
The full spellbook template owns paging, categories, search, gamepad
navigation, spell data, and large two-page dimensions that ATM does not need.

ATM will inherit only `PortraitFrameTemplateMinimizable`, then create its own
content and tab controls inside that shell. This gives ATM the native circular
portrait, border, title treatment, close control, and minimize control without
coupling it to Blizzard's spellbook state.

If the native portrait template cannot be created or initialized, ATM will
fall back to its current safe bare-frame construction. The fallback must still
render a circular-looking portrait treatment, top tabs, parchment-colored
content, and working controls.

## Layout

Keep the existing `420 x 430` window unless native chrome requires a small
measured adjustment during implementation.

The vertical layout is:

1. Native thin title bar with circular pocket-watch portrait.
2. Horizontal tab strip directly below the title.
3. Parchment content page shared by the active panel.
4. Existing reset, settings, and version controls along the bottom.

Overview and By Level tabs remain icon-only with tooltips. They use the
existing spyglass and book icons, are approximately `40 x 40`, and sit from
left to right inside the top edge rather than outside the right frame border.
The active tab has a gold highlight and visually connects to the parchment
page.

## Parchment pages

Create one parchment background texture behind the active content using
`spellbook-page-condensed-c60`, stretched to the content bounds with
`useAtlasSize = false`.

Overview and By Level retain separate panel frames and current data flow.
Switching tabs changes panel visibility but does not recreate frames or
models.

Content text changes from the current light-on-dark palette to spellbook-like
dark brown text:

- headings: dark brown, larger than row labels;
- row labels: medium brown;
- values: near-black or dark brown;
- totals: darker bold/gold-brown emphasis.

## Section treatment

Each Overview group and By Level card uses:

- a plain parchment background rather than dark row bars;
- a heading aligned left;
- the `spellbook-divider` atlas immediately below the heading;
- compact label/value rows with subtle alternating parchment tint only when
  needed for readability;
- the current Total Distance footer emphasis.

The existing section data, row order, calculations, error states, diagnostics,
and level scrolling remain unchanged.

## Controls and behavior

Preserve:

- movable window behavior;
- Escape-to-close;
- minimize/restore HUD behavior;
- reset confirmation;
- settings controls and persistence;
- Overview and By Level tooltips and selected state;
- level scrolling and scrollbar visibility;
- combat-safe, non-protected controls;
- all current SavedVariables and tracking behavior.

The minimized HUD is not restyled in this change, except that its Steps icon
uses the pocket watch.

## Fallbacks

All native-template and atlas use remains guarded:

- rejected portrait-frame creation falls back to a bare frame;
- unavailable parchment atlas falls back to a warm parchment color texture;
- unavailable divider atlas falls back to a one-pixel brown line;
- unavailable native close/minimize children use ATM's existing safe controls.

Fallbacks must remain visible and interactive rather than silently omitting
chrome.

## Testing

Automated tests will verify:

- the pocket-watch identity on every main-icon surface;
- native portrait-frame creation and fallback;
- top-tab position, order, icons, tooltips, and selected state;
- parchment atlas and color fallback;
- divider atlas and line fallback;
- dark text colors suitable for parchment;
- unchanged tab switching, scrolling, reset, settings, minimize, and Escape
  behavior;
- packaging remains free of bundled image assets.

The beta smoke checklist will add visual checks at 80%, 100%, and 120% UI
scale for portrait clipping, title-bar height, tab alignment, parchment
coverage, section divider stretching, text contrast, and control overlap.

## Non-goals

- Reproducing the full two-page spellbook.
- Adding page-turn animations, bookmarks, search, or spellbook navigation.
- Changing ATM calculations, storage, travel classification, or HUD layout.
- Bundling replacement artwork.
