# masonry-layout-k20

**Kind:** work

## Goal

Fix panel packing in the root overlay. With `display: grid; grid-auto-flow:
dense`, a tall panel forces a CSS-Grid row-track height that strands shorter
panels with whitespace above them — a short panel can't tuck up under a
shorter neighbour (the user's "Search should fit under AI/General"). Switch the
panel grid to native CSS masonry, and add an opt-in screen keyword for authors
who want deterministic placement instead.

## Design (settled 2026-06-24, approved)

- **Default = masonry.** `.panel-grid { display: grid-lanes; … }` replacing
  `display: grid; grid-auto-flow: dense`. Panels flow into the shortest lane.
  `grid-template-columns` (auto-fit `minmax` tracks), `gap`, and the span
  classes (`grid-column: span 1`/`span 2`/`1 / -1`) carry over unchanged.
  **No `@supports` fallback** — assume Safari 26.4+ (host is 26.5).
- **Opt-in determinism:** a screen-level keyword `(screen 'scope 'layout 'grid
  …)` switches that screen to the deterministic aligned grid (today's
  `display: grid`). Default is `'masonry`. It threads through `panel-grid-head`
  exactly like `'cols`; the renderer emits it (e.g. `data-layout` on
  `.panel-grid`) and `overlay.js` sets the attribute the same way it sets
  `--panel-grid-cols`. CSS: `.panel-grid[data-layout="grid"] { display: grid;
  grid-auto-flow: dense; }`.
- **No** per-panel column pinning (user declined the finer option).

## Done when

- Root overlay panels masonry-pack by default (verified live in the app).
- `(screen … 'layout 'grid …)` renders the deterministic grid; an omitted /
  `'masonry` value renders masonry. A LayoutDslTests / PanelGridRendererTests
  case asserts the screen carries the layout marker and the default is masonry.
- `'cols` and `'span` still honoured under both modes.
- `swift build` + the layout/renderer suites green; `check-portable-surface.sh`
  green.

## Notes

- Files: `base.css` (`.panel-grid`); `lib/modaliser/dsl.sld` (`panel-grid-head`
  + the `screen`/`open` keyword loops — add `'layout`); `ui/overlay.scm`
  (thread layout into the head/payload); `ui/overlay.js` (apply `data-layout`).
- Docs: `docs/reference/dsl.md` (screen keywords) and `theming.md` / the design
  spec if they enumerate the panel-grid CSS.
- TDD: write the DSL/renderer test first (screen carries `'layout`; default
  masonry), then the CSS swap. Confirm live before retiring.
