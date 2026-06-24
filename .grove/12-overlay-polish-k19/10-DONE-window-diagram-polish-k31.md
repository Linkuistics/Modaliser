# window-diagram-polish-k31

**Kind:** work

## Goal

Two presentation fixes on the Windows overlay's layout diagrams, flagged live by
the user on 2026-06-24 (verbatim): "Their is some visual clipping on the bottom
left in the Windows overlay layout diagrams. Those layout diagrams don't need a
'Layout' header."

1. **Clipping** — diagnose and fix the visual clipping at the **bottom-left** of
   the layout diagrams (likely an `overflow`/border/`border-radius` clip on the
   diagram cell or its host panel).
2. **Drop the 'Layout' header** — the layout diagrams should render without the
   "Layout" panel header. Note: overlay subpanel titles are **config-controlled**,
   not hardcoded (see the overlay-structure-is-config rule), so first decide
   *where* the header should go: drop the `(panel "Layout" …)` title in
   `default-config.scm` (+ the user config), or make diagram-hosting panels
   suppress their header in the renderer (cf. diagram-bare-panel-k22, which
   already made the diagram host background-transparent). Pick the one that keeps
   the panel model clean; if it turns out to need a design decision, decompose.

## Context / pointers

- Diagram block: `lib/modaliser/blocks/window-diagram.{sld,js,css}`.
- Host panel made bare/transparent by **diagram-bare-panel-k22** — start there for
  how the diagram panel is styled; the clipping may live in that same CSS.
- Layout block + its panel wrapper: `lib/modaliser/window-actions.sld`
  (`default-layout-block`, `divisions`) and the `(panel "Layout" …)` usage in
  `default-config.scm` / the user's app-tree configs.
- Renderer: `ui/overlay.scm`, `ui/overlay.js`, `base.css` (`.panel`, diagram).

## Done when

- No bottom-left clipping in the layout diagrams (verified live).
- The layout diagrams render without a 'Layout' header.
- `swift test` green; `./scripts/check-portable-surface.sh` green.
- **Live verify (needs the user):** `./scripts/install.sh`, Relaunch, open the
  Windows overlay — diagrams render un-clipped and headerless.

## Notes

- Surfaced during the focused-window-seed-k29 live review; independent of the
  cursor-seed feature and of responsive-columns-k30.
