# Modular Config Phase B — `(modaliser dsl)` Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the Modaliser DSL surface (`key`, `key-range`, `group`, `selector`, `action`, `define-tree`, `set-leader!`, `set-host-header!`, `set-overlay-delay!`, `set-overlay-css!`, `modifier-symbols->mask`) into a proper R7RS library `(modaliser dsl)` that user-config files can `(import (modaliser dsl))`. Pure-Scheme dependencies (`util`, `keymap`, `state-machine`, `event-dispatch`) become libraries too. No `(lispkit …)` imports anywhere in the user-facing tree.

**Architecture:**

- Five files get carved out as R7RS `define-library` forms under `Sources/Modaliser/Scheme/lib/modaliser/`: `util.sld`, `keymap.sld`, `state-machine.sld`, `event-dispatch.sld`, `dsl.sld`.
- `ui/overlay.scm` and `ui/chooser.scm` stay as plain `.scm` includes (Phase C/D territory). The state-machine library exposes **setter procedures** (`set-overlay-open!`, `set-show-overlay!`, etc.) so the overlay/chooser code can install its real implementations into the library's encapsulated state instead of relying on define-redefinition at the top-level.
- `root.scm` imports the new libraries (whose exports cascade into the top-level environment for the included files and the user's `config.scm` to see), then includes the remaining `.scm` files.
- A `SchemeEngine` fallback locates LispKit's bundled `Libraries/` directory by walking from the executable so `(import (scheme base))` resolves under `swift test`. Without this fix, libraries can't import `(scheme base)` at test time and the Phase A workaround of using `(lispkit base)` would have to persist.
- Tests switch from `evaluateFile` of individual `.scm` files to `(import (modaliser dsl) …)` plus `evaluateFile` for the unconverted UI files.

**Tech Stack:** Swift 5.9, LispKit (R7RS Scheme), SPM, Swift Testing framework.

---

## File Structure

**Created:**

- `Sources/Modaliser/Scheme/lib/modaliser/util.sld` — `(modaliser util)`: `alist-ref`, `props->alist`, `string-join`, `read-file-text`, `log`.
- `Sources/Modaliser/Scheme/lib/modaliser/keymap.sld` — `(modaliser keymap)`: `has-cmd?`, `has-shift?`, `has-alt?`, `has-ctrl?`.
- `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` — `(modaliser state-machine)`: all of `core/state-machine.scm`'s public surface (`register-tree!`, `lookup-tree`, modal-* APIs, node predicates and accessors, sticky helpers, host-header API, `set-overlay-delay!`) plus new setters for the overlay/chooser hooks.
- `Sources/Modaliser/Scheme/lib/modaliser/event-dispatch.sld` — `(modaliser event-dispatch)`: `modal-key-handler`, `local-context-suffix`, `resolve-app-tree`, `make-leader-handler`.
- `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld` — `(modaliser dsl)`: `key`, `key-range`, `group`, `selector`, `action`, `define-tree`, `set-theme!`, `modifier-symbols->mask`, `set-leader!`.

**Modified:**

- `Sources/Modaliser/SchemeEngine.swift` — add a fallback that prepends LispKit's bundled `Libraries/` to the library search path when LispKit's own `Bundle(identifier:)` lookup failed, so `(scheme base)` resolves under `swift test`.
- `Sources/Modaliser/Scheme/root.scm` — replace include lines for converted files with `(import …)` of the new libraries.
- `Sources/Modaliser/Scheme/ui/overlay.scm` — call `(set-overlay-open! …)`, `(set-show-overlay! …)`, `(set-update-overlay! …)`, `(set-hide-overlay! …)` instead of redefining those bindings at the top level.
- `Sources/Modaliser/Scheme/ui/chooser.scm` — call `(set-open-chooser! …)` (and similarly `set-chooser-open!`, `set-close-chooser!` if event-dispatch needs them) instead of redefining.
- `Tests/ModaliserTests/ConfigDslTests.swift` — replace `loadDsl()` / `loadAllModules()` `evaluateFile` lists with `(import …)` of the converted libraries; `evaluateFile` still needed for the unconverted UI files.
- `Tests/ModaliserTests/LibraryPathTests.swift` — replace the `(lispkit base)` workaround in `userConfigRootResolvesUserLibrary` with `(scheme base)` (now that it resolves).
- Other tests that reference converted modules in their `loadAllModules`-style bootstrap — same migration as `ConfigDslTests`. Grep for filenames before editing.

**Deleted (after conversion is verified green):**

- `Sources/Modaliser/Scheme/lib/util.scm`
- `Sources/Modaliser/Scheme/lib/dsl.scm`
- `Sources/Modaliser/Scheme/core/keymap.scm`
- `Sources/Modaliser/Scheme/core/state-machine.scm`
- `Sources/Modaliser/Scheme/core/event-dispatch.scm`

These are replaced by their `.sld` equivalents under `lib/modaliser/`. Removing them prevents accidental re-include and clarifies the new layout.

---

## Task 1: Make `(scheme base)` resolve under `swift test`

**Why first:** Every subsequent task creates a library that imports `(scheme base)`. Without this fix, every conversion would have to use `(lispkit base)` and Phase D would have to re-edit each file. Better to clear the obstacle once.

**Root cause:** `LispKit/Runtime/FileHandler.swift:50-65` only adds the bundled `Libraries/` directory to its library search path when `LispKitContext.bundle?` is non-nil. That bundle reference is `Bundle(identifier: "net.objecthub.LispKit")`, which resolves under the `.app` (LispKit framework is linked in) but is **nil under `swift test`** (the test executable doesn't expose LispKit as a separate bundle). Result: `(import (scheme base))` from a library body fails with `no such file or directory: the file "base.sld" couldn't be opened` at test time. This was confirmed empirically before writing the plan.

**Fix:** in `SchemeEngine.init`, after constructing the context, walk from `ProcessInfo.processInfo.arguments[0]` upward to locate `.build/checkouts/swift-lispkit/Sources/LispKit/Resources/Libraries/` and `addLibrarySearchPath` it. The walk has a depth limit so the fallback degrades gracefully when the directory isn't present (e.g., installed `.app` builds where LispKit's own lookup already succeeded — the fallback then either finds nothing or appends a path that's lower precedence anyway).

**Files:**

- Modify: `Sources/Modaliser/SchemeEngine.swift`
- Test: `Tests/ModaliserTests/SchemeBaseProbeTests.swift` (new)

### Steps

- [ ] **1.1 Write the failing test**

Create `Tests/ModaliserTests/SchemeBaseProbeTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("Scheme base resolution")
struct SchemeBaseProbeTests {
    @Test func schemeBaseResolvesInDefineLibrary() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
            (define-library (probe one)
              (export greet)
              (import (scheme base))
              (begin
                (define (greet) "hello-from-probe")))
        """)
        try engine.evaluate("(import (probe one))")
        #expect(try engine.evaluate("(greet)").asString() == "hello-from-probe")
    }
}
```

- [ ] **1.2 Run the test to verify it fails**

Run: `swift test --filter SchemeBaseProbeTests 2>&1 | tail -10`

Expected: fail with `no such file or directory: the file "base.sld" couldn't be opened` (matches the recon result captured during plan-writing).

- [ ] **1.3 Implement the fallback in `SchemeEngine.swift`**

Add a private file-level helper near the top of `SchemeEngine.swift` (after `import LispKit`):

```swift
/// Locate LispKit's bundled R7RS+SRFI Libraries directory by walking up
/// from the executable to find the SPM checkout. Returns nil if not found
/// — under the installed .app build LispKit's own bundle lookup succeeds
/// and this fallback is unnecessary.
private func locateLispKitLibrariesFallback() -> String? {
    let suffix = ".build/checkouts/swift-lispkit/Sources/LispKit/Resources/Libraries"
    var dir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
    for _ in 0..<8 {
        let candidate = dir.appendingPathComponent(suffix).path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { return nil }
        dir = parent
    }
    return nil
}
```

Then inside `SchemeEngine.init`, **after** the existing `prependLibrarySearchPath(resolvedUserConfigDir)` call and **before** the first `try context.libraries.register(libraryType:…)` call, add:

```swift
        // Fallback: under `swift test` LispKit's own Bundle(identifier:)
        // lookup is nil, so the bundled R7RS+SRFI Libraries/ directory
        // never gets added to the library search path. Locate it via the
        // SPM checkout and append it (lowest precedence so a real LispKit
        // path or user override stays in front). No-op in .app builds
        // where the bundle resolves.
        if let lispKitLibs = locateLispKitLibrariesFallback() {
            _ = context.fileHandler.addLibrarySearchPath(lispKitLibs)
        }
```

(We append unconditionally rather than probing first because `addLibrarySearchPath` is cheap and a duplicate entry is harmless — and there's no clean public probe API on `FileHandler` for "does (scheme base) resolve right now?" If a probe API turns out to be available, gate the call behind it for cleanliness, but functional correctness is the same either way.)

- [ ] **1.4 Run the test to verify it passes**

Run: `swift test --filter SchemeBaseProbeTests 2>&1 | tail -10`

Expected: PASS — `(greet)` returns `"hello-from-probe"`.

- [ ] **1.5 Verify no other tests regressed**

Run: `swift test 2>&1 | tail -20`

Expected: existing tests + 1 new test, all green. If any test newly fails, investigate before committing.

- [ ] **1.6 Commit**

```bash
git add Sources/Modaliser/SchemeEngine.swift Tests/ModaliserTests/SchemeBaseProbeTests.swift
git commit -m "feat(modular-config): make (scheme base) resolve under swift test

LispKit's Bundle(identifier:) lookup is nil in the test process, so its
Resources/Libraries directory never makes it onto the library search
path. Walk from the executable to find the SPM checkout's Libraries
dir and append it as a defensive fallback. Preconditions Phase B's
library-ization of the Modaliser DSL."
```

---

## Task 2: Carve out `(modaliser util)`

**Files:**

- Create: `Sources/Modaliser/Scheme/lib/modaliser/util.sld`
- Test: `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift` (new)

### Steps

- [ ] **2.1 Write the failing test**

Create `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser util) library")
struct ModaliserUtilLibraryTests {
    @Test func alistRefDefaultsToFalse() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(alist-ref '((a . 1) (b . 2)) 'a)") == .fixnum(1))
        #expect(try engine.evaluate("(alist-ref '((a . 1)) 'missing)") == .false)
        #expect(try engine.evaluate("(alist-ref '() 'x 42)") == .fixnum(42))
    }

    @Test func stringJoinHandlesEmptyAndSingle() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(string-join '() \"-\")").asString() == "")
        #expect(try engine.evaluate("(string-join '(\"a\") \"-\")").asString() == "a")
        #expect(try engine.evaluate("(string-join '(\"a\" \"b\" \"c\") \"-\")").asString() == "a-b-c")
    }

    @Test func propsToAlistPairsKeyValues() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(equal? (props->alist 'a 1 'b 2) '((a . 1) (b . 2)))"
        ) == .true)
    }
}
```

- [ ] **2.2 Run the test, expect a resolution failure**

Run: `swift test --filter ModaliserUtilLibraryTests 2>&1 | tail -8`

Expected: fail with "no such file or directory" for `modaliser/util.sld` — the library doesn't exist yet.

- [ ] **2.3 Create the library file**

Write `Sources/Modaliser/Scheme/lib/modaliser/util.sld`:

```scheme
;; (modaliser util) — Shared utility functions used across other
;; (modaliser …) libraries. Pure Scheme; no host primitives.

(define-library (modaliser util)
  (export alist-ref
          props->alist
          string-join
          read-file-text
          log)
  (import (scheme base)
          (scheme file)
          (scheme read)
          (scheme write))
  (begin

    (define (alist-ref alist key . default)
      (let ((pair (assoc key alist)))
        (if pair
          (cdr pair)
          (if (null? default) #f (car default)))))

    (define (props->alist . args)
      (let loop ((rest args) (result '()))
        (if (or (null? rest) (null? (cdr rest)))
          (reverse result)
          (loop (cdr (cdr rest))
                (cons (cons (car rest) (car (cdr rest))) result)))))

    (define (string-join strs sep)
      (if (null? strs)
        ""
        (let loop ((rest (cdr strs)) (result (car strs)))
          (if (null? rest)
            result
            (loop (cdr rest)
                  (string-append result sep (car rest)))))))

    (define (read-file-text path)
      (if (file-exists? path)
        (let ((port (open-input-file path)))
          (let loop ((lines '()))
            (let ((line (read-line port)))
              (if (eof-object? line)
                (begin
                  (close-input-port port)
                  (string-join (reverse lines) "\n"))
                (loop (cons line lines))))))
        ""))

    (define (log . args)
      (for-each display args)
      (newline))))
```

**Audit note:** if any of `(scheme file)` / `(scheme read)` / `(scheme write)` fail to resolve under `swift test` even after Task 1's fix, narrow the imports to `(scheme base)` only — most of `read-line`, `file-exists?`, `open-input-file`, `display`, `newline` live in `(scheme base)`'s R7RS surface as exposed by LispKit. Adjust by running Task 2.4 and reading the error message. **Do not import `(lispkit …)`.**

- [ ] **2.4 Run the test to verify it passes**

Run: `swift test --filter ModaliserUtilLibraryTests 2>&1 | tail -10`

Expected: 3 tests pass.

- [ ] **2.5 Run the full suite — nothing should have regressed**

Run: `swift test 2>&1 | tail -20`

Expected: baseline test count + 3, all green. The old `lib/util.scm` is still present and still included from `root.scm`, so existing behaviour is unchanged.

- [ ] **2.6 Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/util.sld \
        Tests/ModaliserTests/ModaliserUtilLibraryTests.swift
git commit -m "feat(modular-config): (modaliser util) library

First of the Phase B carve-out. Pure-Scheme utilities now importable
as a proper R7RS library. The legacy lib/util.scm include path remains
operational until root.scm switches to imports in a later task."
```

---

## Task 3: Carve out `(modaliser keymap)`

**Files:**

- Create: `Sources/Modaliser/Scheme/lib/modaliser/keymap.sld`
- Test: `Tests/ModaliserTests/ModaliserKeymapLibraryTests.swift` (new)

### Steps

- [ ] **3.1 Write the failing test**

Create `Tests/ModaliserTests/ModaliserKeymapLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser keymap) library")
struct ModaliserKeymapLibraryTests {
    @Test func modifierPredicatesReadBitmask() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser keymap) (modaliser keyboard))")
        #expect(try engine.evaluate("(has-cmd? MOD-CMD)") == .true)
        #expect(try engine.evaluate("(has-shift? MOD-CMD)") == .false)
        #expect(try engine.evaluate(
            "(has-shift? (bitwise-ior MOD-CMD MOD-SHIFT))") == .true)
        #expect(try engine.evaluate("(has-alt? 0)") == .false)
    }
}
```

- [ ] **3.2 Run the test, expect failure**

Run: `swift test --filter ModaliserKeymapLibraryTests 2>&1 | tail -8`

Expected: fail — `keymap.sld` doesn't exist.

- [ ] **3.3 Create the library file**

Write `Sources/Modaliser/Scheme/lib/modaliser/keymap.sld`:

```scheme
;; (modaliser keymap) — Predicates over modifier bitmasks.
;;
;; The MOD-CMD/MOD-SHIFT/MOD-ALT/MOD-CTRL constants themselves live in
;; the native (modaliser keyboard) library (CGEventFlags raw values).
;; This library exists for pure-Scheme code that needs to inspect a
;; modifier mask without depending on host code.

(define-library (modaliser keymap)
  (export has-cmd? has-shift? has-alt? has-ctrl?)
  (import (scheme base)
          (modaliser keyboard))
  (begin
    (define (has-cmd? mods)
      (not (= (bitwise-and mods MOD-CMD) 0)))
    (define (has-shift? mods)
      (not (= (bitwise-and mods MOD-SHIFT) 0)))
    (define (has-alt? mods)
      (not (= (bitwise-and mods MOD-ALT) 0)))
    (define (has-ctrl? mods)
      (not (= (bitwise-and mods MOD-CTRL) 0)))))
```

**Audit note:** if `bitwise-and` isn't in `(scheme base)` as LispKit exposes it, try adding `(scheme bitwise)` to the imports. If only LispKit ships it (e.g., `(lispkit math)`), do **not** import lispkit here — re-export `bitwise-and` and `bitwise-ior` from `(modaliser util)`'s import block (util is the designated home for any unavoidable host-primitive re-exports during Phase B; Phase D will audit and minimise these). Note the workaround in a comment at the top of `util.sld` so Phase D can find it.

- [ ] **3.4 Run the test to verify it passes**

Run: `swift test --filter ModaliserKeymapLibraryTests 2>&1 | tail -8`

Expected: PASS.

- [ ] **3.5 Run the full suite**

Run: `swift test 2>&1 | tail -20`

Expected: all green.

- [ ] **3.6 Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/keymap.sld \
        Tests/ModaliserTests/ModaliserKeymapLibraryTests.swift
git commit -m "feat(modular-config): (modaliser keymap) library

Modifier predicates as a proper library on top of (modaliser keyboard)'s
MOD-CMD/SHIFT/ALT/CTRL bit constants. Sets up the dependency surface
for the upcoming (modaliser state-machine) carve-out."
```

---

## Task 4: Refactor overlay/chooser hooks to setter pattern in state-machine.scm (still .scm)

**Why before Task 5:** state-machine.scm currently uses define-redefinition for overlay/chooser hooks. Once it becomes a library, that pattern is dead — library bindings are hermetic. Move to setter-based injection first, while the file is still a plain `.scm` and tests can verify the change in isolation. Task 5 then library-izes the *new* code shape unchanged.

**Files:**

- Modify: `Sources/Modaliser/Scheme/core/state-machine.scm` — replace stub redefinitions with mutable state plus setter procedures.
- Modify: `Sources/Modaliser/Scheme/ui/overlay.scm` — replace top-level `(define overlay-open? …)` / `(define (show-overlay …) …)` etc. with calls to setters.
- Modify: `Sources/Modaliser/Scheme/ui/chooser.scm` — replace `(define (open-chooser …) …)` with `(set-open-chooser! …)`, and (if `chooser-open?` / `close-chooser` are needed by event-dispatch in Task 6) add matching setters for those.

### Steps

- [ ] **4.1 Write the failing test**

Create `Tests/ModaliserTests/OverlayHookSetterTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("State-machine overlay hook setters")
struct OverlayHookSetterTests {
    @Test func setShowOverlayReplacesHook() throws {
        let engine = try SchemeEngine()
        guard let dir = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); return
        }
        // Load via current include path so the test passes after task 4
        // but before tasks 5+ flip the loader.
        try engine.evaluateFile(dir + "/lib/util.scm")
        try engine.evaluateFile(dir + "/core/keymap.scm")
        try engine.evaluateFile(dir + "/core/state-machine.scm")

        try engine.evaluate("""
          (define show-calls '())
          (set-show-overlay! (lambda (root path)
                               (set! show-calls (cons 'show show-calls))))
          (set-overlay-open! #t)
          (show-overlay 'dummy '())
        """)
        #expect(try engine.evaluate("overlay-open?") == .true)
        #expect(try engine.evaluate("(length show-calls)") == .fixnum(1))
    }
}
```

- [ ] **4.2 Run, expect failure**

Run: `swift test --filter OverlayHookSetterTests 2>&1 | tail -8`

Expected: fail — `set-show-overlay!` is undefined.

- [ ] **4.3 Edit `core/state-machine.scm`**

Find the existing block (around lines 192–200):

```scheme
;; ─── Overlay Hooks (overridden by ui/overlay.scm) ───────────────
;; These stubs allow state-machine.scm to be loaded and tested
;; independently. When overlay.scm loads, it redefines these.

(define overlay-open? #f)
(define (show-overlay node path) (void))
(define (update-overlay node path) (void))
(define (hide-overlay) (void))
(define (open-chooser selector-node) (void))
```

Replace it with:

```scheme
;; ─── Overlay/chooser hooks ────────────────────────────────────
;;
;; In the include-based loader, ui/overlay.scm and ui/chooser.scm
;; redefined the stub bindings below to install their real impls.
;; That pattern doesn't survive library encapsulation — once
;; state-machine becomes a library, its define bindings are hermetic.
;; Instead we expose setters so the UI code installs its hooks by
;; mutation. Same runtime effect, library-clean shape.

(define overlay-open? #f)
(define (set-overlay-open! v) (set! overlay-open? v))

(define show-overlay-impl   (lambda (node path) (if #f #f)))
(define update-overlay-impl (lambda (node path) (if #f #f)))
(define hide-overlay-impl   (lambda ()          (if #f #f)))
(define open-chooser-impl   (lambda (sel)       (if #f #f)))

(define (show-overlay   node path) (show-overlay-impl node path))
(define (update-overlay node path) (update-overlay-impl node path))
(define (hide-overlay)             (hide-overlay-impl))
(define (open-chooser selector-node) (open-chooser-impl selector-node))

(define (set-show-overlay!   fn) (set! show-overlay-impl   fn))
(define (set-update-overlay! fn) (set! update-overlay-impl fn))
(define (set-hide-overlay!   fn) (set! hide-overlay-impl   fn))
(define (set-open-chooser!   fn) (set! open-chooser-impl   fn))
```

Then search the rest of `state-machine.scm` for literal `(void)` calls and replace each with `(if #f #f)` so the file stays R7RS-pure (`void` is LispKit-specific). Likely zero or one occurrence — most uses are implicit (`(when …)` etc.) and need no change.

- [ ] **4.4 Edit `ui/overlay.scm`**

Read the file first. Find each top-level definition that previously *redefined* a state-machine stub: typically `(define overlay-open? …)`, `(define (show-overlay …) …)`, `(define (update-overlay …) …)`, `(define (hide-overlay) …)`. Rename each local binding to a private `*-impl` name:

```scheme
(define (overlay-show-impl root path)
  …existing body…)

(define (overlay-update-impl root path)
  …existing body…)

(define (overlay-hide-impl)
  …existing body…)
```

Replace any `(define overlay-open? …)` at the top level — that binding now lives in state-machine. Anywhere overlay.scm did `(set! overlay-open? #t)` / `(set! overlay-open? #f)`, change to `(set-overlay-open! #t)` / `(set-overlay-open! #f)`. Reads of `overlay-open?` keep working unchanged.

At the bottom of the file, add an install block:

```scheme
;; Install the overlay implementations into the state-machine.
(set-show-overlay!   overlay-show-impl)
(set-update-overlay! overlay-update-impl)
(set-hide-overlay!   overlay-hide-impl)
```

- [ ] **4.5 Edit `ui/chooser.scm`**

Same pattern for `open-chooser`. Read the file. The current `(define (open-chooser selector-node) …)` becomes:

```scheme
(define (chooser-open-impl selector-node)
  …existing body…)
```

Then at the bottom:

```scheme
(set-open-chooser! chooser-open-impl)
```

`chooser.scm` likely also defines `chooser-open?` (a local boolean) and `close-chooser` (a local proc). These are not state-machine stubs in the current code — they're chooser-local state that event-dispatch reaches into via the include's top-level scope. Leave them as plain defines for this task; if Task 6 reveals event-dispatch needs to see them through library encapsulation, *that* task will extend the state-machine setter set to cover them and update `chooser.scm` accordingly.

- [ ] **4.6 Run the new test to verify it passes**

Run: `swift test --filter OverlayHookSetterTests 2>&1 | tail -8`

Expected: PASS.

- [ ] **4.7 Run the full suite — nothing else should have changed externally**

Run: `swift test 2>&1 | tail -30`

Expected: baseline + 1 new test, all green. Pay particular attention to `OverlayIntegrationTests`, `OverlayRenderTests`, `ChooserIntegrationTests`, `ChooserRenderTests`, `EndToEndSchemeModalTests`, `ConfigDslTests` — these exercise the hook plumbing.

- [ ] **4.8 Commit**

```bash
git add Sources/Modaliser/Scheme/core/state-machine.scm \
        Sources/Modaliser/Scheme/ui/overlay.scm \
        Sources/Modaliser/Scheme/ui/chooser.scm \
        Tests/ModaliserTests/OverlayHookSetterTests.swift
git commit -m "feat(modular-config): setter-based overlay/chooser hooks

State-machine exposes set-show-overlay!, set-update-overlay!,
set-hide-overlay!, set-open-chooser!, set-overlay-open! so the UI
modules install their real implementations by mutation instead of
relying on define-redefinition at top level. Prerequisite for
library-izing state-machine in the next step — define-redefinition
doesn't survive library encapsulation."
```

---

## Task 5: Convert state-machine.scm → `(modaliser state-machine)`

**Files:**

- Create: `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` (content sourced from `core/state-machine.scm`)
- Delete: `Sources/Modaliser/Scheme/core/state-machine.scm`
- Modify: `Sources/Modaliser/Scheme/root.scm` — replace `(include "core/state-machine.scm")` with `(import (modaliser state-machine))`. Leave other includes alone for now.
- Modify: tests that included `core/state-machine.scm` in their bootstrap.
- Test: `Tests/ModaliserTests/ModaliserStateMachineLibraryTests.swift` (new)

### Steps

- [ ] **5.1 Write the failing test**

Create `Tests/ModaliserTests/ModaliserStateMachineLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser state-machine) library")
struct ModaliserStateMachineLibraryTests {
    @Test func registerTreeAndLookupRoundtrip() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser state-machine))
          (register-tree! 'global
            (list (cons 'kind 'command)
                  (cons 'key "s")
                  (cons 'label "Safari")
                  (cons 'action (lambda () 'ok))))
        """)
        #expect(try engine.evaluate("(lookup-tree \"global\")") != .false)
    }

    @Test func setOverlayDelayMutatesParameter() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser state-machine))")
        try engine.evaluate("(set-overlay-delay! 0.25)")
        #expect(try engine.evaluate("(= modal-overlay-delay 0.25)") == .true)
    }
}
```

- [ ] **5.2 Run, expect failure**

Run: `swift test --filter ModaliserStateMachineLibraryTests 2>&1 | tail -10`

Expected: fail — `lib/modaliser/state-machine.sld` doesn't exist.

- [ ] **5.3 Create `lib/modaliser/state-machine.sld`**

Copy the entire body of `core/state-machine.scm` (post-Task-4 form) into a `define-library` form:

```scheme
;; (modaliser state-machine) — Modal navigation state machine.
;;
;; Hosts the tree registry, modal-* state, and the overlay/chooser hook
;; setters (see Task 4 in the Phase B plan for why setters instead of
;; define-redefinition).

(define-library (modaliser state-machine)
  (export
    ;; Tree registry
    register-tree! lookup-tree
    ;; Node predicates
    command? group? selector? range-command?
    ;; Node accessors
    node-key node-label node-action node-children node-range-keys
    node-on-enter node-on-leave node-sticky? node-exit-on-unknown?
    node-display-name
    run-on-enter run-on-leave
    find-child navigate-to-path
    ;; Sticky helpers
    deepest-sticky-on-path in-sticky-context? any-on-path?
    exit-on-unknown-context?
    modal-reset-to-sticky-ancestor
    ;; Modal state (read by callers, mutated by modal-* procs and setters)
    modal-active? modal-current-node modal-root-node modal-current-path
    modal-leader-keycode modal-overlay-generation modal-overlay-delay
    modal-root-segments modal-stack
    modal-current-context modal-apply-context!
    ;; Modal lifecycle
    modal-enter modal-exit modal-step-back modal-handle-key
    modal-show-overlay-now modal-show-overlay-delayed
    enter-mode!
    set-overlay-delay!
    ;; Overlay/chooser hooks
    overlay-open? show-overlay update-overlay hide-overlay open-chooser
    set-overlay-open! set-show-overlay! set-update-overlay!
    set-hide-overlay! set-open-chooser!
    ;; Host header
    host-header-name host-header-background host-header-foreground
    host-header-separator-color
    set-host-header! host-header-css
    ;; Breadcrumb
    resolve-app-segments compute-root-segments compute-tree-root-segments)
  (import (scheme base)
          (modaliser util)
          (modaliser app)
          (modaliser keyboard))
  (begin
    …existing body of (post-Task-4) core/state-machine.scm…))
```

**Audit checklist for the library body — primitives that may need routing through `(modaliser util)`:**

- `make-hashtable`, `hashtable-set!`, `hashtable-ref`, `string-hash`: LispKit hash table primitives. May not be in `(scheme base)`. If LispKit only exposes them under `(lispkit hashtable)` or similar, add an import to `(modaliser util)` (e.g., `(import (lispkit hashtable))`) and re-export from there, then import them here via `(modaliser util)`. Document the lispkit dependency in a comment at the top of `util.sld`. R7RS-Large names like `make-hash-table` exist in `(scheme hash-table)` if LispKit's library set includes that.
- `string-split`, `string-trim`, `string-upcase`: same handling. `string-upcase` is in `(scheme char)`. The others may need util-routing.
- `after-delay`: not standard — likely a LispKit primitive from a system library or one of Modaliser's own libs. Check `Sources/Modaliser/LifecycleLibrary.swift` first; if it's in `(modaliser lifecycle)`, add that to the import list. Otherwise route via `(modaliser util)`.
- `focused-app-bundle-id`, `app-display-name`: from `(modaliser app)` — already in imports.

**Rule:** every unavoidable host-primitive dependency goes through `(modaliser util)` so this and other Phase B libraries import only `(scheme …)` and `(modaliser …)`. Annotate each such workaround in `util.sld`'s header comment so Phase D's portability audit can find them.

- [ ] **5.4 Update `root.scm`**

Find the line `(include "core/state-machine.scm")` and replace it with `(import (modaliser state-machine))`. Leave every other line intact for now.

- [ ] **5.5 Delete the old file**

```bash
git rm Sources/Modaliser/Scheme/core/state-machine.scm
```

- [ ] **5.6 Run the new test, expect pass**

Run: `swift test --filter ModaliserStateMachineLibraryTests 2>&1 | tail -10`

Expected: PASS.

- [ ] **5.7 Run the full suite, update test bootstraps**

Run: `swift test 2>&1 | tail -30`

Existing tests in `ConfigDslTests`, `OverlayIntegrationTests`, `OverlayRenderTests`, `EndToEndSchemeModalTests`, etc. still call `evaluateFile("core/state-machine.scm")`. Those will newly fail with file-not-found. For each affected test file, replace the deleted file's line in the bootstrap with an `import` snippet pre-evaluated. Example transformation in `ConfigDslTests.loadDsl()`:

Before:

```swift
let files = [
    "lib/util.scm",
    "core/keymap.scm",
    "core/state-machine.scm",
    "core/event-dispatch.scm",
    "lib/dsl.scm",
]
for file in files {
    try engine.evaluateFile(joinPath(schemePath, file))
}
```

After (only state-machine swapped at this task — keymap and util conversions follow):

```swift
try engine.evaluate("""
  (import (modaliser util)
          (modaliser keymap)
          (modaliser state-machine))
""")
let files = [
    "core/event-dispatch.scm",
    "lib/dsl.scm",
]
for file in files {
    try engine.evaluateFile(joinPath(schemePath, file))
}
```

(util and keymap are now libraries from Tasks 2–3, so import them here too. Order matters: `state-machine` imports `util`, so util must be importable first — and it is, since the imports list is processed by the library manager.)

Apply the same pattern to every other test that lists `core/state-machine.scm` (and update util/keymap references at the same time). Grep before editing:

```
grep -rn 'core/state-machine.scm\|core/keymap.scm\|lib/util.scm' Tests/
```

- [ ] **5.8 Run the full suite again**

Run: `swift test 2>&1 | tail -30`

Expected: all green. If any test still fails, the import order, an unresolved primitive, or a missed bootstrap is the cause.

- [ ] **5.9 Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld \
        Sources/Modaliser/Scheme/root.scm \
        Tests/ModaliserTests/ModaliserStateMachineLibraryTests.swift \
        Tests/ModaliserTests/  # any updated test bootstraps
# also update Sources/Modaliser/Scheme/lib/modaliser/util.sld if any
# host-primitive re-exports were added in 5.3
git rm Sources/Modaliser/Scheme/core/state-machine.scm
git commit -m "feat(modular-config): (modaliser state-machine) library

Carve the modal navigation engine out of core/state-machine.scm into a
proper R7RS library. Exports the full surface (register-tree!, modal-*,
node-*, sticky helpers, host-header API, overlay/chooser hook setters).
Imports only (scheme base), (modaliser util), (modaliser app),
(modaliser keyboard). Test bootstraps migrated to import-style."
```

---

## Task 6: Convert event-dispatch.scm → `(modaliser event-dispatch)`

**Files:**

- Create: `Sources/Modaliser/Scheme/lib/modaliser/event-dispatch.sld`
- Modify: `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` if Task 6 reveals event-dispatch needs `chooser-open?` / `close-chooser` through library encapsulation — add matching setters there.
- Modify: `Sources/Modaliser/Scheme/ui/chooser.scm` to install via the new setters if added.
- Modify: `Sources/Modaliser/Scheme/root.scm` — swap include → import.
- Modify: tests that include `core/event-dispatch.scm`.
- Delete: `Sources/Modaliser/Scheme/core/event-dispatch.scm`
- Test: `Tests/ModaliserTests/ModaliserEventDispatchLibraryTests.swift` (new)

### Steps

- [ ] **6.1 Write the failing test**

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser event-dispatch) library")
struct ModaliserEventDispatchLibraryTests {
    @Test func dispatchProceduresExist() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser event-dispatch))")
        #expect(try engine.evaluate("(procedure? modal-key-handler)") == .true)
        #expect(try engine.evaluate("(procedure? make-leader-handler)") == .true)
    }

    @Test func localContextSuffixDefaultIsFalse() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser event-dispatch))")
        #expect(try engine.evaluate("(local-context-suffix \"com.apple.Safari\")") == .false)
    }
}
```

- [ ] **6.2 Run, expect failure**

Run: `swift test --filter ModaliserEventDispatchLibraryTests 2>&1 | tail -8`

Expected: fail.

- [ ] **6.3 Create `lib/modaliser/event-dispatch.sld`**

```scheme
;; (modaliser event-dispatch) — Keyboard event dispatch into the modal
;; state machine. The catch-all key handler installed by modal-enter
;; lives here, as does the leader-key handler factory.

(define-library (modaliser event-dispatch)
  (export modal-key-handler
          local-context-suffix
          resolve-app-tree
          make-leader-handler)
  (import (scheme base)
          (modaliser keymap)
          (modaliser keyboard)
          (modaliser app)
          (modaliser state-machine))
  (begin
    …body of core/event-dispatch.scm…))
```

**Handling `chooser-open?` and `close-chooser`:** `make-leader-handler` references both. These are currently defined at the top level by `ui/chooser.scm`. Inside a library, they aren't visible unless imported. Two options:

1. *Add setters for them in state-machine* (extending Task 4's pattern): export `chooser-open?`, `close-chooser`, `set-chooser-open!`, `set-close-chooser!` from `(modaliser state-machine)`; update `ui/chooser.scm` to call `(set-chooser-open! …)` / `(set-close-chooser! …)` instead of mutating local bindings.
2. *Import directly* by also making chooser a library — but that's a big lift and Phase C/D territory.

Pick option 1. Edit `lib/modaliser/state-machine.sld`:

```scheme
;; Add to the define-library body:
(define chooser-open? #f)
(define (set-chooser-open! v) (set! chooser-open? v))
(define close-chooser-impl (lambda () (if #f #f)))
(define (close-chooser) (close-chooser-impl))
(define (set-close-chooser! fn) (set! close-chooser-impl fn))
```

Add `chooser-open?`, `close-chooser`, `set-chooser-open!`, `set-close-chooser!` to the export list.

Edit `ui/chooser.scm`:
- Remove the local `(define chooser-open? …)` (move ownership to state-machine).
- Replace every `(set! chooser-open? #t)` with `(set-chooser-open! #t)` (and `#f` similarly).
- Reads of `chooser-open?` keep working (it's exported by state-machine and is at top level after root.scm imports it).
- Replace `(define (close-chooser) …)` with `(define (chooser-close-impl) …)` plus `(set-close-chooser! chooser-close-impl)` at the bottom.

Verify by re-running `OverlayHookSetterTests` and the existing chooser tests after the edit. None of the assertions changed; only the *binding source* moved.

- [ ] **6.4 Update `root.scm`**

Replace `(include "core/event-dispatch.scm")` with `(import (modaliser event-dispatch))`.

- [ ] **6.5 Delete the old file**

```bash
git rm Sources/Modaliser/Scheme/core/event-dispatch.scm
```

- [ ] **6.6 Run new test + full suite**

Run: `swift test 2>&1 | tail -30`

Update any test bootstrap that referenced `core/event-dispatch.scm`. Use the same transformation pattern as Task 5.7. Expected after fixes: all green.

- [ ] **6.7 Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/event-dispatch.sld \
        Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld \
        Sources/Modaliser/Scheme/ui/chooser.scm \
        Sources/Modaliser/Scheme/root.scm \
        Tests/ModaliserTests/ModaliserEventDispatchLibraryTests.swift \
        Tests/ModaliserTests/  # any updated bootstraps
git rm Sources/Modaliser/Scheme/core/event-dispatch.scm
git commit -m "feat(modular-config): (modaliser event-dispatch) library

Carve keyboard dispatch out into its own R7RS library. Extends
state-machine's setter pattern to chooser-open? and close-chooser,
which event-dispatch needs to see but ui/chooser.scm still owns."
```

---

## Task 7: Convert dsl.scm → `(modaliser dsl)`

**Files:**

- Create: `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld`
- Delete: `Sources/Modaliser/Scheme/lib/dsl.scm`
- Modify: `root.scm` (swap include → import)
- Modify: tests that loaded `lib/dsl.scm`
- Test: `Tests/ModaliserTests/ModaliserDslLibraryTests.swift` (new)

### Steps

- [ ] **7.1 Write the failing test**

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser dsl) library")
struct ModaliserDslLibraryTests {
    @Test func keyConstructsCommandAlist() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("""
          (define k (key "s" "Safari" (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("(command? k)") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'key k))").asString() == "s")
        #expect(try engine.evaluate("(cdr (assoc 'label k))").asString() == "Safari")
    }

    @Test func defineTreeRegistersTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("""
          (define-tree 'global
            (key "s" "Safari" (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("(lookup-tree \"global\")") != .false)
    }

    @Test func modifierSymbolsToMaskConvertsToBits() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser keyboard))")
        let expected = try engine.evaluate("(bitwise-ior MOD-SHIFT MOD-CTRL)")
        #expect(try engine.evaluate("(modifier-symbols->mask '(shift ctrl))") == expected)
    }
}
```

- [ ] **7.2 Run, expect failure**

Run: `swift test --filter ModaliserDslLibraryTests 2>&1 | tail -8`

Expected: fail.

- [ ] **7.3 Create `lib/modaliser/dsl.sld`**

```scheme
;; (modaliser dsl) — User-facing DSL.
;;
;; Imports of this library form the contract user configs see. Keep
;; the surface small and the dependencies portable: (scheme base) for
;; primitives, (modaliser state-machine) for tree registration and
;; modal lifecycle, (modaliser event-dispatch) for make-leader-handler,
;; (modaliser keyboard) for hotkey registration / modifier constants.

(define-library (modaliser dsl)
  (export key key-range group selector action
          define-tree set-theme!
          modifier-symbols->mask set-leader!)
  (import (scheme base)
          (modaliser state-machine)
          (modaliser event-dispatch)
          (modaliser keyboard))
  (begin
    …body of lib/dsl.scm, with `(void)` → `(if #f #f)` and any
      LispKit-specific bindings audited and routed via (modaliser util)
      if necessary…))
```

Audit the body for `(void)` — used in `set-theme!`'s stub at minimum. Replace with `(if #f #f)`.

- [ ] **7.4 Update `root.scm`**

Replace `(include "lib/dsl.scm")` with `(import (modaliser dsl))`.

- [ ] **7.5 Delete the old file**

```bash
git rm Sources/Modaliser/Scheme/lib/dsl.scm
```

- [ ] **7.6 Run new tests + full suite**

Run: `swift test 2>&1 | tail -30`

Update test bootstraps that included `lib/dsl.scm`. Expected: all green.

- [ ] **7.7 Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/dsl.sld \
        Sources/Modaliser/Scheme/root.scm \
        Tests/ModaliserTests/ModaliserDslLibraryTests.swift \
        Tests/ModaliserTests/  # updated bootstraps
git rm Sources/Modaliser/Scheme/lib/dsl.scm
git commit -m "feat(modular-config): (modaliser dsl) library

Carve the user-facing DSL out into a proper R7RS library. User configs
can now (import (modaliser dsl)) and get key, key-range, group,
selector, action, define-tree, set-leader!, modifier-symbols->mask
with no (lispkit ...) dependency. Library imports only (scheme base),
(modaliser state-machine), (modaliser event-dispatch),
(modaliser keyboard)."
```

---

## Task 8: Clean up `root.scm`

By the time Task 7 finishes, `root.scm` has multiple new `(import …)` lines interleaved with the surviving `(include …)` lines. Clean it up: imports first as a single block, includes beneath.

**Files:**

- Modify: `Sources/Modaliser/Scheme/root.scm`

### Steps

- [ ] **8.1 Edit `root.scm`** to:

```scheme
;; root.scm — Modaliser application entry point
;;
;; Imports the converted (modaliser …) libraries first; their exports
;; cascade into the top-level environment for the .scm files still
;; loaded via (include). Phases C and D will continue carving these
;; .scm files into libraries.

;; ─── Modaliser libraries ──────────────────────────────────────────
(import (modaliser util)
        (modaliser keymap)
        (modaliser state-machine)
        (modaliser event-dispatch)
        (modaliser dsl))

;; ─── Plain .scm modules (deferred to Phase C/D) ───────────────────
(include "lib/terminal.scm")
(include "ui/dom.scm")
(include "ui/css.scm")
(include "ui/overlay.scm")
(include "ui/chooser.scm")
(include "lib/web-search.scm")
(include "lib/ax-hints.scm")

;; ─── App setup ────────────────────────────────────────────────────
…rest of file unchanged…
```

Order rationale: imports come first so library-exported names are visible to the included files. Within the include block, terminal goes first (no UI dependencies), then UI files, then web-search and ax-hints (which may reference UI primitives). This mirrors the original order modulo the imports.

- [ ] **8.2 Run the full suite**

Run: `swift test 2>&1 | tail -20`

Expected: all green.

- [ ] **8.3 Build and smoke-test the app**

Run: `swift build 2>&1 | tail -5`

Expected: build succeeds. A full GUI smoke test (launching Modaliser, pressing the leader, navigating a tree) is part of Task 11's verification — for now just confirm the build is clean.

- [ ] **8.4 Commit**

```bash
git add Sources/Modaliser/Scheme/root.scm
git commit -m "feat(modular-config): root.scm uses (import) for converted libs

Group the (modaliser ...) imports at the top, leave the remaining .scm
includes in their original order beneath. Phase C and D will continue
carving the included files."
```

---

## Task 9: Restore `(scheme base)` in the Phase A test

Phase A's `userConfigRootResolvesUserLibrary` test used `(lispkit base)` with a comment explaining `(scheme base)` didn't resolve under `swift test`. Task 1 fixed that. Update the test to use the standards-compliant import.

**Files:**

- Modify: `Tests/ModaliserTests/LibraryPathTests.swift`

### Steps

- [ ] **9.1 Edit `LibraryPathTests.swift`**

In the `userConfigRootResolvesUserLibrary` test body, change:

```scheme
(import (lispkit base))
```

to:

```scheme
(import (scheme base))
```

…and delete the multi-line explanatory comment about why `(lispkit base)` was needed (the comment in the Swift source, not in the Scheme literal).

- [ ] **9.2 Run the test**

Run: `swift test --filter LibraryPathTests 2>&1 | tail -10`

Expected: all three tests pass.

- [ ] **9.3 Commit**

```bash
git add Tests/ModaliserTests/LibraryPathTests.swift
git commit -m "test(modular-config): use (scheme base) in user-library probe

Phase A used (lispkit base) because Bundle resolution failed under
swift test. Phase B fixed that; the standards-compliant import now
works."
```

---

## Task 10: End-to-end user-config import test

A new test that mirrors what a user actually does: drop an `.sld` file under a temp user-config dir that imports `(modaliser dsl)`, register a tree, verify it's visible.

**Files:**

- Create: `Tests/ModaliserTests/ModaliserDslImportEndToEndTests.swift`

### Steps

- [ ] **10.1 Write the test**

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("End-to-end: user library imports (modaliser dsl)")
struct ModaliserDslImportEndToEndTests {
    @Test func userLibraryCanImportModaliserDslAndDefineTree() throws {
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modaliser-dsl-e2e-\(UUID().uuidString)",
                                   isDirectory: true)
        let userDir = tmpRoot.appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let libBody = """
        (define-library (user bindings)
          (export register!)
          (import (scheme base)
                  (modaliser dsl)
                  (modaliser state-machine))
          (begin
            (define (register!)
              (define-tree 'global
                (key "s" "Safari" (lambda () 'ok))))))
        """
        try libBody.write(to: userDir.appendingPathComponent("bindings.sld"),
                          atomically: true, encoding: .utf8)

        let engine = try SchemeEngine(userConfigDir: tmpRoot.path)
        try engine.evaluate("(import (user bindings))")
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("""
          (import (modaliser state-machine))
          (lookup-tree \"global\")
        """) != .false)
    }
}
```

- [ ] **10.2 Run, expect pass**

Run: `swift test --filter ModaliserDslImportEndToEndTests 2>&1 | tail -10`

Expected: PASS — proves the full Phase B story works for a user.

- [ ] **10.3 Commit**

```bash
git add Tests/ModaliserTests/ModaliserDslImportEndToEndTests.swift
git commit -m "test(modular-config): e2e — user library imports (modaliser dsl)

Mirrors what a user actually writes: a (define-library …) under
~/.config/modaliser/ that imports (modaliser dsl), calls define-tree,
and the registration is visible via lookup-tree. Locks in the
Phase B contract."
```

---

## Task 11: Final verification

Self-review checklist before handing off to code review.

### Steps

- [ ] **11.1 Audit for stray `(lispkit …)` imports in libraries**

Run:

```bash
grep -rn '(lispkit ' Sources/Modaliser/Scheme/lib/modaliser/
```

Expected: no output OR a single, commented re-export inside `util.sld` with a clear "Phase D should remove this when LispKit/host exposes X under (scheme …)" annotation. Anything else: investigate and route via util.

- [ ] **11.2 Audit for stale `.scm` references in tests**

Run:

```bash
grep -rn 'core/state-machine\|core/event-dispatch\|core/keymap\|lib/util.scm\|lib/dsl.scm' Tests/
```

Expected: no output. Any match means a test bootstrap was missed in Tasks 5–7.

- [ ] **11.3 Audit for stray `(void)` in libraries**

Run:

```bash
grep -rn '(void)' Sources/Modaliser/Scheme/lib/modaliser/
```

Expected: no output. `(if #f #f)` is the R7RS-portable replacement.

- [ ] **11.4 Confirm `default-config.scm` still loads**

The `ConfigDslTests.defaultConfigSchemeLoadsWithoutErrors` test is the canary; run:

```bash
swift test --filter ConfigDslTests 2>&1 | tail -20
```

Expected: all pass.

- [ ] **11.5 Full suite**

```bash
swift test 2>&1 | tail -5
```

Expected: 0 failures.

- [ ] **11.6 Smoke-test the running app (manual)**

```bash
swift build && open .build/debug/Modaliser.app  ## or whatever produces the runnable bundle
```

If the project doesn't produce a `.app` from `swift build`, skip this step — handoff verification will run `scripts/install.sh` and confirm the running app loads the default config without errors. Either way, the verifier should confirm:

1. App launches without fatal Scheme errors in Console.app
2. Pressing the leader (F18) opens the modal overlay
3. Navigating to a registered key fires its action
4. Backspace and Escape behave correctly

If step 11.6 is deferred, **note that explicitly in the merge-readiness summary** so the reviewer/merger knows to do it before merging.

- [ ] **11.7 Final commit (if anything changed during 11.x)**

If audits 11.1–11.3 surface fixes, commit them as a single hygiene commit:

```bash
git add …
git commit -m "chore(modular-config): post-conversion cleanup

Address findings from the Phase B verification audit: stray (void)
calls, missed test bootstraps, etc."
```

---

## Out of scope (Phase C/D)

- Carving `default-config.scm` into per-app stdlib libraries (`(modaliser apps iterm)` etc.) — Phase C.
- Converting `ui/dom.scm`, `ui/css.scm`, `ui/overlay.scm`, `ui/chooser.scm` to libraries — Phase C.
- Converting `lib/terminal.scm`, `lib/web-search.scm`, `lib/ax-hints.scm` — Phase C/D.
- Eliminating any LispKit re-exports in `(modaliser util)` introduced as Phase B audit workarounds — Phase D's portability audit.
- Writing `docs/portability.md` summarising the user-facing surface — Phase D.

---

## Self-review (run before requesting code review)

1. **Spec coverage:** every Phase B bullet in `docs/superpowers/specs/2026-05-16-modular-config-architecture-design.md` (Phase B section) is addressed by a task in this plan. ✅
2. **No placeholders:** every step has either runnable code or a `grep`/command with expected output. Ellipses appear only inside Scheme bodies labeled `…body of <existing file>…` — that's intentional (the executor copies from the live file), and the **audit notes** specify what to check while copying.
3. **Type consistency:** function names (`set-show-overlay!`, `set-overlay-open!`, `chooser-open?` etc.) are used identically across Tasks 4–6. State-machine's export list (Task 5) matches the names referenced in event-dispatch and dsl (Tasks 6–7).
4. **Task ordering:** Task 1 fixes the test-time scheme-base resolution before any library that imports `(scheme base)` is created. Task 4's setter refactor (still `.scm`) is verified by tests before Task 5 freezes that shape into a library. Each conversion task can leave the suite green before the next starts.
