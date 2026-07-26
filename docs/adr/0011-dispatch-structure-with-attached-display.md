# A node is dispatch structure plus an attached display value

Every node in the modal tree factors into two pure layers held **disjointly
on the node**: **dispatch structure** — kind, key, label, action, gates,
`'next`, providers, splices, and the flat `'children` list — and an attached
**Display value**, one `'display` entry produced by the pure display DSL
(`(modaliser display-dsl)`), saying how the node renders: panels referencing
the node's own rows by key, live-list block placement by reference, spans,
order, embeds. Dispatch reads never consult `'display`; renderer reads
resolve through it (the pure `resolve-display` function) — so substituting a
display value *structurally cannot* change the live key set, rather than
merely promising not to.

Two authoring surfaces build the same representation:

- the **bare surface** — canonical: the dispatch constructors
  (`tree-root`/`group`/`key`/`walk`/`splice`) compose plain data, and
  `with-display` (pure, variadic over display clauses) attaches the display
  value. A node with no display renders as plain loose rows in declaration
  order.
- the **authoring sugar** (`screen`/`panel`/`open`, ADR-0012) — a veneer
  lowering onto the bare surface, syntax unchanged, kept provably thin by a
  sugar≡bare equivalence test (identical node output). The overlay's
  isomorphism ("the config is the document") survives for sugar authors.

A **live-list block** is a dispatch atom — authored in the tree, where it
contributes its digit key-range and hooks — and the display value *places*
it by reference (id defaulting to the block's type); display never carries
keys.

Display chooses per edge between **drill** (swap to the target's own display
root — sugar's `open`, and the default presentation of a group edge) and
**embed** (render the target's UI as a section of the parent's display;
firing the edge is a real Visit, presentation activates the section in
place — the fired key highlights, the rest dims, backspace reverts). A
**panel** groups a node's own rows and exists only in the display value —
no panel-shaped node sits among the dispatch children. A **splice** copies
keys into the parent's dispatch and is *not* a display choice. The unit the
overlay renders is the **Display root**: one persistent layout spanning a
node and its embedded sections, restyled as the Visit moves within it.
Contracts (embed semantics, snapshot and show-delay binding, active-rows ≡
live-keys): `docs/specs/configuration-value.md`.

## Why it binds

- The invariant "substituting a display never changes the live key set"
  becomes structural: `find-child` and the FSM lowering read `'children`,
  the renderer reads `'display` — disjoint entries cannot disagree. The
  previous shape (panels as `category` nodes interleaved in children,
  display keys scattered across the node alist) kept the factoring only as
  a promise, tunneled through `flatten-categories` at every dispatch read.
- De-complecting, simplification, and composition are the project's first
  design values: dispatch authored as a plain tree of standard Scheme
  values, display attached as a separate explicit step, is the
  de-complected surface — and the sugar stays a veneer, never the only way
  in.
- Costly to reverse: the lowering pipeline, the display DSL, the renderer
  contract (`resolve-display`), and the configuration value's node shape
  all target the factoring.

## Considered options

1. **Presentation-first single artifact** (the original decision here: the
   layout spec is the one authored surface; the operational tree is lowered
   from it, presentation riding as annotations). Rejected: display is not
   separable or replaceable, and in-place activation of an edge target has
   no expression. Reopened by: nothing.
2. **Surface-only de-complecting** (bare constructors + attach compiling to
   the previous IR — categories injected back into children). Rejected: the
   factoring would exist only at the authoring altitude; the category
   tunneling machinery survives indefinitely and the invariant stays a
   promise. Reopened by: nothing — the representation change subsumes it.
3. **The raw FSM graph DSL as the authoring surface** (states + labelled
   edges, explicit ids — `fsm-graph-state!`/`edge`). Rejected: the author
   mints every state id and hand-writes the up-edges/containment the tree
   lowering derives from nesting for free. The graph DSL remains the
   lowering target and stays config-visible. Reopened by: a real authoring
   need the tree altitude cannot express.
4. **Layout-over-ops by id reference** (a separate display registry
   pointing at nodes from a distance). Rejected: two artifacts to keep in
   sync — attachment to the node avoids the distance. The display's
   *internal* row references (panel key lists, block ids, embed keys) are
   one level deep, against the node's own children, and validated at
   lowering.
5. **Display-only swallow** (embedded rows visible while their keys are not
   live). Rejected: breaks rows-shown ≡ keys-live; dimming must state
   liveness, not decorate it. Reopened by: nothing.
6. **Embed as dispatch flattening** (target's keys merge into the parent).
   Rejected: that is a splice — it already exists; embed's point is a real
   Visit with in-place presentation. Reopened by: nothing.
7. **Split block constructors** (digit key-range authored in the tree, list
   visual authored in the display, wired to one data source by hand).
   Rejected: the block bundle exists because both halves derive from one
   source; splitting reintroduces exactly the by-hand wiring burden the
   fragment model removed. Reopened by: nothing.

## Consequences

- The `category` node kind and the `flatten-categories` tunneling retire;
  a node's `'children` are flat and dispatch-only.
- The renderer consumes the output of the pure `resolve-display` function
  ((children, display value) → render plan), which lives portable-side;
  the overlay serializes it (restyle protocol:
  `docs/reference/renderer-protocol.md`).
- `node-display` / `node-with-display` become total: the display value is
  one entry, extracted and replaced wholesale.
- Every existing config and app library authors through the sugar
  unchanged; the display DSL is config-visible, optional authoring.
- The `fragment` splice form renamed to `splice` ("Fragment" is the
  configuration term — ADR-0018; landed in dsl-purification-k9).
