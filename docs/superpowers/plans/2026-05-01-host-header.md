# Host Header for Overlay & Chooser — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, user-configured host name (with bg/fg colours) prepended to the breadcrumb on both the overlay and the chooser, and replace bundle IDs with resolved app display names — so a user driving multiple Modaliser instances can immediately tell which one a window belongs to.

**Architecture:** New Swift native fn `app-display-name` resolves bundle IDs via Launch Services. New Scheme function `set-host-header!` stores three module-level variables (name, bg, fg) in `state-machine.scm`. `register-tree!` stores the raw scope on the root node; `modal-enter` computes a `modal-root-segments` list (host? + scope-segs, with variant trees split on `/`) once per leader press. Both overlay and chooser breadcrumbs render `(append root-segments [...path])` joined by `>`. Colours are injected as CSS variables into the per-window `<style>` block, with fallbacks so the unset case is identical to today.

**Tech Stack:** Swift / AppKit (LispKit native libraries), R7RS Scheme (LispKit), Swift Testing via `swift test`.

**Spec:** `docs/superpowers/specs/2026-05-01-host-header-design.md`

---

## File Structure

**Modify:**
- `Sources/Modaliser/AppLibrary.swift` — add `app-display-name` Procedure.
- `Sources/Modaliser/Scheme/core/state-machine.scm` — host state, `set-host-header!`, `host-header-css`, `resolve-app-segments`, `compute-root-segments`, `modal-root-segments` state, `modal-enter`/`modal-exit` integration, `register-tree!` change.
- `Sources/Modaliser/Scheme/ui/overlay.scm` — `render-breadcrumb`/`render-overlay-body`/`render-overlay-html` take `root-segments`; `push-overlay-update` emits `rootSegments` JSON; both renderers concatenate `(host-header-css)` into `<style>`.
- `Sources/Modaliser/Scheme/ui/overlay.js` — `updateOverlay` reads `data.rootSegments`.
- `Sources/Modaliser/Scheme/ui/chooser.scm` — replace `chooser-prompt` div with `chooser-header` breadcrumb in both `render-chooser-html` and `chooser-load-skeleton`; concatenate `(host-header-css)` into `<style>`.
- `Sources/Modaliser/Scheme/base.css` — remove `.chooser-prompt`, add `.chooser-header`, update both header selectors to use `var(--color-host-bg, ...)` / `var(--color-host-fg, ...)`.
- `Sources/Modaliser/Scheme/default-config.scm` — commented `set-host-header!` example.
- `Tests/ModaliserTests/AppLibraryTests.swift` — `app-display-name` tests.
- `Tests/ModaliserTests/OverlayRenderTests.swift` — adapt callers to new signature; add host-header tests.
- `Tests/ModaliserTests/ChooserRenderTests.swift` — adapt prompt assertions to breadcrumb; add host-header tests.

**Create:** none.

---

## Task 1: Swift native fn `app-display-name`

**Files:**
- Modify: `Sources/Modaliser/AppLibrary.swift`
- Modify: `Tests/ModaliserTests/AppLibraryTests.swift`

- [ ] **Step 1: Write the failing test**

Add this test method inside the existing `struct AppLibraryTests { ... }` in `Tests/ModaliserTests/AppLibraryTests.swift` (append at end of struct, before the closing brace):

```swift
@Test func appDisplayNameResolvesKnownBundleId() throws {
    let engine = try SchemeEngine()
    // Finder is guaranteed to be installed and Launch Services-registered on macOS.
    let result = try engine.evaluate("(app-display-name \"com.apple.finder\")").asString()
    #expect(result == "Finder")
}

@Test func appDisplayNameReturnsFalseForUnknownBundleId() throws {
    let engine = try SchemeEngine()
    let result = try engine.evaluate("(app-display-name \"com.nonexistent.fake-bundle-id-zzz\")")
    #expect(result == .false)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter appDisplayName`
Expected: FAIL with `unbound identifier: app-display-name`.

- [ ] **Step 3: Implement the native function**

In `Sources/Modaliser/AppLibrary.swift`, add the line below to the `declarations()` body (alongside the other `self.define(...)` calls, e.g. immediately after the `focused-app-bundle-id` define around line 29):

```swift
self.define(Procedure("app-display-name", appDisplayNameFunction))
```

Then add this method to the same class, e.g. immediately after `focusedAppBundleIdFunction` (around line 42):

```swift
/// (app-display-name bundle-id) → string or #f
/// Returns the user-visible name (localized, extension-hidden) for the
/// given bundle identifier, or #f when Launch Services can't resolve it.
private func appDisplayNameFunction(_ idExpr: Expr) throws -> Expr {
    let bundleId = try idExpr.asString()
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
        return .false
    }
    return .makeString(FileManager.default.displayName(atPath: url.path))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter appDisplayName`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/AppLibrary.swift Tests/ModaliserTests/AppLibraryTests.swift
git commit -m "feat(app): add app-display-name native fn

Resolves a bundle ID to its localized, extension-hidden display name
via Launch Services. Returns #f when unresolvable."
```

---

## Task 2: Host state + `set-host-header!` setter

**Files:**
- Modify: `Sources/Modaliser/Scheme/core/state-machine.scm`
- Modify: `Tests/ModaliserTests/OverlayRenderTests.swift` (test only)

- [ ] **Step 1: Write the failing test**

Append this test to `struct OverlayRenderTests { ... }` in `Tests/ModaliserTests/OverlayRenderTests.swift` (just before the closing brace of the struct):

```swift
@Test func setHostHeaderStoresAllThreeFields() throws {
    let engine = try loadOverlay()
    try engine.evaluate("""
        (set-host-header!
          'name "my-server"
          'background "#7a1f3d"
          'foreground "#ffffff")
        """)
    #expect(try engine.evaluate("host-header-name").asString() == "my-server")
    #expect(try engine.evaluate("host-header-background").asString() == "#7a1f3d")
    #expect(try engine.evaluate("host-header-foreground").asString() == "#ffffff")
}

@Test func setHostHeaderAcceptsNameOnly() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(set-host-header! 'name \"local\")")
    #expect(try engine.evaluate("host-header-name").asString() == "local")
    #expect(try engine.evaluate("host-header-background") == .false)
    #expect(try engine.evaluate("host-header-foreground") == .false)
}

@Test func setHostHeaderRejectsUnknownKeyword() throws {
    let engine = try loadOverlay()
    #expect(throws: (any Error).self) {
        try engine.evaluate("(set-host-header! 'name \"x\" 'unknown 1)")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter setHostHeader`
Expected: FAIL with `unbound identifier: set-host-header!` (or `host-header-name`).

- [ ] **Step 3: Add state and setter to state-machine.scm**

In `Sources/Modaliser/Scheme/core/state-machine.scm`, append the following to the end of the file (after the existing `navigate-to-path` definition):

```scheme
;; ─── Host Header ────────────────────────────────────────────────
;;
;; Optional banner identifying which Modaliser instance owns the
;; overlay/chooser. Set once at config load via (set-host-header! ...).

(define host-header-name #f)         ;; #f → no host segment, no recolour
(define host-header-background #f)   ;; CSS colour string or #f
(define host-header-foreground #f)   ;; CSS colour string or #f

;; (set-host-header! 'name VAL [ 'background CSS ] [ 'foreground CSS ])
;;
;; Keyword-style API mirroring set-leader!.  Only 'name is required.
;; Re-calling overwrites the previous values.
(define (set-host-header! . args)
  (let loop ((rest args)
             (name #f) (bg #f) (fg #f) (saw-name? #f))
    (cond
      ((null? rest)
       (unless saw-name?
         (error "set-host-header!: missing required 'name keyword"))
       (set! host-header-name name)
       (set! host-header-background bg)
       (set! host-header-foreground fg))
      ((eq? (car rest) 'name)
       (loop (cddr rest) (cadr rest) bg fg #t))
      ((eq? (car rest) 'background)
       (loop (cddr rest) name (cadr rest) fg saw-name?))
      ((eq? (car rest) 'foreground)
       (loop (cddr rest) name bg (cadr rest) saw-name?))
      (else
       (error "set-host-header!: unknown keyword" (car rest))))))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter setHostHeader`
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/core/state-machine.scm Tests/ModaliserTests/OverlayRenderTests.swift
git commit -m "feat(scheme): add set-host-header! setter and host state

Three module-level vars (name, background, foreground) plus a keyword-style
setter. 'name is required; colours optional. Mirrors set-leader! in shape."
```

---

## Task 3: `host-header-css` helper

**Files:**
- Modify: `Sources/Modaliser/Scheme/core/state-machine.scm`
- Modify: `Tests/ModaliserTests/OverlayRenderTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `OverlayRenderTests`:

```swift
@Test func hostHeaderCssEmptyWhenNoColoursSet() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(set-host-header! 'name \"x\")")
    let css = try engine.evaluate("(host-header-css)").asString()
    #expect(css == "")
}

@Test func hostHeaderCssEmitsBothVariables() throws {
    let engine = try loadOverlay()
    try engine.evaluate("""
        (set-host-header! 'name "x" 'background "#000" 'foreground "#fff")
        """)
    let css = try engine.evaluate("(host-header-css)").asString()
    #expect(css.contains(":root"))
    #expect(css.contains("--color-host-bg: #000"))
    #expect(css.contains("--color-host-fg: #fff"))
}

@Test func hostHeaderCssEmitsOnlyTheSetVariable() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(set-host-header! 'name \"x\" 'background \"#abc\")")
    let css = try engine.evaluate("(host-header-css)").asString()
    #expect(css.contains("--color-host-bg: #abc"))
    #expect(!css.contains("--color-host-fg"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter hostHeaderCss`
Expected: FAIL with `unbound identifier: host-header-css`.

- [ ] **Step 3: Add the helper**

In `Sources/Modaliser/Scheme/core/state-machine.scm`, append after the `set-host-header!` definition:

```scheme
;; (host-header-css) → string
;; Returns a :root { ... } CSS block defining --color-host-bg and/or
;; --color-host-fg when set, or "" when neither is set.  Concatenated
;; into the <style> block by both the overlay and the chooser renderers.
(define (host-header-css)
  (if (and (not host-header-background) (not host-header-foreground))
    ""
    (string-append
      ":root {"
      (if host-header-background
        (string-append " --color-host-bg: " host-header-background ";") "")
      (if host-header-foreground
        (string-append " --color-host-fg: " host-header-foreground ";") "")
      " }")))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter hostHeaderCss`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/core/state-machine.scm Tests/ModaliserTests/OverlayRenderTests.swift
git commit -m "feat(scheme): add host-header-css helper

Emits a :root { ... } block defining --color-host-bg / --color-host-fg
when set; empty string otherwise. Consumed by overlay & chooser renderers."
```

---

## Task 4: `resolve-app-segments` Scheme helper (variant-aware)

**Files:**
- Modify: `Sources/Modaliser/Scheme/core/state-machine.scm`
- Modify: `Tests/ModaliserTests/OverlayRenderTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `OverlayRenderTests`. Note the use of `redefining` `app-display-name` as a Scheme stub so the test does not depend on the actual macOS Launch Services lookup:

```swift
@Test func resolveAppSegmentsResolvesPlainBundleId() throws {
    let engine = try loadOverlay()
    // Stub the Swift native function with a Scheme one for predictability.
    try engine.evaluate("""
        (define (app-display-name id)
          (cond ((equal? id "com.apple.Safari") "Safari")
                ((equal? id "com.googlecode.iterm2") "iTerm")
                (else #f)))
        """)
    #expect(try engine.evaluate("(resolve-app-segments \"com.apple.Safari\")")
              == .pair(.makeString("Safari"), .null))
}

@Test func resolveAppSegmentsSplitsVariant() throws {
    let engine = try loadOverlay()
    try engine.evaluate("""
        (define (app-display-name id)
          (if (equal? id "com.googlecode.iterm2") "iTerm" #f))
        """)
    let result = try engine.evaluate(
        "(resolve-app-segments \"com.googlecode.iterm2/nvim\")")
    // Expect ("iTerm" "nvim") as a Scheme list.
    #expect(result == .pair(.makeString("iTerm"),
                             .pair(.makeString("nvim"), .null)))
}

@Test func resolveAppSegmentsFallsBackToBundleIdWhenUnresolvable() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(define (app-display-name id) #f)")
    #expect(try engine.evaluate("(resolve-app-segments \"com.example.unknown\")")
              == .pair(.makeString("com.example.unknown"), .null))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter resolveAppSegments`
Expected: FAIL with `unbound identifier: resolve-app-segments`.

- [ ] **Step 3: Add the helper**

In `Sources/Modaliser/Scheme/core/state-machine.scm`, append after `host-header-css`:

```scheme
;; (resolve-app-segments scope-str) → list of strings
;;
;; Splits a registered scope key into breadcrumb segments by `/`.
;; The first segment is resolved to a display name via app-display-name;
;; if resolution fails, the bare bundle ID is used.  Subsequent
;; segments (variant suffixes like "nvim") are passed through verbatim.
;;
;;   "com.apple.Safari"            → ("Safari")
;;   "com.googlecode.iterm2/nvim"  → ("iTerm" "nvim")
;;   "com.example.unknown"         → ("com.example.unknown")
(define (resolve-app-segments scope-str)
  (let* ((parts (string-split scope-str "/"))
         (bundle-id (car parts))
         (variant   (cdr parts))
         (display   (or (app-display-name bundle-id) bundle-id)))
    (cons display variant)))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter resolveAppSegments`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/core/state-machine.scm Tests/ModaliserTests/OverlayRenderTests.swift
git commit -m "feat(scheme): add resolve-app-segments helper

Splits a registered scope key on / and resolves the bundle-id portion
via app-display-name; falls back to the bundle id when unresolvable."
```

---

## Task 5: `register-tree!` stores `'scope`; `compute-root-segments` + `modal-enter` integration

This task changes the shape of the root tree node (drops `'label`, adds `'scope`) and wires the modal lifecycle to compute and store breadcrumb segments. Several existing tests assert against the breadcrumb via `render-overlay-html`; those will be migrated in Task 6 once the renderer signature changes. For Task 5 we exercise `compute-root-segments` and `modal-root-segments` directly.

**Files:**
- Modify: `Sources/Modaliser/Scheme/core/state-machine.scm`
- Modify: `Tests/ModaliserTests/OverlayRenderTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `OverlayRenderTests`:

```swift
@Test func registerTreeStoresScopeOnRoot() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
    #expect(try engine.evaluate("(alist-ref (lookup-tree \"global\") 'scope #f)").asString()
              == "global")

    try engine.evaluate("(define-tree 'com.apple.Safari (key \"t\" \"Tabs\" (lambda () 'ok)))")
    #expect(try engine.evaluate("(alist-ref (lookup-tree \"com.apple.Safari\") 'scope #f)").asString()
              == "com.apple.Safari")
}

@Test func computeRootSegmentsGlobalNoHost() throws {
    let engine = try loadOverlay()
    let result = try engine.evaluate("(compute-root-segments \"global\")")
    #expect(result == .pair(.makeString("Global"), .null))
}

@Test func computeRootSegmentsAppNoHost() throws {
    let engine = try loadOverlay()
    try engine.evaluate("""
        (define (app-display-name id)
          (if (equal? id "com.apple.Safari") "Safari" #f))
        """)
    let result = try engine.evaluate("(compute-root-segments \"com.apple.Safari\")")
    #expect(result == .pair(.makeString("Safari"), .null))
}

@Test func computeRootSegmentsPrependsHostWhenSet() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(set-host-header! 'name \"my-server\")")
    try engine.evaluate("""
        (define (app-display-name id)
          (if (equal? id "com.googlecode.iterm2") "iTerm" #f))
        """)
    // List → ("my-server" "iTerm" "nvim"). Pre-bind to a Scheme variable
    // so the assertions can index into it without re-evaluating the expression.
    try engine.evaluate("""
        (define segs (compute-root-segments "com.googlecode.iterm2/nvim"))
        """)
    #expect(try engine.evaluate("(length segs)") == .fixnum(3))
    #expect(try engine.evaluate("(list-ref segs 0)").asString() == "my-server")
    #expect(try engine.evaluate("(list-ref segs 1)").asString() == "iTerm")
    #expect(try engine.evaluate("(list-ref segs 2)").asString() == "nvim")
}

@Test func modalEnterPopulatesRootSegments() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(set-host-header! 'name \"box\")")
    try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
    // Stub the keymap registrations (modal-enter calls register-all-keys!).
    try engine.evaluate("(define (register-all-keys! h) #t)")
    try engine.evaluate("(define (unregister-all-keys!) #t)")
    try engine.evaluate("(modal-enter (lookup-tree \"global\") 0)")
    let len = try engine.evaluate("(length modal-root-segments)")
    #expect(len == .fixnum(2))
    #expect(try engine.evaluate("(list-ref modal-root-segments 0)").asString() == "box")
    #expect(try engine.evaluate("(list-ref modal-root-segments 1)").asString() == "Global")
    try engine.evaluate("(modal-exit)")
    let lenAfter = try engine.evaluate("(length modal-root-segments)")
    #expect(lenAfter == .fixnum(0))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "registerTreeStoresScopeOnRoot|computeRootSegments|modalEnterPopulatesRootSegments"`
Expected: FAIL — none of the new identifiers exist yet.

- [ ] **Step 3: Update `register-tree!` to store `'scope`**

In `Sources/Modaliser/Scheme/core/state-machine.scm`, replace the existing `register-tree!` (lines 15–22) with:

```scheme
;; Register a command tree for a scope.
;; scope: symbol or string (e.g. 'global or "com.apple.Safari")
;; children: alist nodes produced by (key ...), (group ...), etc.
;;
;; The root node carries 'scope (the raw key string) instead of a label;
;; the breadcrumb is computed at modal-enter time via compute-root-segments,
;; not from a baked-in root label.
(define (register-tree! scope . children)
  (let* ((scope-str (if (symbol? scope) (symbol->string scope) scope))
         (root (list (cons 'kind 'group)
                     (cons 'key "")
                     (cons 'scope scope-str)
                     (cons 'children children))))
    (hashtable-set! tree-registry scope-str root)))
```

- [ ] **Step 4: Add `modal-root-segments`, `compute-root-segments`, and lifecycle hooks**

In the same file, find the `;; ─── Modal State ───` section (around line 82) and add `modal-root-segments` to the state declarations alongside `modal-active?` etc.:

```scheme
(define modal-root-segments '())     ;; breadcrumb root: host? + scope segments
```

Then append to the end of the file (after the `host-header-css` helper added in Task 3 / `resolve-app-segments` added in Task 4):

```scheme
;; (compute-root-segments scope-str) → list of strings
;;
;; Builds the breadcrumb root: optional host name, then scope segments.
;;   global tree              → (host? "Global")
;;   app-local tree           → (host? app-name [variant])
(define (compute-root-segments scope-str)
  (let ((host-prefix (if host-header-name (list host-header-name) '()))
        (scope-segs  (if (equal? scope-str "global")
                       (list "Global")
                       (resolve-app-segments scope-str))))
    (append host-prefix scope-segs)))
```

In the existing `modal-enter` (around line 119), update the body to compute segments after setting `modal-root-node`:

```scheme
(define (modal-enter tree leader-kc)
  (when tree
    (set! modal-active? #t)
    (set! modal-root-node tree)
    (set! modal-current-node tree)
    (set! modal-current-path '())
    (set! modal-leader-keycode leader-kc)
    (set! modal-root-segments
      (compute-root-segments
        (or (alist-ref tree 'scope #f) "")))
    (register-all-keys! modal-key-handler)
    (modal-show-overlay-delayed)))
```

In the existing `modal-exit` (around line 131), reset segments alongside the other state:

```scheme
(define (modal-exit)
  (when modal-active?
    (set! modal-overlay-generation (+ modal-overlay-generation 1))
    (unregister-all-keys!)
    (hide-overlay)
    (set! modal-active? #f)
    (set! modal-current-node #f)
    (set! modal-root-node #f)
    (set! modal-current-path '())
    (set! modal-leader-keycode #f)
    (set! modal-root-segments '())))
```

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `swift test --filter "registerTreeStoresScopeOnRoot|computeRootSegments|modalEnterPopulatesRootSegments"`
Expected: PASS (all five).

- [ ] **Step 6: Run the full overlay/chooser test suites — expect Task-6 breakage**

Run: `swift test --filter "OverlayRender|ChooserRender|Overlay Integration"`
Expected: Several existing tests FAIL because `render-overlay-html` still calls `(node-label node)` on the root, which no longer has a `'label` field. This is intentional and will be fixed in Task 6.

Note the failing test names so Task 6's checklist can confirm they recover.

- [ ] **Step 7: Commit**

```bash
git add Sources/Modaliser/Scheme/core/state-machine.scm Tests/ModaliserTests/OverlayRenderTests.swift
git commit -m "feat(scheme): root node carries 'scope; modal-enter computes segments

register-tree! drops the pre-baked 'label on root nodes and stores the raw
scope key as 'scope. modal-enter now computes modal-root-segments (host?
+ scope-segs, with variant trees split on /) once per leader press."
```

---

## Task 6: `render-overlay-html` / `render-overlay-body` / `render-breadcrumb` take `root-segments`

**Files:**
- Modify: `Sources/Modaliser/Scheme/ui/overlay.scm`
- Modify: `Tests/ModaliserTests/OverlayRenderTests.swift`

- [ ] **Step 1: Update existing failing tests to the new signature**

In `Tests/ModaliserTests/OverlayRenderTests.swift`, every existing call to `(render-overlay-html (lookup-tree "global") '(...))` becomes `(render-overlay-html (lookup-tree "global") '("Global") '(...))`. Walk through each test:

- `renderOverlayHtmlProducesValidDocument` (around line 44): change to `(render-overlay-html (lookup-tree "global") '("Global") '())`. Keep the existing `#expect(html.contains("Global"))` — still passes because "Global" is now a literal segment.
- `renderOverlayHtmlShowsEntries` (around line 60): same pattern.
- `renderOverlayHtmlSortsEntriesByKey` (around line 77): same.
- `renderOverlayHtmlShowsGroupWithEllipsis` (around line 95): same.
- `renderOverlayHtmlWithPath` (around line 111): change to `(render-overlay-html (lookup-tree "global") '("Global") '("w"))`. Existing assertions for `"Global"` and `"w"` still pass.
- `renderOverlayHtmlIncludesCSS` (around line 128): same single-arg path pattern.

Also add these new tests to the same struct (append before the closing brace):

```swift
@Test func renderOverlayHtmlPrependsHostSegment() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
    let html = try engine.evaluate("""
        (render-overlay-html (lookup-tree "global") '("my-server" "Global") '("w"))
        """).asString()
    #expect(html.contains("my-server"))
    #expect(html.contains("Global"))
    // The breadcrumb separator is &gt; (HTML-escaped >).
    #expect(html.contains("breadcrumb-sep"))
}

@Test func renderOverlayHtmlVariantSegmentsRendered() throws {
    let engine = try loadOverlay()
    try engine.evaluate(
        "(define-tree 'com.googlecode.iterm2/nvim (key \"x\" \"X\" (lambda () 'ok)))")
    let html = try engine.evaluate("""
        (render-overlay-html (lookup-tree "com.googlecode.iterm2/nvim")
                             '("iTerm" "nvim") '())
        """).asString()
    #expect(html.contains("iTerm"))
    #expect(html.contains("nvim"))
}
```

- [ ] **Step 2: Run all overlay-render tests to confirm they fail in the expected way**

Run: `swift test --filter OverlayRender`
Expected: All FAIL — `render-overlay-html` still has the old `(node path)` arity.

- [ ] **Step 3: Update `render-breadcrumb` to take a list of segments**

In `Sources/Modaliser/Scheme/ui/overlay.scm`, replace the existing `render-breadcrumb` (lines 50–64) with:

```scheme
;; Build the breadcrumb header from a list of segments.
;; segments: non-empty list of strings, e.g. ("my-server" "Global" "w")
(define (render-breadcrumb segments)
  (let ((sep (html->string (span '((class . "breadcrumb-sep")) ">"))))
    (header '((class . "overlay-header"))
      (span '((class . "breadcrumb"))
        (make-raw-html
          (let loop ((segs segments) (result ""))
            (if (null? segs)
              result
              (loop (cdr segs)
                    (string-append result
                      (if (string=? result "") "" sep)
                      (html-escape (car segs)))))))))))
```

- [ ] **Step 4: Update `render-overlay-body` to take `root-segments`**

In the same file, replace `render-overlay-body` (lines 82–93) with:

```scheme
;; Render the full overlay body: header + entry list.
;; root-segments: breadcrumb root (e.g. ("my-server" "Global"))
;; node: the registered root tree node (provides children navigation only)
;; path: navigation path from root, e.g. ("w" "m")
(define (render-overlay-body root-segments node path)
  (let* ((current  (if (null? path) node (navigate-to-path node path)))
         (children (if current (node-children current) '()))
         (sorted   (sort-children children))
         (segments (append root-segments path)))
    (div '((class . "overlay"))
      (render-breadcrumb segments)
      (apply ul (cons '((class . "overlay-entries"))
                      (map render-entry sorted))))))
```

- [ ] **Step 5: Update `render-overlay-html` signature**

In the same file, replace `render-overlay-html` (lines 111–120) with:

```scheme
;; (render-overlay-html node root-segments path) → full HTML document string
;; Pure function. Includes overlay.js for incremental updates.
(define (render-overlay-html node root-segments path)
  (let ((css (if (string=? overlay-custom-css "")
               overlay-base-css
               (string-append overlay-base-css "\n" overlay-custom-css))))
    (html-document
      (make-raw-html
        (string-append
          (html->string (style-element '() css))
          (html->string (script-element '() overlay-js))))
      (render-overlay-body root-segments node path))))
```

- [ ] **Step 6: Update `show-overlay` to pass `modal-root-segments`**

In the same file, replace the body of `show-overlay` (around lines 186–198) — specifically the final `webview-set-html!` call — with:

```scheme
  (webview-set-html! overlay-webview-id
    (render-overlay-html node modal-root-segments path)))
```

(Keep the surrounding `(unless overlay-open? ...)` block unchanged.)

- [ ] **Step 7: Run the overlay-render tests — expect a pass**

Run: `swift test --filter OverlayRender`
Expected: PASS (all original + the two new host/variant tests).

- [ ] **Step 8: Commit**

```bash
git add Sources/Modaliser/Scheme/ui/overlay.scm Tests/ModaliserTests/OverlayRenderTests.swift
git commit -m "refactor(overlay): breadcrumb takes root-segments list

render-overlay-html / render-overlay-body / render-breadcrumb now consume
a pre-computed list of root segments. show-overlay reads modal-root-segments
from state and passes it through. Renderers stay pure."
```

---

## Task 7: `push-overlay-update` emits `rootSegments` JSON; `overlay.js` consumes it

**Files:**
- Modify: `Sources/Modaliser/Scheme/ui/overlay.scm`
- Modify: `Sources/Modaliser/Scheme/ui/overlay.js`
- Modify: `Tests/ModaliserTests/OverlayIntegrationTests.swift` (if it asserts on the JSON shape — check first)

- [ ] **Step 1: Inspect existing assertions for the old `label` field**

Run: `grep -n "label\|updateOverlay\|rootSegments" Tests/ModaliserTests/OverlayIntegrationTests.swift`
If any test asserts `data.label` or the old JSON payload, note it for migration in step 5.

- [ ] **Step 2: Write a failing test for the new payload**

Append to `OverlayRenderTests` (`Tests/ModaliserTests/OverlayRenderTests.swift`):

```swift
@Test func pushOverlayUpdateEmitsRootSegmentsArray() throws {
    let engine = try loadOverlay()
    // Stub webview-eval so we can inspect the emitted JS string.
    try engine.evaluate("""
        (define last-eval-js #f)
        (define (webview-eval id js) (set! last-eval-js js))
        """)
    try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
    try engine.evaluate("(set! overlay-open? #t)")
    // push-overlay-update reads modal-root-segments — set it manually for the test.
    try engine.evaluate("(set! modal-root-segments '(\"my-server\" \"Global\"))")
    try engine.evaluate("(push-overlay-update (lookup-tree \"global\") '(\"w\"))")
    let js = try engine.evaluate("last-eval-js").asString()
    #expect(js.contains("rootSegments"))
    #expect(js.contains("my-server"))
    #expect(js.contains("Global"))
    #expect(!js.contains("\"label\":"))
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter pushOverlayUpdateEmitsRootSegmentsArray`
Expected: FAIL — current payload uses `"label"`.

- [ ] **Step 4: Rewrite `push-overlay-update`**

In `Sources/Modaliser/Scheme/ui/overlay.scm`, replace `push-overlay-update` (around lines 124–161) with:

```scheme
;; Build JSON for overlay update and push to JS updateOverlay().
;; Sends {rootSegments: [...], path: [...], entries: [...]} so the JS
;; can render the breadcrumb identically to the initial Scheme render.
(define (push-overlay-update node path)
  (let* ((current (if (null? path) node (navigate-to-path node path)))
         (children (if current (node-children current) '()))
         (sorted (sort-children children))
         ;; Helper: build a JSON string array from a list of strings.
         (string-list->json
           (lambda (lst)
             (string-append "["
               (let loop ((xs lst) (result ""))
                 (if (null? xs)
                   result
                   (loop (cdr xs)
                         (string-append result
                           (if (string=? result "") "" ",")
                           "\"" (js-escape-overlay (car xs)) "\""))))
               "]")))
         (segments-json (string-list->json modal-root-segments))
         (path-json     (string-list->json path))
         (entries-json
           (string-append "["
             (let loop ((items sorted) (result ""))
               (if (null? items)
                 result
                 (let* ((item (car items))
                        (k (node-key item))
                        (lbl (node-label item))
                        (is-grp (group? item)))
                   (loop (cdr items)
                         (string-append result
                           (if (string=? result "") "" ",")
                           "{\"key\":\"" (js-escape-overlay k)
                           "\",\"label\":\"" (js-escape-overlay lbl)
                           "\",\"isGroup\":" (if is-grp "true" "false")
                           "}")))))
             "]")))
    (webview-eval overlay-webview-id
      (string-append "updateOverlay({\"rootSegments\":" segments-json
        ",\"path\":" path-json
        ",\"entries\":" entries-json "})"))))
```

- [ ] **Step 5: Update `overlay.js` to consume `rootSegments`**

In `Sources/Modaliser/Scheme/ui/overlay.js`, replace `updateOverlay` (lines 27–59) with:

```javascript
// Update overlay content with new entries and breadcrumb.
// data: { rootSegments: ["my-server","Global"], path: ["w"], entries: [...] }
function updateOverlay(data) {
  // Update breadcrumb header
  var header = document.querySelector('.overlay-header');
  if (header) {
    var segments = (data.rootSegments || []).concat(data.path || []);
    var html = '';
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) html += '<span class="breadcrumb-sep">&gt;</span>';
      html += escapeHtml(segments[i]);
    }
    header.innerHTML = '<span class="breadcrumb">' + html + '</span>';
  }

  // Update entry list
  var ul = document.querySelector('.overlay-entries');
  if (ul) {
    var html = '';
    var entries = data.entries;
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i];
      var displayKey = e.key === ' ' ? '␣' : escapeHtml(e.key);
      var labelClass = e.isGroup ? 'entry-label group-label' : 'entry-label';
      var displayLabel = e.isGroup ? escapeHtml(e.label) + ' …' : escapeHtml(e.label);
      html += '<li class="overlay-entry">';
      html += '<span class="entry-key">' + displayKey + '</span>';
      html += '<span class="entry-arrow">→</span>';
      html += '<span class="' + labelClass + '">' + displayLabel + '</span>';
      html += '</li>';
    }
    ul.innerHTML = html;
  }
  notifyResize();
}
```

- [ ] **Step 6: If step 1 found existing integration tests asserting `label`**

Migrate them to expect `rootSegments` (using the same shape as the new test in step 2). If no such tests exist, skip.

- [ ] **Step 7: Run the full overlay test suite**

Run: `swift test --filter "OverlayRender|Overlay Integration"`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/Modaliser/Scheme/ui/overlay.scm Sources/Modaliser/Scheme/ui/overlay.js Tests/ModaliserTests/OverlayRenderTests.swift Tests/ModaliserTests/OverlayIntegrationTests.swift
git commit -m "refactor(overlay): JS update payload uses rootSegments array

push-overlay-update now emits {rootSegments, path, entries} instead of
{label, path, entries}. overlay.js renders the breadcrumb by concatenating
the two arrays. One field rename, identical rendering otherwise."
```

---

## Task 8: Inject `host-header-css` into the overlay style block

**Files:**
- Modify: `Sources/Modaliser/Scheme/ui/overlay.scm`
- Modify: `Tests/ModaliserTests/OverlayRenderTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `OverlayRenderTests`:

```swift
@Test func renderOverlayHtmlIncludesHostCssWhenColoursSet() throws {
    let engine = try loadOverlay()
    try engine.evaluate(
        "(set-host-header! 'name \"x\" 'background \"#abc\" 'foreground \"#def\")")
    try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
    let html = try engine.evaluate("""
        (render-overlay-html (lookup-tree "global") '("x" "Global") '())
        """).asString()
    #expect(html.contains("--color-host-bg: #abc"))
    #expect(html.contains("--color-host-fg: #def"))
}

@Test func renderOverlayHtmlOmitsHostCssWhenNotSet() throws {
    let engine = try loadOverlay()
    try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
    let html = try engine.evaluate("""
        (render-overlay-html (lookup-tree "global") '("Global") '())
        """).asString()
    #expect(!html.contains("--color-host-bg"))
    #expect(!html.contains("--color-host-fg"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "renderOverlayHtmlIncludesHostCss|renderOverlayHtmlOmitsHostCss"`
Expected: FAIL — host CSS is not yet injected.

- [ ] **Step 3: Inject `(host-header-css)` into the style block**

In `Sources/Modaliser/Scheme/ui/overlay.scm`, replace `render-overlay-html` (the let-binding around `css`) with:

```scheme
(define (render-overlay-html node root-segments path)
  (let ((css (string-append overlay-base-css
                            (if (string=? overlay-custom-css "")
                              ""
                              (string-append "\n" overlay-custom-css))
                            "\n"
                            (host-header-css))))
    (html-document
      (make-raw-html
        (string-append
          (html->string (style-element '() css))
          (html->string (script-element '() overlay-js))))
      (render-overlay-body root-segments node path))))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "renderOverlayHtml"`
Expected: PASS (existing + new).

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/ui/overlay.scm Tests/ModaliserTests/OverlayRenderTests.swift
git commit -m "feat(overlay): inject host-header CSS into style block

Concatenated after base.css + user overlay CSS. Empty when no host
colours are set, so the unset case is byte-identical to today."
```

---

## Task 9: Chooser breadcrumb header (replace `chooser-prompt`)

**Files:**
- Modify: `Sources/Modaliser/Scheme/ui/chooser.scm`
- Modify: `Tests/ModaliserTests/ChooserRenderTests.swift`

- [ ] **Step 1: Inspect existing chooser tests for `chooser-prompt` references**

Run: `grep -n "chooser-prompt\|prompt\|Find app" Tests/ModaliserTests/ChooserRenderTests.swift`
Note line numbers — they need to be migrated to assert `chooser-header` / `breadcrumb` instead.

- [ ] **Step 2: Update existing failing tests to the new DOM structure**

In each test that currently asserts `html.contains("chooser-prompt")`, change to assert `html.contains("chooser-header")` and `html.contains("breadcrumb")`. Tests asserting `html.contains("Find app")` continue to pass — the prompt text is still rendered, just inside the breadcrumb. Specifically:

- `renderChooserHtmlContainsSearchInput` — unchanged.
- `renderChooserHtmlContainsPrompt` — change to also assert `html.contains("chooser-header")` and `html.contains("breadcrumb")`. The "Find app" assertion stays.

Add these new tests:

```swift
@Test func renderChooserHtmlBreadcrumbIncludesPrompt() throws {
    let engine = try loadAllModules()
    // The breadcrumb consumes modal-root-segments + (list prompt)
    try engine.evaluate("(set! modal-root-segments '(\"Global\"))")
    let html = try engine.evaluate("""
        (render-chooser-html "Find app…" '() "" 0 #f '())
        """).asString()
    #expect(html.contains("chooser-header"))
    #expect(html.contains("breadcrumb"))
    #expect(html.contains("Global"))
    #expect(html.contains("Find app"))
    #expect(html.contains("breadcrumb-sep"))
}

@Test func renderChooserHtmlPrependsHostSegment() throws {
    let engine = try loadAllModules()
    try engine.evaluate(
        "(set! modal-root-segments '(\"my-server\" \"Global\"))")
    let html = try engine.evaluate("""
        (render-chooser-html "Find app…" '() "" 0 #f '())
        """).asString()
    #expect(html.contains("my-server"))
    #expect(html.contains("Global"))
    #expect(html.contains("Find app"))
}

@Test func renderChooserHtmlIncludesHostCssWhenColoursSet() throws {
    let engine = try loadAllModules()
    try engine.evaluate(
        "(set-host-header! 'name \"x\" 'background \"#abc\" 'foreground \"#def\")")
    try engine.evaluate("(set! modal-root-segments '(\"x\" \"Global\"))")
    let html = try engine.evaluate("""
        (render-chooser-html "Find app…" '() "" 0 #f '())
        """).asString()
    #expect(html.contains("--color-host-bg: #abc"))
    #expect(html.contains("--color-host-fg: #def"))
}
```

- [ ] **Step 3: Run the chooser tests to verify the new tests fail**

Run: `swift test --filter ChooserRender`
Expected: New tests FAIL — breadcrumb DOM and host CSS not yet present.

- [ ] **Step 4: Rewrite `render-chooser-html` to render a breadcrumb header**

In `Sources/Modaliser/Scheme/ui/chooser.scm`, find `render-chooser-html` (around lines 129–170). Replace its body so it:
  - Concatenates `(host-header-css)` into the style block.
  - Renders a `chooser-header` element (mirroring overlay's header) with breadcrumb segments `(append modal-root-segments (list prompt))`.
  - Drops the `chooser-prompt` div.

Replace the existing definition with:

```scheme
(define chooser-max-visible-rows 50)

;; Render breadcrumb segments shared between overlay and chooser.
;; Same DOM shape as ui/overlay.scm's render-breadcrumb but with the
;; "chooser-header" / "overlay-header" class chosen by the caller.
(define (render-header-breadcrumb header-class segments)
  (let ((sep (html->string (span '((class . "breadcrumb-sep")) ">"))))
    (header (list (cons 'class header-class))
      (span '((class . "breadcrumb"))
        (make-raw-html
          (let loop ((segs segments) (result ""))
            (if (null? segs)
              result
              (loop (cdr segs)
                    (string-append result
                      (if (string=? result "") "" sep)
                      (html-escape (car segs)))))))))))

(define (render-chooser-html prompt visible-items query selected-index
                             actions-visible? actions)
  (let* ((css (string-append overlay-base-css
                             (if (string=? overlay-custom-css "")
                               ""
                               (string-append "\n" overlay-custom-css))
                             "\n"
                             (host-header-css)))
         (item-count (length visible-items))
         (footer-text (string-append (number->string item-count)
                        (if (= item-count 1) " item" " items")))
         (segments (append modal-root-segments (list prompt)))
         (body
           (div '((class . "chooser"))
             (render-header-breadcrumb "chooser-header" segments)
             (div '((class . "chooser-search"))
               (input-element (list (cons 'type "text")
                                    (cons 'class "chooser-input")
                                    (cons 'id "chooser-input")
                                    (cons 'value query)
                                    (cons 'autocomplete "off")
                                    (cons 'autofocus #t))))
             (apply ul (cons '((class . "chooser-results"))
                             (let loop ((items visible-items) (i 0) (rows '()))
                               (if (or (null? items) (>= i chooser-max-visible-rows))
                                 (reverse rows)
                                 (let* ((item (car items))
                                        (orig-index (car item))
                                        (source-item (list-ref chooser-items orig-index)))
                                   (loop (cdr items) (+ i 1)
                                         (cons (render-chooser-row item source-item i selected-index)
                                               rows)))))))
             (div '((class . "chooser-footer")) footer-text)
             (if actions-visible?
               (render-action-panel actions chooser-action-index)
               (make-raw-html "")))))
    (html-document
      (make-raw-html
        (string-append
          (html->string (style-element '() css))
          (html->string (script-element '() chooser-js))))
      body)))
```

- [ ] **Step 5: Rewrite `chooser-load-skeleton` similarly**

In the same file, replace `chooser-load-skeleton` (around lines 328–350) with:

```scheme
(define (chooser-load-skeleton)
  (when chooser-open?
    (let* ((prompt (alist-ref chooser-selector-node 'prompt "Select..."))
           (css (string-append overlay-base-css
                               (if (string=? overlay-custom-css "")
                                 ""
                                 (string-append "\n" overlay-custom-css))
                               "\n"
                               (host-header-css)))
           (segments (append modal-root-segments (list prompt)))
           (html (html-document
                   (make-raw-html
                     (string-append
                       (html->string (style-element '() css))
                       (html->string (script-element '() chooser-js))))
                   (div '((class . "chooser"))
                     (render-header-breadcrumb "chooser-header" segments)
                     (div '((class . "chooser-search"))
                       (input-element (list (cons 'type "text")
                                            (cons 'class "chooser-input")
                                            (cons 'id "chooser-input")
                                            (cons 'value "")
                                            (cons 'autocomplete "off")
                                            (cons 'autofocus #t))))
                     (ul '((class . "chooser-results")))
                     (div '((class . "chooser-footer")) "")))))
      (webview-set-html! chooser-webview-id html))))
```

- [ ] **Step 6: Run all chooser tests to verify they pass**

Run: `swift test --filter ChooserRender`
Expected: PASS — both updated existing tests and new host-header tests.

- [ ] **Step 7: Run the broader chooser integration suite**

Run: `swift test --filter "Chooser|Dynamic"`
Expected: PASS — `chooser-open` etc. no longer reference the dropped `chooser-prompt` div, and the breadcrumb is purely additive on top.

- [ ] **Step 8: Commit**

```bash
git add Sources/Modaliser/Scheme/ui/chooser.scm Tests/ModaliserTests/ChooserRenderTests.swift
git commit -m "feat(chooser): add breadcrumb header parallel to overlay

Replaces the chooser-prompt div with a chooser-header element rendering
the breadcrumb (modal-root-segments + prompt as trailing segment). Same
host-header CSS injection as the overlay."
```

---

## Task 10: CSS — `.chooser-header` rules + colour variables with fallbacks

**Files:**
- Modify: `Sources/Modaliser/Scheme/base.css`

- [ ] **Step 1: Read the current CSS for the affected blocks**

Open `Sources/Modaliser/Scheme/base.css` and confirm the locations:
- `.overlay-header { ... }` block (around lines 59–65)
- `.overlay-header .breadcrumb` and `.overlay-header .breadcrumb-sep` (lines 67–74)
- `.chooser-prompt { ... }` (around line 161)

- [ ] **Step 2: Update `.overlay-header` to use the new CSS variables**

Replace the existing `.overlay-header` block (lines 59–65) with:

```css
.overlay-header,
.chooser-header {
  background: var(--color-host-bg, transparent);
  color: var(--color-host-fg, var(--color-header));
  font-size: var(--font-size);
  padding: 4px 6px;
  margin-bottom: 6px;
  border-bottom: 1px solid var(--color-separator);
  border-radius: 4px;
}

.overlay-header .breadcrumb,
.chooser-header .breadcrumb {
  display: inline;
}

.overlay-header .breadcrumb-sep,
.chooser-header .breadcrumb-sep {
  margin: 0 4px;
  color: var(--color-arrow);
}
```

(The original `.overlay-header .breadcrumb` and `.overlay-header .breadcrumb-sep` rules are folded into the combined selectors above — delete the now-redundant blocks at lines 67–74.)

- [ ] **Step 3: Remove `.chooser-prompt` rules**

Delete the `.chooser-prompt { ... }` block around line 161 (the element no longer exists in the DOM after Task 9).

- [ ] **Step 4: Build and run the full test suite**

Run: `swift test`
Expected: All tests PASS. (CSS changes are not directly tested but the test suite confirms no Scheme/Swift regressions.)

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/base.css
git commit -m "style: chooser-header rules + host CSS variables

Both .overlay-header and .chooser-header now respect --color-host-bg /
--color-host-fg with fallbacks to today's appearance. Drops the unused
.chooser-prompt rules (element removed in the prior commit)."
```

---

## Task 11: Default-config example

**Files:**
- Modify: `Sources/Modaliser/Scheme/default-config.scm`

- [ ] **Step 1: Add the commented example**

In `Sources/Modaliser/Scheme/default-config.scm`, after the `(set-overlay-delay! 0.3)` line (around line 13), add:

```scheme

;; Identify this Modaliser instance in the overlay/chooser breadcrumb.
;; Useful when you run multiple instances simultaneously (e.g. a local
;; instance plus one on a remote host viewed via Jump Desktop / VNC).
;; Optional. Background and foreground take any CSS colour value.
;;
;; (set-host-header!
;;   'name       (run-shell "hostname -s")
;;   'background "#7a1f3d"
;;   'foreground "#ffffff")
```

- [ ] **Step 2: Verify the file still parses**

Run: `swift test --filter ConfigDsl`
Expected: PASS — comments don't affect parsing, but this confirms the file is well-formed.

- [ ] **Step 3: Commit**

```bash
git add Sources/Modaliser/Scheme/default-config.scm
git commit -m "docs(config): document set-host-header! in default-config"
```

---

## Task 12: Manual smoke test

**Files:** none.

The Swift/Scheme test suite covers the rendering and state plumbing, but the WebView appearance and the per-host visual identification can only be confirmed by running the app.

- [ ] **Step 1: Sync the bundled default to the user config**

Per the project's saved memory: edits to `default-config.scm` should be mirrored to `~/.config/modaliser/config.scm` (or vice versa). Add the same `set-host-header!` example to `~/.config/modaliser/config.scm`, uncommented this time, with a recognisable name and bright colours:

```scheme
(set-host-header!
  'name       "smoke-test"
  'background "#7a1f3d"
  'foreground "#ffffff")
```

- [ ] **Step 2: Build and install**

Run: `./scripts/install.sh`
Expected: build succeeds; app installed to /Applications.

- [ ] **Step 3: Verify the overlay header**

Trigger the global leader (F18). When the overlay appears, confirm:
  - Top of the panel reads `smoke-test > Global`.
  - The header has the configured background colour (#7a1f3d) and foreground (#ffffff).
  - Navigate into a group (e.g. "w" for Windows) — the breadcrumb extends to `smoke-test > Global > w`.
  - Hit Esc and confirm the next leader press still works.

- [ ] **Step 4: Verify the app-local breadcrumb**

Focus Safari, trigger the local leader (F17). Confirm the header reads `smoke-test > Safari > …` (NOT `com.apple.Safari`). Repeat with Zed (`smoke-test > Zed`).

- [ ] **Step 5: Verify the variant breadcrumb**

If iTerm + nvim is set up: focus iTerm with nvim running, trigger F17. Confirm the breadcrumb reads `smoke-test > iTerm > nvim > …`.

- [ ] **Step 6: Verify the chooser**

Trigger global leader → `f` → `a` (Find Apps). Confirm the chooser header reads `smoke-test > Global > Find app…` with the same colours.

- [ ] **Step 7: Verify the unset case**

Comment out `set-host-header!` in `~/.config/modaliser/config.scm`. Re-run `./scripts/install.sh`. Trigger the leader and confirm the header is back to the original appearance (no host segment, default colours).

- [ ] **Step 8: Restore the user's preferred config**

Re-enable `set-host-header!` (or leave commented per the user's preference). Run `./scripts/install.sh` once more.

This task is checklist-only — no commit.

---

## Self-Review

**Spec coverage:**
- Goal 1 (host name in breadcrumb) → Tasks 2, 5, 6, 7 (overlay), 9 (chooser). ✓
- Goal 2 (recolour) → Tasks 3, 8 (overlay), 9 (chooser), 10 (CSS). ✓
- Goal 3 (app name not bundle ID) → Tasks 1 (Swift), 4 (Scheme resolver). ✓
- Goal 4 (variant trees as segments) → Task 4 (`resolve-app-segments` splits on `/`). ✓
- Goal 5 (chooser identifies host the same way) → Task 9. ✓
- Behavioural spec — breadcrumb composition table → covered by tests in Tasks 4, 5, 6, 9.
- Behavioural spec — colour CSS injection (both renderers) → Tasks 8, 9 (both inject `host-header-css`); Task 10 wires the CSS variables.
- Behavioural spec — chooser DOM (replace prompt with header) → Task 9.
- Behavioural spec — resolution timing (modal-enter, once at startup for host name) → Tasks 2 (host stored at config-load), 5 (segments computed at modal-enter).
- Default-config example → Task 11.
- Tests for AppLibrary, Overlay, Chooser → covered in Tasks 1, 6, 8, 9.

**Type/identifier consistency:**
- `host-header-name` / `host-header-background` / `host-header-foreground` — used consistently in Tasks 2, 3, 4, 5, 8, 9.
- `set-host-header!` keyword args (`'name`, `'background`, `'foreground`) — consistent in Tasks 2, 4, 8, 9, 11, 12.
- `modal-root-segments` — declared in Task 5, consumed in Tasks 6, 7, 9.
- `compute-root-segments` / `resolve-app-segments` — defined in Tasks 4–5, exercised in Task 5.
- `host-header-css` — defined in Task 3, consumed in Tasks 8, 9.
- `render-overlay-html` arity changes from 2 to 3 args (`node root-segments path`) — Task 6 updates ALL existing test callers.
- `render-chooser-html` signature unchanged (existing 6-arg form) — only its body changes to read `modal-root-segments` from state. ✓

**Placeholder scan:** No "TBD" / "implement later" / "similar to Task N" / vague error-handling steps. Every code change shows the actual code. ✓
