# loose-row-columns-k33

**Kind:** work

## Goal

Make the loose region's bare rows **columnize to fill the overlay width** the
rest of the body established — instead of a single flex column. This is the
user's concern 3: "when the elements are at the top level, they should distribute
into columns if the rest of the overlay is wide enough such that it requires
that."

This is child 2 of responsive-columns-k30 (read that node BRIEF for the full
settled design). It builds on panel-aspect-balance-k32, which establishes the
panel grid's natural width `Wp`.

## Design (from the node brief)

- **Shared width, own count.** The overlay has one content width
  `W = max(Wp, Wb)` — `Wp` the balanced panel-grid width (child 1), `Wb` the
  widest full-width loose block (window-diagram / live windows-list) if any. The
  loose **rows** fill `W` with **their own** column count, which is typically
  *more* than the panels' (a key-row — keycap + label — is narrower than a panel
  card). Edges line up; counts differ.
  - Loose-row column count ≈ `floor((W + gap) / (looseRowMinWidth + gap))`,
    optionally aspect-tempered so a tiny handful of rows don't over-spread. Keep
    it simple: fill the available width is the primary intent.
- **Rows columnize; blocks stay full-width.** Within `.panel-loose`, only the
  bare key-rows + folded drill-rows (`renderPanelRow` items, the ones carrying
  `key`) flow into a column grid. Loose **blocks** (items carrying `type` —
  window-diagram, live list, rendered via `renderPanelList`) keep full width.
  Preserve **declaration order**: the loose region interleaves full-width blocks
  with row-grid runs, so consecutive rows between two blocks form one grid run.
- **Global screen** (no loose block): `W = Wp`, so the 4 loose rows (Switch
  Space / Settings / Highlight Cursor / → Windows) spread to fill the 2-column
  panel-grid width. **Windows sub-screen** (no panels, diagram + list blocks):
  `W = Wb` (the diagram width), so `s`/`r` fill that width.

## Done when

- Loose rows columnize to fill the established overlay width (verified live:
  global overlay loose rows span the panel-grid width; Windows sub-screen `s`/`r`
  span the diagram width). Loose blocks (diagram, live list) stay full-width.
- Declaration order preserved across interleaved blocks and row runs.
- A single loose row (or very few) still reads sensibly (no awkward 1-item-per-
  column spread) — temper if needed.
- `swift build` + suites green; `check-portable-surface.sh` green.

## Notes

- Files: `ui/overlay.js` (`renderLoose` — group consecutive row items into a
  grid container; emit full-width blocks as their own children; set the loose
  column count from `W`). `base.css` (`.panel-loose` — today a flex column; add a
  row-grid run container, e.g. `.panel-loose-rows`, that mirrors the panel-grid
  column mechanism with a narrower `--loose-row-min-width`). The renderer
  (`overlay.scm` / payload) likely needs to pass nothing new — `W` is derived in
  JS from the already-rendered panel grid + block widths.
- Sequencing: needs child 1's `Wp` to exist. If child 1 exposes the chosen panel
  width (e.g. via the measured grid element), read it here rather than
  recomputing.
- TDD/verification: the columnization is pure JS/CSS — live verification is the
  real gate (both the global and Windows screens). Add a payload/DSL test only if
  this touches the Scheme surface (it likely doesn't).
