# UI Shell and Persistence Regression Design

## Goal

Correct the remaining tracker-window regressions by adopting the proven Azeroth
Public Library shell treatment and ensuring relogs recover lifetime and
per-level data from the correct saved character record.

## Observed Regressions

The in-client comparison shows:

- the tracker background is substantially darker and more opaque than Azeroth
  Public Library;
- the title bar is too shallow and does not use the same warm translucent
  treatment;
- the top-left addon icon is missing;
- the minimize control is not visible;
- a redundant inset border encloses a fully transparent interior region;
- after a relog, Lifetime, This Session, and Current Level display zero.

The compact 420 x 430 dimensions, right-side tabs, summary layout, Total
Distance footers, settings access, and movable HUD remain desirable.

## Root Causes

### Shell Layer Conflicts

The current window uses `PortraitFrameBaseTemplate` and then overrides parts of
its portrait, title, background, border, and control layers:

- `UI.Create` sets a portrait texture and then hides `PortraitContainer`, which
  directly removes the top-left icon;
- the custom minimize button occupies the native template title-bar region and
  is visually lost beneath or beside template artwork;
- an opaque black backing texture does not match the Public Library's warm,
  translucent backdrop;
- `common-insideframe` adds a second inset border whose center remains
  transparent, producing the unwanted inner rectangle.

Continuing to patch individual template layers would retain the source of these
conflicts.

### Early Character Identity Binding

The SavedVariables file still contains nonzero lifetime, level, and session
data under the previously selected character key. The data therefore survives
disk persistence, but the live addon selects an empty record after relog.

`Core.Initialize` currently reads character identity and constructs the
character key during `ADDON_LOADED`. In Warcraft Forever, player identity can
still be incomplete or differently formatted at that point. The successful but
unstable early value can select a new empty record; the existing retry only
handles identity calls that fail outright.

`Storage.GetCharacter` also starts a new session whenever it is called, coupling
record lookup with session lifecycle.

## Window Architecture

Replace the regular window's outer `PortraitFrameBaseTemplate` shell with a
compact `BackdropTemplate` frame. The new shell owns all visible layers and
does not depend on hidden native portrait internals.

The shell theme follows the installed Azeroth Public Library implementation:

- tooltip background and border assets for the outer backdrop;
- dark brown backdrop color near `(0.08, 0.06, 0.035, 0.95)`;
- `UI-DialogBox-Background-Dark` with warm gold vertex tint;
- a subtle vertical vignette;
- a low-alpha gold top glow;
- a light gold background texture using
  `UI-DialogBox-Gold-Background`.

The implementation must reuse Blizzard assets but remain dependency-free. If
`BackdropTemplate` is unavailable, a bare-frame fallback must still expose a
visible dark background and border.

The regular window remains 420 x 430 pixels and retains safe non-fullscreen
strata, dragging, Escape handling, right-side tabs, settings, reset controls,
and the existing content layout.

## Title Region and Controls

Use a dedicated 42–46 pixel title region:

- a framed 32–36 pixel Sprint icon in the upper-left;
- a left-aligned `Azeroth Travel Tracker` title in warm gold;
- a visible minimize button immediately left of the close button;
- a native-style red close button at the upper-right;
- controls raised above the shell's decorative textures.

The icon is explicitly created and owned by the tracker shell rather than by a
portrait template. Minimize continues to open the 220 x 96 current-session HUD.
Close only hides the regular window and must not initialize storage, select a
character, reset a session, or stop tracking.

## Content and Footer

Remove the redundant `common-insideframe` border around the entire content
surface. The summary sections keep their own Character Panel-style headers and
rows, but sit directly on the shell's warm translucent background.

Add a bottom-right version label:

```text
ATT v0.1.0-beta
```

Read the version from addon metadata through the supported client API when
available. Fall back to the current package version constant when metadata
access is unavailable or malformed. The version label uses a muted disabled
font color and must not overlap settings or reset controls.

## Persistence Lifecycle

Split core startup into two phases.

### Database Phase

On `ADDON_LOADED`:

- initialize and validate `AzerothTravelTrackerDB`;
- retain the database in core state;
- initialize UI-safe metadata that does not depend on player identity;
- do not select a character, reset a session, create a tracker, or start a
  ticker.

### Character Phase

On the first valid `PLAYER_ENTERING_WORLD` for a login:

- read stable character identity;
- resolve the existing character record;
- start a fresh This Session;
- ensure the current-level bucket;
- create the tracker and runtime UI context;
- initialize the minimap launcher;
- start one sampling ticker.

Subsequent `PLAYER_ENTERING_WORLD` events in the same addon runtime reset only
the tracker baseline and refresh capabilities. They must not create another
session or replace the selected character record.

A full login intentionally starts a new This Session. Lifetime and per-level
totals must survive every relog.

## Character Record Recovery

Character lookup first uses the canonical current name/realm key. If that key
is absent, storage searches existing records for matching normalized identity
fields before creating a new record.

Normalization is limited to key-format instability:

- trim surrounding whitespace;
- compare case-insensitively;
- normalize realm/name spacing consistently.

When a unique matching record is found, re-key that same table under the
canonical current key and remove the obsolete key. Totals, levels,
diagnostics, and `firstSeenAt` remain unchanged.

If multiple records match, do not merge them silently. Select the exact key
only or create a new record and record a diagnostic so ambiguous data is not
combined incorrectly.

Record lookup and session start become separate storage operations. Merely
retrieving or refreshing identity must never reset a session.

## Error Handling

- If SavedVariables initialization fails, preserve the original table and show
  the existing initialization error.
- If stable identity is unavailable on `PLAYER_ENTERING_WORLD`, report the
  limitation once and retry on the next entering-world event without creating
  an empty record.
- If metadata lookup fails, show the fallback version without reporting a
  tracking error.
- If a shell asset or template is unavailable, use visible color/fallback
  controls rather than transparent or missing UI.

## Testing

Automated tests will cover:

- the main shell uses the custom backdrop path rather than
  `PortraitFrameBaseTemplate`;
- Public Library-style backdrop colors, warm textures, top glow, and title
  geometry;
- explicit top-left Sprint icon;
- visible, correctly ordered minimize and close controls;
- no whole-content transparent inset border;
- metadata-derived and fallback version labels;
- close and minimap reopen preserve the same lifetime, session, and level
  tables;
- `ADDON_LOADED` initializes only the database;
- unstable early identity is not used to create a character record;
- the first valid `PLAYER_ENTERING_WORLD` restores an existing record and
  starts exactly one fresh session;
- repeated entering-world events do not reset the session;
- normalized identity-key recovery reuses and re-keys the existing record;
- ambiguous identity matches do not merge;
- Lifetime and level totals survive simulated relog initialization;
- the full existing movement, minimap, HUD, and packaging suites remain green.

Manual beta validation will compare the tracker beside Azeroth Public Library
at 80%, 100%, and 120% UI scale, then verify:

- matching background translucency and title warmth;
- visible icon, minimize, close, and version label;
- no redundant inner transparent border;
- close/reopen through the minimap preserves displayed totals;
- logout/login starts a zeroed This Session while restoring Lifetime and
  Current Level totals.
