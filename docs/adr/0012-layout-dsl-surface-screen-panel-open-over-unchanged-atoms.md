# The layout DSL surface is `screen` / `panel` / `open` over the unchanged dispatch atoms

- **Status:** accepted (refines [ADR-0011](0011-presentation-first-layout-spec-lowers-to-operational-node-tree.md) §"layout DSL"); the "no flag-day" consequence was **reversed 2026-06-24** — see [Amendment](#amendment-2026-06-24--the-flag-day-happened-after-all)

ADR-0011 inverts authoring to a presentation-first layout spec that **lowers** to
the operational node-tree. This ADR fixes the *concrete surface*. The layout
introduces exactly three new container forms — **`screen`** (registers a tree
under a scope; its body is an implicit grid of panels; optional `'cols N`,
default CSS-intrinsic auto-fit), **`panel`** (a transparent visual card; optional
`'span 'narrow|'wide|'full`, auto-`wide` when it holds a live-list block), and
**`open`** (a navigable drill-down into a sub-screen) — over the **unchanged
dispatch atoms** `key` / `keys` / `key-range` / `selector` / `group` /
`sticky-set` and the lifecycle keywords, because those atoms *are* the
operational IR the state machine reads; renaming them buys nothing. Reusable
chunks splice in via a **`fragment`** form built on the existing `expand-splices`.

## Considered options

1. **Tight rename — `screen`/`panel`/`open` + unchanged atoms** (chosen). The
   authored leaves stay identical to the IR they lower to; smallest new surface;
   `state-machine.sld` is literally untouched.
2. **Full presentation-first leaves** (`cmd`/`open`/`live-list` wrapping the
   atoms). Rejected: a second name plus an indirection layer over
   `key`/`selector`/list-block, for a uniform "new DSL" feel the author never
   benefits from — more surface to learn, document, and keep in sync, with no
   dispatch gain.
3. **Containers only, no `open`.** Rejected: drill-down would stay
   `(key K L (overlay …))`, an operational-first idiom embedded inside a
   presentation-first surface — the one place the inversion would visibly leak.
4. **Implicit grid + optional `'cols N`** (chosen) **vs. an explicit `(grid …)`
   form.** A screen body is *always* one grid, so a `grid` form would be ceremony
   for the common case; nested sub-grids are expressed by `open` (a new screen),
   not by grid-in-grid nesting, so the standalone form earns nothing.

## Consequences

- **`panel` lowers to a `category` node** (`'kind 'category`) carrying an added
  `'span`; **`screen`/`open`** lower to a tree-root / `group` node carrying
  `'renderer 'panel-grid` (plus `'cols` when authored). So
  `flatten-categories` / `find-child` / `node-renderer-payload` need **no
  change** — the panel's presentation metadata rides the opaque-extras
  pass-through `group` already implements.
- Loose top-level keys under a `screen` (outside any `panel`) pack into an
  implicit **"General"** panel — the presentation-first analogue of today's
  `pack-node-runs` misc bucket.
- The old authoring forms (`define-tree` / `category` / `overlay` /
  `pack-node-runs`) **keep working unchanged**, so nothing breaks before configs
  migrate: real configs move to the new surface in `config-migration-k8`, and the
  old forms are deprecated in `docs-tests-k9`. No flag-day.
- The `'panel-grid` renderer marker is the contract with the panel-grid renderer
  (`panel-grid-renderer-k4`); the exact panel-spec metadata shape is co-designed
  there.
- Portability preserved: all new forms stay within `(scheme …)` / `(srfi …)` /
  `(modaliser …)`; `check-portable-surface.sh` stays green.

## Amendment (2026-06-24) — the flag-day happened after all

The final Consequence above ("No flag-day") was **reversed by a post-k9
user decision**. `docs-tests-k9` deprecated the old forms in the docs but
left the code in place because shipped libraries still used it; the user
then chose to **physically delete** the legacy path rather than finish the
work on deprecation alone.

The `legacy-whichkey-deletion-k13` workstream performed that flag-day in
two steps: `migrate-callers-k14` moved the remaining live callers onto
`screen` / `panel` / `register-tree!`, then `delete-which-key-k15` removed
`define-tree` / `category` / `overlay` / `which-key-block`, the
`(modaliser blocks which-key)` library and its assets, the `which-key`
block-list render path, and the `set-overlay-aspect-ratio!` /
`overlay-column-count` aspect-ratio column search. The layout forms
`screen` / `panel` / `open` / `fragment` over the unchanged dispatch atoms
are now the **only** authoring surface, and the default list renderer that
plain `(group …)` drill-downs use flows CSS-intrinsic auto-fit columns
rather than a Scheme-computed count.

So "the old forms keep working unchanged" holds **only up to the k15
commit**; thereafter they are gone. The dispatch atoms, the lowering
contract, and the `'panel-grid` renderer marker — the substance of this
ADR — are unaffected.
