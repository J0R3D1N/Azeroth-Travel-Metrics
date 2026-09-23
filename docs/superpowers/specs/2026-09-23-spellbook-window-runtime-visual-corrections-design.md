# Spellbook Window Runtime Visual Corrections

## Context

The second in-game candidate exposed three issues that repository tests could not
show:

1. The `spellbook-page-condensed-c60` atlas has a transparent decorative band at
   its top. ATM anchored both the atlas and its content to the same rectangle,
   so the native portrait frame's rock background showed through beneath the
   tabs and the Lifetime heading landed in the transparent band.
2. Dark parchment text retained the default Blizzard font shadows and used small
   font objects, producing muddy, hard-to-read lettering against the textured
   page.
3. ATM placed replacement title controls at frame levels 120-123, while the
   native `PortraitFrameTemplate` title chrome and controls use frame levels
   around 510. The native chrome therefore covered most of ATM's controls,
   leaving them visually below the title bar.

## Considered Approaches

### 1. Crop the parchment atlas

Crop the atlas texture coordinates to remove its transparent top band.

This would eliminate the exposed background, but it would distort or remove the
page's decorative edges and depends on hard-coded texture-coordinate estimates.

### 2. Cover the transparent band with a flat parchment color

Place a tan texture behind the page atlas.

This is simple, but the flat strip would not match the parchment texture and
would remain visibly artificial.

### 3. Separate page art from content geometry

Extend only the parchment art upward behind the tabs while leaving the content
and footer bounds unchanged. The atlas's transparent band then occupies the tab
area, and its opaque parchment begins directly below the tabs.

This preserves the native art without cropping and does not disturb panel or
footer layout. This is the selected approach.

## Design

### Parchment art

Create a dedicated page-art frame whose top begins 34 pixels above the existing
content frame and whose bottom remains aligned with the existing content frame.
Render `spellbook-page-condensed-c60` on that frame. Keep the Overview, By Level,
Settings, and error panels anchored to the existing content frame.

The visible parchment must begin immediately below the horizontal tabs. No
native rock-texture strip may remain between the tabs and parchment. The
Lifetime heading must sit fully on the opaque page.

### Typography

Use regular Blizzard game-font objects for section headings, row labels, and
values instead of the small variants. Preserve the existing dark-brown palette,
but explicitly set every parchment font string's shadow offset to zero, matching
Blizzard's own dark spellbook text treatment.

The existing row count and section structure remain unchanged. Text must not
overlap, clip, or change the displayed metrics.

### Title controls

For the native portrait-frame path:

- retain and show `frame.CloseButton`;
- attach ATM's close behavior to that native button;
- parent the minimize control directly to the main frame;
- place it immediately left of the native close button;
- raise it to the native title-control level (at least 510).

For the fallback non-native frame path, retain ATM-owned controls in the custom
title region.

Both controls must be fully inside the title bar, visible, clickable, and above
the NineSlice/title chrome.

## Testing

Automated tests will verify:

- page art is hosted by a separate frame that extends above content while
  sharing its bottom boundary;
- content-panel geometry and footer clearance remain unchanged;
- parchment fonts use the regular font objects and have zero shadow offsets;
- the native close button is reused rather than hidden;
- the native minimize control is parented to the main frame, anchored beside the
  close button, and raised above native chrome;
- fallback-frame controls retain their existing behavior;
- all existing UI, packaging, identity, and TOC checks continue to pass.

The in-game smoke gate is:

1. no dark rock strip between tabs and parchment;
2. Lifetime is fully visible;
3. all metric text is comfortably readable;
4. minimize and close are fully inside the title bar;
5. the version footer remains unobscured.

## Scope

This correction changes only visual geometry and title-control placement. It
does not change travel calculations, saved data, tab behavior, reset behavior,
window dimensions, or merge status.
