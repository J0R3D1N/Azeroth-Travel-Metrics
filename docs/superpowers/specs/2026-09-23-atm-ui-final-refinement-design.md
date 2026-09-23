# ATM UI Final Refinement Design

## Goal

Finish the in-game candidate without changing the accepted compact shell,
right-side tab layout, travel totals, SavedVariables schema, or compact HUD.

This pass addresses four beta-client findings:

1. the main-window Minimize click target works but has no visible artwork;
2. Reset Session appears on every content tab instead of only Settings;
3. normal `unsupportedState` sample rejections produce a misleading
   "Tracking unavailable" login warning;
4. the Distance Units controls extend beyond the Settings interior.

## Selected Approach

Use ATM-owned title-control artwork for Minimize instead of relying on the
Forever client to render Blizzard's red minimize template. Keep the current
native Close button and place a compact ATM Minimize control immediately to
its left.

Treat Reset Session as a Settings action by controlling its visibility with
the active tab. Keep its existing footer position, confirmation dialog, and
storage behavior.

Keep `unsupportedState` as a diagnostic rejection reason, but remove it from
the reasons that announce tracking failure in chat. The rejection is expected
when the character is mounted, airborne, in a vehicle, or transitioning
between supported travel states.

Give the Metric and Imperial controls explicit positions and bounded labels
inside the first Settings row instead of relying on native checkbox label
placement near the right edge.

## Main Minimize Control

Create the main Minimize button with `UITheme.CreateTitleControl`:

- size `20 x 20`;
- parented to the title-bar shell;
- anchored immediately left of Close without overlap;
- raised above the title region and portrait-frame chrome;
- uses ATM's visible background, highlight, and minimize glyph textures;
- retains the current tooltip and `UI.Minimize()` click behavior.

This deliberately replaces `UIPanelHideButtonNoScripts` and its red-button
atlases for the main window. Two in-game candidates showed that this native
template can remain visually absent in WoW Forever even when the frame,
textures, atlas names, and click handler exist. The ATM-owned glyph path is
already used successfully by the compact HUD and does not depend on client
template artwork.

The native Close button remains unchanged.

## Settings-Only Reset Session

`setPanelVisibility` owns Reset Session visibility:

- Settings selected: show Reset Session;
- Overview selected: hide Reset Session;
- By Level selected: hide Reset Session;
- pending statistics error on a non-Settings tab: keep Reset Session hidden.

The button stays in the existing bottom-left footer position. Its click
handler, confirmation copy, session reset, baseline reset, and error handling
do not change.

The version label remains visible on every tab.

## Distance Units Geometry

The first Settings row keeps the `Distance Units` label at the left. Metric
and Imperial remain mutually exclusive checkboxes on the right, but their
checkboxes and text receive explicit horizontal bounds:

- each checkbox stays `16 x 16`;
- each text label is re-anchored to its checkbox;
- each label receives a fixed width sufficient for its text;
- the Imperial label's right edge remains inside the row's right inset;
- the Metric and Imperial groups do not overlap each other or the row label.

Minimap Button and Diagnostics controls keep their current behavior and row
positions.

## Tracking Warning Behavior

`unsupportedState` remains a normal return value from movement classification
and segment construction. The tracker continues to increment its diagnostic
counter and advance its sample baseline.

Core no longer includes `unsupportedState` in `REPORTABLE_REASONS`. Therefore:

- mounted, airborne, vehicle, or state-transition samples remain uncounted;
- diagnostics can still show the rejection count;
- no "Tracking unavailable: unsupportedState" message appears at login or
  during normal play;
- genuine availability failures such as `positionUnavailable`,
  `mapUnavailable`, `timeUnavailable`, `sampleUnavailable`, and
  `sampleFailed` remain reportable once.

No travel category or classification policy changes in this pass.

## Testing

Test-driven implementation must prove:

- the main Minimize control is an ATM title control with visible glyph
  textures, a `20 x 20` click target, correct title-bar placement, and working
  Minimize behavior;
- the implementation no longer depends on
  `UIPanelHideButtonNoScripts` for the main Minimize control;
- Reset Session is shown on Settings and hidden on Overview, By Level, and
  non-Settings error surfaces;
- Metric and Imperial checkbox and label bounds remain inside their Settings
  row and do not overlap;
- `unsupportedState` is retained in diagnostics but produces no chat warning;
- genuine reportable capability failures still print once;
- all existing Lua, package, release-identity, TOC, deployment, and
  ForeverSVFix checks remain green.

## In-Game Acceptance

1. Minimize is visibly rendered immediately left of Close and still opens the
   compact HUD.
2. Reset Session appears only on Settings.
3. Logging in does not print "Tracking unavailable: unsupportedState".
4. Metric and Imperial remain fully inside the Settings frame.
5. Overview, By Level, Settings, Close, compact HUD controls, diagnostics, and
   session reset otherwise behave as before.
