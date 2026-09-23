# Travel State and Statistics Hardening Design

## Goal

Fix the three issues found in the Forever beta technical review:

1. prevent non-finite step estimates from malformed but finite SavedVariables;
2. keep mounts, flying forms, and vehicles out of on-foot totals while preserving ground and aquatic form behavior;
3. keep capability diagnostics synchronized as transient game state becomes available or unavailable.

## Travel Semantics

Classification remains based on observable movement state rather than class,
spell, or shapeshift-form identifiers:

- taxi travel is recorded as `taxi`;
- swimming, including Druid Aquatic Form, is recorded as `swimming`;
- normal ground movement, including ground Druid forms such as Cat and Bear,
  is recorded as `onFoot`;
- mounted movement is excluded;
- flying movement, including Druid Flight Form, is excluded;
- vehicle movement is excluded;
- falling and samples with unavailable or contradictory state remain excluded.

Forever exposes `IsFlying` and `UnitInVehicle`, so the compatibility adapter
will normalize those predicates alongside taxi, swimming, mounted, and falling
state. Taxi classification retains priority because a flight path can also
appear as flying.

Hard-coded form IDs are intentionally avoided. The Forever API index does not
publish stable shapeshift-form functions, and state-based classification also
handles future forms without a spell-ID table.

## Compatibility and Capability Data

`Compat.ReadSample` will include normalized `flying` and `vehicle` booleans.
The capability matrix will expose matching `flying` and `vehicle` entries and
will require them before declaring on-foot tracking ready.

Every `ReadSample` result, including essential-position failures, will expose
the capability snapshot used for that attempt. `Tracker.Sample` will forward
that snapshot as an additional return value without changing the existing
segment and reason returns. Core will update its existing shared capabilities
table after every sample, preserving table identity for the UI and minimap
contexts. `/atm status` will therefore recover without waiting for another
`PLAYER_ENTERING_WORLD`.

Capability updates remain diagnostic. They do not fabricate values or bypass
the normal movement rejection rules.

## Non-Finite Derived Statistics

`Stride.EstimateSteps` will reject invalid or overflowing calculations instead
of returning infinity. `UIModel` will treat a rejected derived value as
`invalidStatistics`, consistent with its existing handling for malformed and
overflowing category totals.

No value will be capped or silently substituted. Authoritative yard totals
remain unchanged so corrupted data is surfaced rather than rewritten.

## Error Handling

- Missing, throwing, nil, or malformed flying and vehicle predicates produce
  unavailable capabilities and an unsupported movement state.
- A taxi sample does not depend on flying or vehicle state.
- Rejected movement advances or clears the baseline according to the existing
  tracker rules, preventing bridge segments.
- Capability snapshots update even when an essential sample field is
  unavailable.
- Derived step overflow returns `invalidStatistics` through the existing UI
  error surface.

## Testing

Regression coverage will verify:

- mounted, flying-form, and vehicle samples are excluded;
- ground forms remain on-foot because they report normal ground state;
- aquatic forms remain swimming because they report swimming state;
- taxi classification wins when flying is also true;
- missing and malformed flying or vehicle APIs disable the applicable
  capability without throwing;
- samples and tracker returns carry capability snapshots on success and
  failure;
- Core refreshes the shared capability table after failure and recovery;
- extreme finite on-foot totals cannot produce `inf`, `nan`, or `infB`;
- all existing lifecycle, UI, packaging, and identity suites remain green.

In-game smoke testing should cover Cat/Bear movement, Aquatic Form, Flight
Form, a ground mount, and an available vehicle. Forever has no mounted flying,
so no mounted-flight-specific case is required.
