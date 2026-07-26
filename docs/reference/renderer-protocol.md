# Renderer protocol

The overlay renders through a **two-tier renderer registry**.

**Tier 1 — the body renderer.** Which body renderer draws a node is
**derived from its Display value's shape** — there is no authored
renderer marker (ADR-0011 retired the `'renderer 'panel-grid` one). A
display carrying layout structure — `'panels`, `'loose`, `'embed`,
`'cols` or `'layout` — selects the panel grid; a display carrying only
breadcrumb / row-order data (a `walk`'s `'display-name`, a plain group's
`'order`), or no display at all, keeps the built-in list renderer:

| Body renderer | Selected when | Scheme payload builder | JS renderer |
|---|---|---|---|
| panel grid | the display value carries layout structure (`screen` / `open`, or a bare `with-display` that authors any of it) | `panel-grid-payload-json` | `overlayRenderers['panel-grid']` |
| default list | anything else — a plain `(group …)`, a walk's mode tree, a display-less node | inline list payload | `overlayRenderers.list` |

`panel-grid-node?` (in `overlay.scm`) is that derivation, and the panel
grid is the sole custom body renderer — `renderer-body-json` errors
loudly on any other renderer symbol reaching it.

**Tier 2 — the block renderer.** A *block* (an alist carrying `'type`)
is drawn by the JS handler registered under
**`window.overlayBlockRenderers[TYPE]`** — a *separate* registry from the
body renderers' `window.overlayRenderers`. The bundled block types are
the live lists and the diagram: `window-list`, `window-diagram`,
`iterm-panes`, `iterm-tabs`, `herdr-list`, `herdr-jump-legend`,
`display-list`. The **panel-grid body composes tier 2**: it draws each
panel's key-rows with the shared row renderer (`renderPanelRow` in
`overlay.js`) and draws a placed live list by looking that block's own
tier-2 renderer up (`renderPanelList`).

So `panel-grid` is a tier-1 body renderer that *reuses* the tier-2 block
renderers for the dynamic lists the display places inside it — two
registries, two levels of dispatch.

Source: [`ui/overlay.scm`](../../Sources/Modaliser/Scheme/ui/overlay.scm)
(`renderer-body-json`, `panel-grid-payload-json`,
`block-json`, `push-overlay-update`) and
[`ui/overlay.js`](../../Sources/Modaliser/Scheme/ui/overlay.js)
(`window.overlayRenderers` for bodies,
`window.overlayBlockRenderers` for blocks).

Both the initial HTML paint (`render-overlay-custom`) and incremental
push-updates (`push-overlay-update`) route the body through the single
`renderer-body-json` dispatch, so the two paths can never diverge.

## The render plan and the panel-grid payload

A `screen` (or a drilled-into `open`) lowers to a group whose children are
**flat dispatch atoms** and whose single `'display` entry holds the whole
Display value — panels referencing those children by key, block placement
by reference, the loose region, spans, order, `'cols` / `'layout` /
`'embed`. Nothing panel-shaped sits among the children.

The overlay does not read that value directly. `resolve-display`
(pure, in `(modaliser display-dsl)`) turns `(children, display value)`
into a **render plan** — panel membership, row order, embed-row
exclusion and the block partition all resolved — and
`panel-grid-payload-json` only *serializes* that plan, firing the two
things a pure function can't: `'hidden` thunks and each block's
`'on-render-fn`. So the panel-grid payload is one serialization step away
from portable data:

```json
{
  "type": "panel-grid",
  "rootId": "global",              // display-root identity (scope + anchor path); present on overlay renders
  "cols": 3,                       // omitted when no 'cols authored
  "layout": "grid",                // omitted for the masonry default; "grid" opts into deterministic packing
  "sections": [ <section>, … ],    // present only when the node authors 'embed
  "activeSection": "a",            // present only while the Visit sits on that section
  "loose": [ <row> | <block>, … ], // the bare, header-less region above the grid; [] when empty
  "panels": [
    {
      "label": "Applications",
      "span": "narrow",            // "narrow" | "wide" | "full"
      "bare": true,                // present (true) only when the panel hosts a window-diagram
      "rows": [ <row>, … ],
      "list": <block>              // present only when the panel embeds a live list
    },
    …
  ]
}
```

- **`loose`** (bare-loose-rows-k23) is the screen/open's loose region —
  everything not wrapped in a `(panel …)` — rendered **bare** (header-less, no
  card) **above** the panel grid by a `.panel-loose` block. Items keep
  declaration order; each is either a `<row>` (a loose atom, or a folded
  top-level `open` → an `isGroup` drill row) or a `<block>` (a loose diagram /
  live-list, serialized through `block-json` exactly like a panel's `list`). The
  JS tells them apart by shape: a block carries `"type"`, a row carries `"key"`.
  An empty array means the JS draws no `.panel-loose`. An empty `"panels"` array
  (a loose-only screen) means it draws no `.panel-grid`.
- **`<row>`** is the shared entry-row shape (`entry->row-json`):
  `{ "key": "…", "label": "…", "isGroup": bool, "isNext": bool }`.
  `key` is ready key-display HTML (modifier glyphs pre-wrapped). Rows
  carrying `'hidden` are filtered out here (the flag may be a runtime
  thunk, so the pure plan can't pre-drop them). A live list's digit range
  never reaches the plan at all: those rows live *inside* the block spec
  as `'block-children` and are expanded only by `dispatch-children`, so
  the list section is the only thing that renders them.
- **`span`** is always present — the display's panel clause carries it,
  defaulted at construction to `narrow`, or `wide` when the panel
  references a block. The JS maps it to a grid column span:
  `narrow` = 1, `wide` = 2, `full` = the whole row.
- **`list`** is present only when the panel embeds a dynamic list. It is
  serialized through `block-json` (the return-and-merge path described
  below), so the block's `on-render-fn` fires and its live rows merge in. When that list owns the selection cursor, its
  current selected index rides into the payload as `"selected"`, which
  the JS marks `.is-focused`. (A **loose** live-list block is serialized
  first, so it claims the cursor ahead of any panel list.)
- **`bare`** is emitted (`true`) only when the panel's embedded block is a
  `window-diagram` (keyed on the block `'type`; see `panel-bare?`). The JS adds
  the `.panel--bare` modifier so `base.css` drops the card chrome (fill / border
  / shadow) and the list inset, letting the diagram's transparent empty cells
  reveal `--overlay-body-bg` — the window-size proportions read against the body
  tint and there is no white card edge to misalign with the start-aligned grid.
  Auto-applied, no config opt-in; other panels keep their white cards. (A loose
  block needs no `bare` flag — every block in the loose region is drawn bare via
  `.panel-loose .panel-list`.)

A top-level `open` (a navigable group directly under a `screen` / `open`)
**folds into the loose region** as a single drill `<row>` (`isGroup` true);
pressing its key still drills in. A nested `open` declared *inside* a panel
rides that panel's rows as an ordinary accent group-row. A key listed in the
node's `'embed` is the exception to both: its target renders as an embedded
**section** instead (below), and its drill/group row is dropped — the section
replaces the row.

## Embedded sections and the restyle protocol

A node authoring `'embed` (a list of key strings — `screen`/`open` in
[dsl.md](dsl.md)) renders as a **display root** (ADR-0011, CONTEXT.md):
one persistent layout spanning the node and each embedded key's target,
which serializes as a `<section>` card in the same grid the panels pack
into:

```json
{ "key": "a", "keyHtml": "a", "label": "Agents",
  "span": "narrow",              // "wide" when the target carries a live-list block
  "rows": [ <row>, … ],          // the target's static rows: its splice-expanded
                                 // children, blocks partitioned out, ordered by
                                 // the target's own display 'order
  "list": <block> }              // present ONLY while this section is active
```

The Scheme side resolves the **display anchor** once for the initial paint,
the push update, and the DOM-shape tracker (`display-anchor` in
`overlay.scm`): when the current path's last key is in its parent's
`'embed`, the *parent* renders, with `"activeSection"` naming the section.
`"rootId"` (scope + anchor path) is the root's identity.

Contracts (spec `configuration-value.md` "The two-layer node model"):

- **Unvisited sections are static.** An inactive section serializes its
  static rows only — its live-list block is *not* serialized (no
  `on-render-fn` fires), and gates/providers are never evaluated for it.
  On activation the section's `"list"` rides the payload — the
  come-to-rest snapshot populates the section.
- **Restyle, never rebuild.** `overlay.js` stamps `data-root-id` and
  `data-active-section` on the `.overlay-custom-body`. An update whose
  `rootId` matches the DOM and whose `activeSection` moved takes the
  restyle fast path (`restylePanelGridActiveSection`): toggle the marker
  attribute + `.embed-section--active`, re-render only the newly active
  section's content. Root swaps and same-state content refreshes (e.g. a
  cyclic re-arm's live-list update) fall through to the full rebuild.
- **Dimming states liveness** (`base.css`): with no active section the
  section cards dim (their keys are not live); with one active,
  everything but that section dims and the section's header keycap — the
  fired key — takes the accent. Active rows ≡ live keys.
- **The show delay binds to the root** (`fire-group-descent!` in
  `fsm.sld`): a descent along an embedded edge with the overlay still
  closed does not re-arm the pending delayed show — the root's original
  deadline stands, and the delayed paint shows the root with the section
  already active.

`'embed` references are validated at lowering (`lower-node!`): each key
must resolve to a group child of the authoring node — a missing key, a
command leaf, or a step-in rejects as a load-time error.

The panel grid's column count is **JS aspect-balanced by default**
(`balancePanelGridColumns`): a measurement pass over the rendered grid
picks the track count whose shape lands closest to a target
width:height ratio, rather than maximizing what fits. An authored
`'cols N` (payload `"cols"`) hard-pins the track count and skips
measurement — the only override; `base.css`'s auto-fit `minmax` over
`--panel-min-width` is the pre-JS first-paint fallback. The loose region
columnizes separately (`layoutLooseColumns`, run after the grid so it can
read the settled width), since a bare key row is narrower than a panel
card. (The default list renderer that plain `(group …)` drill-downs use
*is* CSS-intrinsic — no column count is computed in Scheme or JS; see
[theming.md](theming.md#default-list-renderer).)

Panels **pack as masonry by default** (`display: grid-lanes`): each panel
drops into the shortest lane, so a short panel tucks up under a shorter
neighbour rather than being stranded by a tall panel's row track. An
authored `'layout 'grid` (payload `"layout"`, reflected onto the
`.panel-grid` as `data-layout="grid"`) opts back into the aligned grid,
where `grid-auto-flow: dense` backfills narrow tiles around wide/full
panels but row tracks share a height.

## Block spec shape

A block is an alist with the following recognised fields. It is a
**dispatch atom**: authored as a child of the node, where its keys and
hooks live; the Display value only *places* it, by reference id (its
`'id` entry, else its `'type` — `block-ref-id`).

| Field | Type | Required | Description |
|---|---|---|---|
| `'type` | symbol | yes | Tier-2 renderer identifier. Bundled: `'window-list`, `'window-diagram`, `'iterm-panes`, `'iterm-tabs`, `'herdr-list`, `'herdr-jump-legend`, `'display-list`. Custom renderers register a handler under `window.overlayBlockRenderers[TYPE]` in JS. |
| `'id` | symbol | optional | The block's reference id, overriding `'type`. Needed only to disambiguate two same-type blocks in one display — duplicate ids are a load-time error. |
| `'block-children` | node list | optional | The block's own dispatch entries (a live list's digit range, a diagram's cell keys). They stay *inside* the spec: `dispatch-children` (`fsm.sld`) expands them at read time, so the state machine routes presses without anything being lifted at construction, and they never reach the render plan. |
| `'on-render-fn` | thunk | optional | Side-effect + return-value hook fired before serialization. Return-and-merge pattern (see below). |
| `'on-enter-fn` | thunk | optional | Fires when the overlay containing this block becomes visible. See [Block hooks](#block-hooks). |
| `'on-leave-fn` | thunk | optional | Fires when the overlay closes. |
| `'cursor-targets-fn` | thunk | optional | `→ ((label . target) …)` accessor offered to the selection cursor; the first list to offer in a render pass owns the cursor. |
| `'cursor-initial-index-fn` | thunk | optional | `→` focused row index (or `#f`). Consulted **once**, when the list first claims the cursor (overlay open), to seed the selection on the currently-focused row instead of row 0; a later arrow-move is preserved across re-renders. `#f` / out-of-range falls back to row 0. The iTerm tab/pane lists supply this; the global windows list does not yet (`list-cursor-window-focus-k28`). |

Anything else in the alist passes through to the JSON payload —
renderers own their own keys (`'panels` for `window-diagram`,
`'windows` for `window-list`, etc.).

## The `on-render-fn` return-and-merge pattern

LispKit excludes `set-cdr!` — blocks cannot mutate their own spec
between renders to splice live data. Instead, the renderer calls
`(fn)` for each block before serialization; if the return value is a
pair/alist, it's merged into the spec for that render (override on
collision). A non-pair return is treated as side-effect only.

This is how the window-list block injects the current window snapshot:

```scheme
(define (make-window-list-block . opts)
  …
  (list (cons 'type 'window-list)
        (cons 'on-render-fn
          (lambda ()
            (paint-and-snapshot! chip-opts)             ; side effects
            (list (cons 'windows current-windows-data)))) ; merged in
        (cons 'on-leave-fn
          (lambda () (hints-hide)))))
```

The serializer sees `(spec ∪ on-render-result)`, so the emitted JSON
carries `"windows": [...]` per render even though the spec itself
never holds windows data. Every block goes through the same `block-json`
path wherever the display places it — inside a `(panel …)`, **loose** in
the bare region, or as an *active* section's list — so the merge is
uniform. The one deliberate exception: an **inactive** embedded section's
block is not serialized at all, so its `'on-render-fn` never fires (see
[Embedded sections](#embedded-sections-and-the-restyle-protocol)).

Order of operations per render:

1. The body renderer walks the render plan: the loose region first (so a
   loose list claims the selection cursor ahead of any panel list), then
   each panel's `'list`, then the active section's.
2. For each block: invoke `'on-render-fn` (if procedure). Capture
   return value.
3. Serialize `(append block on-render-return)` to JSON. Later
   alist entries shadow earlier ones, so dynamic data wins.

## Block hooks

A block's `'on-enter-fn` / `'on-leave-fn` fire **structurally**, from the
node's own splice-expanded children — nothing is composed at
construction. `run-on-enter` / `run-on-leave` (`fsm.sld`, via
`node-block-hook-fns`) run the node's own user hook first, then each block
child's fn in declaration order:

- **On enter:** the node's `'on-enter` (if any), then each block's
  `'on-enter-fn`.
- **On leave:** the node's `'on-leave` (if any), then each block's
  `'on-leave-fn`.

Because the firing is structural, the authoring surface is irrelevant: a
bare `tree-root` / `group` holding a block behaves identically to a
`screen` — the sugar composes nothing. Blocks reached through a `splice`
count; blocks under a nested `open` belong to *that* node and fire on its
own visit.

Block hooks stay **presentation-gated**, paired with `show`/`hide` — they
never fire from the unconditional `'entry` / `'exit` slots, so a chip
paint cannot happen behind an overlay that never displayed. Same
hook-gating rules as the user hooks (see
[state-machine.md](state-machine.md#hook-gating-on-enter--on-leave)):
they fire only when the overlay actually becomes visible.

## Chrome envelope on push-updates

The initial overlay render is HTML, built from `render-overlay-body`.
Subsequent navigation (descend / step-back / cyclic re-arm) sends an
*incremental update* to JS via `webview-eval("updateOverlay(...)")`.

For panel-grid bodies, the update payload is the renderer body augmented
with chrome fields:

| Field | Description |
|---|---|
| `rootSegments` | Breadcrumb root + path-labels — the current breadcrumb. |
| `path` | The key path from root, e.g. `["w", "p"]`. |
| `walk` | Boolean — whether the current node or any ancestor on the path is a Walk (`node-walk?`). |
| `footer` | Pre-rendered HTML for the footer (back-hint, Walk pip, and the `↑↓ move · ⏎ select · 1–9 jump` cursor hints when a live list owns the cursor). |

Without these fields, navigating from a flat root into a custom-renderer
group would leave the previous depth's chrome on screen (notably the
root footer with no backspace hint). Including the chrome in every push
lets JS refresh the header/footer alongside the body.

If the destination node uses a *different* tier-1 renderer than the DOM
was built for (e.g. a list root → a panel-grid group), the update path
falls back to a full `webview-set-html!` — the JS registry can reshape
its own container but cannot swap a `.overlay-entries` `<ul>` for an
`.overlay-custom-body` `<div>`.

The default list renderer has its own update path
(`push-overlay-update-default`) and doesn't need this envelope —
list updates already carry breadcrumb segments and a column count.

## Writing a custom block

A custom block is a tier-2 renderer. Minimum viable:

```scheme
(define-library (my-blocks counter)
  (export counter-block)
  (import (scheme base) (modaliser overlay-assets))
  (begin
    (define (counter-block initial)
      (list (cons 'type 'counter)
            (cons 'count initial)
            (cons 'on-render-fn
              (lambda ()
                (list (cons 'count (current-counter-value)))))))

    (add-overlay-asset-file! 'css "lib/my-blocks/counter.css")
    (add-overlay-asset-file! 'js  "lib/my-blocks/counter.js")))
```

Then in JS, register a **block** renderer — note the registry name
(`overlayBlockRenderers`, not the body renderers' `overlayRenderers`) and
the argument order (payload first, container second):

```javascript
window.overlayBlockRenderers = window.overlayBlockRenderers || {};
window.overlayBlockRenderers['counter'] = function(block, container) {
  container.textContent = '';
  const el = document.createElement('div');
  el.className = 'counter';
  el.textContent = block.count;
  container.appendChild(el);
};
```

The renderer receives the parsed payload (everything from your block's
alist, plus `on-render-fn` merges) and the container element to draw
into — `renderPanelList` has already given it the
`block block-<type>` classes, so your CSS scopes off those. Update calls
re-invoke the same function with the new payload; clear the container
yourself, as the bundled renderers do.

Author the block as a child of the node — it is a dispatch atom — and
let the display place it: inside a `(panel …)` as that panel's single
live list, or **loose** in the bare region if no panel references it. On
the [bare surface](dsl.md#the-bare-authoring-surface) that placement is a
`(d:block 'counter)` ref.

Bundling assets: `(add-overlay-asset-file! 'css PATH)` and
`(add-overlay-asset-file! 'js PATH)` (from `(modaliser
overlay-assets)`) register file paths relative to the Scheme bundle
root. The overlay's `<head>` concatenates them after `base.css` and
`overlay.js`, in registration order.

## See also

- [dsl.md](dsl.md) — `screen` / `panel` / `open`, the embedded live list,
  and [the bare display surface](dsl.md#the-bare-authoring-surface) that
  builds the display value `resolve-display` consumes.
- [libraries.md](libraries.md) — the bundled blocks
  (`window-list`, `window-diagram`, `iterm-panes`, `iterm-tabs`).
- [theming.md](theming.md) — CSS variables your renderer can consume.
