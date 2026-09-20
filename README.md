# Azeroth Travel Tracker

Azeroth Travel Tracker is a dependency-free addon for the **World of Warcraft: Forever beta**. It records travel distance and estimates race-scaled on-foot steps while keeping the underlying totals authoritative in yards.

This repository produces a beta candidate. Automated validation does not replace the pending in-game checks in [`docs/BETA-SMOKE-TESTS.md`](docs/BETA-SMOKE-TESTS.md).

## Features

- Estimated on-foot steps using a race-specific stride length, with a neutral fallback for unknown races.
- Separate on-foot, swimming, and flight-path (taxi) distance.
- Lifetime, current-session, and per-level statistics.
- Metric display by default, with an imperial option.
- Compact, movable native UI with Overview and By Level tabs.
- The highest safe non-tooltip frame strata available, preferring `FULLSCREEN_DIALOG`.
- A draggable minimap launcher and a compact settings panel hidden until requested.

Mounted distance is intentionally excluded. A route map or breadcrumb trail is deferred and is not part of this beta.

## Beta compatibility

The current Forever beta installation used for packaging reported build `1.60.1.69913` and Interface `16001`. The addon TOC must match the highest numeric `## Interface` value found in the beta's installed addon TOCs.

Discover the highest installed Interface value:

```powershell
$addons = 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns'
Get-ChildItem -LiteralPath $addons -Filter '*.toc' -File -Recurse |
    Select-String -Pattern '^## Interface:\s*(\d+)\s*$' |
    ForEach-Object { [int]$_.Matches[0].Groups[1].Value } |
    Measure-Object -Maximum
```

Update the addon TOC from an installed beta:

```powershell
.\tools\Set-InterfaceVersion.ps1 `
    -BetaAddOnsPath 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns'
```

The beta may omit or change movement-state and position APIs. The addon probes required capabilities, rejects unsupported samples rather than inventing distance, and exposes capability and rejection diagnostics. Static API or template inspection is useful evidence but does not prove gameplay behavior.

## Installation

1. Close World of Warcraft before replacing an existing addon installation.
2. Extract the release archive into the Forever beta AddOns directory, normally:

   ```text
   <World of Warcraft>\_classic_beta_\Interface\AddOns\
   ```

3. Confirm the resulting folder is exactly:

   ```text
   <World of Warcraft>\_classic_beta_\Interface\AddOns\AzerothTravelTracker\
   ```

4. Confirm that folder directly contains `AzerothTravelTracker.toc`; do not leave an extra archive directory level.
5. Enable **Azeroth Travel Tracker** in the character-select AddOns list.

Do not overwrite an existing `AzerothTravelTracker` directory without first preserving or intentionally replacing it.

## Controls

Both `/att` and `/azerothtraveltracker` accept the same commands:

| Command | Action |
|---|---|
| `/att` or `/att show` | Open or close the statistics window. |
| `/att reset session` | Open a confirmation before resetting current-session totals. |
| `/att units metric` | Use meters and kilometers. |
| `/att units imperial` | Use yards and miles. |
| `/att diagnostics on` | Show diagnostic counters in the main window. |
| `/att diagnostics off` | Hide diagnostic counters. |
| `/att status` | Print capability state and diagnostic counters to chat. |

The main window can be moved by left-dragging it. Left-click the minimap launcher to toggle the window and drag the launcher to reposition it. Use **Settings** in the main window for units, minimap visibility, and diagnostic visibility.

## Data and reset behavior

`AzerothTravelTrackerDB` is the account SavedVariables table. It stores settings and per-character lifetime and level totals across logout and `/reload`.

The current session is reset when the character is initialized on login/reload, or when **Reset Session** is confirmed. A manual session reset does not erase lifetime totals or per-level history. Level-up starts or selects the new level bucket while preserving earlier levels.

Distances are accumulated internally in yards. Unit selection changes display formatting only. Step counts are estimates derived from on-foot distance and the character race; swimming and taxi distance do not produce steps.

## Tests and packaging

Run the Lua suite:

```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') +
    ';' +
    [System.Environment]::GetEnvironmentVariable('Path','User')
lua .\tests\run.lua
```

Run the packaging validation fixtures:

```powershell
.\tests\Test-PackageAddon.ps1
```

Build the beta candidate:

```powershell
.\tools\Package-Addon.ps1
```

Or specify another TOC/package version:

```powershell
.\tools\Package-Addon.ps1 -Version '0.1.0-beta'
```

Packaging reruns the Lua tests, validates required TOC metadata and file entries, recreates only `artifacts\AzerothTravelTracker`, writes `artifacts\AzerothTravelTracker-<version>.zip`, and verifies that every archive entry is beneath one `AzerothTravelTracker` top-level directory.

## Beta limitations and direction

Tracking depends on the Forever beta exposing usable position, map, timer, taxi, swimming, mounted, and falling-state APIs. Missing or malformed capabilities appear through `/att status` and optional diagnostics; affected samples are excluded. Zoning, portals, hearths, teleports, instances, long sample gaps, implausible speeds, and unsupported state transitions are rejected to avoid false distance.

Future work may revisit mounted travel and a breadcrumb or route-map view after beta APIs and gameplay behavior are understood. Neither is promised for a particular release.
