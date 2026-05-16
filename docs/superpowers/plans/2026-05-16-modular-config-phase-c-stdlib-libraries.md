# Phase C — Carve `default-config.scm` into stdlib libraries

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the reusable per-app trees, window helpers, Spaces 1..N pattern, and leader conveniences out of `default-config.scm` into named `(modaliser …)` stdlib libraries that user configs can import and parameterize. The thinned `default-config.scm` becomes the first-run seed: a short tutorial that imports the new libraries and registers a small set of default trees.

**Architecture:** Each new stdlib library lives at `Sources/Modaliser/Scheme/lib/modaliser/<name>.sld` (or `lib/modaliser/apps/<name>.sld` for per-app trees), declared with `define-library`, importing only `(scheme …)` and other `(modaliser …)` libraries — no `(lispkit …)`. Builders return tree nodes; convenience procedures (`<name>-register!`) wrap `define-tree` for one-line usage. Per-app trees the iTerm builder needs from today's `include`d helpers (`lib/ax-hints.scm`, `lib/terminal.scm`) get library-ized first as `(modaliser ax-hints)` and `(modaliser terminal)`. The Google search / Find Apps / Find File / Find Window selectors in today's `default-config.scm` depend on the `ui/chooser.scm` and `lib/web-search.scm` helpers that have not been library-ized yet — those selectors STAY in the seed (their backing `web-search-handler`, `find-installed-apps`, etc. still resolve from the `include`-loaded helpers and native libraries), but the thin seed at the end calls them at the seed level rather than carving them into builders. `lib/web-search.scm` stays on the `include` path in `root.scm` so existing user configs continue to work.

**Starting point:** The bundled `default-config.scm` was just synced from the active user config (`~/.config/modaliser/config.scm`) per `feedback_config_sync.md`. That synced file is the canonical source of truth for everything we carve: leader keys (F18/F17, no shift modifier, arm-when-frontmost for Jump remote viewer), `the-color = "dodgerblue"` theme threaded through both the host header and iTerm pane chips, flat root-level launchers (no nested Applications group), digit pane labels `1..0` in iTerm, and the `'iterm-panes-focus` sticky-mode containing only hjkl. The new libraries' defaults reflect this canonical shape so a zero-arg `(iterm-register!)` etc. reproduces the user's current behaviour.

**Tech Stack:** Swift Package Manager (`swift build`, `swift test`), LispKit (R7RS Scheme), the layered library architecture established in Phase B.

**Spec reference:** [`docs/superpowers/specs/2026-05-16-modular-config-architecture-design.md`](../specs/2026-05-16-modular-config-architecture-design.md). **Kickoff reference:** [`docs/superpowers/prompts/2026-05-16-modular-config-kickoff.md`](../prompts/2026-05-16-modular-config-kickoff.md).

**Branch / worktree:** This work runs on branch `phase-c-stdlib-libraries` inside `.claude/worktrees/phase-c-stdlib-libraries/` (already created). All commit messages use the `feat(modular-config): …` / `fix(modular-config): …` / `test(modular-config): …` / `docs(modular-config): …` / `refactor(modular-config): …` prefix so phase progress stays greppable.

**Do NOT skip pre-commit hooks (`--no-verify`) or amend pushed commits.**

---

## Background a fresh worker needs

Read these before starting any task:

- The kickoff (`docs/superpowers/prompts/2026-05-16-modular-config-kickoff.md`) — what each phase covers.
- The spec (`docs/superpowers/specs/2026-05-16-modular-config-architecture-design.md`) — layered architecture, builder pattern, lookup-path semantics, `define-library` constraints.
- The user-libraries doc (`docs/user-libraries.md`) — how the library search path resolves and how `include` vs `import` differ. The Phase C work will UPDATE this doc to reflect the new stdlib libraries.
- The current `Sources/Modaliser/Scheme/default-config.scm` — this plan moves chunks of it into libraries.
- The existing Phase B libraries under `Sources/Modaliser/Scheme/lib/modaliser/` — `dsl.sld`, `state-machine.sld`, `event-dispatch.sld`, `keymap.sld`, `util.sld`. These are the style template: explicit `define-library`, explicit `export`, imports listed individually, the `(begin …)` body containing the actual definitions.

### Library exports and native bindings the new libraries will use

| Need | Comes from |
|---|---|
| `key`, `key-range`, `group`, `selector`, `action`, `define-tree`, `set-leader!`, `set-host-header!`, `set-overlay-delay!`, `modifier-symbols->mask`, `set-theme!` | `(modaliser dsl)` |
| `enter-mode!`, `register-tree!`, `lookup-tree`, `MOD-CMD`/`MOD-SHIFT`/etc. constants | `(modaliser state-machine)` (constants are in `(modaliser keyboard)`) |
| `set-local-context-suffix!` | `(modaliser event-dispatch)` |
| `alist-ref`, `props->alist`, `string-join`, `read-file-text`, `log`, `string-split`, `string-trim` | `(modaliser util)` |
| `string-contains?` | **Add** to `(modaliser util)` in Task 0 (wraps LispKit's `string-contains` to return a bool) |
| `run-shell`, `run-shell-async` | `(modaliser shell)` |
| `launch-app`, `activate-app`, `open-url`, `find-installed-apps`, `reveal-in-finder`, `open-with` | `(modaliser app)` |
| `send-keystroke`, `start-keyboard-capture!` | `(modaliser keyboard)` |
| `list-windows`, `focus-window`, `center-window`, `move-window`, `toggle-fullscreen`, `restore-window` | `(modaliser window)` |
| `ax-find-elements`, `ax-find-elements-named` | `(modaliser accessibility)` |
| `hints-show`, `hints-hide` | `(modaliser hints)` |
| `set-clipboard!` | `(modaliser pasteboard)` |
| `relaunch!`, `quit!`, `ensure-permissions!`, `set-activation-policy!`, `create-status-item!` | `(modaliser lifecycle)` |
| `http-get` | `(modaliser http)` |

### Builder-pattern convention

Spec § "Parameterization pattern for stdlib libraries". Each library exports BOTH:

1. A builder procedure that returns a tree node (e.g. `iterm-pane-tree`, `safari-tree`, `window-actions-tree`, `spaces-1-9-binding`). Pure: no side effects, no `define-tree` call inside.
2. A convenience procedure (`<thing>-register!`) that calls `define-tree` with the builder's output under a sensible default scope. Takes the same alist options as the builder.

Both accept options as a flat keyword-style alist of pairs after the first positional argument: e.g.
```scheme
(safari-register! 'extra-bindings (list (key "/" "Search" …)))
```
Use `props->alist` (from `(modaliser util)`) to parse the rest-arg list, or look options up with `alist-ref` after pairing — see existing patterns in `set-leader!` in `dsl.sld:159-176`.

For convenience-procedure naming, mirror existing setter style: imperative-form with a `!`. The builder is a plain noun.

### Test pattern

Existing pattern (see `Tests/ModaliserTests/ModaliserDslLibraryTests.swift`):

```swift
@Test func somethingHappens() throws {
    let engine = try SchemeEngine()
    try engine.evaluate("(import (modaliser dsl) (modaliser apps safari))")
    try engine.evaluate("(safari-register!)")
    #expect(try engine.evaluate("(lookup-tree \"com.apple.Safari\")") != .false)
}
```

For builder tests, construct the node and check its alist via `assoc`. For tree-registration tests, call `lookup-tree` and assert it returns a non-false value.

### Package.swift resource copying

`Package.swift` already copies `Sources/Modaliser/Scheme/` recursively as a bundle resource (verified by Phase B's library files being loadable). No changes needed; new `.sld` files dropped under `Sources/Modaliser/Scheme/lib/modaliser/` are picked up automatically.

---

## Verification commands used throughout

- Build: `swift build` — should complete with no errors.
- Tests: `swift test` — full suite green. Specific test: `swift test --filter <TestName>`.
- Install (manual end-to-end): `./scripts/install.sh` then launch Modaliser from `/Applications`; per memory `feedback_install_flow.md`, source changes need a real install.
- Lint for stray `(lispkit …)` in user-facing libraries: `grep -r '(lispkit ' Sources/Modaliser/Scheme/lib/modaliser/` — should remain empty for the new libraries (existing `(modaliser util)` has documented Phase-D-cleanup imports of `(lispkit hashtable)` / `(lispkit string)` — leave those alone).
- Seed flow: with no `~/.config/modaliser/config.scm`, launching Modaliser should copy the new thin `default-config.scm` to that path; the user then sees a working modal.

---

# Tasks

Tasks 0 through 6 each create one library (or a small util addition) and are independently shippable. Tasks 7 and 8 thin `default-config.scm` and wire root. Task 9 verifies end-to-end. Each task ends with its own commit. Multiple libraries from Tasks 1–6 could in principle parallelize, but executing in listed order is safer because later libraries reference earlier ones in the test-import lines.

---

### Task 0: Add `string-contains?` to `(modaliser util)`

**Files:**
- Modify: `Sources/Modaliser/Scheme/lib/modaliser/util.sld`
- Create: `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift`

The iTerm context-suffix probe in today's `default-config.scm` uses `string-contains?` (predicate). LispKit's `(lispkit string)` exposes `string-contains` returning either an index or `#f`. Wrap it as a true predicate inside `(modaliser util)` so `(modaliser apps iterm)` (Task 6) imports a single helper without pulling `(lispkit string)` into a user-facing library.

- [ ] **Step 1: Write the failing test.**

Create `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser util) library")
struct ModaliserUtilLibraryTests {
    @Test func stringContainsPredicateMatches() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(string-contains? \"hello world\" \"world\")") == .true)
    }

    @Test func stringContainsPredicateMisses() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(string-contains? \"hello world\" \"xyz\")") == .false)
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails.**

```
swift test --filter ModaliserUtilLibraryTests
```

Expected: failure with `string-contains?: unbound identifier` (or similar — the predicate doesn't exist yet).

- [ ] **Step 3: Add `string-contains?` to the library.**

Edit `Sources/Modaliser/Scheme/lib/modaliser/util.sld`. Add `string-contains?` to the `export` list (place it next to `string-split string-trim`) and add this definition inside the existing `(begin …)` body, near the other string helpers:

```scheme
;; (string-contains? haystack needle) → boolean
;;
;; True iff NEEDLE appears anywhere in HAYSTACK. Wraps LispKit's
;; string-contains, which returns an index or #f. Phase D will swap to
;; SRFI 13's string-contains (also returns index/#f) and provide ? via
;; a tiny shim.
(define (string-contains? haystack needle)
  (if (string-contains haystack needle) #t #f))
```

- [ ] **Step 4: Run the test to confirm it passes.**

```
swift test --filter ModaliserUtilLibraryTests
```

Expected: both tests pass. Full suite remains green:
```
swift test
```

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/lib/modaliser/util.sld Tests/ModaliserTests/ModaliserUtilLibraryTests.swift
git commit -m "feat(modular-config): string-contains? predicate in (modaliser util)"
```

---

### Task 1: Library-ize `(modaliser terminal)`

**Files:**
- Create: `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
- Delete (later, in Task 8): `Sources/Modaliser/Scheme/lib/terminal.scm` and its `include` in `root.scm`
- Create: `Tests/ModaliserTests/ModaliserTerminalLibraryTests.swift`

Convert the current `lib/terminal.scm` (probed at startup time today via an `include` in `root.scm`) into a proper R7RS library. Same procedures, same semantics. Imports `(modaliser shell)` for `run-shell` and `(modaliser util)` for `string-split` / `string-trim`.

The current file's contents are reproduced 1:1 inside `(begin …)`; the surrounding `define-library` form adds explicit exports and imports.

- [ ] **Step 1: Write the failing test.**

Create `Tests/ModaliserTests/ModaliserTerminalLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser terminal) library")
struct ModaliserTerminalLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")
        // procedure? on each exported name
        for name in [
            "focused-iterm-tty",
            "tty-foreground-command",
            "focused-terminal-foreground-command",
            "list-nvim-sockets",
            "nvim-server-focused?",
            "focused-nvim-socket",
            "nvim-remote-send",
            "nvim-remote-expr",
            "modaliser-tool-path"
        ] {
            // modaliser-tool-path is a string, the rest are procedures.
            // Just verify each is bound (no exception).
            _ = try engine.evaluate(name)
        }
    }
}
```

- [ ] **Step 2: Run the test, confirm it fails.**

```
swift test --filter ModaliserTerminalLibraryTests
```

Expected: error resolving `(modaliser terminal)` — the library doesn't exist yet.

- [ ] **Step 3: Create the library.**

Create `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`:

```scheme
;; (modaliser terminal) — Probe what's running in the focused terminal pane.
;;
;; The kernel truth for "what is receiving keystrokes in the terminal" is
;; the foreground process group of the controlling tty. `ps -o tpgid` gives
;; that; the row whose pgid equals the tty's tpgid is the foreground process.
;; Full-screen TUIs (zellij, tmux, vim, less, htop, lazygit) all show up this
;; way, so a single probe answers "is X running in the focused pane" for any X.

(define-library (modaliser terminal)
  (export focused-iterm-tty
          tty-foreground-command
          focused-terminal-foreground-command
          modaliser-tool-path
          list-nvim-sockets
          nvim-server-focused?
          focused-nvim-socket
          nvim-remote-send
          nvim-remote-expr)
  (import (scheme base)
          (modaliser shell)
          (modaliser util))
  (begin

    ;; Return the pty path of iTerm2's focused session (e.g. "/dev/ttys003"),
    ;; or #f if iTerm2 is not running or the query fails.
    ;; The `is running` guard prevents the naked `tell application "iTerm2"`
    ;; from auto-launching iTerm via Launch Services.
    (define (focused-iterm-tty)
      (let* ((script
               (string-append
                 "if application \"iTerm2\" is running then "
                 "tell application \"iTerm2\" to "
                 "tell current session of current window to get tty"))
             (out (run-shell
                    (string-append "osascript -e '" script "' 2>/dev/null")))
             (trimmed (string-trim out)))
        (if (string=? trimmed "") #f trimmed)))

    ;; Given a pty path like "/dev/ttys003", return the command string of
    ;; the foreground process on that tty, or #f if none.
    ;; `ps -t <name>` expects the short name without /dev/.
    (define (tty-foreground-command tty)
      (let* ((slash (string-split tty "/"))
             (name  (if (null? slash) tty (list-ref slash (- (length slash) 1))))
             (cmd   (string-append
                      "ps -t " name " -o pgid=,tpgid=,command= | "
                      "awk '$1==$2 { for (i=3; i<=NF; i++) "
                      "printf \"%s%s\", $i, (i==NF?\"\":\" \"); exit }'"))
             (out   (run-shell cmd))
             (trimmed (string-trim out)))
        (if (string=? trimmed "") #f trimmed)))

    ;; Command string of the foreground process in the focused terminal pane,
    ;; or #f. Currently iTerm2-only.
    (define (focused-terminal-foreground-command)
      (cond
        ((focused-iterm-tty) => tty-foreground-command)
        (else #f)))

    ;; PATH prefix for subprocesses that need Homebrew/usr/sbin tools.
    ;; GUI-launched Modaliser inherits a minimal path_helper PATH.
    (define modaliser-tool-path
      "/opt/homebrew/bin:/usr/local/bin:/usr/sbin")

    ;; Unix-socket paths bound by running nvim processes.
    (define (list-nvim-sockets)
      (let ((out (run-shell
                   (string-append
                     "export PATH=" modaliser-tool-path ":$PATH; "
                     "for pid in $(pgrep -x nvim); do "
                     "  lsof -p $pid -a -U -Fn 2>/dev/null "
                     "  | awk '/^n\\// {print substr($0,2)}'; "
                     "done | sort -u"))))
        (let loop ((lines (string-split out "\n")) (acc '()))
          (cond
            ((null? lines) (reverse acc))
            (else
              (let ((s (string-trim (car lines))))
                (loop (cdr lines)
                      (if (string=? s "") acc (cons s acc)))))))))

    ;; True if the nvim at SOCK reports g:modaliser_focused == 1.
    (define (nvim-server-focused? sock)
      (let ((out (run-shell
                   (string-append
                     "export PATH=" modaliser-tool-path ":$PATH; "
                     "nvim --server " sock
                     " --remote-expr 'get(g:, \"modaliser_focused\", 0)'"
                     " </dev/null 2>/dev/null"))))
        (string=? (string-trim out) "1")))

    ;; Socket of the focused nvim, or #f.
    (define (focused-nvim-socket)
      (let loop ((socks (list-nvim-sockets)))
        (cond
          ((null? socks) #f)
          ((nvim-server-focused? (car socks)) (car socks))
          (else (loop (cdr socks))))))

    (define (nvim-remote-send keys)
      (let ((sock (focused-nvim-socket)))
        (when sock
          (run-shell
            (string-append "export PATH=" modaliser-tool-path ":$PATH; "
                           "nvim --server " sock
                           " --remote-send '" keys "'"
                           " </dev/null 2>/dev/null")))))

    (define (nvim-remote-expr expr)
      (let ((sock (focused-nvim-socket)))
        (if sock
          (string-trim
            (run-shell
              (string-append "export PATH=" modaliser-tool-path ":$PATH; "
                             "nvim --server " sock
                             " --remote-expr '" expr "'"
                             " </dev/null 2>/dev/null")))
          #f)))))
```

> Don't delete `lib/terminal.scm` or remove its `include` line from `root.scm` yet — that happens in Task 8 once everything that depends on it has migrated to the library. Until then, the file existing duplicates the bindings, which is fine because root.scm's `include` runs at the top level and the library is imported only by other libraries that wouldn't see the top-level bindings anyway.

- [ ] **Step 4: Confirm test passes.**

```
swift test --filter ModaliserTerminalLibraryTests
swift test
```

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/lib/modaliser/terminal.sld Tests/ModaliserTests/ModaliserTerminalLibraryTests.swift
git commit -m "feat(modular-config): (modaliser terminal) library"
```

---

### Task 2: Library-ize `(modaliser ax-hints)`

**Files:**
- Create: `Sources/Modaliser/Scheme/lib/modaliser/ax-hints.sld`
- Create: `Tests/ModaliserTests/ModaliserAxHintsLibraryTests.swift`
- Delete (later, in Task 8): `Sources/Modaliser/Scheme/lib/ax-hints.scm` and its `include` in `root.scm`

Convert today's `lib/ax-hints.scm`. The library imports `(modaliser dsl)` for `key` (used by `ax-target-bindings`) and `(modaliser accessibility)` for `ax-find-elements`. Body identical to today's file.

- [ ] **Step 1: Write the failing test.**

Create `Tests/ModaliserTests/ModaliserAxHintsLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser ax-hints) library")
struct ModaliserAxHintsLibraryTests {
    @Test func labelPairsTruncatesAtMinLength() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate("(define ps (label-pairs '(\"a\" \"b\" \"c\") '(1 2)))")
        #expect(try engine.evaluate("(length ps)").asInt() == 2)
        #expect(try engine.evaluate("(car (car ps))").asString() == "a")
        #expect(try engine.evaluate("(cdr (car ps))").asInt() == 1)
    }

    @Test func axTargetHintsHandlesEmpty() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        #expect(try engine.evaluate("(null? (ax-target-hints '() '()))") == .true)
    }
}
```

(Adjust `.asInt()` to whatever the existing test helper is — match the rest of the test suite. If only `.asString()` exists, compare via `engine.evaluate("(= (length ps) 2)") == .true` instead.)

- [ ] **Step 2: Run, confirm failure.**

```
swift test --filter ModaliserAxHintsLibraryTests
```

Expected: `(modaliser ax-hints)` not found.

- [ ] **Step 3: Create the library.**

Create `Sources/Modaliser/Scheme/lib/modaliser/ax-hints.sld`:

```scheme
;; (modaliser ax-hints) — AX-based hint flows for any app.
;;
;; Compose these primitives in your config to wire up "see a chip, type a
;; letter, focus that thing" UX over any app's accessible elements:
;;
;;   1. ax-find-labelled  — query AX for elements of a role in an app's
;;                          focused window; pair them with labels in
;;                          reading order. Returns ((label . elem) ...).
;;   2. ax-target-bindings — convert that list into (key ...) bindings
;;                           that fire your action with the AX handle.
;;   3. ax-target-hints   — convert that list into the hint-list shape
;;                          (modaliser hints) hints-show consumes.

(define-library (modaliser ax-hints)
  (export default-hint-options
          label-pairs
          ax-find-labelled
          ax-target-bindings
          ax-target-hints)
  (import (scheme base)
          (modaliser dsl)
          (modaliser accessibility))
  (begin

    ;; Sensible smallish defaults. Override per-tree by passing your own
    ;; opts alist to ax-target-hints.
    ;;
    ;; Keys (all optional):
    ;;   offset-x-frac, offset-y-frac  — chip top-left as fraction of element size
    ;;   font-size, padding, corner-radius, border-width  — pixels
    ;;   color, background, border-color  — CSS colour
    (define default-hint-options
      (list (cons 'offset-x-frac 0.02)
            (cons 'offset-y-frac 0.02)
            (cons 'font-size 24)
            (cons 'padding 6)
            (cons 'corner-radius 6)
            (cons 'color "#000000")
            (cons 'background "#ffffff")
            (cons 'border-width 1)
            (cons 'border-color "#000000")))

    ;; (label-pairs labels elements) → ((label . elem) ...). Truncates at min.
    (define (label-pairs labels elements)
      (let loop ((ls labels) (es elements) (acc '()))
        (cond
          ((or (null? ls) (null? es)) (reverse acc))
          (else (loop (cdr ls) (cdr es)
                      (cons (cons (car ls) (car es)) acc))))))

    (define (hint-opt opts key default)
      (let ((p (assoc key opts)))
        (if p (cdr p) default)))

    ;; (ax-find-labelled bundle-id role labels) → ((label . elem-alist) ...)
    (define (ax-find-labelled bundle-id role labels)
      (label-pairs labels (ax-find-elements bundle-id role)))

    ;; (ax-target-bindings labelled-elements label-prefix action-fn) → (key …)
    (define (ax-target-bindings labelled-elements label-prefix action-fn)
      (let loop ((ps labelled-elements) (acc '()))
        (if (null? ps)
          (reverse acc)
          (let* ((entry (car ps))
                 (label (car entry))
                 (elem  (cdr entry))
                 (handle (cdr (assoc 'handle elem))))
            (loop (cdr ps)
                  (cons (key label
                             (string-append label-prefix label)
                             (lambda () (action-fn handle)))
                        acc))))))

    ;; (ax-target-hints labelled-elements opts) → list ready for hints-show
    (define (ax-target-hints labelled-elements opts)
      (let* ((offx-frac (hint-opt opts 'offset-x-frac 0.02))
             (offy-frac (hint-opt opts 'offset-y-frac 0.02))
             (font-size (hint-opt opts 'font-size 24))
             (padding   (hint-opt opts 'padding 6))
             (corner    (hint-opt opts 'corner-radius 6))
             (color     (hint-opt opts 'color "#000000"))
             (background (hint-opt opts 'background "#ffffff"))
             (border-width (hint-opt opts 'border-width 0))
             (border-color (hint-opt opts 'border-color color))
             (chip-size (+ font-size (* 2 padding))))
        (let loop ((ps labelled-elements) (acc '()))
          (if (null? ps)
            (reverse acc)
            (let* ((entry (car ps))
                   (label (car entry))
                   (elem  (cdr entry))
                   (px (cdr (assoc 'x elem)))
                   (py (cdr (assoc 'y elem)))
                   (pw (cdr (assoc 'w elem)))
                   (ph (cdr (assoc 'h elem)))
                   (hx (+ px (exact (round (* pw offx-frac)))))
                   (hy (+ py (exact (round (* ph offy-frac))))))
              (loop (cdr ps)
                    (cons (list (cons 'label label)
                                (cons 'x hx) (cons 'y hy)
                                (cons 'w chip-size) (cons 'h chip-size)
                                (cons 'color color)
                                (cons 'background background)
                                (cons 'font-size font-size)
                                (cons 'padding padding)
                                (cons 'corner-radius corner)
                                (cons 'border-width border-width)
                                (cons 'border-color border-color))
                          acc)))))))))
```

- [ ] **Step 4: Confirm tests pass.**

```
swift test --filter ModaliserAxHintsLibraryTests
swift test
```

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/lib/modaliser/ax-hints.sld Tests/ModaliserTests/ModaliserAxHintsLibraryTests.swift
git commit -m "feat(modular-config): (modaliser ax-hints) library"
```

---

### Task 3: `(modaliser window-actions)` — window helpers as a library

**Files:**
- Create: `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld`
- Create: `Tests/ModaliserTests/ModaliserWindowActionsLibraryTests.swift`

A builder that returns the per-window-action group node (third/half/center/maximise/restore + window switcher). Plus a convenience that registers it under the `'global` tree at a configurable key (default `"w"` → group "Windows").

API:
```scheme
(window-actions-group [opts...])         ; returns a (group "w" "Windows" …) node
(window-actions-register-global! [opts...]) ; adds it to the 'global tree by re-registering ?? — see note
```

**Design note re registering inside an existing tree.** `define-tree` REGISTERS a fresh tree (replaces if already registered). It does NOT splice children into an existing tree. The cleanest builder pattern is:

- The builder (`window-actions-group`) returns a `group` node.
- The convenience (`window-actions-register!`) takes a `tree-scope` option (default `'global`) and an `under-key` (default `"w"`), then registers a tree at that scope whose only child is the windows group.

This is suboptimal for combining with other top-level keys at `'global`. Real seed usage threads it inline: the user's `config.scm` calls `(window-actions-group)` and splices it among other `(key …)` siblings inside one `(define-tree 'global …)`. So the convenience procedure is primarily for "I want just Windows under F18, nothing else" testing scenarios. Document this in the library's header comment.

Options the builder accepts:
- `'group-key` (default `"w"`) — the key under which the group sits in the parent tree (only used to set the group's own `key`).
- `'group-label` (default `"Windows"`) — the group label.
- `'include-switcher?` (default `#t`) — include the "Switch Window" selector child.
- `'extra-bindings` (default `'()`) — list of additional `key`/`group`/`selector` nodes spliced after the standard set.

Bindings included (verbatim from today's default-config.scm `(group "w" "Windows" …)`):
- `"d"` First Third — `(move-window 0 0 1/3 1)`
- `"D"` First Third Top — `(move-window 0 0 1/3 1/2)`
- `"C"` First Third Bottom — `(move-window 0 1/2 1/3 1/2)`
- `"f"` Center Third — `(move-window 1/3 0 1/3 1)`
- `"F"` Center Third Top — `(move-window 1/3 0 1/3 1/2)`
- `"V"` Center Third Bottom — `(move-window 1/3 1/2 1/3 1/2)`
- `"g"` Last Third — `(move-window 2/3 0 1/3 1)`
- `"G"` Last Third Top — `(move-window 2/3 0 1/3 1/2)`
- `"B"` Last Third Bottom — `(move-window 2/3 1/2 1/3 1/2)`
- `"e"` First Two Thirds — `(move-window 0 0 2/3 1)`
- `"t"` Last Two Thirds — `(move-window 1/3 0 2/3 1)`
- `"c"` Center — `(center-window)`
- `"m"` Maximise — `(toggle-fullscreen)`
- `"r"` Restore — `(restore-window)`
- `"s"` Select Window (selector) — when `include-switcher?` is `#t`.

- [ ] **Step 1: Write the failing test.**

Create `Tests/ModaliserTests/ModaliserWindowActionsLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser window-actions) library")
struct ModaliserWindowActionsLibraryTests {
    @Test func groupBuilderReturnsGroupNode() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(define g (window-actions-group))")
        #expect(try engine.evaluate("(group? g)") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'key g))").asString() == "w")
        #expect(try engine.evaluate("(cdr (assoc 'label g))").asString() == "Windows")
    }

    @Test func groupBuilderHonoursGroupKeyOption() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser window-actions))")
        try engine.evaluate("(define g (window-actions-group 'group-key \"W\" 'group-label \"Win\"))")
        #expect(try engine.evaluate("(cdr (assoc 'key g))").asString() == "W")
        #expect(try engine.evaluate("(cdr (assoc 'label g))").asString() == "Win")
    }

    @Test func includeSwitcherFalseDropsSwitchWindowChild() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (window-actions-group 'include-switcher? #f))
          (define children (cdr (assoc 'children g)))
          (define switcher? (lambda (n) (and (selector? n) (equal? (cdr (assoc 'key n)) "s"))))
          (define has-switcher (let loop ((cs children))
                                 (cond ((null? cs) #f)
                                       ((switcher? (car cs)) #t)
                                       (else (loop (cdr cs))))))
        """)
        #expect(try engine.evaluate("has-switcher") == .false)
    }

    @Test func registerCreatesLookupableTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(window-actions-register! 'tree-scope 'wa-test)")
        #expect(try engine.evaluate("(lookup-tree \"wa-test\")") != .false)
    }
}
```

(Replace `.asString()` / `.asInt()` calls with whatever the existing Swift test helpers use — match `ModaliserDslLibraryTests.swift`. The `group?` and `selector?` predicates are exported by `(modaliser state-machine)`.)

- [ ] **Step 2: Run, confirm failure.**

```
swift test --filter ModaliserWindowActionsLibraryTests
```

Expected: library not found.

- [ ] **Step 3: Create the library.**

Create `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld`:

```scheme
;; (modaliser window-actions) — window-management binding builder.
;;
;; Returns a group node containing the standard third/half/center moves
;; plus maximise/restore/center, and (optionally) a window switcher.
;; Compose with other groups in your config:
;;
;;   (import (modaliser dsl) (modaliser window-actions))
;;   (define-tree 'global
;;     (window-actions-group)
;;     (key "i" "iTerm" (lambda () (launch-app "iTerm"))))
;;
;; The convenience (window-actions-register!) registers a standalone
;; tree containing only the windows group — useful when you want
;; window helpers under a dedicated leader (e.g. its own tree-scope).

(define-library (modaliser window-actions)
  (export window-actions-group
          window-actions-register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser window))
  (begin

    (define (window-actions-group . opts)
      (let* ((alist        (props->alist opts))
             (group-key    (alist-ref alist 'group-key "w"))
             (group-label  (alist-ref alist 'group-label "Windows"))
             (include-sw?  (alist-ref alist 'include-switcher? #t))
             (extra        (alist-ref alist 'extra-bindings '()))
             (core
               (list
                 (key "d" "First Third"
                   (lambda () (move-window 0 0 1/3 1)))
                 (key "D" "First Third Top"
                   (lambda () (move-window 0 0 1/3 1/2)))
                 (key "C" "First Third Bottom"
                   (lambda () (move-window 0 1/2 1/3 1/2)))
                 (key "f" "Center Third"
                   (lambda () (move-window 1/3 0 1/3 1)))
                 (key "F" "Center Third Top"
                   (lambda () (move-window 1/3 0 1/3 1/2)))
                 (key "V" "Center Third Bottom"
                   (lambda () (move-window 1/3 1/2 1/3 1/2)))
                 (key "g" "Last Third"
                   (lambda () (move-window 2/3 0 1/3 1)))
                 (key "G" "Last Third Top"
                   (lambda () (move-window 2/3 0 1/3 1/2)))
                 (key "B" "Last Third Bottom"
                   (lambda () (move-window 2/3 1/2 1/3 1/2)))
                 (key "e" "First Two Thirds"
                   (lambda () (move-window 0 0 2/3 1)))
                 (key "t" "Last Two Thirds"
                   (lambda () (move-window 1/3 0 2/3 1)))
                 (key "c" "Center"
                   (lambda () (center-window)))
                 (key "m" "Maximise"
                   (lambda () (toggle-fullscreen)))
                 (key "r" "Restore"
                   (lambda () (restore-window)))))
             (switcher
               (if include-sw?
                 (list
                   (selector "s" "Select Window"
                     'prompt "Select window…"
                     'source list-windows
                     'on-select focus-window
                     'actions
                       (list
                         (action "Focus" 'description "Select window" 'key 'primary
                           'run (lambda (c) (focus-window c))))))
                 '())))
        (apply group group-key group-label
               (append core switcher extra))))

    (define (window-actions-register! . opts)
      (let* ((alist (props->alist opts))
             (scope (alist-ref alist 'tree-scope 'global)))
        (define-tree scope (apply window-actions-group opts))))))
```

> **`props->alist` check:** look at the existing usage in `set-leader!` (`dsl.sld` near line 159) to confirm the shape — `props->alist` consumes a flat list `(k1 v1 k2 v2 …)` and returns `((k1 . v1) (k2 . v2) …)`. If the export from `(modaliser util)` doesn't match this, adjust `(props->alist opts)` to a hand-rolled pair-loop instead.

- [ ] **Step 4: Confirm tests pass.**

```
swift test --filter ModaliserWindowActionsLibraryTests
swift test
```

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld Tests/ModaliserTests/ModaliserWindowActionsLibraryTests.swift
git commit -m "feat(modular-config): (modaliser window-actions) library"
```

---

### Task 4: `(modaliser space-switching)` — Spaces 1..N range builder

**Files:**
- Create: `Sources/Modaliser/Scheme/lib/modaliser/space-switching.sld`
- Create: `Tests/ModaliserTests/ModaliserSpaceSwitchingLibraryTests.swift`

Today's `(key-range "1.." "Goto Space <n>" '("1".."9") (lambda (k) (send-keystroke '(ctrl) k)))` factored into a builder. Options:

- `'keys` — list of single-character strings; defaults to `'("1" "2" "3" "4" "5" "6" "7" "8" "9")`.
- `'display-key` — overlay key cell; defaults to `(string-append (car keys) ".." (last-elem keys))` (e.g. `"1..9"`). Pass `'display-key "1.."` to match the canonical seed's "Goto Space" row.
- `'label` — overlay label; defaults to `"Goto Space <n>"` (matches the synced personal config).
- `'modifiers` — symbol list for the keystroke; defaults to `'(ctrl)`.

API:
```scheme
(spaces-range-binding [opts...])           ; returns a (key-range …) node
(spaces-1-9-register! [opts...])           ; convenience: registers under 'global as a single-child tree
```

The convenience `spaces-1-9-register!` is mostly for tests / minimal configs — real usage splices `(spaces-range-binding)` into a larger `define-tree 'global` call.

- [ ] **Step 1: Write the failing test.**

Create `Tests/ModaliserTests/ModaliserSpaceSwitchingLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser space-switching) library")
struct ModaliserSpaceSwitchingLibraryTests {
    @Test func defaultBuilderReturnsKeyRangeOneToNine() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser space-switching))")
        try engine.evaluate("(define n (spaces-range-binding))")
        #expect(try engine.evaluate("(range-command? n)") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'key n))").asString() == "1..9")
        #expect(try engine.evaluate("(cdr (assoc 'label n))").asString() == "Goto Space <n>")
        #expect(try engine.evaluate("(length (cdr (assoc 'keys n)))").asInt() == 9)
    }

    @Test func keysOptionOverridesRange() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser space-switching))")
        try engine.evaluate("(define n (spaces-range-binding 'keys '(\"1\" \"2\" \"3\")))")
        #expect(try engine.evaluate("(cdr (assoc 'key n))").asString() == "1..3")
    }

    @Test func displayKeyOptionOverridesDefault() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser space-switching))")
        try engine.evaluate("(define n (spaces-range-binding 'display-key \"1..\"))")
        #expect(try engine.evaluate("(cdr (assoc 'key n))").asString() == "1..")
    }
}
```

- [ ] **Step 2: Run, confirm failure.**

```
swift test --filter ModaliserSpaceSwitchingLibraryTests
```

- [ ] **Step 3: Create the library.**

Create `Sources/Modaliser/Scheme/lib/modaliser/space-switching.sld`:

```scheme
;; (modaliser space-switching) — Bind digits 1..N to macOS Space switching.
;;
;; Requires "Mission Control → Switch to Desktop N" enabled in
;; System Settings → Keyboard → Keyboard Shortcuts. The default sends
;; Ctrl+<n>; pass 'modifiers '(ctrl) (or whatever you prefer) to change.
;;
;; Returns a (key-range …) node that displays as one overlay row, e.g.
;; "1..9 Space <n>". Splice into your tree:
;;
;;   (define-tree 'global
;;     (spaces-range-binding)
;;     ...)

(define-library (modaliser space-switching)
  (export spaces-range-binding
          spaces-1-9-register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser keyboard))
  (begin

    (define default-keys
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9"))

    (define (last-elem lst)
      (cond
        ((null? lst) (error "spaces-range-binding: empty keys list"))
        ((null? (cdr lst)) (car lst))
        (else (last-elem (cdr lst)))))

    (define (spaces-range-binding . opts)
      (let* ((alist        (props->alist opts))
             (keys         (alist-ref alist 'keys default-keys))
             (label        (alist-ref alist 'label "Goto Space <n>"))
             (modifiers    (alist-ref alist 'modifiers '(ctrl)))
             (default-disp (string-append (car keys) ".." (last-elem keys)))
             (display      (alist-ref alist 'display-key default-disp)))
        (key-range display label keys
          (lambda (k) (send-keystroke modifiers k)))))

    (define (spaces-1-9-register! . opts)
      (let* ((alist (props->alist opts))
             (scope (alist-ref alist 'tree-scope 'global)))
        (define-tree scope (apply spaces-range-binding opts))))))
```

- [ ] **Step 4: Confirm tests pass.**

```
swift test --filter ModaliserSpaceSwitchingLibraryTests
swift test
```

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/lib/modaliser/space-switching.sld Tests/ModaliserTests/ModaliserSpaceSwitchingLibraryTests.swift
git commit -m "feat(modular-config): (modaliser space-switching) library"
```

---

### Task 5: `(modaliser leader)` — leader-key conveniences

**Files:**
- Create: `Sources/Modaliser/Scheme/lib/modaliser/leader.sld`
- Create: `Tests/ModaliserTests/ModaliserLeaderLibraryTests.swift`

Two thin helpers wrapping `set-leader!`:

```scheme
(set-global-leader! keycode [opts...])   ; (set-leader! 'global keycode opts...)
(set-local-leader!  keycode [opts...])   ; (set-leader! 'local  keycode opts...)
```

Plus a `set-leaders!` helper that takes a single options alist and configures both the global and local leader at the same keycode with shared options. This is what the seed config uses to demonstrate "I want the same leader on global and local, with these arm-when-frontmost apps":

```scheme
(set-leaders! 'global-keycode F18
              'local-keycode  F17
              'arm-when-frontmost '("com.p5sys.jump.mac.viewer")
              'modifiers '(shift))
```

Behind the scenes it calls `set-leader!` twice. Keep tiny — the value is the readable seed.

- [ ] **Step 1: Failing test.**

Create `Tests/ModaliserTests/ModaliserLeaderLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser leader) library")
struct ModaliserLeaderLibraryTests {
    @Test func setGlobalLeaderRegisters() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser keyboard) (modaliser leader))")
        try engine.evaluate("(set-global-leader! F18)")
        // No exception → success. We don't have a direct observable, so just
        // re-invoke (idempotent) and let the build/runtime confirm.
        try engine.evaluate("(set-global-leader! F18 'modifiers '(shift))")
    }

    @Test func setLeadersBothScopes() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser keyboard) (modaliser leader))")
        try engine.evaluate("""
          (set-leaders! 'global-keycode F18
                        'local-keycode  F17
                        'modifiers '(shift))
        """)
    }
}
```

(If there IS an introspection accessor for the currently-set leader, use it. Otherwise rely on "no exception".)

- [ ] **Step 2: Run, confirm failure.**

```
swift test --filter ModaliserLeaderLibraryTests
```

- [ ] **Step 3: Create the library.**

Create `Sources/Modaliser/Scheme/lib/modaliser/leader.sld`:

```scheme
;; (modaliser leader) — Small conveniences around set-leader!.
;;
;; (set-global-leader! keycode opts...)  — shorthand for set-leader! 'global.
;; (set-local-leader!  keycode opts...)  — shorthand for set-leader! 'local.
;; (set-leaders! opts...)                — set both scopes in one call. Options:
;;     'global-keycode, 'local-keycode   — keycodes (e.g. F18, F17)
;;     'modifiers, 'arm-when-frontmost   — passed verbatim to both calls
;;
;; The shared options apply to both scopes. If you need scope-asymmetric
;; options, call (set-global-leader! …) and (set-local-leader! …) directly.

(define-library (modaliser leader)
  (export set-global-leader!
          set-local-leader!
          set-leaders!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util))
  (begin

    (define (set-global-leader! keycode . opts)
      (apply set-leader! 'global keycode opts))

    (define (set-local-leader! keycode . opts)
      (apply set-leader! 'local keycode opts))

    (define (set-leaders! . opts)
      (let* ((alist           (props->alist opts))
             (global-keycode  (alist-ref alist 'global-keycode #f))
             (local-keycode   (alist-ref alist 'local-keycode #f))
             (shared
               (let loop ((kvs opts) (acc '()))
                 (cond
                   ((null? kvs) (reverse acc))
                   ((null? (cdr kvs))
                    (error "set-leaders!: odd keyword/value list"))
                   ((or (eq? (car kvs) 'global-keycode)
                        (eq? (car kvs) 'local-keycode))
                    (loop (cddr kvs) acc))
                   (else
                    (loop (cddr kvs)
                          (cons (cadr kvs) (cons (car kvs) acc))))))))
        (when global-keycode
          (apply set-leader! 'global global-keycode shared))
        (when local-keycode
          (apply set-leader! 'local local-keycode shared))))))
```

- [ ] **Step 4: Confirm tests pass.**

```
swift test --filter ModaliserLeaderLibraryTests
swift test
```

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/lib/modaliser/leader.sld Tests/ModaliserTests/ModaliserLeaderLibraryTests.swift
git commit -m "feat(modular-config): (modaliser leader) library"
```

---

### Task 6: `(modaliser apps safari)` and `(modaliser apps chrome)`

**Files:**
- Create: `Sources/Modaliser/Scheme/lib/modaliser/apps/safari.sld`
- Create: `Sources/Modaliser/Scheme/lib/modaliser/apps/chrome.sld`
- Create: `Tests/ModaliserTests/ModaliserAppsBrowsersLibraryTests.swift`

Both bundles ship a tiny browser-shortcut tree: Tabs (new / close / reopen) and Browser (focus address bar / find on page). Safari's existing version lives in `default-config.scm` lines 198–210. Chrome doesn't have a tree today; mirror Safari's structure but use the Chrome bundle ID `"com.google.Chrome"`.

Both export:
- `<app>-tree` — builder returning a tree's children list (a list of `(group …)` and `(key …)` nodes).
- `<app>-register!` — convenience that `(define-tree <bundle-id> …<children>)`.

Both accept `'extra-bindings` (list of additional nodes appended after the standard set).

- [ ] **Step 1: Failing test.**

Create `Tests/ModaliserTests/ModaliserAppsBrowsersLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser apps safari) library")
struct ModaliserAppsSafariLibraryTests {
    @Test func registerInstallsSafariTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps safari))")
        try engine.evaluate("(safari-register!)")
        #expect(try engine.evaluate("(lookup-tree \"com.apple.Safari\")") != .false)
    }

    @Test func treeBuilderReturnsList() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps safari))")
        try engine.evaluate("(define cs (safari-tree))")
        #expect(try engine.evaluate("(list? cs)") == .true)
        #expect(try engine.evaluate("(group? (car cs))") == .true)
    }
}

@Suite("(modaliser apps chrome) library")
struct ModaliserAppsChromeLibraryTests {
    @Test func registerInstallsChromeTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps chrome))")
        try engine.evaluate("(chrome-register!)")
        #expect(try engine.evaluate("(lookup-tree \"com.google.Chrome\")") != .false)
    }
}
```

- [ ] **Step 2: Run, confirm failure.**

```
swift test --filter ModaliserAppsBrowsersLibraryTests
```

- [ ] **Step 3: Create both libraries.**

Create `Sources/Modaliser/Scheme/lib/modaliser/apps/safari.sld`:

```scheme
;; (modaliser apps safari) — minimal Safari per-app tree.
;;
;;   (safari-register!)                 ; defaults
;;   (safari-register! 'extra-bindings (list (key "/" "Search" …)))

(define-library (modaliser apps safari)
  (export safari-tree
          safari-register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser keyboard))
  (begin

    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    (define (safari-tree . opts)
      (let* ((alist (props->alist opts))
             (extra (alist-ref alist 'extra-bindings '())))
        (append
          (list
            (group "t" "Tabs"
              (key "n" "New Tab"           (keystroke '(cmd) "t"))
              (key "w" "Close Tab"         (keystroke '(cmd) "w"))
              (key "r" "Reopen Closed Tab" (keystroke '(cmd shift) "t")))
            (group "b" "Browser"
              (key "l" "Focus Address Bar" (keystroke '(cmd) "l"))
              (key "f" "Find on Page"      (keystroke '(cmd) "f"))))
          extra)))

    (define (safari-register! . opts)
      (apply define-tree 'com.apple.Safari (apply safari-tree opts)))))
```

Create `Sources/Modaliser/Scheme/lib/modaliser/apps/chrome.sld`:

```scheme
;; (modaliser apps chrome) — minimal Google Chrome per-app tree.
;;
;;   (chrome-register!)                 ; defaults
;;   (chrome-register! 'extra-bindings (list (key "/" "Search" …)))

(define-library (modaliser apps chrome)
  (export chrome-tree
          chrome-register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser keyboard))
  (begin

    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    (define (chrome-tree . opts)
      (let* ((alist (props->alist opts))
             (extra (alist-ref alist 'extra-bindings '())))
        (append
          (list
            (group "t" "Tabs"
              (key "n" "New Tab"           (keystroke '(cmd) "t"))
              (key "w" "Close Tab"         (keystroke '(cmd) "w"))
              (key "r" "Reopen Closed Tab" (keystroke '(cmd shift) "t")))
            (group "b" "Browser"
              (key "l" "Focus Address Bar" (keystroke '(cmd) "l"))
              (key "f" "Find on Page"      (keystroke '(cmd) "f"))))
          extra)))

    (define (chrome-register! . opts)
      (apply define-tree 'com.google.Chrome (apply chrome-tree opts)))))
```

- [ ] **Step 4: Confirm tests pass.**

```
swift test --filter ModaliserAppsBrowsersLibraryTests
swift test
```

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/lib/modaliser/apps/safari.sld Sources/Modaliser/Scheme/lib/modaliser/apps/chrome.sld Tests/ModaliserTests/ModaliserAppsBrowsersLibraryTests.swift
git commit -m "feat(modular-config): (modaliser apps safari) and (modaliser apps chrome) libraries"
```

---

### Task 7: `(modaliser apps iterm)` — iTerm dynamic-pane builder + sticky focus mode

**Files:**
- Create: `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`
- Create: `Tests/ModaliserTests/ModaliserAppsItermLibraryTests.swift`

The biggest single library. Wraps the iTerm machinery from the synced `default-config.scm` (digit pane labels, dodgerblue-coloured chips, "f Focus" → sticky hjkl mode, transient tree without inline hjkl, copy/zoom/split-group at top level):

- Pane labels default `'("1" "2" "3" "4" "5" "6" "7" "8" "9" "0")`.
- iTerm chip options — generic-but-iTerm-sized defaults (the synced seed overrides background to `the-color`; the library default uses a stable colour so the library has no theme coupling).
- The `iterm-list-session-ids`, `iterm-select-session-by-id`, `iterm-pane-bindings`, `iterm-rebuild-tree!` helpers (renamed from `rebuild-iterm-tree!` for public export).
- The `'iterm-panes-focus` sticky-mode tree (pure hjkl, named "Focus" in the overlay).
- A `local-context-suffix` callback that picks the variant string ("/nvim", "/zellij", "/zellij+nvim", or #f).

**Tree shape (matches the synced seed exactly):**

Transient `'com.googlecode.iterm2` tree top-level children, in order:
- `key-range` over the labelled pane keys, display `"1.."` (or actual `(string-append (car bound) "..")`), label `"Focus Pane <n>"`, action focuses the AppleScript session by UUID.
- `(key "c" "Copy Mode" (keystroke '(cmd shift) "c"))`
- `(key "f" "Focus" (lambda () (enter-mode! 'iterm-panes-focus)))`
- `(key "z" "Toggle Zoom" (keystroke '(cmd shift) "return"))`
- `(group "x" "Split" (key "h" "Left" …) (key "j" "Down" …) (key "k" "Up" …) (key "l" "Right" …))` — `Cmd+Ctrl+Shift+h/j/k/l`.

(Note the absence of inline `hjkl` at the transient tree's top level — focus directions live only in the sticky `'iterm-panes-focus` mode.)

Sticky `'iterm-panes-focus` tree:
- Keyword args: `'sticky #t 'exit-on-unknown #t 'display-name "Focus"`.
- Children: only `(key "h" "Left" …)` `(key "j" "Down" …)` `(key "k" "Up" …)` `(key "l" "Right" …)` — `Cmd+Alt+arrow`.

Exports:
- `iterm-rebuild-tree!` — re-registers the `'com.googlecode.iterm2` tree from the current iTerm pane layout. Accepts opts (`'pane-labels`, `'hint-options`, `'sticky-mode-id`, `'pane-range-label`).
- `iterm-focus-mode-tree` — builder returning the children list for the sticky focus mode.
- `iterm-focus-mode-register!` — registers the sticky mode at id `'iterm-panes-focus` (default; override with `'sticky-mode-id`).
- `iterm-context-suffix-handler` — procedure suitable for passing to `set-local-context-suffix!`. Takes a `bundle-id` arg and returns the variant string, side-effect-rebuilding the iTerm tree first.
- `iterm-register!` — one-stop convenience: registers the dynamic iTerm tree, the sticky mode, and installs the context-suffix handler. Accepts opts: `'pane-labels`, `'hint-options`, `'pane-range-label`, `'sticky-mode-id`, `'install-context-suffix?` (default `#t`).
- `iterm-default-pane-labels`, `iterm-default-hint-options` — constants so user can build on top of them.

The library imports `(modaliser ax-hints)` (Task 2), `(modaliser terminal)` (Task 1), `(modaliser util)` (for `string-contains?` added in Task 0), plus the standard DSL / state-machine / event-dispatch / native imports.

**Critical design decision — context-suffix composability.** Today's `set-local-context-suffix!` accepts one function globally, replacing any prior one. If a user wants both iTerm context-suffix AND their own custom handler for another app, the iTerm library shouldn't trample. We handle this by:

1. `iterm-context-suffix-handler` is a plain procedure the user can call inside their own handler.
2. `iterm-register!`'s default sets `set-local-context-suffix!` to a handler that's ONLY iTerm-aware (returns `#f` for non-iTerm bundle IDs). If the user needs composition, they pass `'install-context-suffix? #f` and install their own composed handler that calls `(iterm-context-suffix-handler bundle-id)` for iTerm and other branches elsewhere.

Document this in the library header.

- [ ] **Step 1: Failing test.**

Create `Tests/ModaliserTests/ModaliserAppsItermLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser apps iterm) library")
struct ModaliserAppsItermLibraryTests {
    @Test func registerInstallsItermTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        try engine.evaluate("(iterm-register! 'install-context-suffix? #f)")
        // The iTerm tree is registered even when iTerm isn't running
        // (AX query returns empty, but the static keys c/h/j/k/l/m/z/x are present).
        #expect(try engine.evaluate("(lookup-tree \"com.googlecode.iterm2\")") != .false)
    }

    @Test func focusModeTreeRegisters() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        try engine.evaluate("(iterm-focus-mode-register!)")
        #expect(try engine.evaluate("(lookup-tree \"iterm-panes-focus\")") != .false)
    }

    @Test func contextSuffixHandlerReturnsFalseForOtherApps() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps iterm))")
        #expect(try engine.evaluate("(iterm-context-suffix-handler \"com.apple.Safari\")") == .false)
    }
}
```

- [ ] **Step 2: Run, confirm failure.**

```
swift test --filter ModaliserAppsItermLibraryTests
```

- [ ] **Step 3: Create the library.**

Create `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`:

```scheme
;; (modaliser apps iterm) — iTerm dynamic-pane builder and sticky focus mode.
;;
;; The dynamic iTerm tree is rebuilt on every leader press (via
;; set-local-context-suffix!) so pane bindings track the current pane
;; layout. Pane chips are painted while the overlay is visible; each
;; chip's digit focuses that pane by UUID (race-free, no event injection).
;;
;; Quick start:
;;   (import (modaliser apps iterm))
;;   (iterm-register!)
;;
;; Defaults mirror the bundled seed: digit pane labels 1..0, transient
;; tree with "c Copy Mode", "f Focus" (enters sticky hjkl mode), "z
;; Toggle Zoom", and a "x Split" group. The sticky 'iterm-panes-focus
;; tree contains only Cmd+Alt+arrow hjkl focus moves.
;;
;; If you've already installed your own (set-local-context-suffix! …),
;; pass 'install-context-suffix? #f and call iterm-context-suffix-handler
;; from inside your own composed handler.

(define-library (modaliser apps iterm)
  (export iterm-rebuild-tree!
          iterm-focus-mode-tree
          iterm-focus-mode-register!
          iterm-context-suffix-handler
          iterm-register!
          iterm-default-pane-labels
          iterm-default-hint-options)
  (import (scheme base)
          (modaliser dsl)
          (modaliser state-machine)
          (modaliser event-dispatch)
          (modaliser util)
          (modaliser shell)
          (modaliser keyboard)
          (modaliser accessibility)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser terminal))
  (begin

    (define iterm-default-pane-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; iTerm-tuned chip appearance: large, neutral defaults so the library
    ;; has no theme coupling. Seeds typically override 'background to
    ;; their host-header colour for a consistent look.
    (define iterm-default-hint-options
      (list (cons 'offset-x-frac 0.02)
            (cons 'offset-y-frac 0.02)
            (cons 'font-size 56)
            (cons 'padding 16)
            (cons 'corner-radius 8)
            (cons 'color "white")
            (cons 'background "dodgerblue")
            (cons 'border-width 1)
            (cons 'border-color "black")))

    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    ;; Query iTerm for the UUIDs of every session in the focused window's
    ;; current tab. iTerm's `id of every session` returns "U1, U2, ..."
    ;; (one line, comma-space separated).
    (define (iterm-list-session-ids)
      (let* ((out (run-shell
                    (string-append
                      "osascript -e 'tell application \"iTerm\" to "
                      "id of every session of current tab of current window' "
                      "2>/dev/null")))
             (trimmed (string-trim out)))
        (if (string=? trimmed "")
          '()
          (let loop ((parts (string-split trimmed ",")) (acc '()))
            (cond
              ((null? parts) (reverse acc))
              (else
                (let ((s (string-trim (car parts))))
                  (loop (cdr parts)
                        (if (string=? s "") acc (cons s acc))))))))))

    ;; UUIDs are URL-safe — inline into AppleScript without escaping.
    (define (iterm-select-session-by-id session-id)
      (run-shell
        (string-append
          "osascript -e 'tell application \"iTerm\" to "
          "tell first session of current tab of current window "
          "whose id is \"" session-id "\" to select' "
          "2>/dev/null")))

    ;; Build a single (key-range ...) node covering every labelled pane.
    ;; Display key is "<first>.." reflecting actually-bound count (so a
    ;; 3-pane window reads "1.." rather than the full label list).
    (define (iterm-pane-bindings labelled-panes session-ids range-label)
      (let loop ((ps labelled-panes) (label->sid '()) (keys '()))
        (cond
          ((null? ps)
           (cond
             ((null? keys) '())
             (else
               (let* ((alist  label->sid)
                      (ks     (reverse keys))
                      (first  (car ks))
                      (display (string-append first ".."))) ; e.g. "1.."
                 (list
                   (key-range display range-label
                     ks
                     (lambda (k)
                       (let ((entry (assoc k alist)))
                         (when entry
                           (iterm-select-session-by-id (cdr entry)))))))))))
          (else
            (let* ((entry (car ps))
                   (label (car entry))
                   (pane  (cdr entry))
                   (idx   (cdr (assoc 'idx pane)))
                   (sid   (and (< idx (length session-ids))
                               (list-ref session-ids idx))))
              (loop (cdr ps)
                    (if sid (cons (cons label sid) label->sid) label->sid)
                    (if sid (cons label keys)                  keys)))))))

    ;; Rebuild and re-register the 'com.googlecode.iterm2 tree from
    ;; the current iTerm pane layout. Cheap when iTerm isn't running
    ;; (AX returns empty, no panes contribute to the range).
    (define (iterm-rebuild-tree! . opts)
      (let* ((alist        (props->alist opts))
             (labels       (alist-ref alist 'pane-labels iterm-default-pane-labels))
             (hint-options (alist-ref alist 'hint-options iterm-default-hint-options))
             (range-label  (alist-ref alist 'pane-range-label "Focus Pane <n>"))
             (sticky-id    (alist-ref alist 'sticky-mode-id 'iterm-panes-focus))
             (raw-panes    (ax-find-elements-named
                             "com.googlecode.iterm2" "AXScrollArea" "AXStaticText"))
             (panes        (label-pairs labels raw-panes))
             (session-ids  (iterm-list-session-ids)))
        (apply define-tree 'com.googlecode.iterm2
          'on-enter (lambda ()
                      (hints-show (ax-target-hints panes hint-options)))
          'on-leave (lambda () (hints-hide))
          (append
            (iterm-pane-bindings panes session-ids range-label)
            (list
              (key "c" "Copy Mode" (keystroke '(cmd shift) "c"))
              (key "f" "Focus"
                (lambda () (enter-mode! sticky-id)))
              (key "z" "Toggle Zoom" (keystroke '(cmd shift) "return"))
              (group "x" "Split"
                (key "h" "Left"  (keystroke '(cmd ctrl shift) "h"))
                (key "j" "Down"  (keystroke '(cmd ctrl shift) "j"))
                (key "k" "Up"    (keystroke '(cmd ctrl shift) "k"))
                (key "l" "Right" (keystroke '(cmd ctrl shift) "l"))))))))

    ;; Sticky focus-mode children. Pure hjkl focus moves, entered from
    ;; the transient tree via "f" or via (enter-mode! 'iterm-panes-focus).
    (define (iterm-focus-mode-tree)
      (list
        (key "h" "Left"  (keystroke '(cmd alt) "left"))
        (key "j" "Down"  (keystroke '(cmd alt) "down"))
        (key "k" "Up"    (keystroke '(cmd alt) "up"))
        (key "l" "Right" (keystroke '(cmd alt) "right"))))

    (define (iterm-focus-mode-register! . opts)
      (let* ((alist     (props->alist opts))
             (id        (alist-ref alist 'sticky-mode-id 'iterm-panes-focus))
             (disp-name (alist-ref alist 'display-name "Focus")))
        (apply define-tree id
          'sticky #t
          'exit-on-unknown #t
          'display-name disp-name
          (iterm-focus-mode-tree))))

    ;; Variant string for the focused iTerm pane, used by the
    ;; (modaliser event-dispatch) dispatcher to select sub-tree variants
    ;; like 'com.googlecode.iterm2/nvim. Returns #f if no variant applies.
    ;; Side-effect: rebuilds the iTerm tree so subsequent lookups see the
    ;; current pane layout.
    (define (iterm-context-suffix-handler bundle-id)
      (cond
        ((equal? bundle-id "com.googlecode.iterm2")
         (iterm-rebuild-tree!)
         (let ((cmd (focused-terminal-foreground-command)))
           (cond
             ((not cmd) #f)
             ((string-contains? cmd "nvim") "/nvim")
             ((or (string-contains? cmd "zellij")
                  (string-contains? cmd "zj"))
              (if (focused-nvim-socket) "/zellij+nvim" "/zellij"))
             (else #f))))
        (else #f)))

    ;; One-stop convenience: register the dynamic iTerm tree, the sticky
    ;; focus mode, and install the context-suffix handler. Pass
    ;; 'install-context-suffix? #f if you compose your own handler.
    (define (iterm-register! . opts)
      (let* ((alist           (props->alist opts))
             (install?        (alist-ref alist 'install-context-suffix? #t))
             (forwarded
               (let loop ((kvs opts) (acc '()))
                 (cond
                   ((null? kvs) (reverse acc))
                   ((null? (cdr kvs))
                    (error "iterm-register!: odd keyword/value list"))
                   ((eq? (car kvs) 'install-context-suffix?)
                    (loop (cddr kvs) acc))
                   (else
                    (loop (cddr kvs)
                          (cons (cadr kvs) (cons (car kvs) acc))))))))
        (apply iterm-rebuild-tree! forwarded)
        (apply iterm-focus-mode-register! forwarded)
        (when install?
          (set-local-context-suffix! iterm-context-suffix-handler))))))
```

- [ ] **Step 4: Confirm tests pass.**

```
swift test --filter ModaliserAppsItermLibraryTests
swift test
```

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld Tests/ModaliserTests/ModaliserAppsItermLibraryTests.swift
git commit -m "feat(modular-config): (modaliser apps iterm) library"
```

---

### Task 8: Thin `default-config.scm` and update `root.scm`

**Files:**
- Modify: `Sources/Modaliser/Scheme/default-config.scm` — full rewrite using the new builders.
- Modify: `Sources/Modaliser/Scheme/root.scm` — drop the `include` lines for `lib/ax-hints.scm` and `lib/terminal.scm` (now libraries). Keep `lib/web-search.scm` and the `ui/` includes for now.
- Delete: `Sources/Modaliser/Scheme/lib/ax-hints.scm` (replaced by `.sld`).
- Delete: `Sources/Modaliser/Scheme/lib/terminal.scm` (replaced by `.sld`).

The new `default-config.scm` reproduces the synced personal config's behaviour using the Phase C libraries. It uses `(import …)` lines for the converted libraries and continues to reference `web-search-handler` / `find-installed-apps` / file-chooser helpers from the legacy `include`-loaded modules (still available because `root.scm` keeps `lib/web-search.scm` and the `ui/*.scm` includes in place).

**What the new seed includes:**
- `(modaliser leader)` — `set-leaders!` for F18 / F17, no shift modifier, arm-when-frontmost Jump.
- `(modaliser space-switching)` — `(spaces-range-binding 'display-key "1..")` for the Goto Space row.
- `(modaliser window-actions)` — `(window-actions-group)` spliced inside the global tree.
- `(modaliser apps safari)` — `(safari-register!)`.
- `(modaliser apps iterm)` — `(iterm-register! 'hint-options …)` overriding the chip background to `the-color`.
- The "g Google Search", "a Applications", "f Files" root-level selectors are KEPT (they reference `web-search-handler`, `find-installed-apps`, etc. from the legacy `include`-loaded modules — unchanged).
- The `the-color = "dodgerblue"` variable shared between the host header and the iTerm pane chips.

**What changes vs the synced personal config:**
- The synced file's hand-rolled iTerm machinery (≈195 lines) collapses into a single `(iterm-register! …)` call.
- The synced file's `(define (local-context-suffix bundle-id) …)` (which silently failed to override the library's binding chain) is replaced with the library's proper `set-local-context-suffix!` installation — incidentally fixing the dead-code bug.
- The synced file's `(group "w" "Windows" …)` becomes `(window-actions-group)`.
- The synced file's `(key-range "1.." …)` becomes `(spaces-range-binding 'display-key "1..")`.
- The synced file's `(set-leader! 'global F18 …)` and `(set-leader! 'local F17 …)` become a single `(set-leaders! …)` call.

**root.scm changes:**
- Remove `(include "lib/ax-hints.scm")` and `(include "lib/terminal.scm")`.
- Keep `(include "lib/web-search.scm")` so `web-search-handler` / `web-search-on-select` resolve.
- Keep all `ui/*.scm` includes — they aren't libraries yet (chooser-using selectors need them).

- [ ] **Step 1: Write the new `default-config.scm`.**

Replace `Sources/Modaliser/Scheme/default-config.scm` entirely with:

```scheme
;; Modaliser configuration — first-run seed.
;;
;; This file is copied to ~/.config/modaliser/config.scm on first launch
;; and serves as a tutorial of the bundled (modaliser …) libraries.
;; Tweak freely; restart Modaliser (or use the "," → "r" reload binding)
;; to see your changes.

(import (modaliser dsl)
        (modaliser keyboard)
        (modaliser shell)
        (modaliser app)
        (modaliser pasteboard)
        (modaliser lifecycle)
        (modaliser leader)
        (modaliser window-actions)
        (modaliser space-switching)
        (modaliser apps safari)
        (modaliser apps iterm))

;; ─── Theme ───────────────────────────────────────────────────────

(define the-color "dodgerblue")

;; ─── Leader keys ─────────────────────────────────────────────────
;; F18 global, F17 local. arm-when-frontmost suppresses leader arming
;; while the Jump Desktop remote viewer is in front (its modifiers are
;; reserved for the remote machine).

(set-leaders! 'global-keycode F18
              'local-keycode  F17
              'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))

(set-overlay-delay! 0.3)

(set-host-header!
  'name       (run-shell "hostname -s")
  'background the-color
  'foreground "white")

;; ─── Global command tree (F18) ───────────────────────────────────

(define-tree 'global

  (group "," "Settings"
    (key "e" "Edit"
      (lambda ()
        (run-shell
          "/usr/bin/open -a Zed \"$HOME/.config/modaliser/config.scm\" || /usr/bin/open \"$HOME/.config/modaliser/config.scm\"")))
    (key "r" "Reload"
      (lambda () (relaunch!))))

  ;; macOS Spaces 1..9 via the system's Ctrl+digit shortcut.
  ;; Enable "Mission Control → Switch to Desktop N" in System Settings →
  ;; Keyboard → Keyboard Shortcuts for this to work.
  (spaces-range-binding 'display-key "1..")

  ;; Quick-launch keys
  (key "b" "Browser - Dia"    (lambda () (launch-app "Dia")))
  (key "e" "Editor - Zed"     (lambda () (launch-app "Zed")))
  (key "t" "Terminal - iTerm" (lambda () (launch-app "iTerm")))

  (key "j" "Jump Desktop"  (lambda () (launch-app "Jump Desktop")))

  (key "c" "ChatGPT"        (lambda () (launch-app "ChatGPT")))
  (key "C" "Claude Desktop" (lambda () (launch-app "Claude")))

  (key "m" "Mail"  (lambda () (launch-app "Mail")))
  (key "n" "Notes" (lambda () (launch-app "Notes")))

  (key "o" "Obsidian" (lambda () (launch-app "Obsidian")))
  (key "z" "Zotero"   (lambda () (launch-app "Zotero")))

  ;; Google search — uses web-search-handler / web-search-on-select from
  ;; the legacy lib/web-search.scm (still loaded via include in root.scm).
  (selector "g" "Google Search"
    'prompt "Search Google…"
    'dynamic-search web-search-handler
    'on-select web-search-on-select)

  (selector "a" "Applications"
    'prompt "Find app…"
    'source find-installed-apps
    'on-select activate-app
    'remember "apps"
    'id-field "bundleId"
    'actions
      (list
        (action "Open" 'description "Launch or focus" 'key 'primary
          'run (lambda (c) (activate-app c)))
        (action "Show in Finder" 'description "Reveal in Finder" 'key 'secondary
          'run (lambda (c) (reveal-in-finder c)))
        (action "Copy Path" 'description "Copy full path to clipboard"
          'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
        (action "Copy Bundle ID" 'description "Copy app bundle identifier"
          'run (lambda (c) (set-clipboard! (cdr (assoc 'bundleId c)))))))

  (selector "f" "Files"
    'prompt "File…"
    'file-roots (list "~")
    'on-select (lambda (c) (run-shell (string-append "/usr/bin/open \"" (cdr (assoc 'path c)) "\"")))
    'actions
      (list
        (action "Open" 'description "Open with default app" 'key 'primary
          'run (lambda (c) (run-shell (string-append "/usr/bin/open \"" (cdr (assoc 'path c)) "\""))))
        (action "Show in Finder" 'description "Reveal in Finder" 'key 'secondary
          'run (lambda (c) (reveal-in-finder c)))
        (action "Copy Path" 'description "Copy full path to clipboard"
          'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
        (action "Open in Zed" 'description "Open file in Zed editor"
          'run (lambda (c) (open-with "Zed" (cdr (assoc 'path c)))))))

  ;; Window management group — third/half/center/maximise/restore + selector.
  (window-actions-group))

;; ─── Per-app trees (F17 when that app is focused) ────────────────

(safari-register!)

;; iTerm: dynamic-pane tree + sticky 'iterm-panes-focus mode + context-
;; suffix handler. Override the chip background to thread the host theme
;; through to the pane chips. Defaults: digit pane labels (1..0), large
;; chips with a black border.
(iterm-register!
  'hint-options
    (list (cons 'offset-x-frac 0.02)
          (cons 'offset-y-frac 0.02)
          (cons 'font-size 56)
          (cons 'padding 16)
          (cons 'corner-radius 8)
          (cons 'color "white")
          (cons 'background the-color)
          (cons 'border-width 1)
          (cons 'border-color "black")))
```

- [ ] **Step 2: Update `root.scm`.**

Edit `Sources/Modaliser/Scheme/root.scm`. Replace this block:

```scheme
;; ─── Plain .scm modules (Phase C/D will library-ize these) ────────

(include "lib/terminal.scm")
(include "ui/dom.scm")
(include "ui/css.scm")
(include "ui/overlay.scm")
(include "ui/chooser.scm")
(include "lib/web-search.scm")
(include "lib/ax-hints.scm")
```

with:

```scheme
;; ─── Plain .scm modules (Phase D will library-ize the remaining ones) ────────

(include "ui/dom.scm")
(include "ui/css.scm")
(include "ui/overlay.scm")
(include "ui/chooser.scm")
(include "lib/web-search.scm")
```

- [ ] **Step 3: Delete the now-replaced files.**

```
git rm Sources/Modaliser/Scheme/lib/terminal.scm Sources/Modaliser/Scheme/lib/ax-hints.scm
```

- [ ] **Step 4: Build and run the full test suite.**

```
swift build
swift test
```

Expected: all green. If any existing test fails because it referenced `terminal.scm`/`ax-hints.scm` top-level bindings via include-loading, fix it by importing the new library at the top of that test (e.g. `(import (modaliser ax-hints))`).

- [ ] **Step 5: Commit.**

```
git add Sources/Modaliser/Scheme/default-config.scm Sources/Modaliser/Scheme/root.scm
git add -A Sources/Modaliser/Scheme/lib/   # picks up the deletions
git commit -m "refactor(modular-config): thin default-config.scm onto stdlib libraries"
```

---

### Task 9: Update `docs/user-libraries.md` to advertise the new stdlib libraries

**Files:**
- Modify: `docs/user-libraries.md`

The "What's not in this phase" section currently says the stdlib of per-app trees and helpers is Phase C work. With Phase C landing, replace that paragraph with a "Bundled stdlib libraries" section listing the new builders and showing a short example for each.

- [ ] **Step 1: Edit the doc.**

Replace the "What's not in this phase" section in `docs/user-libraries.md` with:

```markdown
## Bundled stdlib libraries

Phase C ships an opt-in stdlib of per-app trees and helpers. Each
exports a builder returning a tree node plus a convenience that
registers the tree under a sensible default scope.

```scheme
(import (modaliser apps iterm))      ; iterm-rebuild-tree!,
                                     ; iterm-panes-mode-register!,
                                     ; iterm-context-suffix-handler,
                                     ; iterm-register!
(import (modaliser apps safari))     ; safari-tree, safari-register!
(import (modaliser apps chrome))     ; chrome-tree, chrome-register!
(import (modaliser window-actions))  ; window-actions-group,
                                     ; window-actions-register!
(import (modaliser space-switching)) ; spaces-range-binding,
                                     ; spaces-1-9-register!
(import (modaliser leader))          ; set-global-leader!,
                                     ; set-local-leader!, set-leaders!
(import (modaliser ax-hints))        ; ax-find-labelled, ax-target-bindings,
                                     ; ax-target-hints, label-pairs,
                                     ; default-hint-options
(import (modaliser terminal))        ; focused-terminal-foreground-command,
                                     ; focused-nvim-socket,
                                     ; nvim-remote-send/-expr,
                                     ; modaliser-tool-path
```

Each library takes alist-style keyword options. The simplest call is
always zero-arg:

```scheme
(import (modaliser apps safari))
(safari-register!)                                ; defaults

(safari-register!                                 ; or customised
  'extra-bindings (list (key "/" "Search"
                          (lambda () (send-keystroke '(cmd) "f")))))
```

See the bundled `default-config.scm` (copied to your config dir on
first run) for an end-to-end example combining all of these.

## What's not in this phase

The user-facing tree under `ui/` (overlay rendering, chooser) and the
Google web-search helper are still `include`-style and not yet
importable as `(modaliser …)` libraries. The bundled `default-config.scm`
seed still uses them — `web-search-handler`, `find-installed-apps`,
the file-chooser selector — but it references them as top-level
bindings rather than as imports. Phase D will library-ize chooser /
overlay / web-search and the seed will switch to explicit `(import …)`.
```

- [ ] **Step 2: Build + test (sanity).**

```
swift build
swift test
```

- [ ] **Step 3: Commit.**

```
git add docs/user-libraries.md
git commit -m "docs(modular-config): advertise Phase C stdlib libraries in user-libraries.md"
```

---

### Task 10: Manual end-to-end verification + finishing

**Files:** none (verification only).

Per `feedback_install_flow.md`: source changes need a real `/Applications` install to test the GUI behavior. Per `feedback_config_sync.md`: when the bundled `default-config.scm` changes, the actively-used `~/.config/modaliser/config.scm` will drift unless the user rewrites it; document this in the commit message and don't auto-overwrite.

- [ ] **Step 1: Build the app bundle and install.**

```
./scripts/install.sh
```

Watch for build errors. Fix any and re-run.

- [ ] **Step 2: Verify the first-run seed flow on a clean config.**

For a clean test, temporarily move the existing user config aside:

```
mv ~/.config/modaliser/config.scm ~/.config/modaliser/config.scm.bak 2>/dev/null
```

Launch Modaliser from `/Applications`. Console (or wherever `log` lands) should show: `Modaliser: seeded default config at /Users/…/.config/modaliser/config.scm`. Confirm the file contents match the new thin seed.

Restore your saved config:

```
mv ~/.config/modaliser/config.scm.bak ~/.config/modaliser/config.scm
```

- [ ] **Step 3: Smoke-test seed behaviour live.**

With the seed installed as the active config:

- Press F18 → overlay appears. See `,` Settings, `1..` Goto Space, quick-launch keys (b/e/t/j/c/C/m/n/o/z), `g` Google Search, `a` Applications, `f` Files, `w` Windows.
- Press `,` → enter Settings group. `r` relaunches.
- Press `1` … `9` → Spaces switching keystrokes fire (Ctrl+1..Ctrl+9).
- Press `w` → enter Windows group; `c` centers the focused window; `s` opens the Select Window chooser.
- Press `g` → Google Search chooser opens; typing fetches autocomplete suggestions.
- Press `a` → Applications chooser opens; fuzzy-finder lists installed apps.
- Focus Safari; press F17 → Safari-local overlay shows Tabs + Browser groups.
- Focus iTerm; press F17 → iTerm overlay shows digit pane chips (1, 2, …) themed `the-color`, with `c` Copy Mode, `f` Focus, `z` Zoom, `x` Split group.
- In iTerm press `f` → enter sticky `Focus` mode; `hjkl` move focus, `Esc` exits.

If any step fails, the relevant library (or the seed wiring) needs a fix; don't merge until each works.

- [ ] **Step 4: Verify lint.**

```
grep -r '(lispkit ' Sources/Modaliser/Scheme/lib/modaliser/apps/ Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld Sources/Modaliser/Scheme/lib/modaliser/space-switching.sld Sources/Modaliser/Scheme/lib/modaliser/leader.sld Sources/Modaliser/Scheme/lib/modaliser/ax-hints.sld Sources/Modaliser/Scheme/lib/modaliser/terminal.sld
```

Expected: empty output. (Existing `lib/modaliser/util.sld` has documented `(lispkit hashtable)` / `(lispkit string)` imports — leave those alone; Phase D resolves them.)

- [ ] **Step 5: Run `superpowers:requesting-code-review`.**

Invoke the skill with this scope: "Phase C of the modular config plan — review all new libraries under `Sources/Modaliser/Scheme/lib/modaliser/`, the new tests under `Tests/ModaliserTests/`, the thinned `default-config.scm`, and the `root.scm` `include`-list trim. Spec: `docs/superpowers/specs/2026-05-16-modular-config-architecture-design.md`. Phase scope per `docs/superpowers/prompts/2026-05-16-modular-config-kickoff.md`."

Address any high-confidence findings with fix commits on this branch. Then re-run `swift test` and verify all green.

- [ ] **Step 6: Run `superpowers:finishing-a-development-branch`.**

This skill walks you through the merge to main. The merge commit message follows the kickoff template:

```
Merge: phase C — stdlib libraries (modular config)
```

After the merge, the worktree can be removed (or kept if you want to revisit). The next session can pick up Phase D from `main`.

---

## Spec coverage check

- ✅ `(modaliser apps iterm)` — Task 7.
- ✅ `(modaliser apps safari)` — Task 6.
- ✅ `(modaliser apps chrome)` — Task 6.
- ✅ `(modaliser window-actions)` — Task 3.
- ✅ `(modaliser space-switching)` — Task 4.
- ✅ `(modaliser leader)` — Task 5.
- ✅ Builder pattern (returns tree node + register convenience) — applied in Tasks 3–7.
- ✅ Alist-style keyword options — applied in all builders.
- ✅ Thin `default-config.scm` as first-run seed — Task 8.
- ✅ Doc updated — Task 9.
- ✅ Manual verification of seed behaviour — Task 10.

## Out-of-scope items deferred to Phase D (or later)

- `(modaliser web-search)` — needs `(modaliser chooser)` first.
- `(modaliser chooser)` and `(modaliser overlay)` — `ui/*.scm` files.
- The Google Search / Find Apps / Find File / Find Window selectors in the seed — return once the above libraries land.
- `(modaliser util)`'s residual `(lispkit hashtable)` and `(lispkit string)` imports — Phase D portability cleanup.
- Existing user `~/.config/modaliser/config.scm` files do not auto-migrate. They keep working because every name they reference still resolves through `(modaliser dsl)` + the still-included legacy helpers.
