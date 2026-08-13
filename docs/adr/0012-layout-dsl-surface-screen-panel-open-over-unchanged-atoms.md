# The layout DSL surface is `screen` / `panel` / `open` over the unchanged dispatch atoms

- **Status:** accepted (refines [ADR-0011](0011-dispatch-structure-with-attached-display.md) — the sugar surface over the two-layer node model); the "no flag-day" consequence was **reversed 2026-06-24** — see [Amendment](#amendment-2026-06-24--the-flag-day-happened-after-all)

ADR-0011 inverts authoring to a presentation-first layout spec that **lowers** to
the operational node-tree. This ADR fixes the *concrete surface*. The layout
introduces exactly three new container forms — **`screen`** (a tree under a
scope — a pure constructor returning a tree contribution, ADR-0018; its body
is an implicit grid of panels; optional `'cols N`, default CSS-intrinsic
auto-fit), **`panel`** (a transparent visual card; optional
`'span 'narrow|'wide|'full`, auto-`wide` when it holds a live-list block), and
**`open`** (a navigable drill-down into a sub-screen) — over the **unchanged
dispatch atoms** `key` / `keys` / `key-range` / `selector` / `group` /
`sticky-set` and the lifecycle keywords, because those atoms *are* the
operational IR the state machine reads; renaming them buys nothing. Reusable
chunks splice in via a **`splice`** form (formerly `fragment` — renamed when
"Fragment" became the configuration term, ADR-0018) built on the existing
`expand-splices`.

## Considered options

1. **Tight rename — `screen`/`panel`/`open` + unchanged atoms** (chosen). The
   authored leaves stay identical to the IR they lower to; smallest new surface;
   the dispatch layer is literally untouched.
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

- **The sugar compiles onto the bare surface** (ADR-0011): `screen`/`open`
  lower to a tree-root / `group` whose children are flat dispatch atoms, and
  `panel` becomes a display-value clause referencing its rows by key —
  attached as the node's single `'display` entry, pinned by the sugar≡bare
  equivalence test. Nothing panel-shaped lands among dispatch children.
  (Originally `panel` lowered to a `'kind 'category` child and dispatch
  tunneled through it via `flatten-categories`; the two-layer representation
  change retired that shape.)
- Loose top-level atoms under a `screen` — a `key`/`keys` outside any `panel`,
  a folded top-level `open`, a loose diagram or live-list block — render
  **bare** in a header-less **loose region** above the panel grid. There is no
  auto-collecting "General" card, so eliding an explicitly-authored
  `(panel "General" …)` is a pure authoring migration: drop the wrapper and its
  children become loose rows.
- The old authoring forms (`define-tree` / `category` / `overlay` /
  `pack-node-runs`) are **gone**, along with the `(modaliser blocks which-key)`
  library and its assets, the `which-key` block-list render path, and the
  `set-overlay-aspect-ratio!` / `overlay-column-count` aspect-ratio column
  search. They were deprecated first and then deleted deliberately, once the
  last shipped caller had moved, rather than left to rot behind a deprecation
  notice. `screen` / `panel` / `open` / `splice` over the unchanged dispatch
  atoms are the **only** authoring surface, and the default list renderer that
  plain `(group …)` drill-downs use flows CSS-intrinsic auto-fit columns rather
  than a Scheme-computed count.
- The renderer contract with the panel-grid renderer is the display
  value's shape: the overlay derives the panel-grid render path from a
  structured display ('panels/'loose/'embed/'cols/'layout present) and
  serializes the pure `resolve-display` plan. (The original contract was
  a `'renderer 'panel-grid` marker stamped on the group; the two-layer
  representation change made the marker derivable and retired it.)
- Portability preserved: all new forms stay within `(scheme …)` / `(srfi …)` /
  `(modaliser …)`; `check-portable-surface.sh` stays green.

## What stayed fixed

The legacy authoring path was deleted, loose atoms moved from an implicit
"General" card to a bare region, and the `'panel-grid` renderer marker was
retired in favour of deriving the render path from the display value's shape.
Through all three, the dispatch atoms and the lowering contract — the
substance of this ADR — were unaffected. Only the authoring spelling and the
presentation of unwrapped loose atoms changed.
