# Overlay Category Packing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate wasted vertical space in the which-key category overlay by packing category segments down columns so a short category backfills the gap under another, and shrink columns to their content width.

**Architecture:** A new pure Scheme function `distribute-which-key-columns` groups the overlay's segments into N columns (column-major sequential fill, declared order preserved). `which-key-payload-json` emits these groups as a nested `columns` array instead of a flat `segments` list. `which-key.js` renders one `<div>` per column; `which-key.css` lays the columns out as an equal-width grid sized to content (dropping the old 14rem floor).

**Tech Stack:** LispKit Scheme (`overlay.scm`), vanilla JS + CSS overlay assets (`which-key.js`, `which-key.css`), Swift Testing (`swift test`).

---

## Background for the implementer

The which-key overlay is the panel shown when a modality is active (e.g. **Global**). It renders "segments" — each category is one segment, and consecutive loose entries coalesce into one "misc" segment.

- **Scheme side** (`Sources/Modaliser/Scheme/ui/overlay.scm`): `which-key-payload-json` builds the JSON the renderer consumes. It calls `partition-which-key-segments` (→ ordered segment list), `segments-row-count` (→ total visible rows), `overlay-column-count` (→ column count `N` from an aspect-ratio search), and `render-segment` (→ one segment's JSON).
- **JS side** (`Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js`): `window.overlayBlockRenderers['which-key']` reads the payload and builds DOM.
- **CSS side** (`Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css`): `.block-which-key .wk-columns` lays segments out.

A **segment** is an internal list: `(list 'misc <nodes>)` or `(list 'category <label> <nodes>)`. Only the *count* of `<nodes>` matters for layout (`length`), so unit tests can use synthetic segments built from quoted lists of arbitrary symbols.

The overlay window is `width: max-content` and `overlay.js` reports its natural size back to the native panel via a `ResizeObserver` — so tightening the content tightens the window automatically. No Swift or window-sizing code changes.

Today's payload: `{"type":"which-key","cols":N,"segments":[<seg>,…]}`.
Target payload: `{"type":"which-key","columns":[[<seg>,…],[<seg>,…]]}`.

All work happens in the existing worktree.

---

## Task 1: Packing core — `segment-row-count` + `distribute-which-key-columns`

Two pure Scheme functions in `overlay.scm`. `segment-row-count` is factored out of the existing `segments-row-count`; `distribute-which-key-columns` is new.

**Files:**
- Modify: `Sources/Modaliser/Scheme/ui/overlay.scm` (replace the `segments-row-count` definition near line 453)
- Test: `Tests/ModaliserTests/OverlayRenderTests.swift` (add tests after the `overlay-column-count` tests, ~line 53)

- [ ] **Step 1: Write the failing tests**

Add these tests to `Tests/ModaliserTests/OverlayRenderTests.swift`, immediately after `overlayColumnCountPicksClosestToTargetRatio` (they use the existing `loadOverlay()` helper):

```swift
    // MARK: - Column packing (distribute-which-key-columns)

    @Test func segmentRowCountCountsHeadingForCategory() throws {
        let engine = try loadOverlay()
        // A misc segment's height is its row count.
        #expect(try engine.evaluate("(segment-row-count (list 'misc '(1 2)))").asInt64() == 2)
        // A category adds one row for its heading.
        #expect(try engine.evaluate("(segment-row-count (list 'category \"X\" '(1 2 3)))").asInt64() == 4)
    }

    @Test func distributeBackfillsShortCategoryUnderShortCategory() throws {
        let engine = try loadOverlay()
        // Global overlay: Apps(8 rows) Search(3) AI(2) → heights 9/4/3,
        // target ceil(16/2)=8. Apps fills column 1; Search+AI pack column 2.
        try engine.evaluate("""
          (define cols
            (distribute-which-key-columns
              (list (list 'category "Apps"   '(1 2 3 4 5 6 7 8))
                    (list 'category "Search" '(1 2 3))
                    (list 'category "AI"     '(1 2)))
              2))
        """)
        #expect(try engine.evaluate("(length cols)").asInt64() == 2)
        #expect(try engine.evaluate("(length (car cols))").asInt64() == 1)
        #expect(try engine.evaluate("(cadr (caar cols))").asString() == "Apps")
        #expect(try engine.evaluate("(length (cadr cols))").asInt64() == 2)
        #expect(try engine.evaluate("(cadr (car (cadr cols)))").asString() == "Search")
        #expect(try engine.evaluate("(cadr (cadr (cadr cols)))").asString() == "AI")
    }

    @Test func distributePreservesDeclaredOrder() throws {
        let engine = try loadOverlay()
        // Four equal categories, 2 columns → column 1 = [A,B], column 2 = [C,D].
        try engine.evaluate("""
          (define cols
            (distribute-which-key-columns
              (list (list 'category "A" '(1 2))
                    (list 'category "B" '(1 2))
                    (list 'category "C" '(1 2))
                    (list 'category "D" '(1 2)))
              2))
        """)
        #expect(try engine.evaluate("(cadr (caar cols))").asString() == "A")
        #expect(try engine.evaluate("(cadr (cadr (car cols)))").asString() == "B")
        #expect(try engine.evaluate("(cadr (car (cadr cols)))").asString() == "C")
        #expect(try engine.evaluate("(cadr (cadr (cadr cols)))").asString() == "D")
    }

    @Test func distributeLastColumnAbsorbsRemainder() throws {
        let engine = try loadOverlay()
        // One tall category then three short ones, 2 columns: the short
        // ones all land in column 2 — never a third column.
        try engine.evaluate("""
          (define cols
            (distribute-which-key-columns
              (list (list 'category "Tall" '(1 2 3 4 5 6 7 8))
                    (list 'category "S1"   '(1))
                    (list 'category "S2"   '(1))
                    (list 'category "S3"   '(1)))
              2))
        """)
        #expect(try engine.evaluate("(length cols)").asInt64() == 2)
        #expect(try engine.evaluate("(length (car cols))").asInt64() == 1)
        #expect(try engine.evaluate("(length (cadr cols))").asInt64() == 3)
    }

    @Test func distributeSingleColumnWhenNIsOne() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
          (define cols
            (distribute-which-key-columns
              (list (list 'category "A" '(1 2))
                    (list 'category "B" '(1 2)))
              1))
        """)
        #expect(try engine.evaluate("(length cols)").asInt64() == 1)
        #expect(try engine.evaluate("(length (car cols))").asInt64() == 2)
    }

    @Test func distributeNeverMoreColumnsThanSegments() throws {
        let engine = try loadOverlay()
        // 5 columns requested but only 2 segments → at most 2 columns.
        try engine.evaluate("""
          (define cols
            (distribute-which-key-columns
              (list (list 'category "A" '(1 2 3))
                    (list 'category "B" '(1 2 3)))
              5))
        """)
        #expect(try engine.evaluate("(length cols)").asInt64() == 2)
    }

    @Test func distributeEmptySegmentsYieldsNoColumns() throws {
        let engine = try loadOverlay()
        #expect(try engine.evaluate("(null? (distribute-which-key-columns '() 2))") == .true)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter OverlayRenderTests 2>&1 | tail -30`
Expected: FAIL — the new tests error with an unbound-variable message for `segment-row-count` / `distribute-which-key-columns` (the functions don't exist yet). The pre-existing `overlay-column-count` tests still pass.

- [ ] **Step 3: Implement the two functions**

In `Sources/Modaliser/Scheme/ui/overlay.scm`, replace the entire current `segments-row-count` definition (the comment block + `(define (segments-row-count …))`, near line 453) with the following three definitions:

```scheme
;; (segment-row-count seg) → integer
;; Visible row height of one segment. A misc segment is its row count; a
;; category adds 1 for the heading row.
(define (segment-row-count seg)
  (let ((kind (car seg)))
    (cond ((eq? kind 'misc)     (length (cadr seg)))
          ((eq? kind 'category) (+ 1 (length (caddr seg))))
          (else                 0))))

;; (segments-row-count segments) → integer
;; Total visible rows across all segments. Drives aspect-ratio-aware
;; column-count selection.
(define (segments-row-count segments)
  (let loop ((rest segments) (total 0))
    (if (null? rest)
      total
      (loop (cdr rest) (+ total (segment-row-count (car rest)))))))

;; (distribute-which-key-columns segments n) → list of column lists
;;
;; Column-major sequential fill. Walk `segments` in declared order,
;; accumulating each into the current column; start the next column when
;; the current one is non-empty AND adding the segment would push its
;; height past the per-column target (ceil(total-rows / n)). The last
;; column absorbs every remaining segment, so the result never exceeds
;; `n` columns. Declared order is preserved — the overlay reads top-down
;; column 1, then column 2. Purely functional (accumulate + reverse):
;; LispKit has no set-cdr!.
(define (distribute-which-key-columns segments n)
  (let ((n (min n (length segments))))
    (if (<= n 1)
      (if (null? segments) '() (list segments))
      (let* ((total  (segments-row-count segments))
             (target (quotient (+ total n -1) n)))   ;; ceil(total / n)
        (let loop ((rest  segments)
                   (col   '())     ;; current column, reversed
                   (col-h 0)
                   (done  '()))    ;; completed columns, reversed
          (if (null? rest)
            (reverse (if (null? col) done (cons (reverse col) done)))
            (let* ((seg (car rest))
                   (h   (segment-row-count seg)))
              (if (and (not (null? col))
                       (> (+ col-h h) target)
                       (< (length done) (- n 1)))
                ;; close the current column, open a new one with `seg`
                (loop (cdr rest) (list seg) h (cons (reverse col) done))
                ;; append `seg` to the current column
                (loop (cdr rest) (cons seg col) (+ col-h h) done)))))))))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter OverlayRenderTests 2>&1 | tail -30`
Expected: PASS — all `OverlayRenderTests` pass, including the seven new tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/ui/overlay.scm Tests/ModaliserTests/OverlayRenderTests.swift
git commit -m "feat(overlay): add which-key column-packing function

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Emit the `columns` payload from `which-key-payload-json`

Rewire `which-key-payload-json` to group segments via `distribute-which-key-columns` and serialise a nested `columns` array; drop the `cols` field.

**Files:**
- Modify: `Sources/Modaliser/Scheme/ui/overlay.scm` (`which-key-payload-json`, near line 407)
- Test: `Tests/ModaliserTests/BlocksWhichKeyLibraryTests.swift` (add one test before the closing `}`)

- [ ] **Step 1: Write the failing test**

Add this test to `Tests/ModaliserTests/BlocksWhichKeyLibraryTests.swift`, immediately before the final closing brace of the `struct`:

```swift
    @Test func whichKeyPayloadEmitsNestedColumnGroups() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
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
              'blocks (list (which-key-block
                              (category "Apps"
                                (key "b" "Browser" (lambda () #t)))
                              (category "AI"
                                (key "c" "ChatGPT" (lambda () #t)))))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        guard let s = html.range(of: "data-payload='") else { Issue.record("no payload"); return }
        let after = html[s.upperBound...]
        guard let e = after.firstIndex(of: "'") else { Issue.record("unterminated"); return }
        let payload = String(after[..<e])
        // New shape: segments nested inside a "columns" array of arrays.
        #expect(payload.contains("\"type\":\"which-key\""))
        #expect(payload.contains("\"columns\":[["))
        // Old shape fields are gone.
        #expect(!payload.contains("\"segments\":"))
        #expect(!payload.contains("\"cols\":"))
        // Segment objects still serialise unchanged.
        #expect(payload.contains("\"kind\":\"category\""))
        #expect(payload.contains("\"label\":\"Apps\""))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter BlocksWhichKeyLibraryTests 2>&1 | tail -30`
Expected: FAIL — `whichKeyPayloadEmitsNestedColumnGroups` fails because the payload still contains `"cols":` and `"segments":` and has no `"columns":[[`. The other `BlocksWhichKeyLibraryTests` still pass.

- [ ] **Step 3: Rewrite `which-key-payload-json`**

In `Sources/Modaliser/Scheme/ui/overlay.scm`, replace the comment block and definition of `which-key-payload-json` (near line 407, the lines from `;; (which-key-payload-json children) → JSON object` through the end of the `(define (which-key-payload-json …))` form) with:

```scheme
;; (which-key-payload-json children) → JSON object
;;
;; Partition `children` into ordered segments (each (category …) is its
;; own segment; consecutive non-category entries coalesce into one misc
;; segment in declared position), choose a column count from the total
;; visible row count, then distribute the segments into that many columns
;; so short categories backfill the space under other short ones.
;;
;; Shape: {"type":"which-key","columns":[[<seg>,…],[<seg>,…]]}
;; — an array of columns, each an array of segment objects. The renderer
;; draws one element per column; declared order reads top-down column 1,
;; then column 2.
(define (which-key-payload-json children)
  (let* ((segments  (partition-which-key-segments children))
         (row-count (segments-row-count segments))
         (n-cols    (overlay-column-count row-count))
         (columns   (distribute-which-key-columns segments n-cols)))
    (string-append
      "{\"type\":\"which-key\",\"columns\":["
      (string-join-comma
        (map (lambda (col)
               (string-append "[" (string-join-comma (map render-segment col)) "]"))
             columns))
      "]}")))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter BlocksWhichKeyLibraryTests 2>&1 | tail -30`
Expected: PASS — all `BlocksWhichKeyLibraryTests` pass, including the new test and the pre-existing `explicitWhichKeyBlockPreservesAuthorialOrder` / `whichKeyConsecutiveMiscsCoalesceIntoOneSegment` (their substring assertions survive the shape change).

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/ui/overlay.scm Tests/ModaliserTests/BlocksWhichKeyLibraryTests.swift
git commit -m "feat(overlay): emit which-key payload as nested column groups

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Render one element per column in `which-key.js`

The renderer currently appends every segment directly to `.wk-columns`. Change it to read the nested `columns` array and wrap each column's segments in a `.wk-col` element.

**Files:**
- Modify: `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js`

This is asset JS with no Scheme-side unit-test harness; it is verified visually in Task 5.

- [ ] **Step 1: Replace the renderer function**

In `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js`, replace the entire `window.overlayBlockRenderers['which-key'] = function(block, container) { … };` assignment (the last statement before the closing `})();`) with:

```javascript
  window.overlayBlockRenderers = window.overlayBlockRenderers || {};
  window.overlayBlockRenderers['which-key'] = function(block, container) {
    while (container.firstChild) container.removeChild(container.firstChild);
    const cols = el('div', { class: 'wk-columns' });
    const columns = block.columns || [];
    // One grid track per column; CSS reads --overlay-cols.
    cols.style.setProperty('--overlay-cols', String(Math.max(1, columns.length)));
    for (const column of columns) {
      const colEl = el('div', { class: 'wk-col' });
      for (const seg of column) {
        if (seg.kind === 'category') colEl.appendChild(renderCategory(seg));
        else if (seg.kind === 'misc') colEl.appendChild(renderMisc(seg));
      }
      cols.appendChild(colEl);
    }
    container.appendChild(cols);
  };
```

- [ ] **Step 2: Update the stale header comment**

In the same file, replace the top-of-file block comment (lines 1–18, from `/* which-key.js — renderer for the which-key block.` through the closing ` */`) with:

```javascript
/* which-key.js — renderer for the which-key block.
 *
 * Payload shape:
 *   { type: "which-key",
 *     columns: [                              // one entry per overlay column
 *       [ <segment>, <segment>, ... ],        // column 1, top-to-bottom
 *       [ <segment>, ... ],                   // column 2
 *       ...
 *     ] }
 *
 * Each segment is either:
 *   {kind: "misc",     rows: [<row>, ...]}                 // coalesced loose entries
 *   {kind: "category", label: "Move", rows: [<row>, ...]}  // explicit category
 *
 * Each row: {key, label, isGroup, isSticky}.
 *
 * Columns are precomputed Scheme-side (distribute-which-key-columns in
 * overlay.scm) so short categories backfill the space under other short
 * ones. This renderer draws one .wk-col element per column; which-key.css
 * lays them out as an equal-width grid. --overlay-cols is set inline here
 * from the column count.
 */
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.js
git commit -m "feat(overlay): render which-key payload as per-column elements

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Equal-width content-sized columns in `which-key.css`

Make `.wk-columns` an equal-width grid of `1fr` tracks (dropping the 14rem floor), and add the `.wk-col` rule. Inside the `width: max-content` overlay, equal `1fr` tracks resolve to the widest category's natural width.

**Files:**
- Modify: `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css`

Verified visually in Task 5.

- [ ] **Step 1: Replace the layout rules**

In `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css`, replace the `.block-which-key .wk-columns` rule **and** the `.block-which-key .wk-misc, .block-which-key .wk-category` rule (the block of CSS from `.block-which-key .wk-columns {` through the closing brace of the `.wk-misc, .wk-category` rule) with:

```css
.block-which-key .wk-columns {
  /* One grid track per column. Tracks are 1fr — equal width — and inside
   * the width:max-content overlay they resolve to the widest category's
   * natural width. --overlay-cols is the Scheme-side column count, set
   * inline by which-key.js. */
  display: grid;
  grid-template-columns: repeat(var(--overlay-cols, 1), 1fr);
  column-gap: 1.5rem;
  align-items: start;
}

.block-which-key .wk-col {
  /* One column. Its categories/misc segments stack top-to-bottom; the
   * 0.6rem gap replaces the row-gap the old wrapping grid provided. */
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
}

.block-which-key .wk-misc,
.block-which-key .wk-category {
  display: flex;
  flex-direction: column;
}
```

- [ ] **Step 2: Update the stale header comment**

In the same file, replace the top-of-file block comment (lines 1–6, from `/* which-key.css — multi-column layout for the which-key block.` through the closing ` */`) with:

```css
/* which-key.css — multi-column layout for the which-key block.
 *
 * Segments are pre-grouped into columns Scheme-side (see overlay.scm).
 * .wk-columns is an equal-width CSS grid, one 1fr track per column;
 * each .wk-col stacks its categories/misc segments vertically.
 */
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css
git commit -m "feat(overlay): equal-width content-sized which-key columns

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Full verification — test suite, build, visual check

No code changes — confirm the whole suite passes and the overlay looks right in the running app.

**Files:** none.

- [ ] **Step 1: Run the full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: PASS — the entire suite passes (no regressions in `OverlayRenderTests`, `BlocksWhichKeyLibraryTests`, `OverlayRenderTests`, `OverlayIntegrationTests`, `OverlayRendererDispatchTests`, etc.).

- [ ] **Step 2: Build and install the app**

Run: `./scripts/install.sh 2>&1 | tail -15`
Expected: builds and installs cleanly to `/Applications`. (A source change requires `install.sh` — a plain "Relaunch" only restarts the stale bundle.)

- [ ] **Step 3: Visually verify the Global overlay**

Launch the installed Modaliser, trigger the **Global** modality so the overlay appears, and confirm:
- The category area has **no large empty block** below SEARCH — the AI category sits directly under SEARCH.
- Columns are **no wider than their content** — short labels like "Mail" no longer sit in an over-wide column; the overlay window is visibly narrower than before.
- Both columns are the **same width**, equal to the widest category.
- Category order is unchanged and every binding still works (press a few keys).

If the columns look wrong-width (e.g. not resolving to the widest category), apply the spec's fallback: size the grid tracks `max-content` instead of `1fr`. Otherwise the task is complete.

- [ ] **Step 4: Final commit (only if Step 3 required the fallback)**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css
git commit -m "fix(overlay): size which-key columns with max-content tracks

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage:** packing function (Task 1) ✓; `columns` payload, `cols` dropped (Task 2) ✓; JS per-column rendering (Task 3) ✓; equal-width `1fr` columns + 14rem floor removed + `0.6rem` gap relocated to `.wk-col` (Task 4) ✓; stale header comments in both asset files (Tasks 3, 4) ✓; test plan — order, gap-fill, single-column, N≥segment-count, tall segment, last-column-absorbs-remainder (Task 1) ✓; visual verification + `1fr` fallback (Task 5) ✓.
- **Scoped out (no task, by design):** `overlay-column-count` retuning; deployment-target / Grid Lanes.
- **Type consistency:** `segment-row-count`, `segments-row-count`, `distribute-which-key-columns`, `which-key-payload-json` signatures are consistent across tasks; the `columns` array-of-arrays shape is produced in Task 2 and consumed in Tasks 3–4 identically.
