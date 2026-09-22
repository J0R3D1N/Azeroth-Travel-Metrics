# Azeroth Travel Metrics Beta Smoke Tests

This checklist is the manual release gate for the World of Warcraft: Forever beta. Automated tests and static API inspection do not count as observing gameplay.

## Test record

- **Beta build:** `1.60.1.69913`
- **Interface:** `16001`
- **Beta AddOns path:** `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns`
- **Addon folder:** `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelMetrics`
- **Tester/date:** Not run in this automated session

Before testing, replace the build and Interface values above if the beta has updated. For each scenario, perform the listed steps in the running beta client, replace **Observed** with concise factual evidence, and change **Result** to `PASS` or `FAIL`. Keep `PENDING` when the scenario was not fully observed. For failures, include the character, zone, relevant `/atm status` output, Lua error text, and reproduction steps.

| Scenario | Steps | Expected | Observed | Result |
|---|---|---|---|---|
| Fresh install | Install the packaged `AzerothTravelMetrics` folder, enable it at character select, and log in on a character with no prior `AzerothTravelMetricsDB`. | Addon loads without Lua errors; default settings are metric, minimap shown, diagnostics hidden; lifetime/session/current-level values begin coherently. | Not run in this automated session | PENDING |
| Login/logout and `/reload` | Record totals, run `/reload`, then log out and back in; also cross a zone boundary without reloading. | `/reload` preserves This Session, Lifetime, By Level totals, and settings without adding a bridge segment. A full character login starts a fresh This Session while preserving Lifetime, By Level totals, and settings. Repeated zoning does not reset the session. | 2026-09-21: Full Windows client restart succeeded after applying ForeverSVFix v1.0.2; the addon loaded with the restored Lifetime and By Level data intact. `/reload`, session-reset, relog, and zoning checks remain pending. | PARTIAL |
| Relog character recovery | On a character with nonzero Lifetime, This Session, and Current Level totals, record the character and totals, log out, log back in, and inspect the character list and panel. | The same saved character record is recovered with unchanged Lifetime and By Level totals; This Session is fresh at zero; no duplicate empty character record appears. | PENDING | PENDING |
| Walking/running | Walk and run measured routes while unmounted, then open `/atm`. | On-foot yards increase; estimated steps increase using the character race; swimming and taxi totals do not increase. | Not run in this automated session | PENDING |
| Idle | Remain stationary longer than several sampling intervals. | No distance or estimated steps are added. | Not run in this automated session | PENDING |
| Swimming entry/exit | Walk into swimmable water, swim, then return to land. | Swimming distance increases only during stable swimming samples; category transitions do not create jump distance. | Not run in this automated session | PENDING |
| Completed flight path | Take a flight path from takeoff through landing. | Taxi distance increases during the stable taxi portion; on-foot and swimming totals do not increase from the flight. | Not run in this automated session | PENDING |
| Interrupted flight path | Begin a flight path and interrupt it if the beta permits, or disconnect/reload during travel. | Recorded taxi distance remains plausible; interruption does not create a bridge or large false segment. | Not run in this automated session | PENDING |
| Zoning, portal, hearth, teleport, and instance transitions | Exercise each available transition and inspect totals immediately before and after. | Map/instance discontinuities and implausible jumps are excluded; normal tracking resumes from a new baseline. | Not run in this automated session | PENDING |
| Level-up rollover | Record current-level totals, gain a level, move normally, and inspect Overview and By Level. | Previous level totals remain; the new level bucket receives subsequent distance; lifetime/session totals continue. | Not run in this automated session | PENDING |
| Mounted movement excluded | Travel while mounted outside a taxi, dismount, then walk. | Mounted distance is excluded; normal on-foot tracking resumes without a bridge segment. | Not run in this automated session | PENDING |
| Minimap and slash controls | Click and drag the minimap launcher; run `/atm`, reset, units, diagnostics, and status commands. | The `/atm` command works; launcher position and visibility behave correctly; reset requires confirmation; invalid command values show usage; status prints capabilities/diagnostics. | Not run in this automated session | PENDING |
| Login tracking readiness | Log in, then run `/reload`, while watching chat for addon diagnostics. | Neither initialization prints `Tracking unavailable: unsupported state`; tracking begins normally. | PENDING | PENDING |
| Character panel shell | Open the regular panel and inspect the outer trim, title area, controls, and content background. | The shell has Public Library-style warm translucency; the gold title is correctly sized; the Sprint icon, minimize, close, and `ATM v1.0.0-beta` footer are visible; no transparent inner rectangle remains. | PENDING | PENDING |
| Close and reopen data preservation | Open the regular panel and record the visible Lifetime, This Session, and Current Level totals. Close it, move a known short route while the panel is hidden, then reopen it from the minimap launcher. | The panel reopens with the original totals plus the expected hidden-route increments; no values reset, and no bridge distance is added between the pre-close position and the hidden route. | PENDING | PENDING |
| Right-side icon tabs | Inspect and click Overview and By Level, then hover each tab. | Both tabs are right-side icons with the correct tooltip and a clear selected state. | PENDING | PENDING |
| Overview readability at 80/100/120% UI scale | At each UI scale, inspect all three Overview sections and each section's four statistic rows. | Every section and row remains readable without clipping, overlap, or missing values. | PENDING | PENDING |
| Total distance summaries | Compare each Lifetime, This Session, Current Level, and By Level total against the visible On Foot + Swimming + Flight Path values in metric and imperial. | Every Total Distance footer equals the three component distances, switches units, is gold/readable, and does not clip or enlarge the 420x430 panel at 80/100/120% UI scale. | PENDING | PENDING |
| By Level scrolling | Populate or use data containing multiple levels, open By Level, and scroll from newest to oldest. | Scrolling exposes every recorded level and all four values for each level. | PENDING | PENDING |
| Collapsed settings and footer | Open the regular panel without expanding settings, then inspect and use the footer controls. | Settings starts collapsed; footer controls remain usable and do not overlap content. | PENDING | PENDING |
| Minimized session HUD | Click minimize from the regular panel. | A translucent 220 x 96 HUD opens with a dedicated control row above a 2 x 2 grid; Restore and Close do not cover labels or values. | PENDING | PENDING |
| Live HUD values | With the HUD visible, walk on foot, swim, and take a flight path. | The corresponding steps, on-foot, swim, and taxi values update live and independently. | PENDING | PENDING |
| HUD persistence and controls | Drag the HUD, `/reload`, hover it, use Restore and Close, minimize again, then click the minimap launcher. | Position persists; hover reveals working Restore and Close controls; minimap click hides the HUD and opens the regular panel. | PENDING | PENDING |
| Compact number formatting | Accumulate or use approved test data around 1,000 meters and across K, M, and B magnitude boundaries. | Metric distance switches from meters to kilometers at 1,000 m; large step and distance values use deterministic K/M/B suffixes without clipping. | PENDING | PENDING |
| Sprint minimap launcher | Inspect the minimap launcher, click it from closed and minimized states, and drag it to a new position. | The sprint icon renders; clicks always open the regular panel; dragging and persisted positioning remain correct. | PENDING | PENDING |
| Minimap launcher outside rim | At 80%, 100%, and 120% UI scale, inspect the sprint button at several saved angles, then drag it around the full perimeter on round, square, and available corner/side minimap shapes. | The sprint icon itself clears the actual minimap rim and renders above its border at every angle, shape, and scale; dragging preserves the cursor's polar angle and the saved position survives `/reload`. | PENDING | PENDING |
| Character panel interaction error sweep | Open and move the panel, switch tabs, expand/change settings, reset with confirmation, minimize, and restore. | No Lua errors occur during any interaction. | PENDING | PENDING |
| Movable main window | Open the main window and left-drag it from multiple points. | Window moves smoothly without blocking its buttons, tabs, or close control. | Not run in this automated session | PENDING |
| Compact layout at 80/100/120% UI scale | At each UI scale, inspect Overview, By Level, settings, reset confirmation, and scroll behavior. | Content remains readable, uncrowded, inside the frame, and usable without overlap or clipping. | Not run in this automated session | PENDING |
| Surface layering and Escape | Open the tracker and HUD over ordinary world/HUD content, open the fullscreen world map, play a cinematic, hover controls for tooltips, and press Escape with the regular tracker open. | Tracker and HUD remain usable above ordinary world/HUD content and below tooltips, but render behind the fullscreen world map and cinematics; Escape closes the regular tracker window. | Not run in this automated session | PENDING |
| Settings persistence | Change units, minimap visibility/position, and diagnostic visibility; `/reload` and relog. | Settings persist exactly; metric is the default only for fresh data and imperial remains selected when chosen. | Not run in this automated session | PENDING |
| Combat-safe UI | Enter combat, toggle the window, switch tabs/settings, move the frame, use the minimap launcher, and allow samples to accumulate. | No blocked-action or taint errors; controls remain usable and tracking continues. | Not run in this automated session | PENDING |
| Missing capability diagnostic | In a beta build/environment where a required capability is unavailable, or with an approved diagnostic test build, run `/atm status` and enable diagnostics. | Missing capability is reported without repeated chat spam; affected movement category is excluded rather than estimated from fabricated state. | Not run in this automated session | PENDING |

## Automated evidence

The release preparation workflow must separately record:

- `tests\run.lua` result.
- `tests\Test-PackageAddon.ps1` result, including rejection of a missing TOC file, nonnumeric Interface, and invalid zip layout.
- `tests\Test-ReleaseIdentityContent.ps1` result, covering all seven release identity regression cases.
- Standalone `tests\Test-ReleaseIdentity.ps1` result after the identity regression suite.
- `tools\Package-Addon.ps1` result and final archive path.
- Independent zip entry inspection confirming one `AzerothTravelMetrics` top-level directory in `AzerothTravelMetrics-1.0.0-beta.zip`.
- Highest installed Blizzard/addon TOC Interface value and equality with `AzerothTravelMetrics.toc`.

Run the identity checks in this order:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
```

These checks can qualify the archive as a beta candidate, but they do not change any smoke-test row from `PENDING`.
