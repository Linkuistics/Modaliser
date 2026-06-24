# responsive-columns-k30 — brief

**Kind:** node (design settled 2026-06-24; implementation in the children)

## Goal

Make the overlay distribute content into the *right number of columns for the
content*, not the maximum that fits. Today the panel grid renders three columns
where two would balance better (the user's "Search and AI fit on one column"),
and the loose top-level region never columnizes at all.

Surfaced live by the user on 2026-06-24 while reviewing the shipped overlay
(verbatim):

- "The global overlay has three panels in three columns that could be two
  columns because the Search and AI panels fit on one column."
- "When the elements are at the top level, they should distribute into columns
  if the rest of the overlay is wide enough such that it requires that."

## Diagnosis (why it over-columns today)

`.overlay` is `width: max-content`; `.panel-grid` is
`grid-template-columns: repeat(auto-fit, minmax(184px, 1fr))` capped at
`max-width: 760px`. Under max-content sizing, `auto-fit` **maximizes** the track
count — every panel gets its own column until the 760px cap. Three panels →
three columns. CSS masonry (`display: grid-lanes`, masonry-layout-k20) packs into
the *shortest lane* but only **within** the lane count auto-fit already chose; it
never **reduces** the count. The loose region (`.panel-loose`) is a single flex
column with no columnization. So this is **new logic, not a masonry bug**:
choosing *fewer* columns by content balance can't be done in pure CSS auto-fit —
it needs a measurement pass (JS, which has rendered heights), reviving the spirit
of the deleted `overlay-column-count` aspect search but for the panel grid.

## Settled design (grilled 2026-06-24, approved)

**1. Auto principle — aspect-ratio balance (JS-measured).** After the body's DOM
is built, JS measures content and picks the column count whose resulting overall
shape is closest to a **target width:height ratio** (default ≈ **1.4**), i.e.
`argmin_c |ratio(c) − target|`. This naturally covers *both* complaints: it
reduces 3→2 for short panels (3 cols is too wide/short) **and** raises 1→2+ for a
tall stack (1 col is too narrow/tall). It supersedes the CSS-intrinsic auto-fit
default for the panel grid.

**2. Override — `(screen … 'cols N)` hard pin only.** The existing DSL keyword
stays the single escape hatch: present → force exactly N columns, skip
measurement; absent → auto-balance is the default. No `max-cols` cap, no target
tuning, no per-screen aspect knob (target ≈ 1.4 is a fixed constant). `'layout
'grid` (deterministic aligned placement) is unchanged and orthogonal — balance
still chooses the count; `'layout` only chooses lanes-vs-aligned packing.

**3. Shared width, independent counts (panels vs loose).** The overlay has **one
content width W**, but the two regions pack into **different** column counts
because their natural item widths differ (a loose key-row ≈ keycap+label is
narrower than a panel card with its header band + padding). Concretely:
  - Balance the **panel grid** first (principle 1) → that fixes the panel column
    count and the panel grid's natural width `Wp`.
  - `W = max(Wp, Wb)` where `Wb` is the widest **full-width loose block**
    (window-diagram / live windows-list), if any. (Global screen: no block →
    `W = Wp`. Windows sub-screen: no panels → `W = Wb`.)
  - The **loose rows** then fill `W` with **their own** column count (more
    columns than the panels, since rows are narrower). Left/right edges line up;
    counts differ. This is "distribute into columns if the rest of the overlay is
    wide enough" — loose rows fill the width the rest established.

**4. Loose region — rows columnize, blocks stay full-width.** Only the bare
key-rows + folded drill-rows flow into columns. Loose **blocks** (window-diagram,
live windows-list) keep full width — they need horizontal room (original design:
"compact groups tile into columns; dynamic lists get horizontal room"). So
`.panel-loose` becomes: full-width blocks interleaved with row-grid runs, in
declaration order.

### Why not an ADR

This is recorded as a **design-spec amendment** (§4 of the spec), consistent with
how the sibling masonry-layout-k20 renderer change was recorded — not a fresh
ADR. It amends the spec's "Column count is CSS-intrinsic auto-fit" line, not a
load-bearing cross-cutting decision.

## Children (ordered — child 1 establishes W, child 2 consumes it)

1. **panel-aspect-balance-k32** — the core: JS aspect-balance for the panel grid
   (principles 1+2). Fixes concern 1 (the primary complaint) and ships alone.
   Establishes `Wp`.
2. **loose-row-columns-k33** — the loose region fills `W` with its own row-column
   count (principles 3+4). Builds on child 1's `W`.

## Done when (node)

- Both children retired: the global overlay balances to 2 panel columns by
  default, and loose rows columnize to fill the established width; `'cols N` still
  pins; `'layout 'grid` still switches packing; portable-surface + tests green.

## Pointers

- Renderer: `ui/overlay.scm` (panel-grid payload — `cols`/`layout`/`loose`/
  `panels`), `ui/overlay.js` (`overlayRenderers['panel-grid']`, `renderLoose`,
  `renderPanel`), `base.css` (`.panel-grid`, `.panel-loose`).
- DSL: `lib/modaliser/dsl.sld` (`'cols` already plumbs to the payload).
- Design spec: `docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md`
  §4 (amend the column-count line), §11 decisions.
- Prior art (deleted): `overlay-column-count` / `set-overlay-aspect-ratio!` —
  the legacy aspect search; ADR-0012 flag-day amendment.
- Glossary: **panel**, **loose region**, **span**; add **column balancing**.

## Notes

- Measurement happens in JS by necessity (rendered heights). Keep the *policy*
  (target ≈ 1.4) a JS constant — the user declined exposing it. The balance must
  honour spans (`wide` = 2 of the chosen columns, `full` = all) when simulating
  lane heights, and re-run on live-list updates (the panel/loose render path
  already re-fires on push-updates).
- Verify live per change (`./scripts/install.sh` then Relaunch); the global
  overlay (Applications=8 rows / AI=2 / Search=3) is the canonical 3→2 case.
