# Renderer protocol

The overlay renders through a **two-tier renderer registry**.

**Tier 1 — the body renderer.** A group's `'renderer` metadata selects
how its whole body is drawn. Three outcomes:

| `'renderer` | Authored by | Scheme payload builder | JS renderer |
|---|---|---|---|
| `'panel-grid` | `screen` / `open` (layout DSL) | `panel-grid-payload-json` | `overlayRenderers['panel-grid']` |
| `'blocks` | `define-tree` / `overlay` (legacy) | `block-list-payload-json` | `overlayRenderers.blocks` |
| *(none)* | a plain `(group …)` | inline list payload | `overlayRenderers.list` |

**Tier 2 — the block renderer.** A *block* (an alist carrying `'type`)
is drawn by the JS handler registered under `window.overlayRenderers[TYPE]`.
The block-list body iterates its blocks and dispatches each by `'type`
(`window-list`, `iterm-panes`, `window-diagram`, the legacy
`which-key`). The **panel-grid body composes tier 2**: it draws each
panel's key-rows with the shared row renderer (`window.overlayRenderRow`,
contributed by `which-key.js`) and draws a panel's embedded live list by
calling that list block's own tier-2 renderer.

So `panel-grid` is a tier-1 body renderer that *reuses* the tier-2 block
renderers for the dynamic lists inside its panels — one registry, two
levels of dispatch.

Source: [`ui/overlay.scm`](../../Sources/Modaliser/Scheme/ui/overlay.scm)
(`renderer-body-json`, `panel-grid-payload-json`, `block-list-payload-json`,
`block-json`, `push-overlay-update`) and
[`ui/overlay.js`](../../Sources/Modaliser/Scheme/ui/overlay.js)
(`window.overlayRenderers`).

Both the initial HTML paint (`render-overlay-custom`) and incremental
push-updates (`push-overlay-update`) route the body through the single
`renderer-body-json` dispatch, so the two paths can never diverge.

## The panel-grid payload

A `screen` (or a drilled-into `open`) lowers to a group carrying
`'renderer 'panel-grid` plus an optional authored `'cols`. Its direct
children are the grid cells: **panels** (transparent `'kind 'category`
nodes) and nested **opens** (navigable `'kind 'group` nodes).
`panel-grid-payload-json` serializes exactly the alist the layout DSL
lowering emits:

```json
{
  "type": "panel-grid",
  "cols": 3,                       // omitted when no 'cols authored
  "panels": [
    {
      "label": "General",
      "span": "narrow",            // "narrow" | "wide" | "full"
      "rows": [ <row>, … ],
      "list": <block>              // present only when the panel embeds a live list
    },
    …
  ]
}
```

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
  serialized through the **same `block-json` path** the block-list
  renderer uses, so the block's `on-render-fn` fires and its live rows
  merge in (see below). When that list owns the selection cursor, its
  current selected index rides into the payload as `"selected"`, which
  the JS marks `.is-focused`.

A top-level `open` (a navigable group directly under a `screen`)
serializes as a minimal single-row panel whose one row is its drill-in
affordance; a nested `open` declared *inside* a panel rides that panel's
rows as an ordinary accent group-row.

The panel grid's column count is **CSS-intrinsic auto-fit by default**:
panels flow into as many `--panel-min-width` tracks as fit, with
`grid-auto-flow: dense` backfilling narrow tiles around wide/full
panels. An authored `'cols N` (payload `"cols"`) pins an explicit track
count instead. The legacy `set-overlay-aspect-ratio!` column search does
**not** apply here — it governs only the default list renderer.

## Block spec shape

A block is an alist with the following recognised fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `'type` | symbol | yes | Tier-2 renderer identifier. Built-ins: `'window-list`, `'window-diagram`, `'iterm-panes`, `'iterm-tabs`, and the legacy `'which-key`. Custom renderers register a handler under `window.overlayRenderers[TYPE]` in JS. |
| `'block-children` | node list | optional | Dispatch entries — keys lifted onto the parent group's `'children` so the state machine routes presses correctly. The `(overlay …)` constructor lifts these for legacy block-list groups; `(panel …)` lifts an embedded list's `'block-children` into the panel's dispatch children. |
| `'on-render-fn` | thunk | optional | Side-effect + return-value hook fired before serialization. Return-and-merge pattern (see below). |
| `'on-enter-fn` | thunk | optional | Fires when the overlay containing this block becomes visible. Composed with user-supplied `'on-enter` in the parent `(overlay …)` / `(screen …)` / `(open …)`. |
| `'on-leave-fn` | thunk | optional | Fires when the overlay closes. Composed with user-supplied `'on-leave`. |
| `'cursor-targets-fn` | thunk | optional | `→ ((label . target) …)` accessor offered to the selection cursor; the first list to offer in a render pass owns the cursor. |

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
never holds windows data. This is identical whether the block sits at
the top level of a legacy `(overlay …)` or **embedded inside a
`(panel …)`** — the panel-grid renderer calls the same `block-json`.

Order of operations per render:

1. The body renderer walks its blocks (or a panel's `'list`).
2. For each block: invoke `'on-render-fn` (if procedure). Capture
   return value.
3. Serialize `(append block on-render-return)` to JSON. Later
   alist entries shadow earlier ones, so dynamic data wins.

## Hook composition

When the user supplies `'on-enter` / `'on-leave` to a container that
holds blocks — a legacy `(overlay …)`, or a `(screen …)` / `(open …)`
whose panels embed live lists — the resulting group's hooks are
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

For custom-renderer bodies (panel-grid and the legacy block-list), the
update payload is the renderer body augmented with chrome fields:

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

Your block can be embedded in a `(panel …)` as its single live list
(the panel-grid renderer calls `overlayRenderers[block.type]` for it),
or placed at the top level of a legacy `(overlay …)`.

Bundling assets: `(add-overlay-asset-file! 'css PATH)` and
`(add-overlay-asset-file! 'js PATH)` (from `(modaliser
overlay-assets)`) register file paths relative to the Scheme bundle
root. The overlay's `<head>` concatenates them after `base.css` and
`overlay.js`, in registration order.

## Legacy: the which-key payload

The which-key block — produced by the deprecated `define-tree` /
`category` / `overlay` auto-packing — has its own serialization path
(`which-key-payload-json`, handled specially in `block-json`). It
partitions its children into ordered segments (each `(category …)` its
own segment; consecutive loose entries coalesce into a `misc` segment),
chooses a column count from the total visible row count and the target
aspect ratio (`set-overlay-aspect-ratio!`), and distributes the segments
into that many columns:

```json
{
  "type": "which-key",
  "columns": [ [ <segment>, … ], … ]
}
```

where `<segment>` is `{ "kind": "misc", "rows": [...] }` or
`{ "kind": "category", "label": "…", "rows": [...] }`. This is the
auto-layout the panel grid replaces — a `panel` declares its grouping
and span explicitly instead of having the renderer infer them. New
configs should not depend on this path.

## See also

- [dsl.md](dsl.md) — `screen` / `panel` / `open`, the embedded live
  list, and the deprecated block forms.
- [libraries.md](libraries.md) — the bundled blocks
  (`window-list`, `window-diagram`, `iterm-panes`, `iterm-tabs`, and the
  legacy `which-key`).
- [theming.md](theming.md) — CSS variables your renderer can consume.
