# Azeroth Travel Metrics Release Rename Design

## Goal

Rename the unreleased addon completely from **Azeroth Travel Tracker** to
**Azeroth Travel Metrics** for its first CurseForge beta release while
preserving the developer's current local test data.

The release version is `1.0.0-beta`.

## Scope

This is an atomic identity rename. It does not change movement tracking,
distance calculations, statistics, UI behavior, or persistence semantics.

The active project identity becomes:

| Surface | New identity |
|---|---|
| Repository directory | `D:\_projects\azeroth-travel-metrics` |
| Addon directory | `AzerothTravelMetrics` |
| TOC file | `AzerothTravelMetrics.toc` |
| AddOns title | `Azeroth Travel Metrics - WoW: Forever (beta)` |
| Lua addon name | `AzerothTravelMetrics` |
| Shared namespace/local abbreviation | `ATM` |
| SavedVariables global | `AzerothTravelMetricsDB` |
| Primary slash command | `/atm` |
| Runtime logo | `ATMLogo.tga` |
| UI footer | `ATM v1.0.0-beta` |
| Package | `AzerothTravelMetrics-1.0.0-beta.zip` |

There will be no `/att` or `/azerothtraveltracker` aliases. The addon has not
been publicly released, so the distribution will not carry legacy identity or
migration code.

## Rename Boundaries

Rename all active implementation and release surfaces:

- addon folder and TOC;
- Lua addon namespace and local namespace variables;
- SavedVariables declaration and runtime global;
- named frames, popup keys, slash registry keys, and related constants;
- title, footer, tooltip, chat, error, and status text;
- runtime media names and paths;
- package scripts, package tests, fixtures, and archive roots;
- README, active smoke tests, and current release documentation;
- local repository directory.

Historical planning documents and previous design records may retain old names
when rewriting them would falsify the history of completed work. Current
release specifications, implementation plans, tests, and user-facing
documentation must use the ATM identity.

## Local-Only SavedVariables Migration

The distributed addon will be clean ATM code. Existing ATT data is migrated
only in the developer's local Forever beta installation.

With WoW closed:

1. Back up the active `AzerothTravelTracker.lua` SavedVariables file.
2. Require exactly one top-level `AzerothTravelTrackerDB =` assignment.
3. Create `AzerothTravelMetrics.lua` by changing only that assignment to
   `AzerothTravelMetricsDB =`.
4. Verify the serialized payload is otherwise byte-identical.
5. Install only the packaged `AzerothTravelMetrics` addon folder.
6. Remove only the old installed `AzerothTravelTracker` addon folder.
7. Reapply ForeverSVFix and run `doctor`.
8. Verify the new active and linked SavedVariables files match.
9. Launch ATM and confirm the existing lifetime, session, and level data.
10. After confirmation, archive the old SavedVariables file outside the
    active SavedVariables directory rather than deleting it.

Migration must stop without modifying active data when:

- WoW is running;
- the old SavedVariables file is missing or malformed;
- the expected root assignment is absent or duplicated;
- transformed payload verification fails;
- the package or install path is unexpected;
- ForeverSVFix reports an unhealthy installation.

## Packaging and Installation

The clean package has exactly one top-level `AzerothTravelMetrics` directory.
It contains the renamed TOC, Lua modules, and three runtime TGA assets. It must
not contain:

- an `AzerothTravelTracker` directory;
- ATT-named runtime files or active identifiers;
- source JPG files or reference artwork;
- ForeverSVFix markers, helper files, or account-specific links.

The install target is:

`D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics`

ForeverSVFix is reapplied only after the clean folder replacement.

## Validation

Implementation follows test-driven development. Failing tests will first
assert:

- the new TOC filename, metadata, version, SavedVariables, and load order;
- `AzerothTravelMetrics` addon loading with an `ATM` namespace;
- `AzerothTravelMetricsDB` lifecycle behavior;
- renamed frame, popup, and slash registry keys;
- `/atm` as the only registered command;
- `ATMLogo.tga` runtime use;
- the ATM package filename and archive root;
- rejection of ATT identifiers from active release surfaces;
- fail-closed local migration behavior and payload preservation.

Final automated validation requires:

- all icon asset tests passing;
- all Lua tests passing;
- all package tests passing except the existing privilege-dependent skip;
- the clean package validator passing;
- no unexpected active ATT identifiers in source, tests, tooling, README, or
  package contents.

## Release Acceptance

The `1.0.0-beta` release is ready only when:

1. The package and installed addon use the ATM identity exclusively.
2. Existing local test data loads under `AzerothTravelMetricsDB`.
3. `/atm` opens and controls the addon; old slash commands are absent.
4. The AddOns list, title bar, footer, tooltip, chat, and errors show ATM.
5. ForeverSVFix doctor reports a healthy ATM installation.
6. Launch, `/reload`, close/reopen, minimize/restore, and statistics
   persistence pass under the renamed addon.
7. The old SavedVariables file is archived only after successful in-game
   confirmation.

