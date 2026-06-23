# config-migration-k8

**Kind:** work

## Goal

Rewrite the bundled default, the user config, and the per-app trees in the
**presentation-first layout DSL**, exercising the new surface end-to-end
(spec §9). Behaviour-preserving: dispatch is unchanged, only authoring +
presentation change.

## Context

- `Sources/Modaliser/Scheme/default-config.scm` → named panels (General /
  Applications / AI / Search) + per-app trees as **screens**; mark live-list
  panels `wide`.
- User `~/.config/modaliser/config.scm` + `app-trees/*.scm` (user pre-approved
  the migration). Keep `config.scm` in **sync** with the bundled default per the
  existing convention (see config-sync user memory).
- Author shared sets via **fragments / splice** (window-actions etc.).
- Loose top-level keys become an explicit **"General"** panel.
- Depends on [[layout-dsl-k3]] (the surface); best done after
  [[panel-grid-renderer-k4]] + [[list-cursor-k6]] so the result is visibly
  correct.

## Done when

- Bundled `default-config.scm` restructured into screens/panels of the layout
  DSL; the user config + `app-trees/*` migrated; the bundled default tracks the
  user config.
- First-run + the migrated trees render as panels and **dispatch identically**
  to before (transparent dispatch preserved).
- EndToEnd coverage for the global tree + at least one app tree rendering as
  panels.

## Deferred here from panel-grid-renderer-k4

[[panel-grid-renderer-k4]] added the `panel-grid` renderer **additively** and
left the legacy auto-layout in place, because the bundled `default-config.scm`
(+ the user config + ~10 test suites) still drive the old `define-tree` /
`overlay` / `which-key-block` path that those functions serve. ADR-0011's
"retire the auto-layout heuristics" therefore lands **here**, once this leaf
migrates the last callers off the old forms (lowering-k10's "no flag-day; old
forms stay working until k8" — that promise is kept). After the migration,
delete (in `ui/overlay.scm` unless noted):

- `which-key-payload-json`, `partition-which-key-segments`,
  `distribute-which-key-columns`, `segment-row-count`, `segments-row-count`,
  `render-segment` — the which-key block's whole-overlay column packing;
- `overlay-column-count` (+ its `overlay-col-width-px` / `overlay-row-height-px`
  seeds) — but **only after** `render-overlay-default` /
  `push-overlay-update-default` stop calling it (the default *list* renderer
  still uses it; either migrate its callers too or replace with a CSS-intrinsic
  count);
- the `'which-key` branch of `block-json`, and the `(modaliser blocks which-key)`
  library + its `.js`/`.css` once nothing constructs a `which-key-block`. The
  panel-grid row renderer in `overlay.js` (`renderPanelRow`) already carries an
  identical local fallback, so deleting `which-key.js` (which sets
  `window.overlayRenderRow`) leaves panel rows rendering unchanged.

Then drop the `OverlayRenderTests` / `BlocksWhichKeyLibraryTests` cases that
pin the deleted functions, and confirm `check-portable-surface.sh` stays green.

## Notes

- Watch the façade-cutover failure mode (see feedback memory): a silent backend
  gap can break inline-tree configs — audit that every migrated tree still
  registers + dispatches.
