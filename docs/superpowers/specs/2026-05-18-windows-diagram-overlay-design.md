# Windows diagram overlay — design

Date: 2026-05-18
Status: Approved (ready for implementation plan)

## Goal

Replace the textual which-key list for the Windows group with a diagrammatic panel that shows window-position keybindings spatially — each key letter sits in the screen region it targets. Generalise the mechanism so users can declare their own diagrammatic groups for arbitrary `cols × rows` divisions (halves, quarters, etc.), and add a numbered-window picker (`1..`) that paints chips on visible windows, mirroring the existing iTerm pane pattern.

The visual target (locked in during brainstorming, v19): a 3×2 grid of mini screen-diagrams above a strip of three text entries.

```
┌─────────────┐  ┌─────────────┐  ┌─────┐ ┌─────┐
│  d │ f │ g  │  │ D │ F │ G   │  │ e e│ │  t t│
└─────────────┘  ├───┼───┼─────┤  └─────┘ └─────┘
                 │ C │ V │ B   │
                 └───┴───┴─────┘
┌─────────────┐  ┌─────────────┐   n  → Named…
│ █████ m ███ │  │   ┌─┐  c    │  1.. → Window <n>
│ ███████████ │  │ → │ │ ←     │   r  → Restore
└─────────────┘  │   └─┘       │
                 └─────────────┘
```

Filled (white) cells = key target. The grid uses 0.5px / `rgba(0,0,0,0.65)` lines; SVG strokes use `vector-effect: non-scaling-stroke` at 1px so they render as exactly one device pixel and match the CSS borders. Key glyphs use the standard `.entry-key` style (blue, bold, 14px). Restore is byte-identical to a normal overlay entry.

## 1. Renderer mechanism (overlay.scm + overlay.js)

A group node may declare `'renderer 'diagram` and a `'panels` payload. Groups without `'renderer` keep the current key/arrow/label rendering — no behaviour change for any existing tree.

`render-overlay-body` (initial HTML) and `push-overlay-update` (incremental JSON update) check for `'renderer` on the group; when set, they emit a typed payload:

```js
{ type: "diagram", panels: [...], entries: [...] }
```

instead of the bare `{ entries: [...] }`. `overlay.js`'s top-level render loop dispatches on `payload.type`:

```js
window.overlayRenderers = window.overlayRenderers || {};
window.overlayRenderers.list = renderList;         // built-in default

function render(payload, container) {
  const fn = window.overlayRenderers[payload.type] || window.overlayRenderers.list;
  fn(payload, container);
}
```

Renderer libraries (incl. `diagram-panel`) register themselves into `window.overlayRenderers` when their JS is loaded. Headers, footers, and panel chrome are shared — only the body region is dispatched.

This is the "typed renderer registry" approach (option 2 from brainstorming). The future "arbitrary DOM via render-fn" escape hatch (option 3) slots into the same dispatch with a `'function` renderer type.

## 2. Panel-spec data model

A panel is one of three types:

- **`grid`** — N×M cells. Each cell is either a key glyph (rendered with `.has-key` white fill) or empty. Cells may span multiple grid positions (rectangular).
  ```js
  { type: "grid", cols: 3, rows: 2, cells: [
      {key: "D", col: 1, row: 1, colSpan: 1, rowSpan: 1},
      ...
  ]}
  ```

- **`center`** — outer frame + inner filled rect at fractional bounds + four inward arrows + key glyph in the inner rect.
  ```js
  { type: "center", key: "c" }
  ```

- **`fill`** — single white-filled rectangle covering the whole panel with a key glyph centred. (A `grid` of `cols: 1, rows: 1` with one full-span key is rendered identically; library code prefers the natural `grid` form, but `fill` is kept as an explicit type for clarity.)

JSON sent to JS as the panel list. Renderer draws each panel as a 102×60 (default) bordered rectangle in the panel-grid layout.

## 3. Single configurable builder (matrix-driven)

The builder takes an array of arrays whose values are the key strings (or `#f` for empty cells). Grid shape, bindings, and the panel-spec all derive from the matrix.

```scheme
(window:divisions '(("d" "f" "g")))                ; full thirds: d | f | g
(window:divisions '(("D" "F" "G")
                    ("C" "V" "B")))                ; half thirds, 6 cells
(window:divisions '(("e" "e" #f)))                 ; e spans cols 1-2; col 3 empty
(window:divisions '((#f "t" "t")))                 ; t spans cols 2-3
(window:divisions '(("m")))                        ; single cell = whole screen → Maximise

;; Halves and quarters fall out:
(window:divisions '(("h" "l")))                    ; left/right halves, full height
(window:divisions '(("H" "L")
                    ("N" "M")))                    ; quadrants
(window:divisions '(("a" "s" "d" "f")))            ; quarters, full height
(window:divisions '(("a") ("s")))                  ; top/bottom halves

;; 2D spans:
(window:divisions '(("x" "x" "y")
                    ("x" "x" "y")))                ; x = 2×2 block, y = full-height right
```

### Semantics

The matrix has `rows` rows and `cols` columns (every row same length, validated). For each unique non-`#f` value, find its bounding box `(minCol, maxCol, minRow, maxRow)` and emit:

- a `(key K …)` node with action
  `(move-window (minCol−1)/cols (minRow−1)/rows (maxCol−minCol+1)/cols (maxRow−minRow+1)/rows)`
- a panel cell at that bounding box, rendered as `.has-key` with the key glyph.

`#f` cells contribute nothing — no binding, no fill (empty grid cell in the diagram).

### Validation

Every cell inside a key's bounding box must be that same key. No `#f` holes, no other key splitting it. The builder throws a clear error otherwise — guarantees both the move-window rect and the diagram cell are clean rectangles.

```scheme
;; Rejected:
'(("x" "x" "y")
  ("x" #f  "y"))     ; x's bounding box is rows 1-2 × cols 1-2, but (2,2) is #f
```

### Return value

`window:divisions` returns a `<panel>` record carrying:
- the panel-spec (data for the JSON payload)
- the list of generated `(key …)` nodes

The convenience `(window:actions)` builder unpacks records, collects all panels and all keys, plus the center panel, plus text-only children, into a single `diagram-group` node.

### Center panel (special)

`center-window` is not a grid move — it centres without resizing — so it has its own constructor:

```scheme
(window:center-panel 'key "c")
;; → <panel> with spec {type: "center", key: "c"} and key node (key "c" "Center" center-window)
```

## 4. Numbered window selector (`1..`)

Mirrors the existing iTerm pane pattern (`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`). Per leader press:

1. The Windows group's tree is rebuilt:
   - Enumerate current-space windows with bounds via the new `list-current-space-windows` Scheme function (see §5).
   - Compute hint-chip positions from each window's `x/y/w/h` (top-left + small fractional offset, same shape as `ax-target-hints`).
   - Generate a `(key-range "1.." "Window <n>" labels action)` node whose action focuses the N-th window by `(windowId, ownerPid)`.
2. The group's `'on-enter` hook calls `(hints-show chip-positions)`; `'on-leave` calls `(hints-hide)`.

The rebuild happens via `set-local-context-suffix!` if running inside an app's local tree; for the global windows group, an equivalent hook on `define-tree 'global` provides the same per-press rebuild semantics (a small extension — currently the per-press rebuild is only wired for local trees).

## 5. Swift-side: surface window bounds to Scheme

`WindowCache.listWindows()` already computes `bounds: CGRect` for current-space windows (`WindowCache.swift:102-117`). The data is collected; only the Scheme alist excludes it.

Add a new function:

```swift
/// (list-current-space-windows) → list of alists
/// Each entry: text, subText, icon, iconType, windowId, ownerPid, x, y, w, h
```

It returns the subset of `listWindows()` whose `bounds != .zero` (current-space windows only, since cached other-space entries have no live bounds), with `x/y/w/h` fixnum keys added to the alist. Existing `list-windows` and `focus-window` are unchanged.

## 6. Named selector rename

`s "Select Window"` (current `actions` body in `window-actions.sld`) becomes `n "Named…"`. Same selector body, just relabeled and rekeyed. Sits as a text entry in the bottom-right of the diagram panel.

## 7. Library-owned assets (CSS + JS)

A new asset-registration API lets any library contribute snippets that the overlay concatenates into the panel HTML.

### File layout

```
Sources/Modaliser/Scheme/lib/modaliser/diagram-panel.sld   ; panel + renderer registration
Sources/Modaliser/Scheme/lib/modaliser/diagram-panel.js    ; render function
Sources/Modaliser/Scheme/lib/modaliser/diagram-panel.css   ; panel + cell + arrow styles
```

The `.sld` reads its sibling files (via `read-file-text` resolved against `*scheme-directory*`) and registers them at library-load time:

```scheme
(add-overlay-asset! 'css (read-file-text (library-asset "lib/modaliser/diagram-panel.css")))
(add-overlay-asset! 'js  (read-file-text (library-asset "lib/modaliser/diagram-panel.js")))
```

### New overlay API

Two helpers in `overlay.scm`:

- `(add-overlay-asset! kind text)` — appends to `overlay-extra-css` or `overlay-extra-js` (list, preserves load order).
- `render-overlay-html` concatenates `base.css + extra-css + user-css` for the `<style>` block, and `overlay.js + extra-js` for the `<script>` block. The existing `set-overlay-css!` (set-once user override) stays as-is and applies last so the user wins.

The diagram-panel JS registers into the renderer dispatch:

```js
window.overlayRenderers = window.overlayRenderers || {};
window.overlayRenderers.diagram = function(payload, container) { ... };
```

### Discoverability for users

`diagram-panel` becomes the canonical worked example for "library that owns its renderer". Users writing their own:

1. Put `.scm` / `.js` / `.css` in `~/.config/modaliser/my-renderer/`.
2. Their `.scm` calls `(add-overlay-asset! 'css …)` and `(add-overlay-asset! 'js …)` the same way.
3. Their JS registers `window.overlayRenderers['my-type'] = …`.
4. Their group nodes declare `'renderer 'my-type 'payload …`.

The existing `(modaliser apps iterm)` library (which sets a context-suffix handler and paints native chips) fits the same "library-owned extension" mould, and its docs can cross-reference diagram-panel as the renderer analogue.

## 8. Non-Swift files always live in (and load from) the user config dir

**Principle:** the bundle's `Sources/Modaliser/Scheme/` tree is the canonical source. On startup, `SysSync` mirrors it (fingerprint-gated) into `~/.config/modaliser/sys/scheme/`. The Scheme runtime *always* reads from the synced location — `*scheme-directory*` points there. The bundle is never read directly at runtime except by the sync itself.

### What gets synced

- `root.scm`, `default-config.scm`, `base.css` — current bundle-root files
- `ui/overlay.{scm,js}`, `ui/chooser.{scm,js}`, `ui/css.scm` — UI subdirectory
- `lib/modaliser/**` — already synced today; folded into the broader sync
- New `lib/modaliser/diagram-panel.{sld,js,css}` — rides the same train

### Special cases

`default-config.scm` keeps its one-time-seed semantics: it seeds `~/.config/modaliser/config.scm` on first launch and never overwrites. It *also* syncs to `sys/scheme/default-config.scm` like everything else — so users can `diff` their `config.scm` against the canonical default after an upgrade.

### Search-path shadow stays uniform

User-level files (e.g. `~/.config/modaliser/modaliser/diagram-panel.js`, or `~/.config/modaliser/base.css`) take precedence over the synced `sys/` copy. The mechanism is identical for code (.scm/.sld) and assets (.js/.css/.svg).

### Implementation impact

- `SysSync` broadens its source dir from `Sources/Modaliser/Scheme/lib/modaliser/` to `Sources/Modaliser/Scheme/` and its target from `sys/modaliser/` to `sys/scheme/`. Fingerprint and copy logic unchanged.
- `SchemeEngine.swift` sets `*scheme-directory*` to the synced sys dir (returned from `SysSync`) instead of the bundle Scheme dir.
- `overlay.scm`'s asset loads (`read-file-text (string-append *scheme-directory* "/base.css")` etc.) need no source change — `*scheme-directory*` just resolves to a different absolute path.
- The new `add-overlay-asset!` API uses `read-file-text` with paths under `*scheme-directory*` — automatically gets the synced (and possibly user-shadowed) copy.

### User experience

- Every bundled file is at `~/.config/modaliser/sys/scheme/` — browseable, diffable, copyable.
- Forking any file: copy it to the corresponding non-`sys/` shadow path. Next launch picks up the shadow automatically.
- Editing files in `sys/` directly is intentionally not preserved — sync overwrites them. The "shadow if you want to keep it" rule is the same as today, applied to more files.

## 9. Wiring summary

### New files

- `Sources/Modaliser/Scheme/lib/modaliser/diagram-panel.sld`
- `Sources/Modaliser/Scheme/lib/modaliser/diagram-panel.js`
- `Sources/Modaliser/Scheme/lib/modaliser/diagram-panel.css`

### Touched Swift

- `WindowLibrary.swift` — register `list-current-space-windows`; existing `list-windows` and `focus-window` untouched.
- `SysSync.swift` — broaden source/target paths (one-line change to the constants; logic unchanged).
- `SchemeEngine.swift` — set `*scheme-directory*` to the synced sys dir instead of the bundle Scheme dir.
- `WindowCache.swift` — **no change** (bounds already collected).

### Touched Scheme

- `lib/modaliser/window-actions.sld` — substantial: matrix-driven builder, dynamic tree with chip painting, renames `s`→`n`, integrates `1..` key-range, sets `'renderer 'diagram 'panels …` on the group, on-enter/on-leave hints hooks.
- `ui/overlay.scm` — add `add-overlay-asset!` API; thread `extra-css` / `extra-js` through `render-overlay-html`; dispatch on `'renderer` in `render-overlay-body` and `push-overlay-update` (typed JSON payload for `'diagram` groups).
- `ui/overlay.js` — wrap render loop in renderer dispatch; preserve the existing list renderer as the default.

### Untouched

- `base.css` (no diagram styles bleed into the core stylesheet).
- All other libraries (iTerm, ax-hints, hints, etc.).

## Open question (resolved during brainstorming)

- **Panel-spec constructors location:** in `diagram-panel.sld` (the library that owns the renderer). `window-actions.sld` imports it and adds `window:divisions` / `window:center-panel` as window-specific wrappers that compute `move-window` actions on top of the generic panel constructor.

- **Dynamic chip painting for `1..`:** iTerm pattern (per-leader-press rebuild via `set-local-context-suffix!`), extended with an equivalent hook on `define-tree 'global` so the global windows group rebuilds per press too.

## Non-goals

- No change to the chooser panel renderer (only the overlay).
- No change to `focus-window`, `move-window`, `toggle-fullscreen`, `restore-window`, or `center-window` semantics.
- No change to the sticky-mode / breadcrumb / footer rendering.
- No keymap migration: bindings stay alphabetical key-comparable (the matrix only changes how `window-actions` produces them, not the set of keys themselves).
