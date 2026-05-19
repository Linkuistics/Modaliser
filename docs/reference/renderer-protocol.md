# Renderer protocol

The overlay renders one of two ways:

1. **List renderer (default)** — for groups with no `'renderer` keyword
   set. Emits a flat list of `(key, label)` rows partitioned into
   columns. The bundled which-key block uses the same row format but
   wrapped in a richer category-aware payload.
2. **Block-list renderer (`'renderer 'blocks`)** — for any group that
   declares `'renderer 'blocks` and a `'blocks (…)` payload.
   `define-tree` and `(overlay …)` both set this. The renderer
   iterates the block list, runs each block's `on-render-fn` (if any),
   and emits a typed JSON payload per block. The JS in
   `overlay.js` dispatches each block to its registered
   `window.overlayRenderers[TYPE]`.

This page describes the block-list protocol: what shape blocks have,
which hooks they can opt into, and how the chrome envelope flows
through push-updates.

Source: [`ui/overlay.scm`](../../Sources/Modaliser/Scheme/ui/overlay.scm)
(see `block-list-payload-json`, `block-json`, `push-overlay-update`).

## Block spec shape

A block is an alist with the following recognised fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `'type` | symbol | yes | Renderer identifier. Built-ins: `'which-key`, `'window-list`, `'window-diagram`. Custom renderers register a handler under `window.overlayRenderers[TYPE]` in JS. |
| `'block-children` | node list | optional | Dispatch entries — keys lifted onto the parent group's `'children` so the state machine routes presses correctly. The `(overlay …)` constructor in `(modaliser dsl)` does the lifting automatically. |
| `'on-render-fn` | thunk | optional | Side-effect + return-value hook fired before serialization. Return-and-merge pattern (see below). |
| `'on-enter-fn` | thunk | optional | Fires when the overlay containing this block becomes visible. Composed with user-supplied `'on-enter` in the parent `(overlay …)`. |
| `'on-leave-fn` | thunk | optional | Fires when the overlay closes. Composed with user-supplied `'on-leave`. |

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
never holds windows data.

Order of operations per render:

1. The renderer walks `'blocks`.
2. For each block: invoke `'on-render-fn` (if procedure). Capture
   return value.
3. Serialize `(append block on-render-return)` to JSON. Later
   alist entries shadow earlier ones, so dynamic data wins.

## Hook composition in `(overlay …)`

When the user calls `(overlay 'on-enter user-hook 'on-leave user-hook
… block-1 block-2 …)`, the resulting group's hooks are composed:

- **On enter:** `user-on-enter` runs first; then each block's
  `'on-enter-fn` in declaration order.
- **On leave:** `user-on-leave` runs first; then each block's
  `'on-leave-fn` in declaration order.

The composed thunk is `#f` when nothing would run, so the state
machine's `node-on-enter` / `node-on-leave` accessors see a clean
`#f` rather than an empty no-op procedure.

Same hook-gating rules apply (see
[state-machine.md](state-machine.md#hook-gating-on-enter--on-leave)):
all hooks fire only when the overlay actually becomes visible.

## The which-key payload

The which-key block has its own serialization path (handled
specially in `block-json`). The output shape:

```json
{
  "type": "which-key",
  "cols": <integer>,
  "segments": [
    { "kind": "misc",     "rows": [...] },
    { "kind": "category", "label": "…", "rows": [...] },
    …
  ]
}
```

Each row is `{ "key": "…", "label": "…", "kind": "…", "sticky": bool }`.

Partitioning:

- Consecutive non-category entries coalesce into one `"kind":"misc"`
  segment at their position.
- Each `(category …)` becomes its own segment.
- `'hidden #t` entries are dropped from the rendered output (but
  remain dispatchable in the state machine — used by the
  `window-list` block's `1..` digit range).

Column count is computed from total visible row count and the target
aspect ratio (`set-overlay-aspect-ratio!`).

`(modaliser dsl)`'s auto-pack splits mixed runs into two blocks
(uncategorised first, then categories) before serialization, so a
typical which-key block is homogeneous. The mixed path still works
inside an explicit user-authored `(which-key-block …)`; declared
order is preserved.

## Chrome envelope on push-updates

The initial overlay render is HTML, built from
`render-overlay-body` and `render-overlay-custom`. Subsequent
navigation (descend / step-back / sticky-reset) sends an *incremental
update* to JS via `webview-eval("updateOverlay(...)")`.

For block-list overlays, the update payload is the block body
augmented with chrome fields:

| Field | Description |
|---|---|
| `rootSegments` | Breadcrumb root + path-labels — the current breadcrumb. |
| `path` | The key path from root, e.g. `["w", "p"]`. |
| `sticky` | Boolean — whether any sticky ancestor is on the path. |
| `footer` | Pre-rendered HTML for the footer (back-hint, sticky pip). |

Without these fields, navigating from a flat root into a nested
block-list group would leave the previous depth's chrome on screen
(notably the root footer with no backspace hint). Including the chrome
in every push lets JS refresh the header/footer alongside the body.

The default list renderer has its own update path
(`push-overlay-update-default`) and doesn't need this envelope —
list updates already carry breadcrumb segments.

## Writing a custom block

Minimum viable custom block:

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

Bundling assets: `(add-overlay-asset-file! 'css PATH)` and
`(add-overlay-asset-file! 'js PATH)` (from `(modaliser
overlay-assets)`) register file paths relative to the Scheme bundle
root. The overlay's `<head>` concatenates them after `base.css` and
`overlay.js`, in registration order.

## See also

- [dsl.md](dsl.md) — `(overlay …)`, `(which-key-block …)`, block
  packing.
- [libraries.md](libraries.md) — the bundled blocks
  (`window-list`, `window-diagram`, `which-key`).
- [theming.md](theming.md) — CSS variables your renderer can consume.
