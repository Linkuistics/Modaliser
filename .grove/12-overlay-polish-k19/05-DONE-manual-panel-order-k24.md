# manual-panel-order-k24

**Kind:** planning

## Goal

Give configs the option to **disable key-sorting of a panel's entries** so the
rows render in **declaration order** (manual ordering), instead of always being
sorted alphabetically by key. Requested by the user on 2026-06-24 while
reviewing the overlay live.

## Context

- Today `panel->json` (ui/overlay.scm) renders a panel's rows through
  `(filtered-rows (sort-children …))`, and the default list renderer
  (`render-overlay-default`) sorts too. `sort-children` / `sort-key-lt?`
  (overlay.scm) is the comparator.
- **Precedent just landed:** bare-loose-rows-k23 made the screen/open **loose
  region** preserve *declaration order* (it is rendered from the lowered
  `'loose` list verbatim, not sorted). So the overlay already has one
  declaration-ordered surface; this leaf extends author control to panels.
- Per ADR-0011/0012 the `panel` form lowers to a `'kind 'category` node; the
  DSL owns the alist, the renderer owns the JSON. A "don't sort" signal would
  ride as opaque metadata the renderer reads back (like `'span` / `'list`).

## Design — to settle (grill first)

- **Keyword + values.** e.g. `(panel "X" 'sort 'declared …)` vs the default
  `'sort 'keys`; or a boolean `'sort #f`. Recommend `'sort` taking
  `'keys` (default) | `'declared` — symmetric, extensible, reads well.
- **Scope.** Panel only, or also `screen` / `open` (a grid-wide default), or the
  loose region (already declaration-ordered — likely n/a)? Recommend
  per-`panel` first, with a screen/open default override as a possible later add.
- **Default stays `'keys`** (sorted) so every existing config is unchanged.
- Dispatch is unaffected — sorting is presentation only (`find-child` is
  order-independent).

## Done when

- A panel can opt out of key-sorting and render its rows in declaration order.
- Default behaviour (sorted) is unchanged; existing tests stay green.
- Renderer + DSL tests cover the opt-out; docs (`docs/reference/dsl.md`,
  `theming.md` if relevant) and `CONTEXT.md` updated.
- `check-portable-surface.sh` green. Verified live.

## Notes

- Files: `lib/modaliser/dsl.sld` (`panel` / `make-panel-node`; maybe
  `screen`/`open`), `ui/overlay.scm` (`panel->json` — gate the `sort-children`
  call on the panel's sort mode).
- Independent of list-cursor-initial-focus-k25 and util-extraction-audit-k26.
