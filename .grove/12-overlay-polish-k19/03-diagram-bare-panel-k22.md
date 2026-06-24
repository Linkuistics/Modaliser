# diagram-bare-panel-k22

**Kind:** work

## Goal

A panel hosting a window-diagram (the window-sizing layout boxes) currently
sits on the standard white panel card. Because the diagram's filled cells are
also white (`--diagram-cell-bg: #fff`), empty cells blend into the card — the
window-size proportions are invisible — and the start-aligned diagram grid
leaves a white card edge that reads as misaligned. Render the diagram's host
panel background-transparent so the diagrams float on the tinted overlay body.

## Design (settled 2026-06-24, approved)

- The panel embedding a `window-diagram` block renders with **no card
  fill / border / shadow** (a "bare" / transparent panel variant), so empty
  diagram cells show `--overlay-body-bg` (proportions become legible: white
  filled cell vs tinted empty cell) and there's no white card edge to read as
  misaligned.
- **Auto-applied** when a panel embeds a window-diagram block — configs need no
  change. Other panels (key lists, the pane / window live-lists) keep their
  white cards.
- Scope: the window-diagram host panel only.

## Done when

- The Windows-screen "Layout" panel renders transparent; diagram proportions
  are legible against the body tint; no misaligned white card edge (verified
  live in the app).
- All other panels unchanged (still white cards).
- `swift build` + the renderer suite green.

## Notes

- Diagram block: `lib/modaliser/blocks/window-diagram.{sld,js,css}`
  (`.block-window-diagram .diagram-panel`, `--diagram-cell-bg`). Panel card
  styling: `base.css` `.panel`; panel-grid renderer: `ui/overlay.scm` /
  `ui/overlay.js`.
- Likely approach: a panel modifier class (e.g. `.panel--bare`) the renderer
  adds when the panel's embedded block is a window-diagram — detect the diagram
  block in `make-panel-node` / the panel payload and mark the panel bare. Avoid
  requiring a config opt-in.
- Interaction with **masonry-layout-k20**: a transparent panel still occupies a
  lane — confirm it packs sanely under `grid-lanes`.
