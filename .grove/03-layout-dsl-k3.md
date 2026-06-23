# layout-dsl-k3

**Kind:** work

## Goal

Introduce the **presentation-first layout spec DSL** and the **lowering** that
extracts the operational model from it (ADR-0011). The layout is a tree of named
**screens**, each a **grid of panels**; a panel holds command rows, drill-down
`open` affordances, and **live lists**; reusable **fragments** splice in. Walking
a layout emits the existing `(kind . group)` / `(kind . command)` operational
node-tree IR **plus presentation metadata** (`panel`, `span`, `screen`) that only
the renderer reads.

## Context

- **ADR-0011** is the charter: presentation authored, operations *extracted*; the
  node-tree becomes a compile target, not a hand-authored surface.
- `lib/modaliser/dsl.sld`: `category` (334–344) is transparent for dispatch and
  takes only `(label . children)`; `group` (299–332) has a keyword-parsing loop
  that accumulates opaque extras into the node alist (the pattern `'span` rides
  on); `pack-node-runs` / `flush-node-run` (553–593) today bucket nodes into
  misc/category `which-key` blocks and attach `'renderer 'blocks` + `'blocks
  <list>`; `overlay` / `define-tree` (400–538) attach the renderer.
- `state-machine.sld`: `node-renderer` / `node-renderer-payload` (308–324) read
  the metadata back; `flatten-categories` / `find-child` (177–331) do transparent
  dispatch — **must keep working**; `block-children` → `children` lifting wires
  dynamic lists into dispatch.
- Recent commit *"Allow splicing of stick groups (DRY)"* added `expand-splices`
  — **reuse it for fragments**.
- `set-theme!` is a no-op stub (`dsl.sld:598`).
- **Portability:** stay within `(scheme …)` / `(srfi …)` / `(modaliser …)`.

## Done when

- A layout DSL exists — `screen` / `grid` / `panel` / `cmd` / `open` /
  `live-list` / `splice` (settle the exact names + a tiny surface ADR at session
  start; the planning preview is indicative, not binding).
- **Lowering** walks a layout to operational nodes the **unchanged** state
  machine dispatches: transparent panel dispatch, `open` → navigable `group`,
  `key-range` digit-jump, `selector`, `block-children` lifting all intact.
- Lowered nodes carry presentation metadata (`panel` label, `span`, `screen` id);
  `'span 'narrow|'wide|'full` parsed; a list-bearing panel auto-promotes to
  `wide`; a live-list block is accepted as a panel child.
- Fragments splice (DRY for `window-actions` + shared sets).
- Scheme **lowering tests** (a layout → expected node-tree + dispatch behaviour).
- `check-portable-surface.sh` stays green.

## Notes

- **Biggest leaf.** If it exceeds one focused session, `grove-llm leaf-decompose`
  it — natural children: surface-design / lowering-walker / fragments+splice.
- **Co-design the panel-spec shape** with [[panel-grid-renderer-k4]] (the
  metadata this emits is what that renderer consumes).
- Open detail to settle here: **grid column-count authored vs derived** —
  recommend an optional per-screen `'cols N` defaulting to CSS-intrinsic auto-fit,
  retiring the Scheme aspect-ratio search (the retirement itself lands in
  [[panel-grid-renderer-k4]]).
- Do **not** migrate real configs here — a minimal example tree suffices for
  tests; real migration is [[config-migration-k8]].
