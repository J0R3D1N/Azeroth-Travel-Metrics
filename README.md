# Azeroth Travel Metrics

Azeroth Travel Metrics is a dependency-free addon for the **World of Warcraft: Forever beta**. It records travel distance and estimates race-scaled on-foot steps while keeping the underlying totals authoritative in yards.

The WoW AddOns menu lists this build as **Azeroth Travel Metrics - WoW: Forever (beta)** so it cannot be confused with a release for another client. The UI footer identifies the release as **ATM v1.0.0-beta**.

This repository produces a beta candidate. Automated validation does not replace the pending in-game checks in [`docs/BETA-SMOKE-TESTS.md`](docs/BETA-SMOKE-TESTS.md).

## Features

- Estimated on-foot steps using a race-specific stride length, with a neutral fallback for unknown races.
- Separate on-foot, swimming, and flight-path (taxi) distance.
- Lifetime, current-session, and per-level statistics.
- Metric display by default, with an imperial option.
- Compact, movable native UI with Overview and By Level tabs.
- Regular and HUD windows stay above ordinary world/HUD content but behind fullscreen maps and cinematics.
- Escape closes the regular addon window.
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
   <World of Warcraft>\_classic_beta_\Interface\AddOns\AzerothTravelMetrics\
   ```

4. Confirm that folder directly contains `AzerothTravelMetrics.toc`; do not leave an extra archive directory level.
5. Enable **Azeroth Travel Metrics - WoW: Forever (beta)** in the character-select AddOns list.

Do not overwrite an existing `AzerothTravelMetrics` directory without first preserving or intentionally replacing it.

After replacing the installed addon folder or TOC, keep WoW closed, reapply ForeverSVFix, and then run its `doctor` command before launching WoW.

## Controls

`/atm` is the only slash command:

| Command | Action |
|---|---|
| `/atm` or `/atm show` | Open or close the statistics window. |
| `/atm reset session` | Open a confirmation before resetting current-session totals. |
| `/atm units metric` | Use meters and kilometers. |
| `/atm units imperial` | Use yards and miles. |
| `/atm diagnostics on` | Show diagnostic counters in the main window. |
| `/atm diagnostics off` | Hide diagnostic counters. |
| `/atm status` | Print capability state and diagnostic counters to chat. |

The main window can be moved by left-dragging it. Left-click the minimap launcher to always open the regular panel; if the minimized HUD is visible, the regular panel replaces it. The launcher does not toggle the regular panel closed. Drag the launcher to reposition it. Use **Settings** in the main window for units, minimap visibility, and diagnostic visibility.

## Data and reset behavior

`AzerothTravelMetricsDB` is the account SavedVariables table. It stores settings and per-character lifetime, session, and level totals across `/reload`. Lifetime and level totals also persist across logout.

The current session is reset on a full character login or when **Reset Session** is confirmed. `/reload` preserves the active session. A manual session reset does not erase lifetime totals or per-level history. Level-up starts or selects the new level bucket while preserving earlier levels.

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
.\tools\Package-Addon.ps1 -Version '1.0.0-beta'
```

Packaging reruns the Lua tests, validates required TOC metadata and file entries, recreates only `artifacts\AzerothTravelMetrics`, writes `artifacts\AzerothTravelMetrics-1.0.0-beta.zip`, and verifies that every archive entry is beneath one `AzerothTravelMetrics` top-level directory.

The clean package intentionally excludes `X-ForeverSVFix` markers, `ForeverSVFixData`, generated files, and account-specific junctions. After replacing an installed addon folder or TOC during development, keep WoW closed, reapply ForeverSVFix, and run its `doctor` command before launching WoW.

### Icon assets

The editable source JPGs live in `artwork/source/`. The small title and
minimap badge is generated from `azeroth_travel_metrics.jpg`; the Overview
and By Level tab sources remain `overview_icon.jpg` and `by_level_icon.jpg`.
Regenerate the three 64 x 64 WoW runtime textures with:

```powershell
python .\tools\Build-IconAssets.py
```

The distribution package includes only the three
`AzerothTravelMetrics/Media/*.tga` outputs. Source JPGs and the
`tab_iconography.jpg` comparison sheet are not packaged.

## Beta limitations and direction

Tracking depends on the Forever beta exposing usable position, map, timer, taxi, swimming, mounted, and falling-state APIs. Missing or malformed capabilities appear through `/atm status` and optional diagnostics; affected samples are excluded. Zoning, portals, hearths, teleports, instances, long sample gaps, implausible speeds, and unsupported state transitions are rejected to avoid false distance.

Future work may revisit mounted travel and a breadcrumb or route-map view after beta APIs and gameplay behavior are understood. Neither is promised for a particular release.
