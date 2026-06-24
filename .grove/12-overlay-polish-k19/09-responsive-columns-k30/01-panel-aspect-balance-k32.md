# panel-aspect-balance-k32

**Kind:** work

## Goal

Replace the panel grid's CSS-intrinsic auto-fit column count with a **JS
aspect-balance** pass: measure the panels, pick the column count whose resulting
grid shape is closest to a target width:height ratio (≈ 1.4), and set
`--panel-grid-cols` to it. Fixes the primary complaint — the global overlay
renders 3 columns where 2 balance better (Applications=8 rows / AI=2 / Search=3 →
Applications | AI-over-Search).

This is child 1 of responsive-columns-k30 (read that node BRIEF for the full
settled design). It ships value alone and establishes the panel grid's natural
width `Wp` that loose-row-columns-k33 will consume.

## Design (from the node brief)

- **When `'cols N` is absent** (the default), compute the column count in JS:
  for candidate counts `c = 1 … maxFit` (maxFit = how many `--panel-min-width`
  tracks fit the `--panel-grid-max-width` cap), predict the grid's `(width,
  height)` and pick `argmin_c |width/height − 1.4|`. Set `--panel-grid-cols = c`.
  Predicting height per `c`: simulate the masonry shortest-lane packing the
  browser does — assign each panel (in payload order) to the currently-shortest
  lane, honouring spans (`wide` occupies 2 adjacent lanes, `full` occupies all),
  track per-lane running height, grid height = tallest lane. Width ≈
  `c · panelMinTrack + (c−1) · gap` (or measured). One measurement pass for the
  per-panel natural heights, then pure arithmetic over candidates — avoid N
  reflows. (If render-then-measure per candidate proves simpler/robust enough for
  a ≤~6-panel grid, that's acceptable; just don't flash — see below.)
- **When `'cols N` is present**, keep today's behaviour exactly: set
  `--panel-grid-cols = N`, skip measurement (hard pin = the only override).
- **`'layout 'grid` is orthogonal**: balance still picks the count; `data-layout`
  still selects masonry-lanes vs aligned-dense packing. Confirm balance works
  under both (the aligned mode shares row-track heights, so the height-prediction
  for `'layout 'grid` may differ — at minimum, don't regress it; aligned mode can
  keep a simpler prediction or fall back to maxFit if simulation is masonry-only).
- **Target ≈ 1.4 is a JS constant** (user declined exposing it).
- **No first-paint flash**: the overlay appears on keypress; do the measure +
  `--panel-grid-cols` set before the panel is shown / within the same frame
  (e.g. measure with the grid laid out but the panel still hidden, or set cols
  synchronously in the render function before `notifyResize`). Check the bootstrap
  vs push-update paths in `overlayRenderers['panel-grid']`.
- **Re-run on updates**: a panel embedding a live list changes height when the
  list updates; the render path already re-fires on push-updates, so recomputing
  each render is correct — just make sure measurement reads the *populated* list.

## Done when

- Global overlay balances to **2 panel columns** by default (verified live:
  `./scripts/install.sh` → Relaunch → leader → observe Applications | AI/Search).
- `(screen … 'cols N)` still pins exactly N (no measurement); `'layout 'grid`
  still switches packing and isn't regressed.
- No visible column-count flash on overlay show.
- A renderer/DSL test asserts the payload still carries `'cols` when authored and
  the default omits it (the JS balance is the default path). `swift build` +
  layout/renderer suites green; `check-portable-surface.sh` green.

## Notes

- Files: `ui/overlay.js` (`overlayRenderers['panel-grid']` — add the balance
  helper and call it where `--panel-grid-cols` is set today, lines ~162–177);
  `base.css` (`.panel-grid` — `--panel-grid-cols` already drives the track count;
  the `auto-fit` fallback stays for the no-JS/edge case). `ui/overlay.scm` +
  `dsl.sld` likely unchanged (`'cols` already plumbs through) — confirm.
- The pure JS balance is hard to cover in the Swift/Scheme suites; rely on the
  DSL/renderer payload test + live verification. If the lane-packing math is
  worth a unit test, factor it as a pure function and consider a minimal JS test
  harness — but don't over-invest; live is the real gate.
- TDD: write the payload/DSL assertion first, then the JS. Confirm live before
  retiring; the node brief's canonical case is the 3→2 global overlay.
