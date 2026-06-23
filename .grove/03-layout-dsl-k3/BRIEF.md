# layout-dsl-k3 — brief

Introduce the **presentation-first layout DSL** and the **lowering** that extracts
the operational model from it (ADR-0011). The surface was settled at the start of
this node's work and recorded in **ADR-0012**; this brief is the shared charter
for the two child leaves. Split because the leaf was the grove's biggest: the
surface decision + ADR landed in the decomposing session; the implementation is
`01-lowering-k10`; the reusable-DRY layer is `02-fragments-splice-k11`.

## Settled surface (ADR-0012)

Three new **container** forms over the **unchanged dispatch atoms** (`key` /
`keys` / `key-range` / `selector` / `group` / `sticky-set` + lifecycle keywords —
they *are* the operational IR, so they are kept verbatim):

- **`(screen 'scope [keywords…] panel…)`** — registers a tree under `'scope`
  (the `define-tree` analogue). Body is an **implicit grid of panels**; optional
  **`'cols N`** (default = CSS-intrinsic auto-fit). Lowers to a tree-root carrying
  `'renderer 'panel-grid` (+ `'cols`).
- **`(panel "label" ['span 'narrow|'wide|'full] child…)`** — a transparent visual
  card (the `category` analogue). Children are atoms / `open` / a live-list block.
  Lowers to a **`'kind 'category`** node + a `'span` entry → `flatten-categories`
  / `find-child` keep descending unchanged. Default span `narrow`; **auto-`wide`**
  when a live-list block is present and no explicit span is given.
- **`(open KEY LABEL [keywords…] panel…)`** — a navigable drill-down into a
  sub-screen (the panel-native replacement for `(key K L (overlay …))`). Lowers to
  a navigable **`group`** whose children are the sub-grid's lowered panels,
  carrying `'renderer 'panel-grid`.
- **`fragment`** — reusable splice of panels/keys, built on the existing
  `expand-splices` (state-machine.sld:205). `02-fragments-splice-k11`'s job.

Loose top-level keys under a `screen` (outside any `panel`) pack into an implicit
**"General"** panel — the presentation-first analogue of `pack-node-runs`.

## Context (anchors)

- **ADR-0011** charter (presentation authored, operations *extracted*);
  **ADR-0012** fixes the concrete surface above.
- `lib/modaliser/dsl.sld`: `category` (334–344) takes `(label . children)`;
  `group` (299–332) has the keyword loop that accumulates **opaque extras** into
  the node alist — the pattern `'span` / `'renderer` / `'cols` ride on;
  `pack-node-runs` / `flush-node-run` (553–593) is the misc/category bucketing to
  mirror as **panel packing**; `overlay` / `define-tree` (400–538) attach the
  renderer. **In this codebase lowering happens at construction time** — the new
  forms emit operational alists directly, exactly like `category`/`group` do.
- `state-machine.sld`: `node-renderer` / `node-renderer-payload` (308–324) read
  metadata back; `flatten-categories` / `find-child` (177–331), `expand-splices`
  (205) — **must keep working untouched**.
- The old forms (`define-tree` / `category` / `overlay` / `pack-node-runs`) **stay
  working** (additive) — no flag-day. Real config migration is
  [[config-migration-k8]]; deprecation of old forms is [[docs-tests-k9]].
- **Portability:** stay within `(scheme …)` / `(srfi …)` / `(modaliser …)`;
  `check-portable-surface.sh` stays green.

## Co-design notes

- The `'renderer 'panel-grid` marker + the per-panel metadata shape (`'span`,
  panel label, `'cols`) is the contract consumed by **[[panel-grid-renderer-k4]]**
  — co-design the payload shape with that leaf as it is built.
- Do **not** migrate real configs here — a minimal example screen tree suffices
  for tests.
