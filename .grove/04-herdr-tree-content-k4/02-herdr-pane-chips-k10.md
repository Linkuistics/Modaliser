# herdr-pane-chips-k10

**Kind:** work

## Goal

Give the herdr panes list block a chip overlay: digit-labelled chips painted over the
on-screen herdr panes in **replace** mode, mirroring the tmux-style rect synthesis.
Depends on `herdr-controls-k9` (the herdr-panes block + tree content exist; this adds
the `'chips?` path).

## Context

Read this node's `BRIEF.md` (the `pane layout` JSON shape + area offset) and
`muxes/tmux.sld`'s "Digit-jump chip rendering" section (`host-frame`, `chip-entries`,
grid → rect synthesis, `ax-target-hints` + `hints-show`). tmux is the closest model:
neither herdr nor tmux exposes native pixel rects, so both derive chip rects from
cell/canvas coords × the focused iTerm session's AX frame.

herdr specifics:

- Rects from `herdr pane layout`: `result.layout.area {x,y,width,height}` is the herdr
  canvas in **cells**, `panes[].rect {x,y,width,height}` each pane in cells. The area's
  `x`≥26 is herdr's **left sidebar** — chips are **area-relative**: subtract `area.x`/
  `area.y` before scaling so the sidebar offset doesn't shift every chip right.
- Scale: `cell_w = host_frame.w / area.width`, `cell_h = host_frame.h / area.height`;
  `chip.x = host.x + (rect.x - area.x) * cell_w`, etc. (host_frame = focused iTerm
  AXScrollArea, same `host-frame` source tmux uses).
- **Replace mode is correct** (herdr owns the sole AXScrollArea). **Augment mode**: the
  `(car panes)` first-AXScrollArea soft spot means the host frame may be the wrong
  split, so chips can target the wrong place — **document this limitation** in the block
  header + `docs/reference/terminal-detection.md` (or wherever chips are documented).
  hjkl focus is unaffected; digit-jump still *works* (focus by pane_id), only the chip
  *pixels* may be off. The proper fix (a focused-iTerm-session-frame primitive) stays
  the optional deferred leaf, not this one.

## Done when

- `(herdr:pane-list-block 'chips? #t)` paints digit chips over herdr panes in replace
  mode; `on-leave` hides them (mirror iterm-panes' `paint-and-snapshot!` / `hints-hide`).
- Augment-mode limitation documented.
- Chip-rect synthesis unit-tested (pure cell→pixel math on a fixed `pane layout`
  fixture, like tmux's). Live visual confirm in the installed app (`./scripts/install.sh`
  + herdr iTerm window frontmost + F17) — this is the natural moment for the deferred
  leaf-3 visual confirmation of the whole herdr variant-tree path too.
- `swift test` + `check-portable-surface.sh` green.

## Notes
