# lowering-k10

**Kind:** work

## Goal

Implement the layout-DSL **container forms** and their **lowering** in
`lib/modaliser/dsl.sld`: `screen`, `panel`, and `open` (surface fixed by
ADR-0012; see the node BRIEF). Lowering is construction-time — each form emits
operational alist nodes carrying presentation metadata the renderer reads, with
the **state machine untouched**. Fragments are the sibling leaf
[[fragments-splice-k11]]; this leaf just wires `expand-splices` into the new
forms so splices (incl. `sticky-set`) work inside panels/screens.

## Done when

- **`panel`** — `(panel "label" ['span S] child…)` → a `'kind 'category` node
  with a `'span` entry. `flatten-categories` / `find-child` descend through it
  unchanged (verify by test). Default span `narrow`; **auto-`wide`** when a
  live-list block is among the children and no explicit `'span` was given.
  `'span` accepts `'narrow|'wide|'full` (reject others with a clear error).
  Accepts a live-list block (`window:list-block` / `iterm:pane-list-block` etc.)
  as a child alongside key rows.
- **`screen`** — `(screen 'scope [keywords…] panel…)` registers a tree under
  `'scope` via `register-tree!`, carrying `'renderer 'panel-grid` and `'cols N`
  when given. Loose top-level atoms (non-panel children) pack into an implicit
  **"General"** `panel` (mirror `pack-node-runs`/`flush-node-run`); explicit
  panels pass through in declaration order. Lifecycle keywords (`on-enter` /
  `on-leave` / `sticky` / `display-name` / `exit-on-unknown`) accepted as on
  `define-tree`.
- **`open`** — `(open KEY LABEL [keywords…] panel…)` → a navigable `group` (own
  key/label) whose children are the lowered sub-grid panels, carrying
  `'renderer 'panel-grid`. Descends correctly under modal navigation (test).
- `expand-splices` runs over `screen`/`panel`/`open` bodies so existing splice
  producers (`sticky-set`) and future `fragment`s hoist in place.
- New exports added to `(modaliser dsl)`; old forms (`category` / `overlay` /
  `define-tree`) untouched and still working.
- A **minimal example screen tree** for tests (not a real-config migration).
- **Scheme lowering tests** (new `LayoutDslTests` or extend `ConfigDslTests`),
  through a real LispKit context per repo convention: panel→category+span;
  General packing; span parse + reject; auto-`wide`; list-block as panel child;
  `open`→group+panel-grid + dispatch descends; `find-child` transparency through
  panels; a `screen` registers + renders panel-grid metadata.
- `check-portable-surface.sh` stays green.

## Notes

- **Co-design** the `'renderer 'panel-grid` payload (span, panel label, `'cols`)
  with [[panel-grid-renderer-k4]] — that renderer consumes exactly this metadata.
- The `'span`/`'cols`/`'renderer` extras ride the same opaque pass-through
  `group` already implements (dsl.sld:323–328); `node-renderer-payload`
  (state-machine.sld:322) reads them back — no new accessor needed unless a
  span-specific reader reads cleaner.
- Default column count is **CSS-intrinsic auto-fit**; the Scheme aspect-ratio
  search is retired in [[panel-grid-renderer-k4]], not here.
