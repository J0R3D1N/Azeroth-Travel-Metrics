# Lessons from Building a World of Warcraft Addon

This document captures the reusable engineering lessons learned while building
and releasing **Azeroth Travel Metrics (ATM)** for the World of Warcraft:
Forever beta. It focuses on practices that should carry forward to future WoW
addons rather than documenting ATM's features alone.

## 1. Treat the Game Client as the Final Authority

- Static API documentation, FrameXML inspection, Lua unit tests, and package
  validation are necessary, but none proves that an addon works in the client.
- Beta clients can differ from public documentation in API availability,
  template structure, return values, strata behavior, and asset rendering.
- Maintain a written in-game smoke checklist. Record only behavior actually
  observed in the client and leave everything else pending.
- Enable Lua errors during development and retain the complete error, stack,
  arguments, and locals. The first UI failure was diagnosed from the fact that
  `PanelTemplates_TabResize` expected a `Text` region that the selected beta
  template did not create.
- Never mark gameplay behavior as passing based solely on automated tests.

## 2. Put Beta Compatibility Behind One Adapter

Game API uncertainty should not spread throughout the addon.

- Keep position, map, time, movement state, character identity, and chat API
  access in one compatibility module.
- Check that optional functions exist before calling them.
- Protect beta API calls and validate their returned types and numeric values.
- Distinguish `false` from `nil`. A valid predicate returning `false` is not the
  same as an unavailable capability.
- Expose a capability report so the runtime and `/status` command can explain
  what is safe to track.
- Disable only the categories whose complete dependency set is unavailable.
  Do not fabricate state or position values to keep a feature apparently
  working.
- Throttle repeated capability messages. Diagnostics should help the player,
  not spam chat every sampling interval.

## 3. Store Authoritative Measurements, Derive Estimates

- Persist distance in the game's native unit, yards.
- Derive meters, kilometers, miles, and step estimates for presentation.
- Do not persist estimated steps when they can be recomputed. Race stride
  assumptions may improve later, and derived values should not require a data
  migration.
- Keep display formatting separate from stored values. Changing metric or
  imperial settings must not modify the underlying statistics.
- Validate totals before mutation:
  - category must be recognized;
  - distance must be finite and nonnegative;
  - additions must not overflow;
  - existing totals must be structurally valid.
- Treat zero distance as a valid no-op rather than an error.

## 4. Movement Tracking Must Prefer Missing Data over False Data

False distance is worse than an omitted sample.

- The first sample establishes a baseline and records no distance.
- Reset the baseline on login boundaries, zoning, level changes, teleports,
  and read failures.
- Compare map and instance identifiers before calculating distance.
- Reject invalid elapsed time, excessive sampling gaps, impossible speeds,
  category transitions, and contradictory movement states.
- Calculate three-dimensional distance when the client supplies altitude.
- Advance the baseline after a rejected discontinuity so one bad segment does
  not poison later samples.
- Mounted movement should remain explicitly unsupported until mounted tracking
  is designed. It must not silently become on-foot movement.
- Keep a normalized movement-segment callback containing category, distance,
  elapsed time, and source/destination samples. This provides a stable
  extension point for future mount or route-map features.
- Do not persist coordinate history unless the feature actually requires it.

## 5. SavedVariables Lifecycle Is More Subtle Than Table Initialization

Many apparent UI data-loss bugs are storage lifecycle bugs.

- `ADDON_LOADED` means SavedVariables are available; it does not necessarily
  mean character identity and world state are ready.
- Bind the active character after entering the world, not by guessing early.
- A `/reload` must preserve the current session. A full login may intentionally
  begin a new session.
- Looking up an existing character must not recreate or reset its session.
- Character recovery should use stable normalized identity and must refuse
  ambiguous matches rather than selecting one arbitrarily.
- Keep the SavedVariables table and nested character objects alive. Replacing
  tables unnecessarily can disconnect modules from the objects WoW will save.
- Closing, reopening, minimizing, or restoring a window must never initialize
  or replace persistent state.
- Test persistence using object identity as well as visible values. Equal
  values can conceal that the runtime is writing to a detached replacement
  table.
- A schema newer than the addon understands must be preserved and rejected,
  not downgraded or overwritten.
- Backfill missing known settings without overwriting valid customized values.

## 6. UI State Must Be Separate from Data State

- Frame creation should be lazy and idempotent.
- `Hide()` and `Show()` are presentation operations. They must not reset,
  recreate, or rebind data.
- Coordinate the main window and minimized HUD explicitly so only the intended
  surface is visible.
- Clear stale hover state when hiding, closing, minimizing, or restoring.
- Preserve tooltip behavior when adding hover scripts. Prefer `HookScript`
  where available and safely compose existing scripts when it is not.
- Register Escape handling once and tolerate missing or malformed beta globals.
- Keep combat interactions nonprotected unless the addon genuinely requires
  protected actions.
- Refresh the UI from a pure presentation model rather than reading and
  formatting persistent data directly in frame code.
- When refresh fails, show an explicit error state instead of blank or
  success-shaped content.

## 7. Blizzard Templates Are Useful but Not Stable Contracts

- Prefer native Blizzard templates, atlases, fonts, and controls when they work
  in the target client.
- Do not assume a similarly named Classic, Mainline, or deprecated template
  has the same child regions.
- A template can be accepted by `CreateFrame` and still be unusable later.
  Validate the expected children and setup methods.
- If native setup fails, hide the rejected control before creating a fallback.
- Fallbacks must be visibly usable, not merely avoid a Lua exception.
- Native window-size controls provided the correct Condense and Expand
  behavior, but directional-arrow fallbacks were still required.
- Do not use fullscreen strata merely to keep an addon visible. Choose the
  highest safe non-tooltip layer that stays above ordinary UI while remaining
  behind fullscreen maps, cinematics, and tooltips.

## 8. Small UI Geometry Errors Become Large Usability Problems

- Design against the actual outer frame dimensions, content inset, title bar,
  footer, scroll region, and UI scale.
- Account for every vertical gap. A few extra pixels per section can push the
  final rows or diagnostics out of a compact window.
- Do not leave a trailing gap after the final repeated card or row.
- Scrollbars belong inside the visible window and must remain readable against
  the background.
- Hide only the direct scrollbar chrome owned by the current scroll frame.
  Broad child discovery can accidentally hide unrelated controls.
- Clamp retained scroll offsets after content shrinks.
- Reuse row/card frames and hide stale rows after a shorter refresh.
- Diagnostics should consume no layout space when disabled.
- Validate at 80%, 100%, and 120% UI scale in the client.

## 9. Visual Opacity and Hierarchy Need Deliberate Design

- "Native-looking" is not the same as using a fully opaque default backdrop.
- Separate title-bar tint, body tint, borders, and inset backgrounds so the
  window has visual depth.
- Compare against a known-good addon or Blizzard panel in the same client when
  judging opacity, title height, trim, and layering.
- A transparent inner rectangle usually means the shell and content inset are
  both drawing borders while neither owns the intended background.
- Title icons should be explicitly positioned relative to title text and
  controls. Do not rely on template chrome that may cover custom artwork.
- Version text is useful in the footer because screenshots immediately show
  which build is being tested.

## 10. Tiny Runtime Icons Need Purpose-Built Artwork

- A source image that looks good at full size may be unreadable at 20-32
  pixels.
- Crop around the subject, isolate it from the background, mask transparent
  corners, and test the generated image at its actual display sizes.
- Connected-component isolation was more reliable than retaining the original
  terrain around the boot artwork.
- Test generated assets:
  - exact dimensions;
  - expected transparency;
  - absence of source-background colors;
  - correct target names and paths.
- Package only runtime assets. Keep source JPGs and comparison sheets out of
  the addon archive.

## 11. Minimap Placement Is Geometry, Not a Fixed Radius

- Use the live minimap width, height, effective scale, and shape.
- Round and square minimaps need different perimeter calculations.
- Corner and side masks require quadrant-aware placement.
- Place the icon itself outside the rim, not merely its center on the rim.
- Preserve the cursor's polar angle while dragging.
- Prefer the minimap's effective scale, then fall back safely to the parent
  scale.
- Suppress only the click generated by the drag that just ended.
- Validate several angles, shapes, and UI scales in the client.
- Persist a normalized angle rather than raw screen coordinates.

## 12. Package from Tracked Git State, Not the Working Directory

A release archive should represent a known commit, not whatever happens to be
on disk.

- Reject dirty tracked addon files.
- Reject untracked files inside the addon root.
- Build from an immutable Git snapshot.
- Reject source roots or files that are reparse points, junctions, or symbolic
  links.
- Protect against a path being swapped to a junction after validation.
- Validate every TOC file entry and required metadata field.
- Require exactly one top-level addon directory in the ZIP.
- Reject path traversal, absolute paths, drive-qualified paths, duplicate
  separators, and alternate separator tricks.
- Verify that every expected tracked addon file is present in the archive and
  no unexpected file is included.
- Explicitly reject account-specific links, ForeverSVFix data, source artwork,
  and legacy addon identity.

## 13. Reproducible ZIPs Require More Than Fixed Timestamps

Several layers of nondeterminism had to be removed.

- `git archive` ZIP timestamps depend on the enclosing commit, so an unrelated
  repository commit can change package bytes even when the addon tree is
  identical.
- Normalize entry timestamps to a fixed ZIP-safe value.
- Sort paths with `StringComparer.Ordinal`; `Sort-Object` is culture-sensitive
  and changes Unicode filename order between locales.
- .NET Framework and modern .NET can produce different Deflate bytes for the
  same input. Even `NoCompression` does not map to the same ZIP method on every
  runtime.
- For true cross-runtime reproducibility, write canonical ZIP32 stored entries:
  - deterministic ordinal order;
  - UTF-8 names;
  - fixed DOS timestamp;
  - stored, uncompressed content;
  - explicit CRC-32;
  - validated sizes and offsets;
  - no comments or extra fields.
- Test reproducibility:
  - repeated builds of one commit;
  - unrelated commits with the same addon tree;
  - Windows PowerShell and PowerShell 7;
  - multiple cultures such as `en-US` and `sv-SE`.
- Write to a unique `CreateNew` temporary file beside the final archive.
- Close and validate the temporary archive before publishing it.
- Preserve an existing valid package if a replacement build fails.
- Atomically move or replace the final archive only after validation.
- Delete only the temporary file owned by the failed invocation.

## 14. Release Identity Renames Must Be Atomic

Renaming only the title creates a confusing half-renamed addon.

Rename all active surfaces together:

- repository and addon directories;
- TOC filename and metadata;
- Lua addon name and namespace abbreviation;
- SavedVariables global;
- frame names and popup keys;
- slash registry and command;
- media filenames and runtime paths;
- chat prefixes, titles, footers, tooltips, and errors;
- package filename and root;
- tests, fixtures, scripts, README, and active smoke documentation.

Additional lessons:

- If the addon has never shipped, remove old command aliases rather than
  carrying permanent compatibility baggage.
- Historical plans may retain old terminology when rewriting them would
  falsify history.
- Add a release-identity guard that scans active file contents, filenames, and
  directory names.
- Scan every path that packaging can include, even if a directory name usually
  represents generated content.
- Keep the identity guard compatible with the oldest supported PowerShell.
- Test text, Lua, binary files, legacy filenames, legacy directories, ignored
  directories, and packaged paths.

## 15. SavedVariables Migration Must Be a Separate Fail-Closed Tool

Do not ship one-off developer migration code in the public addon when it is
not needed by users.

- Require WoW to be closed and recheck immediately before each output.
- Open the source with sharing that blocks writes and deletion for the full
  migration.
- Use strict UTF-8 decoding and preserve the original BOM state.
- Change only the equal-length ASCII root token so all remaining bytes stay
  identical.
- Lex Lua sufficiently to ignore root-like text in:
  - line comments;
  - multiline comments;
  - quoted strings;
  - long strings, including equal-delimited forms.
- Fail closed on unterminated lexical constructs.
- Require exactly one top-level legacy root assignment.
- Reject malformed comparison or multiple-equals forms.
- Reject any pre-existing top-level destination root; otherwise migration can
  produce two assignments and Lua will silently let the later one win.
- Refuse to overwrite an existing destination or backup.
- Create and verify a byte-identical backup before creating the destination.
- Use exclusive `CreateNew` writes.
- Remove only invocation-owned, unverified partial outputs after failure.
- Preserve a verified backup if destination creation later fails.
- Report hashes derived from verified byte snapshots, not from a path that may
  have changed.
- Test missing files, malformed roots, comments/strings, invalid UTF-8, BOM and
  no-BOM input, Unicode payloads, collisions, process races, partial writes,
  verification failures, source locking, and hash reporting.

## 16. A SavedVariables Hash Is Not Stable After Gameplay

- The migrated file can be byte-identical before first launch.
- After WoW runs, it can reorder table keys, update sessions and diagnostics,
  and record new distance. The hash will legitimately change.
- Do not require the post-game hash to match the pre-launch migration hash.
- After smoke testing, validate:
  - exactly one expected root;
  - supported schema version;
  - expected character records;
  - preservation of lifetime and per-level values;
  - plausible new session and diagnostic changes;
  - equality between the active file and linked restore path.
- Preserve the pre-launch `.bak`, migration backup, and retired legacy file for
  rollback and forensic comparison.

## 17. Installation and ForeverSVFix Have a Required Order

For the Forever beta environment used by ATM:

1. Close WoW. Never terminate it automatically.
2. Validate and extract the clean package to a temporary directory.
3. Confirm one expected addon root and TOC before modifying the installation.
4. Replace only the exact addon directory; never use broad wildcards.
5. Remove only the exact obsolete addon directory.
6. Reapply ForeverSVFix after replacing an addon folder or TOC.
7. Run ForeverSVFix `doctor`.
8. Require:

   ```text
   Active installation checks: OK
   No repair needed.
   ```

9. Confirm the generated restore entry follows `Core.lua`.
10. Confirm active and linked SavedVariables hashes match.
11. Only then launch WoW.

Keep rollback copies until the replacement and doctor checks succeed.

## 18. Test the Failure Paths, Not Just the Feature

The most valuable tests often came from review findings.

- Subscriber callbacks that throw must not abort tracking.
- Storage mutation failures must not emit a successful segment.
- Missing APIs, nil returns, invalid numbers, NaN, and exceptions all need
  fixtures.
- UI template rejection, missing methods, malformed globals, absent atlases,
  and fallback rendering need tests.
- Package tests should attack traversal, reparse points, dirty state,
  untracked files, source swaps, culture, runtime, and partial writes.
- Migration tests should inject process changes, write failures, verification
  failures, malformed Lua, collisions, and existing destination roots.
- A regression test is only trustworthy after observing it fail against the
  broken implementation.

## 19. Review in Layers

A productive release workflow used distinct gates:

1. Implement with test-driven development.
2. Review against the exact specification.
3. Review code quality and operational safety.
4. Fix every Critical or Important finding.
5. Re-run the appropriate reviewer after each fix.
6. Run a final whole-release review.
7. Run fresh end-to-end verification before claiming completion.

Spec review catches missing requirements. Quality review catches unsafe
implementations that technically satisfy the written steps. Both are needed.

## 20. Practical Rules for Future WoW Addons

### Always

- Discover the live client's Interface number.
- Keep beta API calls behind an adapter.
- Store authoritative data and derive presentation values.
- Reset movement baselines across discontinuities.
- Separate UI visibility from persistence lifecycle.
- Test frame-template fallbacks.
- Verify UI at multiple scales in the client.
- Package from clean tracked Git state.
- Produce and validate one exact addon-root archive.
- Keep WoW closed during install and SavedVariables operations.
- Preserve backups and verify hashes.
- Record manual smoke evidence separately from automated evidence.

### Never

- Invent movement state when an API is missing.
- Treat unavailable data as zero movement.
- Add teleport or zoning bridges to totals.
- Reinitialize persistent state when opening a window.
- Assume a Blizzard template has the regions another client version has.
- Put the minimap icon center on the rim and call it outside.
- Package the live working directory or account-specific links.
- Overwrite SavedVariables or backups.
- Normalize encoding or line endings during migration.
- Trust a post-game SavedVariables hash to equal the pre-launch hash.
- Claim an in-game scenario passed because unit tests passed.
- Publish a release archive directly to its final path before validation.

## 21. Reusable Release Checklist

1. Run asset generation tests.
2. Run all Lua tests.
3. Run package safety and reproducibility tests.
4. Run migration tests, if applicable.
5. Run release-identity tests.
6. Build the package under every supported packaging runtime.
7. Confirm package hashes are identical.
8. Inspect archive paths and content independently.
9. Confirm WoW is closed.
10. Back up or migrate SavedVariables with fail-closed tooling.
11. Install only the validated package.
12. Reapply persistence/link tooling such as ForeverSVFix.
13. Run its health check.
14. Confirm active and linked data match.
15. Perform the in-game smoke checklist.
16. Record only observed results.
17. Archive legacy data only after successful confirmation.
18. Re-run automated validation.
19. Commit release evidence.
20. Push and verify the remote commit.

