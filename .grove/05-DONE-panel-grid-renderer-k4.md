# panel-grid-renderer-k4

**Kind:** work

## Goal

Add a dedicated **`panel-grid` overlay renderer** that draws a screen as a
**CSS-Grid of banded panels** from the presentation metadata [[layout-dsl-k3]]
emits, and **retire the Scheme-side auto-layout heuristics** (ADR-0011).

## Context

- `ui/overlay.scm` has two render paths: `render-overlay-default` (flat list) and
  `render-overlay-custom` (dispatch on the `node-renderer` symbol; emits
  `<div class="overlay-custom-body" data-renderer data-payload>`).
- `block-list-payload-json` (overlay.scm:379) builds
  `{"type":"blocks","blocks":[…]}`; `block-json` (395) dispatches per block.
- **To retire:** `which-key-payload-json` / `partition-which-key-segments` /
  `distribute-which-key-columns` / `segments-row-count` (411–506) and
  `overlay-column-count` (90) — the aspect-ratio auto-layout.
- JS: two-tier registry — `overlayRenderers[TYPE]` (`list`, `blocks`) +
  `overlayBlockRenderers[type]` (`which-key`, `window-list`, …); the `blocks`
  renderer (overlay.js:134) makes one `.block` div per block; `updateOverlay` /
  `bootstrapCustomBody` dispatch by `type`.
- `push-overlay-update` (overlay.scm:699) splices chrome (breadcrumb/sticky/
  footer) into the live payload — keep working for incremental list updates.
- **Keep** `which-key.js` `renderRow` / `renderCategory` (42–78) as the per-panel
  **key-row renderer**; delete its whole-overlay column packing.

## Input contract — the node-alist shape (from layout-dsl-k3)

Promoted here when `layout-dsl-k3` retired (it was that node's BRIEF). `lowering-k10`
fixed the node-metadata this renderer reads — the renderer owns the JSON; **this is
the alist shape it walks.** Consume exactly this:

- **screen / open group** carries `'renderer 'panel-grid` and, when authored,
  `'cols N` (read via `node-renderer-payload`). An `open` is a navigable
  `'kind 'group` (own `'key`/`'label`); a `screen` is the registered tree root.
- **each panel** is a `'kind 'category` node (transparent for dispatch) carrying:
  - `'label` — the banded-header text;
  - `'span` — always present, one of `'narrow|'wide|'full` (default `narrow`,
    auto-`wide` when a list is embedded);
  - `'children` — the dispatch atoms (key-rows) **plus** any embedded list block's
    lifted `block-children` (the hidden `1..` range), so `find-child` resolves
    digits transparently;
  - `'list` — present **iff** the panel embeds a live list; its value is the single
    block-spec (`'type` = `window-list`/`iterm-panes`/`iterm-tabs`), ready to feed
    the renderer's existing `block-json` path (call its `on-render-fn`, render
    rows). The block's `on-enter-fn`/`on-leave-fn` are **already composed** onto the
    screen/open group's `on-enter`/`on-leave` (like `define-tree`), so the renderer
    does **not** re-run lifecycle hooks.
- **General packing:** loose top-level atoms (outside any `panel`) lower to one
  leading `'kind 'category` panel labelled `"General"`, placed first, then the
  authored panels/opens in declaration order.
- **Fragments are invisible.** `fragment` (and `sticky-set`) lower to `'kind 'splice`
  nodes that `expand-splices` hoists away **at construction time** — the renderer
  never sees a splice node, only the lowered panels/keys. No renderer handling
  needed; a fragment-spliced panel is indistinguishable from an inline one.

## Done when

- `overlayRenderers['panel-grid']` registered.
- Scheme emits `{type:"panel-grid", cols?, panels:[{label, span, rows:[…],
  list?:{…}}]}` via a `panel-grid-payload-json` that reads node presentation
  metadata.
- JS builds the grid container, maps `span` → grid-column-span with
  `grid-auto-flow: dense`, and draws per-panel **banded header + key-rows**
  (reuse `renderRow`) + an optional **embedded live-list section**.
- Both the bootstrap and `push-overlay-update` paths handle the new payload;
  incremental live-list updates keep working.
- The retired Scheme auto-layout fns are deleted; `which-key`'s whole-overlay
  packing removed (row renderer kept).
- **Structural** CSS present (grid / panel / header / inset — not the aesthetic
  skin); a panel-grid payload **JSON snapshot test**; existing overlay tests
  updated; `check-portable-surface.sh` green.

## Notes

- Settle **grid column-count** here with [[layout-dsl-k3]] — recommend
  CSS-intrinsic `repeat(auto-fit, minmax(…))` + spans (no Scheme column search),
  with an optional authored `'cols`.
- The aesthetic (colors / bands / keycaps) is [[visual-skin-k5]]; this leaf is
  structure + payload only.
- Embedded live-list **cursor behaviour** is [[list-cursor-k6]]; here, just
  render the list section.
