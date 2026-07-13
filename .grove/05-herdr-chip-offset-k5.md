# herdr-chip-offset-k5

**Kind:** work

## Goal

Fix the herdr pane-chip placement: chips currently paint **to the left of**
their pane, not over it. Each digit chip must land inside its pane's
on-screen rect (replace mode; augment stays a documented v1 limitation).

## Context

- Human report (2026-07-13, mid prev-next-nav-k4 grilling): "In herdr, the
  chips for the panes show to the left of the pane, not over the pane
  itself."
- Suspect: `herdr-chip-entries` in
  `Sources/Modaliser/Scheme/lib/modaliser/blocks/herdr-list.sld` — the
  cell→pixel mapping that subtracts `layout.area.x`/`.y` (herdr's left
  sidebar) before scaling pane rects onto the iTerm AXScrollArea frame. A
  systematic left shift smells like that sidebar compensation over- or
  double-correcting: e.g. herdr's `pane layout` rects may already be
  area-relative (so subtracting area.x again shifts everything left), or
  the AXScrollArea host frame may start left of the herdr content area.
  Diagnose against live output of `herdr pane layout` before changing the
  arithmetic — do not assume.
- The pure synthesis is fixture-tested; update the fixtures to encode the
  *verified* live geometry, not the current assumption.

## Done when

Chips visually land on their panes in a live replace-mode herdr session
(multi-pane tab); `herdr-chip-entries` fixture tests updated to match the
verified geometry; tests green.

## Notes

herdr 0.7.3 is installed now; the geometry assumptions were validated
against an earlier herdr — a herdr-side change to `pane layout`'s area
semantics is a live possibility.
