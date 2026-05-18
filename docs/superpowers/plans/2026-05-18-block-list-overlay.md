# Block-List Overlay Architecture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILLS: `superpowers:writing-plans` (to expand any task that needs finer-grained TDD steps), `superpowers:test-driven-development` (per step), `superpowers:subagent-driven-development` (for parallel independent tasks). The task list below is a roadmap, not a step-by-step recipe — for each task, draft the TDD steps in the same checkbox style the modular-config phase plans use.

**Goal:** Replace the windows-overlay's hardcoded "diagram + entries + windows-list" rendering pipeline with a generic *block-list* renderer. Each group declares an ordered list of blocks (top to bottom); each block has a type (`'window-diagram`, `'which-key`, `'window-list`, …) with its own render function and optional on-screen side-effect (chip painting). The current windows overlay becomes one configuration of this generic system. Future overlays (iTerm panes, etc.) reuse the same machinery instead of cloning the diagram renderer.

**Architecture:** A new `'blocks` renderer is added alongside the existing `'diagram` renderer (which can be retired once windows migrates). Each block type ships as a `.sld + .js + .css` trio mirroring the current `lib/modaliser/diagram-panel.*` layout — the .sld exports a constructor, registers its assets via `add-overlay-asset-file!`, and (for blocks with side-effects) exports an on-render thunk; the .js registers a render function under a globally-known key; the .css scopes its styles under a per-block class prefix. The renderer in `ui/overlay.scm` iterates the group's `'blocks` list, emits each block's payload as a tagged JSON entry, and the JS dispatcher renders them in order. Side-effects (chip painting) run after render via a small Scheme-side effect registry that the group's `on-enter` invokes.

**Tech Stack:** Scheme (LispKit) for the overlay state machine + per-block constructors + side-effect thunks. JS (WKWebView) for per-block DOM rendering. CSS for per-block styling. No new Swift code expected — the existing `windowVisibleAtFunction` and chip-painting primitives are unchanged.

---

## Design decisions (settled during brainstorm)

Captured here so the implementing session doesn't have to re-litigate them:

1. **Blocks stack top-to-bottom** in a group's `'blocks` list; order in the list = visual order in the overlay. No reflow between blocks.
2. **Each block type is a .sld + .js + .css trio.** The .sld is the only Scheme-side surface; the .js and .css are registered via the existing `add-overlay-asset-file!` mechanism at library import time.
3. **Chip-painting is a block-level effect, not a group-level effect.** A block that paints chips (e.g. `window-list` with `'show-chips #t`) exports a thunk; the renderer pipeline runs all such thunks after emitting the rendered HTML. Today's `on-enter` chip painting on the windows group moves into the `window-list` block's effect.
4. **Categories (in `which-key` block) use a wrapping form:**
   ```scheme
   (which-key-block
     (category "Move"  (key "h" "Left" hl) (key "j" "Down" jd))
     (category "Edit"  (key "x" "Cut"  xx) (key "v" "Paste" vp))
     (key "q" "Quit" qq))   ; bare entries are misc — flow individually
   ```
5. **State machine sees categories as transparent.** Children of `(category …)` are bound at the block's level (same dispatch behavior as if hoisted). Categories exist purely as render-time grouping metadata.
6. **CSS multi-column layout for which-key:** container uses `column-width: 14rem; column-count: auto; column-fill: auto` (top-down sequential fill, more predictable than balanced).
7. **Categories stay atomic; misc flows freely.** `.wk-category { break-inside: avoid; }` keeps a labelled category in one column. Misc entries are bare `<div class="wk-row">` siblings with no break-inside rule — each row flows independently across columns.
8. **Source order is preserved across the misc/category mix.** A misc row declared before `(category "Move" …)` renders before Move; column packer respects the source-order sequence.
9. **The misc bucket is the implicit home for items NOT inside any `(category …)`.** "No categories declared" is just an instance of "every item is uncategorized" — same code path, no separate mode.
10. **Each category renders as: label + divider under label + rows.** Header is a `<h4>` (or equivalent semantic element), divider is a `border-bottom` on the header.

---

## File Structure

**Create:**

- `Sources/Modaliser/Scheme/lib/modaliser/block-list.sld` — entry point for the block-list renderer. Exports nothing for users; registers nothing global except the `'blocks` renderer dispatcher (or it could be implicit — see Task 1). Co-located with diagram-panel for symmetry.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.sld` — `make-window-diagram-block` constructor; registers `window-diagram.js` + `.css`.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.js` — render function for the panel grid (lifted from current `diagram-panel.js`).
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.css` — panel-grid CSS (lifted from current `diagram-panel.css`).
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.sld` — `make-which-key-block` constructor, plus `category` constructor and category-collection helpers.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js` — render function: multi-column container, per-category divs, bare misc rows.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css` — `column-width` / `column-fill: auto` / `break-inside: avoid` rules.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld` — `make-window-list-block` constructor; optional `'show-chips #t` registers the on-render effect that runs chip painting.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.js` — render function for the labelled windows list (lifted from `renderWindowsList` in current `diagram-panel.js`).
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.css` — styles (lifted from `.diagram-windows-list` rules in current `diagram-panel.css`).
- `Tests/ModaliserTests/BlockListLibraryTests.swift` — tests the block-list renderer's payload serialization, block-type dispatch, on-render effect ordering.
- `Tests/ModaliserTests/ModaliserBlocksWhichKeyLibraryTests.swift` — tests `category` flattening through state machine; misc-vs-category split in render payload; source-order preservation.

**Modify:**

- `Sources/Modaliser/Scheme/ui/overlay.scm` — extend `custom-renderer-payload-json` (or add a sibling `block-list-payload-json`) to handle the new `'blocks` renderer; iterate `'blocks` list, emit each block's tagged JSON, run on-render effects.
- `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld` — migrate `actions` to use `'renderer 'blocks` with `(window-diagram-block …) (which-key-block) (window-list-block 'show-chips #t)` instead of `'renderer 'diagram` + `'panels` + `'dynamic-data-fn windows-overlay-data`. The on-enter chip painting moves into the `window-list-block` effect.
- `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` — child-collection traversal must descend transparently through `'category` nodes. One small recursive helper in `node-children` (or wherever the binding map is built).
- `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld` — export `category` so user configs can declare them. Add the constructor.

**Migrate then delete:**

- `Sources/Modaliser/Scheme/lib/modaliser/diagram-panel.{sld,js,css}` — content lifted into `blocks/window-diagram.*` (panels) and `blocks/window-list.*` (windows list section). The `'diagram` renderer dispatch in `overlay.scm` can be retired once windows is the only caller, and migrated. The matrix parser + panel-spec constructors stay where they are (still used by `window-actions.sld`'s `divisions`).

**Untouched:**

- `Sources/Modaliser/WindowLibrary.swift` — `window-visible-at?` and other primitives are reused as-is.
- `Sources/Modaliser/Scheme/lib/modaliser/hints.sld` — chip painting still goes through `hints-show`.
- iTerm modules — Task 6 is optional; if the implementing session has bandwidth, migrate iterm-actions to use the same block-list with an `iterm-pane-list` block; otherwise defer to a follow-up.

---

## Task 1: Block-list renderer scaffolding

**Files:** Create `block-list.sld`, modify `overlay.scm`, create `BlockListLibraryTests.swift`.

**Outcome:** A group with `'renderer 'blocks 'blocks (list …)` emits a JSON payload of shape `{type: "blocks", blocks: [{type: "<block-type>", …}, …], entries: […]}`. Each block in the list serializes its own payload via a block-type-specific JSON-builder dispatched by the block's `'type` tag. The JS side has a `window.overlayBlockRenderers` registry that maps `type` → render function (registered by each block's .js).

**TDD steps to draft in the implementing session's detailed plan:**
- Write a failing test that constructs a synthetic block-list group with a single stub block-type and asserts the emitted JSON shape.
- Implement the dispatch in `overlay.scm` so the test passes.
- Add a second stub block type; assert ordering in the payload matches the list order.
- Add an on-render effect to one stub block; assert the effect fires after render (state visible in some accessible Scheme variable the test inspects).

## Task 2: `window-diagram` block (lift current panel-grid)

**Files:** Create `blocks/window-diagram.{sld,js,css}`.

**Outcome:** The current `diagram-panel.js`'s `renderGridPanel` / `renderFillPanel` / `renderCenterPanel` are wrapped in a block renderer that takes `{type: "window-diagram", panels: [...]}` and emits the panel grid. The CSS is the same auto-fill grid as today (with the row-gap / padding tweaks from this branch preserved). Constructor: `(make-window-diagram-block panel-spec-list)`. No on-render effect.

**TDD steps:** test asserts `'window-diagram` block with N panel-specs emits the expected DOM structure (use DOM smoke test or just JSON assertion).

## Task 3: `which-key` block with category/misc support

**Files:** Create `blocks/which-key.{sld,js,css}`, modify `dsl.sld` (export `category`), modify `state-machine.sld` (transparent traversal).

**Outcome:**
- `(category "label" . children)` produces a `(kind . category)` node carrying its label and children.
- The state machine treats category nodes as transparent: dispatch/binding behaves as if children were hoisted. Add a `flatten-categories` helper in `state-machine.sld` used by the binding map builder.
- The which-key block's JSON payload partitions children into ordered `(misc | category)` segments — preserving source order — and the JS renderer emits a multi-column container with `.wk-category` units (atomic) interleaved with bare `.wk-row` misc rows.
- CSS: container uses `column-width: 14rem; column-fill: auto`; categories `break-inside: avoid`; misc rows have no break rule.

**TDD steps:**
- Test: `(key "h" "Left" h-fn)` bound under `(category "Move" …)` dispatches the same as if not wrapped (state machine flattening).
- Test: a block containing one category + one bare key produces a JSON payload with one `category` segment and one `misc` row, in source order.
- Test: column rendering — load CSS in a JSDOM-like harness (or just assert the class structure; visual is a manual check).

## Task 4: `window-list` block with optional chip-painting effect

**Files:** Create `blocks/window-list.{sld,js,css}`.

**Outcome:**
- `(make-window-list-block . opts)` returns a block spec. Opts include `'show-chips #t` (default `#f`) and `'chip-options …` (current chip-options alist).
- Render side: emits the labelled windows list with the visibility-derived dulled-row styling (today's `renderWindowsList`).
- Effect side: when `'show-chips` is true, the block's on-render thunk computes chip positions, calls `window-visible-at?` per chip, and forwards the results to `hints-show` (today's `paint-window-chips!` flow). Effect reads the chip-options from the block spec.
- The dynamic data (list of windows + their visibility) is fetched inside the effect, so the render and the effect share a single computation. Pass the visibility annotations to the JSON payload too, so the rendered rows are dulled correctly.

**TDD steps:** the chip-painting effect is hard to test in isolation — at minimum, test that the block's JSON payload shape matches what JS expects when given a mock window list. The chip-painting effect itself is verified manually post-migration (Task 5).

## Task 5: Migrate `window-actions` to block-list

**Files:** Modify `window-actions.sld`.

**Outcome:** The `actions` group uses `'renderer 'blocks` with:

```scheme
'blocks (list
  (make-window-diagram-block panel-specs)
  (make-which-key-block)         ; bare entries (n, r) end up as misc rows
  (make-window-list-block 'show-chips #t 'chip-options chip-opts))
```

The current `on-enter` hook (which called `paint-window-chips!`) is removed — the chip-painting effect on `window-list-block` replaces it. The current `'panels` / `'dynamic-data-fn` group-level properties are removed. The `current-window-targets` / `current-windows-data` state may move into the `window-list-block` module or stay in `window-actions` — pick whichever is cleaner.

Verification:
- Build + relaunch.
- Leader → `w` shows the same panel grid + same n/r entries strip + same windows list at bottom.
- Window chips paint identically (HazeOver still correctly skipped, deterministic ordering preserved).
- The "1.. → Window <n>" entry remains hidden (the `'hidden` flag we added still works).

## Task 6 (optional): Migrate iTerm pane-actions

**Files:** Modify `lib/modaliser/apps/iterm.sld`. Create `blocks/iterm-pane-list.{sld,js,css}`.

**Outcome:** iTerm's pane-selection group uses the block-list with an `iterm-pane-list` block (chip-painting analogue for iTerm panes — needs a `pane-visible-at?` probe, which is a follow-up consideration noted but not blocked on here). If the time isn't there, defer this entirely — the architecture supports it but only windows needs to migrate to validate the design.

---

## Cross-task conventions

- **Branch:** `block-list-overlay`.
- **Commits:** conventional-commits prefix. `feat(blocks):` for new infrastructure, `refactor(windows-overlay):` for the migration, etc.
- **Tests:** each task leaves the suite green (target: same 466+ count, plus new tests).
- **Manual verification per task:** the existing windows behavior must keep working through every step. The migration in Task 5 is the moment of truth; everything before that is additive.
- **The `'diagram` renderer can be removed** once `window-actions` is the only caller and Task 5 lands. If anyone external uses it, leave it; this is a single-callsite refactor in practice.
- **Code review:** invoke `superpowers:requesting-code-review` before merging — the block protocol is new public surface for any future block authors.

---

## Out of scope (explicit)

- Multi-display chip painting (still primary-screen only — separate concern).
- `pane-visible-at?` probe for iTerm chips (Task 6 either reuses a heuristic or defers).
- Generic visibility-probe abstraction across window vs pane (premature — wait for second use case).
- Async/lazy block rendering (all blocks render synchronously today; no reason to change).
- A general-purpose `'hidden` flag in the DSL (the current ad-hoc cons in `window-actions.sld` works; categories largely subsume the use case).
- Block-level dynamic-data thunks beyond what each block needs internally (no group-level `'dynamic-data-fn` carries over — each block fetches its own).
