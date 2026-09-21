# Total Distance Summary Design

## Goal

Show the combined tracked distance for every statistics scope without changing
the saved-data schema or enlarging the compact main window.

## Calculation

For each lifetime, current-session, and character-level totals table:

```text
total distance = on-foot distance + swimming distance + flight-path distance
```

The calculation uses the existing authoritative values stored in WoW yards.
`UIModel` exposes both `totalYards` and a `total` display string formatted with
the active metric or imperial setting. Estimated steps remain derived only from
on-foot distance.

## Presentation

Add a gold-accented **Total Distance** footer after the Flight Path row in:

- Lifetime;
- This Session;
- Current Level;
- every card in the By Level view.

The footer is visually distinct from the alternating statistic rows but remains
inside each Character Panel-style section. The regular window remains
approximately 420 x 430 pixels. Section and level-card geometry may be
rebalanced within that shell to make room; the window itself must not grow.

The minimized live HUD is unchanged because its purpose is a minimal breakdown
of current-session movement categories.

## Data and Compatibility

Total distance is derived at presentation time. Existing SavedVariables require
no migration, and no new persisted field is introduced. Invalid component
totals continue to produce the existing `invalidStatistics` model error rather
than a partial or success-shaped total.

## Testing

Automated coverage will verify:

- lifetime, session, and current-level raw totals;
- metric and imperial formatting;
- By Level totals for every row;
- unit changes preserve raw totals and change only display strings;
- Overview and By Level sections expose the footer without overlap;
- existing estimated-step semantics remain on-foot-only.

Manual beta validation will confirm the footer is readable at 80%, 100%, and
120% UI scale and that the 420 x 430 panel remains compact and unclipped.
