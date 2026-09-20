# Character Panel UI Redesign

## Goal

Restyle Azeroth Travel Tracker so it visually belongs beside World of Warcraft: Forever's default character panel while preserving the addon's compact layout, movable window, top-layer behavior, statistics, settings, and reset workflow.

The supplied character-panel screenshot is the visual source of truth. The existing addon screenshot identifies the problems to remove: flat black space, bright top text tabs, oversized red utility buttons, weak grouping, and sparse three-column statistics.

## Approved Direction

Use a compact **Character Panel Shell**:

- native bronze/gold portrait-frame chrome;
- dark brown layered inset content;
- beveled character-stat section headers;
- yellow stat labels and white right-aligned values;
- subtle textured row separators;
- right-side vertical square icon tabs;
- built-in WoW icons for the portrait, tabs, settings, and minimap;
- no custom image assets or imitation skins.

## Native Forever Assets

Prefer the templates and atlases present in the Interface 16001 source:

- main shell: `PortraitFrameBaseTemplate`, with the existing safe frame fallback;
- side navigation: `LargeSideTabButtonTemplate`;
- side-tab art: `common-sidetab`, `common-sidetab-selected`, and its native icon mask supplied by the template;
- section heading: `UI-Character-Info-Title`;
- statistic row: `UI-Character-Info-Line-Bounce` or `UI-Character-Info-Line-Bounce2`;
- inner content border: `common-insideframe`;
- close control: native portrait-frame close button or `UIPanelCloseButton`;
- fonts: `GameFontNormal`, `GameFontHighlight`, and their small variants.

Every template or atlas use requires a protected fallback. A missing native asset must degrade to a visible bronze/brown frame or button without emitting a Lua error.

## Window Structure

- Keep the window movable by left-button drag.
- Keep `FULLSCREEN_DIALOG` as the preferred strata, followed by `FULLSCREEN`, `DIALOG`, and `HIGH`.
- Target a very compact footprint of approximately **420 x 430 pixels**. The right-side tabs sit outside that footprint and must not force a wider content area.
- Use 24-pixel section headers, 18-pixel statistic rows, and no more than 6 pixels between stacked sections.
- Do not reserve permanent blank space for settings, diagnostics, or controls that are currently hidden.
- Use the built-in map icon `Interface\Icons\INV_Misc_Map_01` as the portrait.
- Keep the title centered in the native title bar.
- Keep the settings panel collapsed by default.

## Navigation

Replace the top text tabs with two right-side vertical icon tabs modeled on the character panel:

1. **Overview**
   - icon: `Interface\Icons\INV_Misc_Map_01`
   - tooltip: `Overview`
2. **By Level**
   - icon: `Interface\Icons\INV_Misc_Book_09`
   - tooltip: `By Level`

Use `LargeSideTabButtonTemplate` when available. The selected tab displays the native gold selected treatment. The fallback must provide a visible square icon, gold border/highlight, selected state, and tooltip without depending on deprecated tab templates.

## Overview Panel

Replace the three sparse columns with three stacked character-stat sections:

1. Lifetime
2. This Session
3. Current Level

Each section contains one 24-pixel beveled header and four 18-pixel rows:

- Estimated Steps
- On Foot
- Swimming
- Flight Path

Labels use WoW yellow; values use white and align right. Rows use the character stat line atlas and maintain consistent spacing. The panel contains no decorative empty region.

## By Level Panel

Use the same character-stat visual language:

- one section heading labeled `Travel by Level`;
- a compact scrollable list that fills the inset;
- each level begins with a 24-pixel beveled level header;
- rows show Estimated Steps, On Foot, Swimming, and Flight Path;
- newest/highest level appears first;
- all levels remain reachable through scrolling.

## Utility Controls

- Replace the prominent red Settings button with a small native gear-icon button in the lower footer or title-adjacent utility area.
- Use `Interface\Icons\INV_Misc_Gear_01` for settings.
- Keep the settings panel hidden until requested.
- Replace the large red Reset Session button with a restrained native text button in the footer.
- Reset Session retains confirmation and baseline-reset behavior.

## Minimap Button

Replace the riding-horse icon with `Interface\Icons\Ability_Rogue_Sprint`.

Keep:

- native minimap background and tracking border;
- click to toggle;
- drag to reposition;
- persisted angle;
- drag-release click suppression;
- tooltip.

## Error and Diagnostics Presentation

- Errors remain visible inside the frame but use the character-panel inset area rather than floating over content.
- Missing native visual assets fall back silently and visibly.
- Tracking capability errors remain diagnostics, not repeated chat spam.
- Normal false predicate results from Forever APIs are normalized as false, not unavailable.

## Testing

Automated tests must verify:

- preferred and fallback portrait-frame creation;
- preferred `LargeSideTabButtonTemplate` and visible fallback;
- tab icons, tooltips, selected state, and right-side placement;
- no deprecated top-tab templates are requested;
- map portrait and sprint minimap icons;
- exactly three stacked overview sections with four rows each;
- character-stat atlases are requested with visible fallback shading;
- By Level exposes all levels in the scrollable character-stat layout;
- settings remains collapsed;
- reset remains confirmed;
- movable frame and strata order remain unchanged;
- nil WoW predicate results normalize to false and permit on-foot tracking;
- all prior tests remain green.

## Acceptance Criteria

- The addon frame immediately reads as part of the default Forever character-panel family.
- Overview and By Level use right-side icon tabs, not top text tabs.
- Coloring, shading, borders, labels, values, and row treatment mirror the supplied character panel.
- The approximately 420 x 430 layout is dense, readable, and contains no large unused black area.
- The minimap button uses a built-in movement icon.
- Opening, moving, tabbing, settings, reset, and tracking produce no Lua errors.
