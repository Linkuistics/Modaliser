# Block-List Overlay — Detailed TDD Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The companion architecture doc lives at [`2026-05-18-block-list-overlay.md`](2026-05-18-block-list-overlay.md) — it captures the design rationale and is referenced from this plan; **do not re-litigate decisions documented there.**

**Goal:** Replace the windows-overlay's hardcoded "diagram + entries + windows-list" rendering pipeline with a generic *block-list* renderer. Each group declares an ordered list of typed blocks; each block ships as a `.sld + .js + .css` trio with a tagged-JSON contract and an optional on-render side-effect (e.g. chip painting). The current windows overlay becomes one configuration of this generic system.

**Architecture:** A new `'blocks` renderer is added alongside the existing `'diagram` renderer in `ui/overlay.scm`. Each block type lives under `lib/modaliser/blocks/<type>.{sld,js,css}` — the `.sld` exports a constructor and registers JS+CSS assets via `add-overlay-asset-file!`, the `.js` registers a render function on `window.overlayBlockRenderers[type]`, the `.css` scopes styles under a per-block class prefix. The renderer iterates the group's `'blocks` list, dispatches each block's JSON payload to its JS renderer in order, then runs any block-level on-render effects.

**Tech Stack:** Scheme (LispKit) for the overlay state machine, block constructors, and side-effect thunks. JS (WKWebView) for per-block DOM rendering. CSS for per-block styling. No new Swift code.

---

## Design contracts pinned (settled — read before reading tasks)

These resolve ambiguities in the architecture doc so each task has unambiguous file/function signatures. They are **derived from** the architecture doc's settled decisions, not in conflict with them.

### Block spec shape (Scheme-side)

A block is an alist returned by its constructor. Required keys:

- `'type` SYMBOL — block type tag (e.g. `'window-diagram`, `'which-key`, `'window-list`).

Optional keys (each block type may use any combination):

- `'consumed-keys` LIST-OF-STRINGS — single-char keys this block visually "paints" (e.g. panel cells). The which-key block excludes these from its rendered entries. Default `'()`.
- `'on-render-fn` THUNK — runs after the block's JS renderer has been dispatched, on every render (initial + every update). Used by `window-list` (with `'show-chips #t`) to call `paint-window-chips!`. Default `#f`.
- Block-specific data keys (e.g. `'panels` on `window-diagram`, `'show-chips`/`'chip-options` on `window-list`).

### Group with `'renderer 'blocks`

Carries:

- `'renderer` = `'blocks`
- `'blocks` LIST-OF-BLOCK-SPECS (order = visual top-to-bottom stack order)
- `'children` (as today) — the dispatch tree. **All bindings live on the group's `'children`**, not on blocks. Blocks read from the group at render time (window-diagram already does this through panels; which-key reads children directly).

### JSON payload contract (Scheme → JS)

```
{
  "type": "blocks",
  "blocks": [
    {"type": "<block-type-symbol>", ...block-specific fields...},
    ...
  ]
}
```

The dispatcher in `overlay.js` (extended in Task 1) iterates `payload.blocks` and calls `window.overlayBlockRenderers[block.type](block, blockContainer)` for each, in order. Each block renderer appends its own DOM into a per-block `<div class="block block-<type>">` container.

### Categories (decided in arch doc decision 4–10)

- DSL adds `(category LABEL . CHILDREN)` constructor in `(modaliser dsl)`, returning `((kind . category) (label . LABEL) (children . CHILDREN))`.
- Group children may include category nodes alongside `(key …)`/`(group …)`/etc.
- State machine treats category nodes as **transparent**: `find-child` and related helpers descend into category children as if the category weren't there.
- The which-key block partitions the group's children into `(misc | category)` segments, preserving source order. Children whose key is in any block's `'consumed-keys` are skipped (so panel-painted keys don't double-render).
- `(category …)` nodes also pass through the `'hidden` filter (decision 9 — a category whose entire content is hidden simply has zero rows, no separate handling needed).

### which-key payload shape

```
{
  "type": "which-key",
  "segments": [
    {"kind": "misc",     "row": {"key": "...", "label": "...", "isGroup": false, "isSticky": false}},
    {"kind": "category", "label": "Move", "rows": [<row>, ...]},
    ...
  ]
}
```

Source order is preserved across the `segments` array. Misc rows have one row per segment entry (so columns can re-flow them independently). Category segments are atomic — all their rows stay together.

### Asset registration

Each block's `.sld` calls (at library import time):

```scheme
(add-overlay-asset-file! 'css "lib/modaliser/blocks/<type>.css")
(add-overlay-asset-file! 'js  "lib/modaliser/blocks/<type>.js")
```

This is the same mechanism `diagram-panel.sld` uses today.

---

## File Structure

**Create:**

- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.sld` — constructor + asset reg.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.js` — `window.overlayBlockRenderers['window-diagram']`.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.css` — panel-grid styles (lifted from `diagram-panel.css`).
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.sld` — `make-which-key-block` + asset reg.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js` — `window.overlayBlockRenderers['which-key']`.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css` — multi-column layout.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld` — `make-window-list-block` + asset reg + on-render effect.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.js` — `window.overlayBlockRenderers['window-list']`.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.css` — windows-list styles (lifted from `.diagram-windows-list`).
- `Tests/ModaliserTests/BlockListRendererTests.swift` — block-list renderer scaffolding + dispatch tests (Task 1).
- `Tests/ModaliserTests/BlocksWindowDiagramLibraryTests.swift` — window-diagram block tests (Task 2).
- `Tests/ModaliserTests/BlocksWhichKeyLibraryTests.swift` — which-key block + category flattening tests (Task 3).
- `Tests/ModaliserTests/BlocksWindowListLibraryTests.swift` — window-list block tests (Task 4).

**Modify:**

- `Sources/Modaliser/Scheme/ui/overlay.scm` — add `block-list-payload-json` for `'renderer 'blocks` and route effects via a small registry. Extend `push-overlay-update` similarly.
- `Sources/Modaliser/Scheme/ui/overlay.js` — extend dispatcher to handle `payload.type === "blocks"`: clear children, iterate blocks, dispatch each to `window.overlayBlockRenderers[block.type]`.
- `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` — `find-child` and `node-children` (or just `find-child`) descend through category nodes transparently. Single helper `flatten-categories` consumes a child-list and returns a new list with category-children spliced in.
- `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld` — export `category`, add the constructor.
- `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld` — migrate to `'renderer 'blocks` with the three block constructors (Task 5). Remove `'panels`/`'dynamic-data-fn`/`'on-enter`/`'on-leave`.

**Untouched:**

- `lib/modaliser/diagram-panel.{sld,js,css}` — stays as-is. window-diagram block lifts its rendering and CSS but does NOT delete the original until all callers migrate. The `divisions` and `parse-matrix` helpers used by `window-actions.sld` still live there.
- `lib/modaliser/hints.sld` — chip painting still goes through `hints-show`.
- iTerm modules — Task 6 is optional.

---

## Cross-task conventions

- **Branch:** `block-list-overlay` (already created via `EnterWorktree`).
- **Commits:** conventional-commits. `feat(blocks):` for new infrastructure, `feat(blocks/window-diagram):` for the diagram block, `feat(blocks/which-key):` for which-key, `feat(blocks/window-list):` for window-list, `refactor(window-actions):` for the migration.
- **Tests:** every commit leaves `swift test` green.
- **Run a single test** with: `swift test --filter <SuiteName>/<TestName>` (Swift Testing flat-string filter).
- **Run the full suite** with: `swift test`.

---

## Task 1: Block-list renderer scaffolding

**Files:**

- Modify: `Sources/Modaliser/Scheme/ui/overlay.scm` (add `block-list-payload-json`, route blocks renderer)
- Modify: `Sources/Modaliser/Scheme/ui/overlay.js` (extend dispatcher for `type === "blocks"`)
- Create: `Tests/ModaliserTests/BlockListRendererTests.swift`

**Outcome:** A group declared with `'renderer 'blocks 'blocks (list spec1 spec2 …)` renders an `.overlay-custom-body` whose `data-renderer="blocks"` and `data-payload` is `{"type":"blocks","blocks":[{"type":"<symbol>", …}, …]}`. The JS dispatcher reads the payload, iterates `payload.blocks`, and dispatches each block to `window.overlayBlockRenderers[block.type]`. An on-render effect registry runs any block-level `'on-render-fn` thunks after the JS has been pushed.

### Step 1.1: Write the failing test for blocks payload shape

- [ ] **Step 1.1: Write the failing test**

Create `Tests/ModaliserTests/BlockListRendererTests.swift`:

```swift
import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Block-list renderer scaffolding")
struct BlockListRendererTests {

    private func loadOverlay() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    @Test func blocksRendererEmitsTypedPayloadWithBlocksArray() throws {
        let engine = try loadOverlay()
        // Two stub block specs in declaration order: 'foo then 'bar.
        try engine.evaluate("""
          (define foo (list (cons 'type 'foo) (cons 'note "F")))
          (define bar (list (cons 'type 'bar) (cons 'note "B")))
          (define grp (group "w" "Win" 'renderer 'blocks 'blocks (list foo bar)
                        (key "x" "X" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("data-renderer=\"blocks\""))
        // Extract data-payload
        guard let payloadStart = html.range(of: "data-payload='") else {
            Issue.record("data-payload absent: \(html)"); return
        }
        let after = html[payloadStart.upperBound...]
        guard let payloadEnd = after.firstIndex(of: "'") else {
            Issue.record("data-payload not terminated"); return
        }
        let payload = String(after[..<payloadEnd])
        #expect(payload.contains("\"type\":\"blocks\""))
        // 'foo' must precede 'bar' in the blocks array (order preserved).
        guard let fooIdx = payload.range(of: "\"type\":\"foo\""),
              let barIdx = payload.range(of: "\"type\":\"bar\"") else {
            Issue.record("block types missing in payload: \(payload)"); return
        }
        #expect(fooIdx.lowerBound < barIdx.lowerBound)
        // Each block's spec fields are emitted
        #expect(payload.contains("\"note\":\"F\""))
        #expect(payload.contains("\"note\":\"B\""))
    }
}
```

- [ ] **Step 1.2: Run the test to confirm it fails**

Run: `swift test --filter BlockListRendererTests/blocksRendererEmitsTypedPayloadWithBlocksArray`

Expected: FAIL — either compile error (`render-overlay-html` doesn't yet recognise `'blocks` renderer) or the payload contains an unexpected/empty shape.

- [ ] **Step 1.3: Implement `block-list-payload-json` in `ui/overlay.scm`**

In `Sources/Modaliser/Scheme/ui/overlay.scm`, locate `custom-renderer-payload-json` (around line 338). After its definition, add:

```scheme
;; (block-list-payload-json current) → JSON string
;; Payload shape: {"type":"blocks","blocks":[<block-json>, ...]}
;; Each block in the group's 'blocks list is rendered by calling
;; alist->json on its spec — every Scheme symbol becomes a quoted string,
;; the order is the spec's declared order. Block-specific fields are
;; carried through verbatim; the JS dispatcher pulls them out by name.
(define (block-list-payload-json current)
  (let ((blocks (or (node-renderer-payload current 'blocks) '())))
    (string-append
      "{\"type\":\"blocks\",\"blocks\":["
      (string-join-comma (map alist->json blocks))
      "]}")))
```

Then change `custom-renderer-payload-json`'s callers to dispatch on `renderer`. Find the body of `render-overlay-custom` (around line 271):

```scheme
(define (render-overlay-custom cls segments current renderer path)
  (let* ((payload-json (custom-renderer-payload-json current renderer))
```

Change to:

```scheme
(define (render-overlay-custom cls segments current renderer path)
  (let* ((payload-json
           (cond
             ((eq? renderer 'blocks) (block-list-payload-json current))
             (else (custom-renderer-payload-json current renderer))))
```

Do the same in `push-overlay-update` (around line 487):

```scheme
(define (push-overlay-update node path)
  (let* ((current (if (null? path) node (navigate-to-path node path)))
         (renderer (and current (node-renderer current))))
    (cond
      (renderer
        (let ((payload
                (cond
                  ((eq? renderer 'blocks) (block-list-payload-json current))
                  (else (custom-renderer-payload-json current renderer)))))
          (webview-eval overlay-webview-id
            (string-append "updateOverlay(" payload ")"))))
      (else
        (push-overlay-update-default node current path)))))
```

- [ ] **Step 1.4: Run the payload test to confirm it passes**

Run: `swift test --filter BlockListRendererTests/blocksRendererEmitsTypedPayloadWithBlocksArray`

Expected: PASS.

- [ ] **Step 1.5: Extend the JS dispatcher**

In `Sources/Modaliser/Scheme/ui/overlay.js`, after the `window.overlayRenderers.list = …` definition (around line 120), add:

```javascript
// Block-list renderer — handles {type: "blocks", blocks: [{type, …}, …]}
// payloads. Each block in payload.blocks is rendered by looking up
// window.overlayBlockRenderers[block.type] and calling it with
// (block, blockContainer). Block renderers append their own DOM into
// their per-block container; the renderer here just builds the row of
// containers in source order. Containers carry a "block block-<type>"
// class so block-specific CSS can scope its styles.
window.overlayBlockRenderers = window.overlayBlockRenderers || {};

window.overlayRenderers.blocks = function(data, container) {
  var root = container || document.querySelector('.overlay-custom-body[data-renderer="blocks"]');
  if (!root) return;
  while (root.firstChild) root.removeChild(root.firstChild);
  var list = data.blocks || [];
  for (var i = 0; i < list.length; i++) {
    var block = list[i];
    var bc = document.createElement('div');
    bc.className = 'block block-' + block.type;
    root.appendChild(bc);
    var fn = window.overlayBlockRenderers[block.type];
    if (fn) {
      try {
        fn(block, bc);
      } catch (e) {
        console.error('block ' + block.type + ' render failed', e);
      }
    } else {
      console.warn('overlay: no block renderer for', block.type);
    }
  }
  notifyResize();
};
```

- [ ] **Step 1.6: Write a test that verifies the JS dispatcher exposes the registry**

Append to `BlockListRendererTests.swift`:

```swift
    @Test func overlayJsExposesBlockRendererRegistry() throws {
        let engine = try loadOverlay()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); return
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        #expect(js.contains("window.overlayBlockRenderers"))
        #expect(js.contains("overlayRenderers.blocks"))
    }
```

- [ ] **Step 1.7: Run both tests**

Run: `swift test --filter BlockListRendererTests`

Expected: both PASS.

- [ ] **Step 1.8: Add on-render effect registry test**

Append to `BlockListRendererTests.swift`:

```swift
    @Test func blockOnRenderFnFiresWhenPayloadIsBuilt() throws {
        let engine = try loadOverlay()
        // A block spec with an 'on-render-fn that bumps a counter when fired.
        try engine.evaluate("""
          (define counter 0)
          (define stub-block
            (list (cons 'type 'stub)
                  (cons 'on-render-fn (lambda () (set! counter (+ counter 1))))))
          (define grp (group "w" "Win" 'renderer 'blocks 'blocks (list stub-block)))
          ;; Building the JSON payload runs the block's effects.
          (define payload (block-list-payload-json grp))
        """)
        #expect(try engine.evaluate("(>= counter 1)") == .true)
        // The effect MUST NOT appear in the serialized JSON (it's a Scheme
        // procedure, not a value the JS side cares about).
        let payload = try engine.evaluate("payload").asString()
        #expect(!payload.contains("on-render-fn"))
    }
```

- [ ] **Step 1.9: Implement on-render effect dispatch**

The previous step's test will fail because `block-list-payload-json` doesn't run effects yet. Update it:

```scheme
(define (block-list-payload-json current)
  (let* ((blocks (or (node-renderer-payload current 'blocks) '())))
    ;; Run on-render-fn thunks before serializing — gives blocks a
    ;; chance to refresh dynamic state (e.g. window-list paints chips
    ;; here so the chip data and the rendered list stay in sync).
    (for-each
      (lambda (b)
        (let ((fn (let ((e (assoc 'on-render-fn b))) (and e (cdr e)))))
          (when (procedure? fn) (fn))))
      blocks)
    ;; Serialize each block. Filter out 'on-render-fn — alist->json
    ;; emits "null" for procedures, but the key is internal-only and
    ;; should not appear in the payload at all.
    (string-append
      "{\"type\":\"blocks\",\"blocks\":["
      (string-join-comma (map block-spec->json blocks))
      "]}")))

;; (block-spec->json spec) → JSON object string
;; Skip pairs whose value is a procedure (e.g. 'on-render-fn) — those are
;; Scheme-side hooks, not data for the JS renderer.
(define (block-spec->json spec)
  (let loop ((rest spec) (acc '()))
    (cond
      ((null? rest)
       (string-append "{" (string-join-comma (reverse acc)) "}"))
      (else
        (let* ((entry (car rest))
               (k (car entry))
               (v (cdr entry)))
          (cond
            ((procedure? v) (loop (cdr rest) acc))   ; skip thunks
            (else
              (loop (cdr rest)
                    (cons (string-append
                            "\"" (js-escape-overlay (symbol->string k))
                            "\":" (alist->json v))
                          acc)))))))))
```

- [ ] **Step 1.10: Run all Task-1 tests**

Run: `swift test --filter BlockListRendererTests`

Expected: all three PASS.

- [ ] **Step 1.11: Run the full suite to catch regressions**

Run: `swift test`

Expected: green, no failures from existing tests.

- [ ] **Step 1.12: Commit Task 1**

```bash
git add Sources/Modaliser/Scheme/ui/overlay.scm \
        Sources/Modaliser/Scheme/ui/overlay.js \
        Tests/ModaliserTests/BlockListRendererTests.swift
git commit -m "$(cat <<'EOF'
feat(blocks): block-list renderer scaffolding

Adds 'renderer 'blocks alongside the existing 'diagram path: groups
declare a 'blocks list of typed specs; the renderer serialises them to
{type:"blocks",blocks:[…]} and a new JS dispatcher iterates the array
in declaration order, routing each to window.overlayBlockRenderers[type].
Block specs may carry an 'on-render-fn thunk that runs at payload-build
time — the hook block types will use for chip painting and similar
side-effects.

No callsites use 'blocks yet; the diagram renderer keeps working
unchanged.
EOF
)"
```

---

## Task 2: `window-diagram` block (lifts the panel grid)

**Files:**

- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.sld`
- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.js`
- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.css`
- Create: `Tests/ModaliserTests/BlocksWindowDiagramLibraryTests.swift`

**Outcome:** `(make-window-diagram-block panel-specs)` returns a block spec with `'type 'window-diagram`, carries `'panels` (already-converted to JS camelCase by the caller — same `js-cell` shape currently used by `window-actions.sld`), and declares `'consumed-keys` listing every key painted on a panel cell. The JS render function paints the same panel grid the current `diagram-panel.js` paints (grid + center + fill panels) and emits identical CSS classes.

### Step 2.1: Write the failing test for `make-window-diagram-block`

- [ ] **Step 2.1: Write the failing test**

Create `Tests/ModaliserTests/BlocksWindowDiagramLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser blocks window-diagram) library")
struct BlocksWindowDiagramLibraryTests {

    @Test func makeWindowDiagramBlockReturnsSpec() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-diagram))")
        try engine.evaluate("""
          (define spec
            (list (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                        (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                 (cons 'colSpan 1) (cons 'rowSpan 1)))))))
          (define b (make-window-diagram-block spec))
        """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'window-diagram)") == .true)
        // 'panels carries the original list
        #expect(try engine.evaluate("(equal? (cdr (assoc 'panels b)) spec)") == .true)
        // 'consumed-keys lists the keys painted on the panel(s)
        #expect(try engine.evaluate("(member \"d\" (cdr (assoc 'consumed-keys b)))") != .false)
    }

    @Test func consumedKeysCoversGridCenterAndFill() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-diagram))")
        try engine.evaluate("""
          (define grid (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                             (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                      (cons 'colSpan 1) (cons 'rowSpan 1))))))
          (define cen  (list (cons 'type 'center) (cons 'key "c")))
          (define fil  (list (cons 'type 'fill)   (cons 'key "m")))
          (define b (make-window-diagram-block (list grid cen fil)))
          (define ck (cdr (assoc 'consumed-keys b)))
        """)
        #expect(try engine.evaluate("(member \"d\" ck)") != .false)
        #expect(try engine.evaluate("(member \"c\" ck)") != .false)
        #expect(try engine.evaluate("(member \"m\" ck)") != .false)
    }
}
```

- [ ] **Step 2.2: Run to confirm fail**

Run: `swift test --filter BlocksWindowDiagramLibraryTests`

Expected: FAIL — `(modaliser blocks window-diagram)` not found.

- [ ] **Step 2.3: Create the `.sld`**

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.sld`:

```scheme
;; (modaliser blocks window-diagram) — block constructor for the
;; window-diagram block type. Used by the block-list renderer; co-located
;; with its JS + CSS so the asset trio lives in one directory.
;;
;; (make-window-diagram-block panel-specs) → block-spec alist
;;
;; panel-specs is a list of panel-spec alists in the camelCase shape the
;; JS renderer expects (see window-actions.sld's js-cell). Returns an
;; alist with:
;;   'type           — 'window-diagram
;;   'panels         — verbatim panel-specs (carried through to JS)
;;   'consumed-keys  — every key painted on a cell/center/fill, used by
;;                     the which-key block to skip those keys when
;;                     rendering the entries list.

(define-library (modaliser blocks window-diagram)
  (export make-window-diagram-block)
  (import (scheme base)
          (modaliser overlay-assets))
  (begin

    ;; (panel-bound-keys panels) → list of strings
    ;; Mirrors the helper in ui/overlay.scm but lives here so the block is
    ;; self-contained — the renderer reads 'consumed-keys off the spec
    ;; and doesn't need to know how to walk panels.
    (define (panel-bound-keys panels)
      (let loop ((ps panels) (acc '()))
        (cond
          ((null? ps) (reverse acc))
          (else
            (let* ((p (car ps))
                   (ptype (let ((e (assoc 'type p))) (and e (cdr e)))))
              (cond
                ((eq? ptype 'grid)
                 (let* ((cells-entry (assoc 'cells p))
                        (cells (and cells-entry (cdr cells-entry))))
                   (loop (cdr ps)
                         (let cells-loop ((cs (or cells '())) (a acc))
                           (cond
                             ((null? cs) a)
                             (else
                               (let* ((c (car cs))
                                      (ke (assoc 'key c))
                                      (k (and ke (cdr ke))))
                                 (cells-loop (cdr cs) (if k (cons k a) a))))))))) 
                ((or (eq? ptype 'center) (eq? ptype 'fill))
                 (let* ((ke (assoc 'key p))
                        (k (and ke (cdr ke))))
                   (loop (cdr ps) (if k (cons k acc) acc))))
                (else (loop (cdr ps) acc))))))))

    (define (make-window-diagram-block panels)
      (list (cons 'type 'window-diagram)
            (cons 'panels panels)
            (cons 'consumed-keys (panel-bound-keys panels))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/window-diagram.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/window-diagram.js")))
```

- [ ] **Step 2.4: Create the `.js`** (lifted from `diagram-panel.js`'s `renderGridPanel`/`renderFillPanel`/`renderCenterPanel`)

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.js`:

```javascript
/* window-diagram.js — block renderer for the panel-grid block.
 *
 * Lives next to window-diagram.sld; loaded via add-overlay-asset-file!
 * at library import time. Registers itself on
 * window.overlayBlockRenderers['window-diagram'].
 *
 * Payload shape (one block in the blocks-list payload):
 *   { type: "window-diagram",
 *     panels: [
 *       { type: "grid",   cols, rows, cells: [{key, col, row, colSpan, rowSpan}, ...] },
 *       { type: "center", key },
 *       { type: "fill",   key },
 *     ] }
 *
 * Lifted with no behavioural change from lib/modaliser/diagram-panel.js
 * — same DOM structure, same CSS class names (.diagram-panel, .diagram-
 * cell, etc.) so the existing stylesheet keeps working. The block lives
 * inside a per-block container (.block.block-window-diagram); the actual
 * panel grid is the .diagram-panel-grid child the JS appends.
 */

(function() {
  function el(tag, attrs, ...kids) {
    const e = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') e.className = attrs[k];
        else if (k === 'text') e.textContent = attrs[k];
        else e.setAttribute(k, attrs[k]);
      }
    }
    for (const kid of kids) {
      if (kid == null) continue;
      e.appendChild(typeof kid === 'string' ? document.createTextNode(kid) : kid);
    }
    return e;
  }

  function svg(tag, attrs, ...kids) {
    const e = document.createElementNS('http://www.w3.org/2000/svg', tag);
    if (attrs) for (const k in attrs) e.setAttribute(k, attrs[k]);
    for (const kid of kids) if (kid) e.appendChild(kid);
    return e;
  }

  function gridLineClasses(cell) {
    const cls = ['diagram-cell'];
    if (cell.key) cls.push('has-key');
    if (cell.col > 1) cls.push('left-line');
    if (cell.row > 1) cls.push('top-line');
    return cls.join(' ');
  }

  function renderGridPanel(panel) {
    const div = el('div', {
      class: 'diagram-panel grid',
      style: `grid-template-columns: repeat(${panel.cols}, 1fr); grid-template-rows: repeat(${panel.rows}, 1fr);`
    });
    const covered = new Set();
    for (const cell of panel.cells) {
      for (let dr = 0; dr < (cell.rowSpan || 1); dr++) {
        for (let dc = 0; dc < (cell.colSpan || 1); dc++) {
          covered.add((cell.col + dc) + ',' + (cell.row + dr));
        }
      }
    }
    for (const cell of panel.cells) {
      div.appendChild(el('div', {
        class: gridLineClasses(cell),
        style: `grid-column: ${cell.col} / span ${cell.colSpan}; grid-row: ${cell.row} / span ${cell.rowSpan};`,
        text: cell.key || ''
      }));
    }
    for (let r = 1; r <= panel.rows; r++) {
      for (let c = 1; c <= panel.cols; c++) {
        if (covered.has(c + ',' + r)) continue;
        const placeholder = { col: c, row: r, colSpan: 1, rowSpan: 1, key: null };
        div.appendChild(el('div', {
          class: gridLineClasses(placeholder),
          style: `grid-column: ${c} / span 1; grid-row: ${r} / span 1;`
        }));
      }
    }
    return div;
  }

  function renderFillPanel(panel) {
    return el('div', { class: 'diagram-panel fill', text: panel.key });
  }

  function renderCenterPanel(panel) {
    const s = svg('svg', { viewBox: '0 0 102 60', preserveAspectRatio: 'none' });
    s.appendChild(svg('rect', { class: 'diagram-inner-fill', x: '35', y: '20', width: '32', height: '20' }));
    s.appendChild(svg('rect', { class: 'diagram-stroke', x: '35', y: '20', width: '32', height: '20' }));
    const shafts = [
      ['51','6','51','12'],
      ['51','54','51','48'],
      ['7','30','27','30'],
      ['95','30','75','30'],
    ];
    for (const [x1, y1, x2, y2] of shafts) {
      s.appendChild(svg('line', { class: 'diagram-stroke', x1, y1, x2, y2 }));
    }
    const heads = [
      '51,17 47,11 55,11',
      '51,43 47,49 55,49',
      '32,30 26,26 26,34',
      '70,30 76,26 76,34',
    ];
    for (const points of heads) {
      s.appendChild(svg('polygon', { class: 'diagram-arrow', points }));
    }
    const t = svg('text', { class: 'diagram-key', x: '51', y: '35', 'text-anchor': 'middle' });
    t.textContent = panel.key;
    s.appendChild(t);
    return el('div', { class: 'diagram-panel center' }, s);
  }

  function renderPanel(panel) {
    switch (panel.type) {
      case 'grid':   return renderGridPanel(panel);
      case 'fill':   return renderFillPanel(panel);
      case 'center': return renderCenterPanel(panel);
      default:
        console.warn('window-diagram: unknown panel type', panel.type);
        return el('div');
    }
  }

  window.overlayBlockRenderers = window.overlayBlockRenderers || {};
  window.overlayBlockRenderers['window-diagram'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const grid = el('div', { class: 'diagram-panel-grid' });
    for (const panel of (block.panels || [])) {
      grid.appendChild(renderPanel(panel));
    }
    container.appendChild(grid);
  };
})();
```

- [ ] **Step 2.5: Create the `.css`** — lift the panel-related rules from `diagram-panel.css`, scoped under `.block-window-diagram`

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.css`:

```css
/* window-diagram.css — styles for the window-diagram block.
 *
 * Scoped under .block-window-diagram so other blocks don't collide
 * with .diagram-panel etc. The rules are otherwise lifted verbatim
 * from lib/modaliser/diagram-panel.css.
 */

:root {
  --diagram-line: rgba(0, 0, 0, 0.65);
  --diagram-cell-bg: #ffffff;
  --diagram-panel-w: 102px;
  --diagram-panel-h: 60px;
}

.block-window-diagram {
  padding: 8px 0;
}

.block-window-diagram .diagram-panel-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, var(--diagram-panel-w));
  gap: 0.5rem 1.6rem;
  justify-content: start;
  align-items: center;
  min-width: calc(3 * var(--diagram-panel-w) + 2 * 1.6rem);
}

.block-window-diagram .diagram-panel {
  width: var(--diagram-panel-w);
  height: var(--diagram-panel-h);
  border: 0.5px solid var(--diagram-line);
  background: transparent;
  position: relative;
  box-sizing: border-box;
  display: grid;
}

.block-window-diagram .diagram-cell {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-key);
  font-weight: 600;
  font-family: var(--font-family);
  font-size: var(--font-size);
  background: transparent;
}
.block-window-diagram .diagram-cell.has-key { background: var(--diagram-cell-bg); }
.block-window-diagram .diagram-cell.left-line { border-left: 0.5px solid var(--diagram-line); }
.block-window-diagram .diagram-cell.top-line  { border-top:  0.5px solid var(--diagram-line); }

.block-window-diagram .diagram-panel.fill {
  background: var(--diagram-cell-bg);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-key);
  font-weight: 600;
  font-family: var(--font-family);
  font-size: var(--font-size);
}

.block-window-diagram .diagram-panel.center svg {
  display: block;
  width: 100%;
  height: 100%;
  color: var(--diagram-line);
}
.block-window-diagram .diagram-panel.center .diagram-inner-fill { fill: var(--diagram-cell-bg); stroke: none; }
.block-window-diagram .diagram-panel.center .diagram-stroke {
  stroke: currentColor;
  stroke-width: 1;
  vector-effect: non-scaling-stroke;
  fill: none;
  stroke-linecap: round;
}
.block-window-diagram .diagram-panel.center .diagram-arrow { fill: currentColor; stroke: none; }
.block-window-diagram .diagram-panel.center .diagram-key {
  fill: var(--color-key);
  font-family: var(--font-family);
  font-size: 14px;
  font-weight: 600;
}
```

- [ ] **Step 2.6: Run the Task-2 tests to confirm pass**

Run: `swift test --filter BlocksWindowDiagramLibraryTests`

Expected: PASS.

- [ ] **Step 2.7: Add a test that the block's JSON payload comes through the renderer cleanly**

Append to `BlocksWindowDiagramLibraryTests.swift`:

```swift
    @Test func blockRendersViaBlockListInOverlay() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); return
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-diagram))")
        try engine.evaluate("""
          (define panel (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                              (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                       (cons 'colSpan 1) (cons 'rowSpan 1))))))
          (define b (make-window-diagram-block (list panel)))
          (define grp (group "w" "Win" 'renderer 'blocks 'blocks (list b)))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        // Block JS + CSS registered → strings present in rendered HTML
        #expect(html.contains("window.overlayBlockRenderers"))
        #expect(html.contains(".block-window-diagram"))
        // Block payload type is window-diagram
        #expect(html.contains("\"type\":\"window-diagram\""))
        // Panel cell key flows through
        #expect(html.contains("\"key\":\"d\""))
    }
```

Run: `swift test --filter BlocksWindowDiagramLibraryTests/blockRendersViaBlockListInOverlay`

Expected: PASS.

- [ ] **Step 2.8: Run the full suite**

Run: `swift test`

Expected: green.

- [ ] **Step 2.9: Commit Task 2**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.sld \
        Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.js \
        Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.css \
        Tests/ModaliserTests/BlocksWindowDiagramLibraryTests.swift
git commit -m "$(cat <<'EOF'
feat(blocks/window-diagram): panel-grid block

Lifts the panel rendering from diagram-panel.{js,css} into a self-
contained block under lib/modaliser/blocks/window-diagram.{sld,js,css}.
The .sld constructor (make-window-diagram-block panel-specs) returns
the block spec with 'consumed-keys derived from the panel cells —
the which-key block will use that to skip panel-painted keys when
rendering the entries list.
EOF
)"
```

---

## Task 3: `which-key` block with category / misc support

**Files:**

- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.sld`
- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js`
- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css`
- Modify: `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld` — add and export `category`
- Modify: `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` — `find-child` descends through category nodes transparently
- Create: `Tests/ModaliserTests/BlocksWhichKeyLibraryTests.swift`

**Outcome:**

- `(category "label" . children)` produces a `((kind . category) (label . LABEL) (children . CHILDREN))` node.
- The state machine treats categories transparently: `find-child` resolves keys as if category children were hoisted into the parent.
- `(make-which-key-block)` returns a block spec `'(((type . which-key)))`.
- At render time, the block-list renderer walks the parent group's children, filters out keys consumed by sibling blocks (via the union of all `'consumed-keys`), partitions remaining children into `(misc | category)` segments preserving source order, and emits a JSON payload that the JS renderer turns into a multi-column container.

### Step 3.1: Failing test for `(category …)` constructor

- [ ] **Step 3.1: Write the failing test**

Create `Tests/ModaliserTests/BlocksWhichKeyLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser blocks which-key) + category DSL")
struct BlocksWhichKeyLibraryTests {

    @Test func categoryConstructorReturnsCategoryNode() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("""
          (define c (category "Move"
                      (key "h" "Left"  (lambda () #t))
                      (key "j" "Down"  (lambda () #t))))
        """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind c)) 'category)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label c)) \"Move\")") == .true)
        #expect(try engine.evaluate("(= (length (cdr (assoc 'children c))) 2)") == .true)
    }
}
```

- [ ] **Step 3.2: Run to confirm fail**

Run: `swift test --filter BlocksWhichKeyLibraryTests/categoryConstructorReturnsCategoryNode`

Expected: FAIL — `category` is unbound.

- [ ] **Step 3.3: Add `category` to `dsl.sld`**

In `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld`, add `category` to the export list:

```scheme
  (export key key-range group selector action
          category
          define-tree set-theme!
```

After the `(group …)` definition, add:

```scheme
;; (category label . children) → category alist
;;
;; Category nodes group a slice of group children under a label for
;; rendering by the (modaliser blocks which-key) block. The state machine
;; treats them as TRANSPARENT for dispatch: find-child descends through
;; category nodes as if their children were hoisted into the parent.
;; This lets configs add visual grouping without changing key paths.
(define (category label . children)
  (list (cons 'kind 'category)
        (cons 'label label)
        (cons 'children children)))
```

- [ ] **Step 3.4: Run the constructor test**

Run: `swift test --filter BlocksWhichKeyLibraryTests/categoryConstructorReturnsCategoryNode`

Expected: PASS.

### Step 3.5–3.7: State-machine transparent traversal

- [ ] **Step 3.5: Failing test — `find-child` resolves through a category**

Append to `BlocksWhichKeyLibraryTests.swift`:

```swift
    @Test func findChildResolvesThroughCategoryTransparently() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("""
          (define grp
            (group "w" "Win"
              (category "Move"
                (key "h" "Left" (lambda () 'left))
                (key "j" "Down" (lambda () 'down)))
              (key "q" "Quit" (lambda () 'quit))))
          ;; "h" lives under a category; find-child must still resolve it.
          (define h-node (find-child grp "h"))
          (define q-node (find-child grp "q"))
        """)
        #expect(try engine.evaluate("(and h-node #t)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key h-node)) \"h\")") == .true)
        #expect(try engine.evaluate("(and q-node #t)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key q-node)) \"q\")") == .true)
    }
```

- [ ] **Step 3.6: Run to confirm fail**

Run: `swift test --filter BlocksWhichKeyLibraryTests/findChildResolvesThroughCategoryTransparently`

Expected: FAIL — `find-child` doesn't descend.

- [ ] **Step 3.7: Implement transparent traversal in `state-machine.sld`**

In `state-machine.sld`, add a `category?` predicate near the other kind predicates (around line 137):

```scheme
(define (category? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'category)))))
```

Then add a flattener:

```scheme
;; (flatten-categories children) → list of non-category nodes
;; Walks `children` and splices the children of any (category …) node
;; into the result at the category's source position. Recursive — nested
;; categories flatten transparently. Used by find-child so dispatch sees
;; category-wrapped keys as if they were direct group children.
(define (flatten-categories children)
  (let loop ((rest children) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((category? (car rest))
       (let ((inner (flatten-categories
                      (let ((e (assoc 'children (car rest))))
                        (if e (cdr e) '())))))
         (loop (cdr rest)
               (append (reverse inner) acc))))
      (else
       (loop (cdr rest) (cons (car rest) acc))))))
```

Update `find-child` (line 260 area) to flatten:

```scheme
(define (find-child node key)
  (let loop ((children (flatten-categories (node-children node))) (range-hit #f))
    (cond
      ((null? children) range-hit)
      ((and (not (range-command? (car children)))
            (equal? (node-key (car children)) key))
       (car children))
      ((and (not range-hit)
            (range-command? (car children))
            (member key (node-range-keys (car children))))
       (loop (cdr children) range-hit))
      (else (loop (cdr children) range-hit)))))
```

Export `category?` and `flatten-categories` so the which-key block can use them:

In the `(export …)` block (around line 8):

```scheme
    command? group? selector? range-command? category? flatten-categories
```

Also update `node-children` callers in the default list renderer (`render-overlay-default` in `overlay.scm`) — they should flatten so a default-rendered overlay with `(category …)` children also shows the keys. Find `render-overlay-default` (line 244):

```scheme
(define (render-overlay-default cls segments current path)
  (let* ((children (if current (flatten-categories (node-children current)) '()))
```

Same for `push-overlay-update-default` (line 500):

```scheme
(define (push-overlay-update-default node current path)
  (let* ((children (if current (flatten-categories (node-children current)) '()))
```

This means the `(modaliser state-machine)` library needs `flatten-categories` visible to `ui/overlay.scm`. Since `overlay.scm` already imports the state-machine library, exporting it makes it available. (No change needed to overlay.scm's import line.)

- [ ] **Step 3.8: Run the traversal test**

Run: `swift test --filter BlocksWhichKeyLibraryTests/findChildResolvesThroughCategoryTransparently`

Expected: PASS.

- [ ] **Step 3.9: Sanity-check the full suite**

Run: `swift test`

Expected: green. (Existing tests should still pass — `flatten-categories` is a no-op for children with no categories.)

### Step 3.10–3.14: `which-key` block

- [ ] **Step 3.10: Failing test — `make-which-key-block` returns a spec; block payload partitions misc + category in source order**

Append to `BlocksWhichKeyLibraryTests.swift`:

```swift
    @Test func makeWhichKeyBlockReturnsTypeSpec() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks which-key))")
        try engine.evaluate("(define b (make-which-key-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'which-key)") == .true)
    }

    @Test func whichKeyPayloadPartitionsCategoriesAndMiscInSourceOrder() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); return
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks which-key))")
        try engine.evaluate("""
          (define grp
            (group "w" "Win"
              'renderer 'blocks
              'blocks (list (make-which-key-block))
              (key "a" "Apple" (lambda () #t))
              (category "Move"
                (key "h" "Left" (lambda () #t))
                (key "j" "Down" (lambda () #t)))
              (key "z" "Zebra" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        // Pull out data-payload
        guard let s = html.range(of: "data-payload='") else { Issue.record("no payload"); return }
        let after = html[s.upperBound...]
        guard let e = after.firstIndex(of: "'") else { Issue.record("unterminated"); return }
        let payload = String(after[..<e])
        // Verify source order: a → Move → z
        let aIdx = payload.range(of: "\"label\":\"Apple\"")!.lowerBound
        let moveIdx = payload.range(of: "\"label\":\"Move\"")!.lowerBound
        let zIdx = payload.range(of: "\"label\":\"Zebra\"")!.lowerBound
        #expect(aIdx < moveIdx)
        #expect(moveIdx < zIdx)
        // Category contains its rows (h, j)
        #expect(payload.contains("\"key\":\"h\""))
        #expect(payload.contains("\"key\":\"j\""))
        // kind tags exist
        #expect(payload.contains("\"kind\":\"misc\""))
        #expect(payload.contains("\"kind\":\"category\""))
    }
```

- [ ] **Step 3.11: Run to confirm fail**

Run: `swift test --filter BlocksWhichKeyLibraryTests`

Expected: FAIL — `(modaliser blocks which-key)` not found.

- [ ] **Step 3.12: Create the `.sld`**

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.sld`:

```scheme
;; (modaliser blocks which-key) — which-key block constructor.
;;
;; (make-which-key-block) returns a marker spec; the block has no
;; spec-level data. At render time the block-list renderer in
;; ui/overlay.scm walks the parent group's children, filters out keys
;; claimed by any sibling block via 'consumed-keys, partitions what
;; remains into (misc | category) segments preserving source order,
;; and emits the payload below.
;;
;; The render-time partitioning lives in ui/overlay.scm because that's
;; where the parent group is in scope. This library only exposes the
;; constructor + asset registration.

(define-library (modaliser blocks which-key)
  (export make-which-key-block)
  (import (scheme base)
          (modaliser overlay-assets))
  (begin

    (define (make-which-key-block)
      (list (cons 'type 'which-key)))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/which-key.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/which-key.js")))
```

- [ ] **Step 3.13: Render-time partitioning in `overlay.scm`**

In `ui/overlay.scm`, replace the body of `block-list-payload-json` so it computes segments for which-key blocks:

```scheme
;; (block-list-payload-json current) → JSON string
;; Payload: {"type":"blocks","blocks":[<block-json>, ...]}
;;
;; Some block types are "derived" — their JSON depends on the parent
;; group's children and the keys consumed by sibling blocks. which-key
;; partitions group children into misc/category segments. Other blocks
;; (window-diagram, window-list) serialize their spec directly via
;; block-spec->json.
(define (block-list-payload-json current)
  (let* ((blocks (or (node-renderer-payload current 'blocks) '()))
         (consumed
           (let loop ((bs blocks) (acc '()))
             (cond
               ((null? bs) acc)
               (else
                 (let ((e (assoc 'consumed-keys (car bs))))
                   (loop (cdr bs)
                         (if e (append acc (cdr e)) acc)))))))
         (group-children (node-children current)))
    ;; Run on-render thunks before serializing.
    (for-each
      (lambda (b)
        (let ((fn (let ((e (assoc 'on-render-fn b))) (and e (cdr e)))))
          (when (procedure? fn) (fn))))
      blocks)
    (string-append
      "{\"type\":\"blocks\",\"blocks\":["
      (string-join-comma
        (map (lambda (b) (block-json b group-children consumed)) blocks))
      "]}")))

;; (block-json b group-children consumed) → JSON object
;; Dispatch on block 'type:
;;   'which-key — emit segments by partitioning (group-children − consumed).
;;   other      — block-spec->json (verbatim alist, sans procedures).
(define (block-json b group-children consumed)
  (let ((type (let ((e (assoc 'type b))) (and e (cdr e)))))
    (cond
      ((eq? type 'which-key)
       (which-key-payload-json group-children consumed))
      (else
       (block-spec->json b)))))

;; (which-key-payload-json children consumed-keys) → JSON object
;; Walks `children` once. For each entry:
;;   - category? → emit a {"kind":"category","label":…,"rows":[<row>,…]}
;;     where rows is the category's children, also filtered by consumed.
;;   - else      → emit a {"kind":"misc","row":<row>} segment.
;; Hidden entries (cons (cons 'hidden #t) …) and keys in `consumed` are
;; skipped, matching the existing diagram renderer's behaviour.
(define (which-key-payload-json children consumed)
  (let ((segments
          (let loop ((xs children) (acc '()))
            (cond
              ((null? xs) (reverse acc))
              (else
                (let ((c (car xs)))
                  (cond
                    ((category? c)
                     (let* ((label (let ((e (assoc 'label c))) (if e (cdr e) "")))
                            (inner (let ((e (assoc 'children c))) (if e (cdr e) '())))
                            (rows (filtered-rows inner consumed))
                            (seg (string-append
                                   "{\"kind\":\"category\",\"label\":\""
                                   (js-escape-overlay label)
                                   "\",\"rows\":["
                                   (string-join-comma rows) "]}")))
                       (loop (cdr xs) (cons seg acc))))
                    (else
                     (let ((row (entry->row-json c consumed)))
                       (if row
                         (loop (cdr xs)
                               (cons (string-append "{\"kind\":\"misc\",\"row\":" row "}") acc))
                         (loop (cdr xs) acc))))))))))) 
    (string-append "{\"type\":\"which-key\",\"segments\":["
                   (string-join-comma segments) "]}")))

;; (filtered-rows children consumed) → list of JSON strings (each a row)
(define (filtered-rows children consumed)
  (let loop ((xs children) (acc '()))
    (cond
      ((null? xs) (reverse acc))
      (else
        (let ((row (entry->row-json (car xs) consumed)))
          (loop (cdr xs) (if row (cons row acc) acc)))))))

;; (entry->row-json c consumed) → JSON string OR #f if skipped
;; Skips hidden entries and entries whose key is in consumed.
(define (entry->row-json c consumed)
  (let* ((hidden-pair (assoc 'hidden c))
         (hidden? (and hidden-pair (cdr hidden-pair)))
         (k (node-key c))
         (lbl (node-label c))
         (is-grp (group? c))
         (sticky-target (and (command? c) (node-sticky-target c))))
    (cond
      (hidden? #f)
      ((member k consumed) #f)
      (else
       (string-append "{\"key\":\"" (js-escape-overlay k)
                      "\",\"label\":\"" (js-escape-overlay lbl)
                      "\",\"isGroup\":" (if is-grp "true" "false")
                      ",\"isSticky\":" (if sticky-target "true" "false")
                      "}")))))
```

Add `category?` to the import in overlay.scm if not already present — actually overlay.scm doesn't have explicit imports for state-machine items (it uses the include-based loader for ui code), so as long as `state-machine.sld` exports `category?` and `flatten-categories` (Task 3.7), they'll be visible.

- [ ] **Step 3.14: Run which-key tests**

Run: `swift test --filter BlocksWhichKeyLibraryTests`

Expected: PASS (both new tests).

### Step 3.15–3.18: `.js` + `.css` + integration

- [ ] **Step 3.15: Create the `.js`**

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js`:

```javascript
/* which-key.js — renderer for the which-key block.
 *
 * Payload shape:
 *   { type: "which-key",
 *     segments: [
 *       {kind: "misc",     row: {key, label, isGroup, isSticky}},
 *       {kind: "category", label: "Move", rows: [<row>, ...]},
 *       ...
 *     ] }
 *
 * Lays segments out in a CSS multi-column flow (column-fill: auto)
 * scoped under .block-which-key. Categories are atomic units
 * (.wk-category, break-inside: avoid). Misc rows are bare siblings
 * with no break rule — each flows independently across columns.
 */

(function() {
  function el(tag, attrs, ...kids) {
    const e = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') e.className = attrs[k];
        else if (k === 'text') e.textContent = attrs[k];
        else e.setAttribute(k, attrs[k]);
      }
    }
    for (const kid of kids) {
      if (kid == null) continue;
      e.appendChild(typeof kid === 'string' ? document.createTextNode(kid) : kid);
    }
    return e;
  }

  function renderRow(row) {
    const displayKey = row.key === ' ' ? '␣' : row.key;
    const labelClass = row.isGroup ? 'entry-label group-label' : 'entry-label';
    let labelText = row.isGroup ? (row.label + ' …') : row.label;
    const labelNode = el('span', { class: labelClass });
    if (row.isSticky) {
      const marker = el('span', { class: 'entry-sticky-marker', text: '↻' });
      labelNode.appendChild(marker);
      labelNode.appendChild(document.createTextNode(labelText));
    } else {
      labelNode.textContent = labelText;
    }
    return el('div', { class: 'wk-row' },
      el('span', { class: 'entry-key', text: displayKey }),
      el('span', { class: 'entry-arrow', text: '→' }),
      labelNode
    );
  }

  function renderCategory(seg) {
    const cat = el('div', { class: 'wk-category' });
    cat.appendChild(el('h4', { class: 'wk-category-label', text: seg.label }));
    for (const row of (seg.rows || [])) {
      cat.appendChild(renderRow(row));
    }
    return cat;
  }

  window.overlayBlockRenderers = window.overlayBlockRenderers || {};
  window.overlayBlockRenderers['which-key'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const cols = el('div', { class: 'wk-columns' });
    for (const seg of (block.segments || [])) {
      if (seg.kind === 'category') {
        cols.appendChild(renderCategory(seg));
      } else if (seg.kind === 'misc') {
        cols.appendChild(renderRow(seg.row));
      }
    }
    container.appendChild(cols);
  };
})();
```

- [ ] **Step 3.16: Create the `.css`**

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css`:

```css
/* which-key.css — multi-column layout for the which-key block.
 *
 * Container uses CSS columns with column-fill: auto for top-down
 * sequential packing. Categories are atomic (break-inside: avoid),
 * misc rows have no break rule so they can flow independently.
 */

.block-which-key {
  margin-top: 14px;
  padding-top: 6px;
  border-top: 1px solid var(--color-separator);
}

.block-which-key .wk-columns {
  column-width: 14rem;
  column-count: auto;
  column-fill: auto;
  column-gap: 1.5rem;
}

.block-which-key .wk-category {
  break-inside: avoid;
  margin-bottom: 0.4rem;
}

.block-which-key .wk-category-label {
  margin: 0 0 2px 0;
  padding-bottom: 2px;
  border-bottom: 1px solid var(--color-separator);
  font-size: var(--font-size);
  font-weight: 600;
  color: var(--color-label);
}

.block-which-key .wk-row {
  display: grid;
  grid-template-columns: 3ch auto 1fr;
  column-gap: 4px;
  align-items: baseline;
  padding: 1px 0;
}

.block-which-key .wk-row .entry-key { color: var(--color-key); font-weight: 600; }
.block-which-key .wk-row .entry-arrow { color: var(--color-arrow); }
.block-which-key .wk-row .entry-label { color: var(--color-label); }
.block-which-key .wk-row .group-label { color: var(--color-label); }
.block-which-key .wk-row .entry-sticky-marker {
  font-size: calc(var(--font-size) + 4px);
  position: relative;
  top: -1px;
  margin-right: 2px;
}
```

- [ ] **Step 3.17: Integration test — block-list + which-key in a group**

Append to `BlocksWhichKeyLibraryTests.swift`:

```swift
    @Test func whichKeySkipsConsumedKeys() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); return
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks which-key) (modaliser blocks window-diagram))")
        try engine.evaluate("""
          (define panel (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                              (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                       (cons 'colSpan 1) (cons 'rowSpan 1))))))
          (define grp (group "w" "Win"
                        'renderer 'blocks
                        'blocks (list (make-window-diagram-block (list panel))
                                      (make-which-key-block))
                        (key "d" "First Third" (lambda () #t))
                        (key "r" "Restore" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        // Extract the which-key segments substring
        guard let wkRange = html.range(of: "\"type\":\"which-key\"") else {
            Issue.record("no which-key payload"); return
        }
        let tail = html[wkRange.lowerBound...]
        // "r" must appear in which-key segments (it's a misc row).
        #expect(tail.contains("\"label\":\"Restore\""))
        // "d" must NOT appear in which-key segments — it's painted on the panel.
        // Look only at the which-key portion. Find the closing of "blocks":[…]
        // by trimming at the next "}]}" sequence.
        let wkSlice = String(tail.prefix(while: { $0 != "]" }))
        #expect(!wkSlice.contains("\"key\":\"d\""))
    }
```

Run: `swift test --filter BlocksWhichKeyLibraryTests/whichKeySkipsConsumedKeys`

Expected: PASS.

- [ ] **Step 3.18: Run the full suite**

Run: `swift test`

Expected: green.

- [ ] **Step 3.19: Commit Task 3**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/dsl.sld \
        Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld \
        Sources/Modaliser/Scheme/ui/overlay.scm \
        Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.sld \
        Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js \
        Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css \
        Tests/ModaliserTests/BlocksWhichKeyLibraryTests.swift
git commit -m "$(cat <<'EOF'
feat(blocks/which-key): which-key block with category support

Adds (category LABEL . children) to the DSL; the state machine flattens
category nodes transparently so dispatch isn't affected.  The which-key
block partitions a parent group's children into ordered misc/category
segments preserving source order, skipping any keys claimed by sibling
blocks via 'consumed-keys.  CSS uses a multi-column flow with
break-inside: avoid on categories.
EOF
)"
```

---

## Task 4: `window-list` block (with optional chip painting)

**Files:**

- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld`
- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.js`
- Create: `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.css`
- Create: `Tests/ModaliserTests/BlocksWindowListLibraryTests.swift`

**Outcome:**

- `(make-window-list-block . opts)` returns a block spec. Opts:
  - `'show-chips` BOOL — default `#f`. When true, an on-render effect computes per-window chip positions, runs visibility probes, and forwards to `hints-show`.
  - `'chip-options` ALIST — chip styling overrides (merged with `default-window-chip-options`).
  - `'on-focus-list-fn` PROC — function the spec exposes to the parent group so it can register a `(key-range …)` that dispatches presses 1..0 back into `focus-by-digit`. Default `#f` (the parent registers its own range — see Task 5).
- The block's payload carries the current window list with `(label, app, title, visible)` per row, computed inside the on-render effect so it shares one snapshot of the windows with the chip painter.

### Step 4.1: Failing test for the constructor

- [ ] **Step 4.1: Write the failing test**

Create `Tests/ModaliserTests/BlocksWindowListLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser blocks window-list) library")
struct BlocksWindowListLibraryTests {

    @Test func makeWindowListBlockDefaultShowChipsIsFalse() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("(define b (make-window-list-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'window-list)") == .true)
        // No on-render-fn when show-chips defaulted to #f
        #expect(try engine.evaluate("(not (assoc 'on-render-fn b))") == .true)
    }

    @Test func makeWindowListBlockWithShowChipsAttachesOnRenderFn() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("(define b (make-window-list-block 'show-chips #t))")
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-render-fn b)))") == .true)
    }
}
```

- [ ] **Step 4.2: Run to confirm fail**

Run: `swift test --filter BlocksWindowListLibraryTests`

Expected: FAIL — library not found.

- [ ] **Step 4.3: Create the `.sld`**

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld`:

```scheme
;; (modaliser blocks window-list) — block constructor for the
;; window-list block. Lifts the labelled windows-list section from
;; the old diagram renderer, plus the chip-painting side-effect.
;;
;; (make-window-list-block . opts) → block-spec alist
;;
;; Opts:
;;   'show-chips    BOOL  — default #f. When true, the block's
;;                          on-render-fn computes chip positions,
;;                          runs window-visible-at? probes, and forwards
;;                          to hints-show. The block's payload also
;;                          carries the current windows list so the
;;                          rendered rows mirror the chip placement.
;;   'chip-options  ALIST — chip styling overrides; merged with
;;                          default-window-chip-options.
;;
;; The current window snapshot is exposed via window-list-current-labels
;; so the parent group can build a (key-range …) that dispatches
;; per-digit window focus.

(define-library (modaliser blocks window-list)
  (export make-window-list-block
          window-list-current-labels
          window-list-current-targets)
  (import (scheme base)
          (modaliser util)
          (modaliser window)
          (modaliser hints)
          (modaliser overlay-assets))
  (begin

    ;; Per-render state — refreshed by the on-render effect every render.
    ;; The parent group's focus-by-digit binding reads from these.
    (define current-window-targets '())   ;; ((label . window-alist) ...)
    (define current-windows-data '())     ;; ((label . app . title . visible) shape, see build-row)

    (define (window-list-current-targets) current-window-targets)
    (define (window-list-current-labels)
      (map car current-window-targets))

    (define default-window-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    (define default-chip-options
      (list (cons 'offset-x-frac 0.02)
            (cons 'offset-y-frac 0.02)
            (cons 'font-size 56)
            (cons 'padding 16)
            (cons 'corner-radius 8)
            (cons 'color "white")
            (cons 'background "dodgerblue")
            (cons 'faded-background "#6f8baa")
            (cons 'border-width 1)
            (cons 'border-color "black")))

    (define (merge-chip-options overrides)
      (let loop ((rest default-chip-options) (acc '()))
        (cond
          ((null? rest) (append (reverse acc) overrides))
          ((assoc (car (car rest)) overrides)
           (loop (cdr rest) acc))
          (else (loop (cdr rest) (cons (car rest) acc))))))

    ;; ─── Chip placement helpers — lifted from window-actions.sld ────
    ;; Kept private to this library so it owns chip painting end-to-end.

    (define chip-overlap-gap 4)
    (define chip-resolve-max-attempts 64)

    (define (chips-overlap? a b)
      (let ((ax (cdr (assoc 'x a))) (ay (cdr (assoc 'y a)))
            (aw (cdr (assoc 'w a))) (ah (cdr (assoc 'h a)))
            (bx (cdr (assoc 'x b))) (by (cdr (assoc 'y b)))
            (bw (cdr (assoc 'w b))) (bh (cdr (assoc 'h b))))
        (and (< ax (+ bx bw))
             (< bx (+ ax aw))
             (< ay (+ by bh))
             (< by (+ ay ah)))))

    (define (chip-with-position c nx ny)
      (map (lambda (entry)
             (cond
               ((eq? (car entry) 'x) (cons 'x nx))
               ((eq? (car entry) 'y) (cons 'y ny))
               (else entry)))
           c))

    (define (clamp-chip-to-screen c sw sh)
      (let* ((cx (cdr (assoc 'x c))) (cy (cdr (assoc 'y c)))
             (cw (cdr (assoc 'w c))) (ch (cdr (assoc 'h c)))
             (nx (max 0 (min cx (- sw cw))))
             (ny (max 0 (min cy (- sh ch)))))
        (chip-with-position c nx ny)))

    (define (find-overlapping placed c)
      (cond
        ((null? placed) #f)
        ((chips-overlap? c (car placed)) (car placed))
        (else (find-overlapping (cdr placed) c))))

    (define (chip-with-background chip new-bg)
      (map (lambda (entry)
             (if (eq? (car entry) 'background)
               (cons 'background new-bg)
               entry))
           chip))

    (define (window-chip-for digit win opts)
      (let* ((wx (cdr (assoc 'x win))) (wy (cdr (assoc 'y win)))
             (ww (cdr (assoc 'w win))) (wh (cdr (assoc 'h win)))
             (font-size (cdr (assoc 'font-size opts)))
             (padding (cdr (assoc 'padding opts)))
             (offx (cdr (assoc 'offset-x-frac opts)))
             (offy (cdr (assoc 'offset-y-frac opts)))
             (chip-x (+ wx (exact (round (* ww offx)))))
             (chip-y (+ wy (exact (round (* wh offy)))))
             (chip-size (+ font-size (* 2 padding))))
        (list (cons 'label digit)
              (cons 'x chip-x) (cons 'y chip-y)
              (cons 'w chip-size) (cons 'h chip-size)
              (cons 'font-size font-size)
              (cons 'padding padding)
              (cons 'corner-radius (cdr (assoc 'corner-radius opts)))
              (cons 'color (cdr (assoc 'color opts)))
              (cons 'background (cdr (assoc 'background opts)))
              (cons 'border-width (cdr (assoc 'border-width opts)))
              (cons 'border-color (cdr (assoc 'border-color opts))))))

    (define (resolve-occluded-against-visible chips initial-placed sw sh)
      (let outer ((rest chips)
                  (placed (let r ((xs initial-placed) (a '()))
                            (if (null? xs) a (r (cdr xs) (cons (car xs) a)))))
                  (new-count 0))
        (cond
          ((null? rest)
            (let collect ((p placed) (remaining new-count) (acc '()))
              (cond
                ((zero? remaining) acc)
                (else (collect (cdr p) (- remaining 1) (cons (car p) acc))))))
          (else
            (let* ((c0 (clamp-chip-to-screen (car rest) sw sh))
                   (natural-y (cdr (assoc 'y c0))))
              (let inner ((c c0) (attempts 0))
                (cond
                  ((>= attempts chip-resolve-max-attempts)
                   (outer (cdr rest) (cons c placed) (+ new-count 1)))
                  (else
                    (let ((conflict (find-overlapping placed c)))
                      (cond
                        ((not conflict)
                         (outer (cdr rest) (cons c placed) (+ new-count 1)))
                        (else
                          (let* ((cw (cdr (assoc 'w c))) (ch (cdr (assoc 'h c)))
                                 (cx (cdr (assoc 'x c)))
                                 (cf-x (cdr (assoc 'x conflict)))
                                 (cf-y (cdr (assoc 'y conflict)))
                                 (cf-w (cdr (assoc 'w conflict)))
                                 (cf-h (cdr (assoc 'h conflict)))
                                 (try-y (+ cf-y cf-h chip-overlap-gap))
                                 (try-x-right (+ cf-x cf-w chip-overlap-gap))
                                 (new-c
                                   (cond
                                     ((<= (+ try-y ch) sh)
                                      (chip-with-position c cx try-y))
                                     ((<= (+ try-x-right cw) sw)
                                      (chip-with-position c try-x-right natural-y))
                                     (else c))))
                            (inner new-c (+ attempts 1))))))))))))))

    (define (resolve-chips-with-visibility annotated sw sh)
      (let split ((rest annotated) (visible-rev '()) (occluded-rev '()))
        (cond
          ((null? rest)
            (let* ((visible-chips (reverse visible-rev))
                   (occluded-chips (reverse occluded-rev))
                   (occluded-resolved (resolve-occluded-against-visible
                                        occluded-chips visible-chips sw sh)))
              (let reassemble ((src annotated)
                               (vp visible-chips)
                               (op occluded-resolved)
                               (acc '()))
                (cond
                  ((null? src) (reverse acc))
                  ((car (car src))
                   (reassemble (cdr src) (cdr vp) op (cons (car vp) acc)))
                  (else
                   (reassemble (cdr src) vp (cdr op) (cons (car op) acc)))))))
          ((car (car rest))
            (split (cdr rest)
                   (cons (clamp-chip-to-screen (cdr (car rest)) sw sh) visible-rev)
                   occluded-rev))
          (else
            (split (cdr rest)
                   visible-rev
                   (cons (cdr (car rest)) occluded-rev))))))

    ;; ─── on-render side-effect ─────────────────────────────────────
    (define (paint-and-snapshot! opts)
      (let* ((ws (list-current-space-windows))
             (labelled (label-pairs default-window-labels ws))
             (raw-chips
               (map (lambda (lw)
                      (window-chip-for (car lw) (cdr lw) opts))
                    labelled))
             (faded-bg (cdr (assoc 'faded-background opts)))
             (annotated
               (map (lambda (lw chip)
                      (let* ((win (cdr lw))
                             (wid (cdr (assoc 'windowId win)))
                             (pid (cdr (assoc 'ownerPid win)))
                             (cx (cdr (assoc 'x chip))) (cy (cdr (assoc 'y chip)))
                             (cw (cdr (assoc 'w chip))) (ch (cdr (assoc 'h chip)))
                             (test-x (+ cx (quotient cw 2)))
                             (test-y (+ cy (quotient ch 2)))
                             (visible? (window-visible-at? wid pid test-x test-y))
                             (styled (if visible?
                                       chip
                                       (chip-with-background chip faded-bg))))
                        (cons visible? styled)))
                    labelled raw-chips))
             (windows-data
               (map (lambda (lw vc)
                      (let* ((win (cdr lw))
                             (label (car lw))
                             (visible? (car vc)))
                        (list (cons 'label label)
                              (cons 'app (cdr (assoc 'subText win)))
                              (cons 'title (cdr (assoc 'text win)))
                              (cons 'visible visible?))))
                    labelled annotated))
             (screen (primary-screen-size))
             (chips (resolve-chips-with-visibility
                      annotated
                      (cdr (assoc 'w screen))
                      (cdr (assoc 'h screen)))))
        (set! current-window-targets labelled)
        (set! current-windows-data windows-data)
        (hints-show chips)))

    ;; Constructor.
    ;; A block spec is an alist; we tuck the (live!) windows-data into
    ;; 'windows so the JS renderer sees the current snapshot every render.
    ;; alist->json reads the cell at serialization time, so set! between
    ;; render() and the spec being built isn't a race — block-list-
    ;; payload-json calls on-render-fn FIRST, then serializes.
    (define (make-window-list-block . opts)
      (let* ((alist (apply props->alist opts))
             (show-chips? (alist-ref alist 'show-chips #f))
             (chip-overrides (alist-ref alist 'chip-options '()))
             (chip-opts (merge-chip-options chip-overrides)))
        (let ((base
                (list (cons 'type 'window-list)
                      ;; Carry windows as a thunk-resolved value. We can't
                      ;; bake the snapshot into the spec since the spec is
                      ;; constructed once at group-build time. Instead the
                      ;; on-render-fn updates current-windows-data and the
                      ;; serializer pulls it via assoc each render — but
                      ;; alist->json reads the cell value as of serialize
                      ;; time, so we use a wrapper that resolves at JSON
                      ;; build time. The simplest mechanism: list a sentinel
                      ;; key 'windows-resolver and have block-list-payload-
                      ;; json call it. To avoid extending the protocol we
                      ;; instead keep the on-render-fn pattern: when
                      ;; show-chips, on-render-fn mutates the spec's
                      ;; 'windows entry in place via set-cdr!.
                      (cons 'windows '()))))
          (cond
            (show-chips?
              ;; Build an effect closure that captures the mutable spec
              ;; for in-place update. The closure refreshes 'windows on
              ;; every render so the JS payload matches what was just
              ;; painted on screen.
              (let ((spec base))
                (define (effect)
                  (paint-and-snapshot! chip-opts)
                  (let ((win-entry (assoc 'windows spec)))
                    (set-cdr! win-entry current-windows-data)))
                (append spec
                        (list (cons 'on-render-fn effect)))))
            (else base)))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/window-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/window-list.js")))
```

**Note on `set-cdr!`:** LispKit's mutable pair support is required here. If the codebase has historically avoided `set-cdr!`, the alternative is to register a per-render builder: extend `block-list-payload-json` to call a `'windows-resolver` thunk if present. For now, use `set-cdr!` — it's a standard R7RS pair mutator and the simplest path.

- [ ] **Step 4.4: Run constructor tests**

Run: `swift test --filter BlocksWindowListLibraryTests`

Expected: PASS.

- [ ] **Step 4.5: Add payload-shape test**

Append:

```swift
    @Test func windowListPayloadCarriesEmptyWindowsByDefault() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { Issue.record("scheme path"); return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("""
          (define grp (group "w" "Win" 'renderer 'blocks
                        'blocks (list (make-window-list-block))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("\"type\":\"window-list\""))
        #expect(html.contains("\"windows\":[]"))
    }
```

- [ ] **Step 4.6: Run it**

Run: `swift test --filter BlocksWindowListLibraryTests/windowListPayloadCarriesEmptyWindowsByDefault`

Expected: PASS.

- [ ] **Step 4.7: Create the `.js`** (lifted from `renderWindowsList` in `diagram-panel.js`)

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.js`:

```javascript
/* window-list.js — block renderer for the labelled windows list. */

(function() {
  function el(tag, attrs, ...kids) {
    const e = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') e.className = attrs[k];
        else if (k === 'text') e.textContent = attrs[k];
        else e.setAttribute(k, attrs[k]);
      }
    }
    for (const kid of kids) {
      if (kid == null) continue;
      e.appendChild(typeof kid === 'string' ? document.createTextNode(kid) : kid);
    }
    return e;
  }

  window.overlayBlockRenderers = window.overlayBlockRenderers || {};
  window.overlayBlockRenderers['window-list'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const windows = block.windows || [];
    for (const w of windows) {
      const name = w.title ? (w.app + ' · ' + w.title) : w.app;
      const cls = w.visible ? 'wl-row' : 'wl-row dulled';
      const row = el('div', { class: cls },
        el('span', { class: 'entry-key', text: w.label }),
        el('span', { class: 'entry-arrow', text: '→' }),
        el('span', { class: 'entry-label', text: name })
      );
      container.appendChild(row);
    }
  };
})();
```

- [ ] **Step 4.8: Create the `.css`** (lifted from `.diagram-windows-list` in `diagram-panel.css`)

Create `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.css`:

```css
/* window-list.css — labelled windows-list block. */

.block-window-list {
  margin-top: 14px;
  padding-top: 6px;
  border-top: 1px solid var(--color-separator);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.block-window-list .wl-row {
  display: grid;
  grid-template-columns: 3ch auto 1fr;
  column-gap: 4px;
  align-items: baseline;
}

.block-window-list .wl-row .entry-key { color: var(--color-key); font-weight: 600; }
.block-window-list .wl-row .entry-arrow { color: var(--color-arrow); }
.block-window-list .wl-row .entry-label {
  color: var(--color-label);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.block-window-list .wl-row.dulled .entry-key,
.block-window-list .wl-row.dulled .entry-arrow,
.block-window-list .wl-row.dulled .entry-label {
  opacity: 0.5;
}
```

- [ ] **Step 4.9: Add a CSS-presence test**

Append:

```swift
    @Test func windowListRegistersJsAndCss() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { Issue.record("scheme path"); return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("""
          (define grp (group "w" "Win" 'renderer 'blocks
                        'blocks (list (make-window-list-block))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("overlayBlockRenderers['window-list']"))
        #expect(html.contains(".block-window-list"))
    }
```

- [ ] **Step 4.10: Run all Task-4 tests + full suite**

Run: `swift test --filter BlocksWindowListLibraryTests`
Then: `swift test`

Expected: green.

- [ ] **Step 4.11: Commit Task 4**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld \
        Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.js \
        Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.css \
        Tests/ModaliserTests/BlocksWindowListLibraryTests.swift
git commit -m "$(cat <<'EOF'
feat(blocks/window-list): labelled windows-list block + chip painting

Wraps the labelled list under .block-window-list and the (optional)
chip-painting side-effect into a single block.  show-chips #t attaches
an on-render-fn that paints chips, runs window-visible-at? probes, and
mutates the spec's 'windows entry in place so the rendered list matches
the chips painted on screen.

The block exposes window-list-current-targets / -labels so the parent
group can build a (key-range "1..") that focuses by digit — Task 5
wires this up in window-actions.sld.
EOF
)"
```

---

## Task 5: Migrate `window-actions` to block-list

**Files:**

- Modify: `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld`

**Outcome:** The `actions` group uses `'renderer 'blocks` with three blocks. The current `on-enter`/`on-leave` chip painting moves into `window-list-block`'s on-render-fn (chips are painted on every render, including push-updates — same effect as today's on-enter). The `current-window-targets`/`current-windows-data` state moves to the `window-list` library. `focus-by-digit` reads from `window-list-current-targets`. The `window-range` binding stays in `window-actions.sld` because it's group-level dispatch glue, not block content.

### Step 5.1: Read the current state

- [ ] **Step 5.1: Re-read `window-actions.sld`**

`Read` `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld` to refresh context. The migration changes: imports, `actions`, removes the chip-painting helpers (moved to `window-list.sld`).

### Step 5.2: Write the migration target test FIRST

- [ ] **Step 5.2: Add a test that fails today and passes after migration**

Append to `Tests/ModaliserTests/ModaliserWindowActionsLibraryTests.swift`:

```swift
    @Test func actionsGroupUsesBlocksRendererAfterMigration() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(define g (actions))")
        #expect(try engine.evaluate("(eq? (node-renderer g) 'blocks)") == .true)
        // Three blocks: window-diagram, which-key, window-list
        try engine.evaluate("(define blocks (node-renderer-payload g 'blocks))")
        #expect(try engine.evaluate("(= (length blocks) 3)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (list-ref blocks 0))) 'window-diagram)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (list-ref blocks 1))) 'which-key)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (list-ref blocks 2))) 'window-list)") == .true)
    }
```

Run: `swift test --filter ModaliserWindowActionsLibraryTests/actionsGroupUsesBlocksRendererAfterMigration`

Expected: FAIL — current `actions` returns `'renderer 'diagram`.

### Step 5.3: Update existing tests that check `'diagram` renderer

- [ ] **Step 5.3: Update `defaultActionsGroupCarriesDiagramRendererAndPanels` (line 31 area)**

Either delete the test or rename + rewrite it to reflect the new shape. Replace with:

```swift
    @Test func defaultActionsGroupCarriesBlocksRendererAndPanels() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(define g (actions))")
        #expect(try engine.evaluate("(eq? (node-renderer g) 'blocks)") == .true)
        try engine.evaluate("""
          (define blocks (node-renderer-payload g 'blocks))
          (define wd (car blocks))
          (define panels (cdr (assoc 'panels wd)))
        """)
        // Six panels: full thirds, half thirds, two two-thirds, fill (m), center (c)
        #expect(try engine.evaluate("(= (length panels) 6)") == .true)
        try engine.evaluate("(define p1 (car panels))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type p1)) 'grid)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'cols p1)) 3)") == .true)
    }
```

Also delete `actionsGroupHasOnEnterAndOnLeaveHooks` (since on-enter/on-leave move to the block's on-render-fn).

### Step 5.4: Rewrite `window-actions.sld`

- [ ] **Step 5.4: Rewrite `actions` to use the blocks renderer**

Replace the body of `window-actions.sld` with a slimmed-down version:

```scheme
(define-library (modaliser window-actions)
  (export actions register! divisions center-panel)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser window)
          (modaliser diagram-panel)
          (modaliser blocks window-diagram)
          (modaliser blocks which-key)
          (modaliser blocks window-list))
  (begin

    (define (js-cell cell)
      (list (cons 'key      (cdr (assoc 'key cell)))
            (cons 'col      (cdr (assoc 'col cell)))
            (cons 'row      (cdr (assoc 'row cell)))
            (cons 'colSpan  (cdr (assoc 'col-span cell)))
            (cons 'rowSpan  (cdr (assoc 'row-span cell)))))

    (define (divisions matrix)
      (let* ((rows (length matrix))
             (cols (length (car matrix)))
             (cells (parse-matrix matrix))
             (spec (make-grid-panel-spec cols rows (map js-cell cells)))
             (keys (map (lambda (cell)
                          (let* ((k (cdr (assoc 'key cell)))
                                 (c (cdr (assoc 'col cell)))
                                 (r (cdr (assoc 'row cell)))
                                 (cs (cdr (assoc 'col-span cell)))
                                 (rs (cdr (assoc 'row-span cell)))
                                 (x  (/ (- c 1) cols))
                                 (y  (/ (- r 1) rows))
                                 (w  (/ cs cols))
                                 (h  (/ rs rows)))
                            (key k k (lambda () (move-window x y w h)))))
                        cells)))
        (list spec keys)))

    (define (center-panel k)
      (list (make-center-panel-spec k)
            (list (key k "Center" (lambda () (center-window))))))

    (define (panel-spec-of p) (car p))
    (define (panel-keys-of p) (cadr p))

    (define (default-panels)
      (list
        (divisions '(("d" "f" "g")))
        (divisions '(("D" "F" "G") ("C" "V" "B")))
        (divisions '(("e" "e" #f)))
        (divisions '((#f "t" "t")))
        (divisions '(("m")))
        (center-panel "c")))

    (define default-window-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    (define (focus-by-digit d)
      (let ((entry (assoc d (window-list-current-targets))))
        (when entry (focus-window (cdr entry)))))

    ;; The 1.. range stays group-level so the state machine sees it
    ;; alongside the other children. 'hidden suppresses it from the
    ;; which-key strip — the window-list block at the bottom already
    ;; surfaces the digit → window mapping per row.
    (define (window-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Window <n>"
              default-window-labels
              (lambda (k) (focus-by-digit k)))))

    (define (actions . opts)
      (let* ((alist        (apply props->alist opts))
             (group-key    (alist-ref alist 'key "w"))
             (group-label  (alist-ref alist 'label "Windows"))
             (custom-panels (alist-ref alist 'panels #f))
             (panels        (or custom-panels (default-panels)))
             (panel-specs   (map panel-spec-of panels))
             (panel-keys    (apply append (map panel-keys-of panels)))
             (chip-overrides (alist-ref alist 'chip-options '()))
             ;; window-diagram block: a single js-cell-converted form of
             ;; ALL panel specs (the block-spec carries the full panels list).
             ;; consumed-keys is derived inside the block constructor.
             (wd-block (make-window-diagram-block panel-specs))
             (wk-block (make-which-key-block))
             (wl-block (make-window-list-block 'show-chips #t
                                               'chip-options chip-overrides))
             (text-entries
               (list
                 (selector "n" "Named…"
                   'prompt "Select window…"
                   'source list-windows
                   'on-select focus-window
                   'actions
                     (list
                       (action "Focus" 'description "Select window" 'key 'primary
                         'run (lambda (c) (focus-window c)))))
                 (window-range)
                 (key "r" "Restore" (lambda () (restore-window)))))
             (children (append panel-keys text-entries)))
        (apply group group-key group-label
               'renderer 'blocks
               'blocks (list wd-block wk-block wl-block)
               children)))

    (define (register! . opts)
      (let* ((alist (apply props->alist opts))
             (scope (alist-ref alist 'tree-scope 'global)))
        (define-tree scope (apply actions opts))))))
```

Notes:
- The chip-painting logic, `current-window-targets`, `current-windows-data`, `paint-window-chips!`, and chip resolution helpers are gone from this file — they live in `(modaliser blocks window-list)`. `focus-by-digit` reads via the exported `window-list-current-targets` accessor.
- `on-enter`/`on-leave` are removed: the on-render-fn on the window-list block paints chips every render. `hints-hide` was the on-leave equivalent — see the next step for replacement.

- [ ] **Step 5.5: Handle the chip-hide-on-exit case**

The current on-leave fires `hints-hide`. With the new design, chips are painted in the on-render-fn but never explicitly hidden when the overlay closes. Add a group-level on-leave to the actions group that hides chips:

In `actions`, change the `apply group` call to:

```scheme
        (apply group group-key group-label
               'renderer 'blocks
               'blocks (list wd-block wk-block wl-block)
               'on-leave (lambda () (hints-hide))
               children)))
```

And add `hints-hide` to the imports — change `(modaliser window)` to include the hints lib too:

```scheme
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser window)
          (modaliser hints)
          (modaliser diagram-panel)
          (modaliser blocks window-diagram)
          (modaliser blocks which-key)
          (modaliser blocks window-list))
```

### Step 5.6: Run the migration tests

- [ ] **Step 5.6: Run targeted tests**

Run: `swift test --filter ModaliserWindowActionsLibraryTests`

Expected: all pass.

- [ ] **Step 5.7: Run the full suite**

Run: `swift test`

Expected: green. If `OverlayRendererDispatchTests` references `'diagram` specifically for the windows path, those tests still pass against synthetic groups; they don't assert anything about `actions` itself.

### Step 5.8: Manual smoke (recorded in plan, executed by human)

- [ ] **Step 5.8: Run install + relaunch + verify**

```bash
./scripts/install.sh
# Relaunch Modaliser via the macOS app (or whatever the install script outputs as next step).
```

Then:
1. Press leader (default ⌥-space), then `w`.
2. Confirm overlay shows: panel grid (6 panels) on top + n/r entries strip + windows-list at bottom with chips painted on screen.
3. Press `1` (or whichever digit) — focus jumps to the corresponding window.
4. Press leader+w again — chips repaint, deterministic ordering preserved.
5. Switch to a desktop where HazeOver dims windows — confirm the chip behind the dim is still rendered as visible (not dulled).

If any of these fail, file what fails. Don't proceed to commit until smoke passes.

### Step 5.9: Commit the migration

- [ ] **Step 5.9: Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld \
        Tests/ModaliserTests/ModaliserWindowActionsLibraryTests.swift
git commit -m "$(cat <<'EOF'
refactor(window-actions): migrate to block-list renderer

The actions group now uses 'renderer 'blocks with three blocks:
window-diagram, which-key, window-list (show-chips #t).  Chip-painting
moves into window-list's on-render-fn; the group-level on-leave
continues to hide chips on overlay close.

current-window-targets and the chip resolution helpers move out of this
file and into (modaliser blocks window-list); focus-by-digit reads via
window-list-current-targets.  The 1.. range stays on the group as a
hidden binding — the window-list block surfaces the mapping visually.

The old 'diagram renderer in ui/overlay.scm still exists for any future
callers, but actions is no longer one of them.  Removal is deferred.
EOF
)"
```

---

## Task 6 (optional): Migrate iTerm pane-actions

Per the architecture doc: defer unless time permits. Skip for this implementation if Tasks 1–5 + Steps 5.8 smoke pass cleanly and the suite is green. If the implementing session has bandwidth, mirror `window-list.sld` as `iterm-pane-list.sld` with whatever visibility-probe analogue exists for iTerm panes (none right now — that's the "follow-up consideration" the arch doc notes).

---

## Cross-cutting verification (run after Task 5)

- [ ] **Full suite green:** `swift test` — no regressions across the 466+ tests.
- [ ] **Pre-existing `swift test` counts unchanged + new tests added:** record the new count, expect monotonic increase.
- [ ] **Manual smoke per Step 5.8** — chip painting, deterministic ordering, HazeOver visibility.
- [ ] **Visual smoke** — overlay still reads as before (panel grid + n/r + window list), no missing styles, no orphan classes.
- [ ] **`'renderer 'diagram` dispatch still works** — synthetic test groups in `OverlayRendererDispatchTests` continue to pass.

---

## Out of scope (explicit)

- Multi-display chip painting.
- iTerm pane visibility probe.
- Generic visibility-probe abstraction.
- Async/lazy block rendering.
- Removing the `'diagram` renderer from `ui/overlay.scm` (separate commit if/when no callers remain).
