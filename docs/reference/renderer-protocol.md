# Renderer protocol

The overlay renders through a **two-tier renderer registry**.

**Tier 1 — the body renderer.** A group's `'renderer` metadata selects
how its whole body is drawn. Two outcomes:

| `'renderer` | Authored by | Scheme payload builder | JS renderer |
|---|---|---|---|
| `'panel-grid` | `screen` / `open` (layout DSL) | `panel-grid-payload-json` | `overlayRenderers['panel-grid']` |
| *(none)* | a plain `(group …)` | inline list payload | `overlayRenderers.list` |

`'panel-grid` is the sole custom body renderer; any other `'renderer`
marker is a misuse and errors loudly.

**Tier 2 — the block renderer.** A *block* (an alist carrying `'type`)
is drawn by the JS handler registered under `window.overlayRenderers[TYPE]`.
The built-in block types are the live lists — `window-list`,
`iterm-panes`, `iterm-tabs`, `window-diagram`. The **panel-grid body
composes tier 2**: it draws each panel's key-rows with the shared row
renderer (`renderPanelRow` in `overlay.js`) and draws a panel's embedded
live list by calling that list block's own tier-2 renderer.

So `panel-grid` is a tier-1 body renderer that *reuses* the tier-2 block
renderers for the dynamic lists inside its panels — one registry, two
levels of dispatch.

Source: [`ui/overlay.scm`](../../Sources/Modaliser/Scheme/ui/overlay.scm)
(`renderer-body-json`, `panel-grid-payload-json`,
`block-json`, `push-overlay-update`) and
[`ui/overlay.js`](../../Sources/Modaliser/Scheme/ui/overlay.js)
(`window.overlayRenderers`).

Both the initial HTML paint (`render-overlay-custom`) and incremental
push-updates (`push-overlay-update`) route the body through the single
`renderer-body-json` dispatch, so the two paths can never diverge.

## The panel-grid payload

A `screen` (or a drilled-into `open`) lowers to a group carrying
`'renderer 'panel-grid` plus an optional authored `'cols` / `'layout` and a
`'loose` region. Its direct children are the dispatch children (loose atoms /
folded opens, the lifted keys of loose blocks, and the **panel** categories);
the categories serialize as grid cells, while the loose region rides the
`'loose` marker. `panel-grid-payload-json` serializes exactly the alist the
layout DSL lowering emits:

```json
{
  "type": "panel-grid",
  "cols": 3,                       // omitted when no 'cols authored
  "layout": "grid",                // omitted for the masonry default; "grid" opts into deterministic packing
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
  `{ "key": "…", "label": "…", "isGroup": bool, "isSticky": bool }`.
  `key` is ready key-display HTML (modifier glyphs pre-wrapped). Hidden
  entries and nested-category entries are filtered out — including the
  lifted, hidden digit range of an embedded list, which the list section
  renders instead.
- **`span`** is always present (`make-panel-node` defaults it to
  `narrow`, or `wide` when the panel embeds a list). The JS maps it to a
  grid column span: `narrow` = 1, `wide` = 2, `full` = the whole row.
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
rides that panel's rows as an ordinary accent group-row.

The panel grid's column count is **CSS-intrinsic auto-fit by default**:
panels flow into as many `--panel-min-width` tracks as fit. An authored
`'cols N` (payload `"cols"`) pins an explicit track count instead. (The
default list renderer that plain `(group …)` drill-downs use is likewise
CSS-intrinsic — no column count is computed in Scheme; see
[theming.md](theming.md#default-list-renderer).)

Panels **pack as masonry by default** (`display: grid-lanes`): each panel
drops into the shortest lane, so a short panel tucks up under a shorter
neighbour rather than being stranded by a tall panel's row track. An
authored `'layout 'grid` (payload `"layout"`, reflected onto the
`.panel-grid` as `data-layout="grid"`) opts back into the aligned grid,
where `grid-auto-flow: dense` backfills narrow tiles around wide/full
panels but row tracks share a height.

## Block spec shape

A block is an alist with the following recognised fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `'type` | symbol | yes | Tier-2 renderer identifier. Built-ins: `'window-list`, `'window-diagram`, `'iterm-panes`, `'iterm-tabs`. Custom renderers register a handler under `window.overlayRenderers[TYPE]` in JS. |
| `'block-children` | node list | optional | Dispatch entries — keys lifted onto the parent group's `'children` so the state machine routes presses correctly. `(panel …)` lifts an embedded list's `'block-children` into the panel's dispatch children. |
| `'on-render-fn` | thunk | optional | Side-effect + return-value hook fired before serialization. Return-and-merge pattern (see below). |
| `'on-enter-fn` | thunk | optional | Fires when the overlay containing this block becomes visible. Composed with user-supplied `'on-enter` in the parent `(screen …)` / `(open …)`. |
| `'on-leave-fn` | thunk | optional | Fires when the overlay closes. Composed with user-supplied `'on-leave`. |
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
never holds windows data. This fires identically for every block
**embedded inside a `(panel …)`** — the panel-grid renderer calls
`block-json` for each one.

Order of operations per render:

1. The body renderer walks its blocks (or a panel's `'list`).
2. For each block: invoke `'on-render-fn` (if procedure). Capture
   return value.
3. Serialize `(append block on-render-return)` to JSON. Later
   alist entries shadow earlier ones, so dynamic data wins.

## Hook composition

When the user supplies `'on-enter` / `'on-leave` to a `(screen …)` /
`(open …)` whose panels embed live lists, the resulting group's hooks are
composed:

- **On enter:** the user hook runs first; then each block's
  `'on-enter-fn` in declaration order.
- **On leave:** the user hook runs first; then each block's
  `'on-leave-fn` in declaration order.

For `screen` / `open`, the composed blocks are the live lists embedded
in that level's **direct** panels; a list under a nested `open` composes
onto that open's group instead. The composed thunk is `#f` when nothing
would run, so the state machine's `node-on-enter` / `node-on-leave`
accessors see a clean `#f` rather than an empty no-op procedure.

Same hook-gating rules apply (see
[state-machine.md](state-machine.md#hook-gating-on-enter--on-leave)):
all hooks fire only when the overlay actually becomes visible.

## Chrome envelope on push-updates

The initial overlay render is HTML, built from `render-overlay-body`.
Subsequent navigation (descend / step-back / sticky-reset) sends an
*incremental update* to JS via `webview-eval("updateOverlay(...)")`.

For panel-grid bodies, the update payload is the renderer body augmented
with chrome fields:

| Field | Description |
|---|---|
| `rootSegments` | Breadcrumb root + path-labels — the current breadcrumb. |
| `path` | The key path from root, e.g. `["w", "p"]`. |
| `sticky` | Boolean — whether any sticky ancestor is on the path. |
| `footer` | Pre-rendered HTML for the footer (back-hint, sticky pip, and the `↑↓ move · ⏎ select · 1–9 jump` cursor hints when a live list owns the cursor). |

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

Then in JS, register a renderer:

```javascript
window.overlayRenderers['counter'] = function(host, payload) {
  host.innerHTML = `<div class="counter">${payload.count}</div>`;
};
```

The renderer receives the host DOM element and the parsed payload
(everything from your block's alist, plus `on-render-fn` merges).
Update calls re-invoke the same function with the new payload.

Your block can be embedded in a `(panel …)` as its single live list —
the panel-grid renderer calls `overlayRenderers[block.type]` for it.

Bundling assets: `(add-overlay-asset-file! 'css PATH)` and
`(add-overlay-asset-file! 'js PATH)` (from `(modaliser
overlay-assets)`) register file paths relative to the Scheme bundle
root. The overlay's `<head>` concatenates them after `base.css` and
`overlay.js`, in registration order.

## See also

- [dsl.md](dsl.md) — `screen` / `panel` / `open` and the embedded live
  list.
- [libraries.md](libraries.md) — the bundled blocks
  (`window-list`, `window-diagram`, `iterm-panes`, `iterm-tabs`).
- [theming.md](theming.md) — CSS variables your renderer can consume.
