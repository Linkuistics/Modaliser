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

## Notes

- Watch the façade-cutover failure mode (see feedback memory): a silent backend
  gap can break inline-tree configs — audit that every migrated tree still
  registers + dispatches.
