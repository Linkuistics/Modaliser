# Modular Config Phase D — Portability Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate every `(lispkit …)` import from the user-facing `(modaliser …)` library tree, document the portable surface, and add an audit check so future drift is caught early.

**Architecture:** The audit shows a single chokepoint: `(modaliser util)` re-exports a handful of LispKit-style hashtable and string primitives via `(import (lispkit hashtable) (lispkit string))`. Phase D (a) replaces the string ops with local pure-Scheme implementations (LispKit ships no SRFI 13), (b) replaces the hashtable ops with `(srfi 69)` and renames exports to standard names, (c) updates the lone consumer (`state-machine.sld`), (d) adds an audit script, and (e) writes `docs/portability.md` + corrects spec drift in `docs/user-libraries.md`. No new abstractions, no library carving — the spec's Phase D non-goal is explicit that internal `.scm` plumbing (overlay, chooser, web-search) stays as-is.

**Tech Stack:** Swift Package Manager, LispKit (R7RS Scheme host), Swift Testing framework (`@Suite`/`@Test`), shell scripts.

**Source of truth for Phase D scope:** `docs/superpowers/specs/2026-05-16-modular-config-architecture-design.md` (the umbrella spec) and `docs/superpowers/prompts/2026-05-16-modular-config-kickoff.md` (Phase D section).

---

## File Structure

**Modified:**
- `Sources/Modaliser/Scheme/lib/modaliser/util.sld` — drop `(lispkit hashtable)` and `(lispkit string)` imports; replace exports with `(srfi 69)`-backed hashtable names and local string ops.
- `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` — rename three call sites to SRFI 69 names with corrected argument order.
- `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift` — add tests covering string ops and hashtable ops (both pre- and post-change must pass; the change is a refactor with semantic equivalence on the exposed surface).
- `docs/user-libraries.md` — correct the inaccurate "What's not in this phase" section that promises Phase D will library-ize chooser/overlay/web-search (it doesn't; that's deferred).

**Created:**
- `scripts/check-portable-surface.sh` — greps the user-facing tree for `(lispkit ` and exits non-zero if anything is found.
- `docs/portability.md` — describes the portable surface user configs can rely on, the convention every new `(modaliser …)` library must follow, and how to run the audit check.

**Untouched (intentional, per kickoff non-goals):**
- `Sources/Modaliser/Scheme/lib/web-search.scm`, `Sources/Modaliser/Scheme/ui/*.scm` — internal plumbing that uses `include` and may legitimately reach for LispKit-only bindings. Phase D leaves these alone.
- All native libraries (`(modaliser shell)`, `(modaliser webview)`, etc.) — they're implementations of portable names in Swift; portability of the name surface is what matters, not the implementation.

---

## Task 1: Add direct tests for `(modaliser util)` string ops

**Why a separate task:** the existing `ModaliserUtilLibraryTests.swift` only covers `string-contains?`. Before swapping `string-split` and `string-trim` to local implementations, lock in the observable behaviour with tests so the refactor is provably semantic-preserving.

**Files:**
- Modify: `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift`

- [ ] **Step 1: Add the failing tests**

In `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift`, append these inside the existing `struct ModaliserUtilLibraryTests` (before the closing brace):

```swift
    @Test func stringSplitOnSingleCharSeparator() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(equal? (string-split \"a/b/c\" \"/\") '(\"a\" \"b\" \"c\"))"
        ) == .true)
    }

    @Test func stringSplitOnNewline() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(equal? (string-split \"one\\ntwo\\nthree\" \"\\n\") '(\"one\" \"two\" \"three\"))"
        ) == .true)
    }

    @Test func stringSplitEmptyInputReturnsListWithEmptyString() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        // Locks in current LispKit (lispkit string)/string-split semantics so the
        // local replacement preserves them. If you discover the LispKit value is
        // different at the time of writing, update both this expectation and the
        // local string-split implementation in Task 2 to match — the goal is
        // *no behavioural change*, only a portable implementation.
        #expect(try engine.evaluate(
            "(equal? (string-split \"\" \"/\") '(\"\"))"
        ) == .true)
    }

    @Test func stringSplitNoMatchReturnsSingleton() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(equal? (string-split \"abc\" \"/\") '(\"abc\"))"
        ) == .true)
    }

    @Test func stringTrimStripsLeadingAndTrailingWhitespace() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(string-trim \"  hello  \")").asString() == "hello")
        #expect(try engine.evaluate("(string-trim \"\\t hi \\n\")").asString() == "hi")
        #expect(try engine.evaluate("(string-trim \"nochange\")").asString() == "nochange")
        #expect(try engine.evaluate("(string-trim \"\")").asString() == "")
    }
```

- [ ] **Step 2: Run the new tests against the current LispKit-backed implementation**

Run:
```bash
swift test --filter ModaliserUtilLibraryTests
```

Expected: all assertions PASS. The current implementation is `(lispkit string)` — we want a *baseline* of its semantics. If `stringSplitEmptyInputReturnsListWithEmptyString` fails because LispKit returns `'()` instead of `'("")`, edit the test (and Task 2's implementation) to match LispKit's actual behaviour and re-run. The whole point of the baseline is to ensure Task 2 introduces no change.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModaliserTests/ModaliserUtilLibraryTests.swift
git commit -m "$(cat <<'EOF'
test(modular-config): lock in string-split/string-trim semantics for util

Direct tests for (modaliser util)'s string-split and string-trim
exports, in preparation for swapping the underlying implementation
from (lispkit string) to local pure-Scheme code. Captures the
current observable behaviour so the refactor is provably
semantic-preserving.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Replace `(lispkit string)` with local implementations

**Files:**
- Modify: `Sources/Modaliser/Scheme/lib/modaliser/util.sld`

- [ ] **Step 1: Drop the `(lispkit string)` import and add local implementations**

Edit `Sources/Modaliser/Scheme/lib/modaliser/util.sld`. Replace the entire `(define-library …)` form with:

```scheme
;; (modaliser util) — Shared utility functions used across other
;; (modaliser …) libraries. Pure Scheme except for the centralised
;; SRFI 69 hashtable re-exports below. After Phase D this library
;; imports only (scheme …) and (srfi …); no (lispkit …).

(define-library (modaliser util)
  (export alist-ref
          props->alist
          string-join
          read-file-text
          log
          ;; SRFI 69 hashtable surface (re-exported for callers that
          ;; import (modaliser util) and don't want to depend on
          ;; (srfi 69) by name).
          make-hash-table hash-table-set! hash-table-ref/default
          string-hash
          ;; Local string helpers (no SRFI 13 in LispKit's bundle,
          ;; so we implement these on (scheme base) directly).
          string-split string-trim string-contains?)
  (import (scheme base)
          (scheme file)
          (scheme write)
          (scheme char)
          (srfi 69))
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
      (newline))

    ;; ─── Local string ops ───────────────────────────────────────
    ;; Implemented on (scheme base) only; no SRFI 13 needed.

    (define (string-index-of haystack needle start)
      ;; Returns the index of the first match of needle in haystack at
      ;; or after start, or #f if not found. Naive O(n*m) scan — fine
      ;; for the short strings we split on (paths, command output).
      (let ((hlen (string-length haystack))
            (nlen (string-length needle)))
        (if (zero? nlen)
          start
          (let outer ((i start))
            (cond
              ((> (+ i nlen) hlen) #f)
              ((let inner ((j 0))
                 (cond
                   ((= j nlen) #t)
                   ((char=? (string-ref haystack (+ i j))
                            (string-ref needle j))
                    (inner (+ j 1)))
                   (else #f)))
               i)
              (else (outer (+ i 1))))))))

    (define (string-contains? haystack needle)
      (if (string-index-of haystack needle 0) #t #f))

    (define (string-split str sep)
      ;; Split str on every occurrence of the literal string sep.
      ;; Matches the input/output shape the existing callers rely on:
      ;;   (string-split "a/b/c" "/") => ("a" "b" "c")
      ;;   (string-split "abc" "/")   => ("abc")
      ;;   (string-split "" "/")      => ("")
      (let ((slen (string-length str))
            (seplen (string-length sep)))
        (if (zero? seplen)
          (list str)
          (let loop ((start 0) (acc '()))
            (let ((hit (string-index-of str sep start)))
              (if hit
                (loop (+ hit seplen)
                      (cons (substring str start hit) acc))
                (reverse (cons (substring str start slen) acc))))))))

    (define (string-trim str)
      ;; Strip leading/trailing whitespace (per char-whitespace?).
      (let ((len (string-length str)))
        (let scan-left ((i 0))
          (cond
            ((= i len) "")
            ((char-whitespace? (string-ref str i)) (scan-left (+ i 1)))
            (else
              (let scan-right ((j (- len 1)))
                (if (char-whitespace? (string-ref str j))
                  (scan-right (- j 1))
                  (substring str i (+ j 1))))))))) ))
```

Notes on what changed:
- `(import (lispkit hashtable) (lispkit string))` → `(import (srfi 69))` (plus `(scheme char)` for `char-whitespace?`).
- Exports `make-hashtable` / `hashtable-set!` / `hashtable-ref` are **renamed** to SRFI 69 standard names `make-hash-table` / `hash-table-set!` / `hash-table-ref/default`. (Task 3 updates the caller in `state-machine.sld`.)
- `string-hash` stays — SRFI 69 also exports it.
- `string-split`, `string-trim`, `string-contains?` are now local definitions. The behaviour matches Task 1's baseline tests.

- [ ] **Step 2: Run the util tests**

Run:
```bash
swift test --filter ModaliserUtilLibraryTests
```

Expected: ALL string-related tests PASS (alist-ref, string-join, props->alist, string-contains?, string-split, string-trim).

If `stringSplitEmptyInputReturnsListWithEmptyString` (or any other baseline test) fails because the local implementation differs from LispKit's behaviour, decide:
- If LispKit's old behaviour was a quirk that nobody relies on (search call sites — `terminal.sld`, `state-machine.sld`, `iterm.sld`): adopt the new local behaviour and update the baseline test to match.
- If a caller does rely on it: adjust the local implementation to match.

- [ ] **Step 3: Run the full suite to catch indirect callers**

Run:
```bash
swift test
```

Expected: all tests PASS. Indirect callers of `string-split` / `string-trim` are exercised by `ModaliserStateMachineLibraryTests`, `ModaliserTerminalLibraryTests`, `ModaliserAppsItermLibraryTests`. Hashtable callers will fail until Task 3 is done — that's expected. **Tolerate** hashtable failures here; assert all *non-hashtable* tests pass.

- [ ] **Step 4: Verify the audit grep is clean for strings**

Run:
```bash
grep -rn "lispkit string" Sources/Modaliser/Scheme/lib/modaliser/
```

Expected: no matches (the only earlier comment mentioning `(lispkit string)` was the TODO inside `util.sld`, which is gone after Step 1).

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/util.sld
git commit -m "$(cat <<'EOF'
feat(modular-config): replace (lispkit string) with local string ops

string-split, string-trim, and string-contains? are now implemented
in (modaliser util) using only (scheme base) and (scheme char).
LispKit's bundle does not ship SRFI 13, so we can't delegate to a
standard string library; the local implementations are tiny and
keep the (modaliser …) tree free of (lispkit …) imports.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Migrate `(lispkit hashtable)` to `(srfi 69)` and update the lone caller

**Files:**
- Modify: `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld`
- Modify: `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift` (add direct hashtable export tests)

- [ ] **Step 1: Add failing tests covering the renamed hashtable surface**

In `Tests/ModaliserTests/ModaliserUtilLibraryTests.swift`, append these tests:

```swift
    @Test func hashTableMakeAndSetAndRef() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        try engine.evaluate("(define ht (make-hash-table string=? string-hash))")
        try engine.evaluate("(hash-table-set! ht \"alpha\" 1)")
        try engine.evaluate("(hash-table-set! ht \"beta\" 2)")
        #expect(try engine.evaluate("(hash-table-ref/default ht \"alpha\" #f)") == .fixnum(1))
        #expect(try engine.evaluate("(hash-table-ref/default ht \"beta\" #f)") == .fixnum(2))
        #expect(try engine.evaluate("(hash-table-ref/default ht \"missing\" #f)") == .false)
    }

    @Test func hashTableOverwriteOnRepeatSet() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        try engine.evaluate("(define ht (make-hash-table string=? string-hash))")
        try engine.evaluate("(hash-table-set! ht \"k\" 1)")
        try engine.evaluate("(hash-table-set! ht \"k\" 2)")
        #expect(try engine.evaluate("(hash-table-ref/default ht \"k\" #f)") == .fixnum(2))
    }
```

- [ ] **Step 2: Run the hashtable tests — confirm they FAIL**

Run:
```bash
swift test --filter ModaliserUtilLibraryTests
```

Expected: the two new `hashTable*` tests FAIL because `make-hash-table` / `hash-table-set!` / `hash-table-ref/default` are not yet exported (Task 2 changed the names; this confirms the new surface is what we want). If the names happen to resolve from another import path, double-check by running them in isolation:

```bash
swift test --filter hashTableMakeAndSetAndRef
```

If they unexpectedly PASS at this step, Task 2's import surface might already be wired correctly — proceed to Step 3 without worry.

- [ ] **Step 3: Update `state-machine.sld` call sites**

Edit `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld`.

Replace **line 59** (`(define tree-registry (make-hashtable string-hash string=?))`) with:

```scheme
;; SRFI 69 make-hash-table is (equality hash) — opposite order to
;; LispKit's (lispkit hashtable) make-hashtable. Easy to miss.
(define tree-registry (make-hash-table string=? string-hash))
```

Replace **line 123** (`(hashtable-set! tree-registry scope-str acc)`) with:

```scheme
            (hash-table-set! tree-registry scope-str acc)))))))
```

(Keep the surrounding indentation as it was — the only change is the procedure name.)

Replace **line 128** (`(hashtable-ref tree-registry scope-str #f)`) with:

```scheme
    (hash-table-ref/default tree-registry scope-str #f)))
```

- [ ] **Step 4: Run the hashtable tests — confirm they PASS**

Run:
```bash
swift test --filter ModaliserUtilLibraryTests
```

Expected: all tests in the suite PASS, including the two new `hashTable*` tests.

- [ ] **Step 5: Run the full suite**

Run:
```bash
swift test
```

Expected: full suite PASSES. `ModaliserStateMachineLibraryTests` is the primary integration test for the hashtable migration — it exercises `register-tree!` and `lookup-tree`, both of which touch the renamed call sites.

- [ ] **Step 6: Verify the audit grep is clean overall**

Run:
```bash
grep -rn "(lispkit " Sources/Modaliser/Scheme/lib/modaliser/
```

Expected: **no output**. This is the kickoff's verification criterion ("`grep -r '(lispkit ' Sources/Modaliser/Scheme/lib/modaliser/` returns nothing"). If anything is left, fix it before committing.

The earlier `dsl.sld:10` comment said "no (lispkit …)" — that's a *comment* containing the literal string `(lispkit …)`, which the grep above does NOT match (the trailing space in `(lispkit ` filters it out). Confirm by reading the line if in doubt.

- [ ] **Step 7: Commit**

```bash
git add Sources/Modaliser/Scheme/lib/modaliser/util.sld \
        Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld \
        Tests/ModaliserTests/ModaliserUtilLibraryTests.swift
git commit -m "$(cat <<'EOF'
feat(modular-config): replace (lispkit hashtable) with (srfi 69)

(modaliser util) now imports (srfi 69) and re-exports the standard
make-hash-table / hash-table-set! / hash-table-ref/default /
string-hash names. (modaliser state-machine) — the only caller — is
updated to match, including SRFI 69's (equality hash) argument order
for make-hash-table (the opposite of LispKit's (hash equality)).

After this commit, `grep -r '(lispkit ' Sources/Modaliser/Scheme/lib/modaliser/`
returns nothing — the user-facing library tree is fully portable.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add the portability audit script

**Files:**
- Create: `scripts/check-portable-surface.sh`

- [ ] **Step 1: Create the script**

Create `scripts/check-portable-surface.sh` with this content:

```bash
#!/usr/bin/env bash
# scripts/check-portable-surface.sh
#
# Audit the user-facing Modaliser library tree for host-specific
# (lispkit …) imports. The (modaliser …) library tree must depend
# only on (scheme …), (srfi …), and other (modaliser …) libraries —
# that's the portability contract documented in docs/portability.md.
#
# Exit codes:
#   0  — clean
#   1  — at least one (lispkit …) reference found in the user-facing tree
#
# Usage:
#   ./scripts/check-portable-surface.sh
#
# Wire it into CI by running this script as a build/test step.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/Sources/Modaliser/Scheme/lib/modaliser"

if [[ ! -d "$TARGET" ]]; then
  echo "check-portable-surface: $TARGET does not exist" >&2
  exit 2
fi

# -F: literal pattern, no regex surprises with parens.
# We match "(lispkit " (with the trailing space) so that prose
# comments like "no (lispkit …)" don't trip the check — they don't
# contain a space immediately after `lispkit`.
if grep -rnF '(lispkit ' "$TARGET"; then
  echo
  echo "check-portable-surface: FAIL — (lispkit …) references found in $TARGET"
  echo "The (modaliser …) library tree must import only (scheme …),"
  echo "(srfi …), and other (modaliser …) libraries."
  echo "See docs/portability.md."
  exit 1
fi

echo "check-portable-surface: OK — no (lispkit …) references in $TARGET"
```

- [ ] **Step 2: Make it executable and run it**

```bash
chmod +x scripts/check-portable-surface.sh
./scripts/check-portable-surface.sh
```

Expected output:
```
check-portable-surface: OK — no (lispkit …) references in <repo>/Sources/Modaliser/Scheme/lib/modaliser
```

Exit code: 0.

- [ ] **Step 3: Sanity-check the script catches violations**

Temporarily add `(lispkit foo)` to a .sld file to confirm the script flags it:

```bash
# Inject a fake violation
echo ';; (lispkit foo)' >> Sources/Modaliser/Scheme/lib/modaliser/util.sld
./scripts/check-portable-surface.sh; echo "exit=$?"
# Should print a match line and exit 1.
# Revert the injection:
git checkout -- Sources/Modaliser/Scheme/lib/modaliser/util.sld
./scripts/check-portable-surface.sh; echo "exit=$?"
# Should be clean again, exit 0.
```

Expected: first invocation prints the injected violation and exits 1; the post-revert invocation prints OK and exits 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/check-portable-surface.sh
git commit -m "$(cat <<'EOF'
feat(modular-config): scripts/check-portable-surface.sh audit script

Greps the (modaliser …) library tree for (lispkit …) imports and
fails the build if any are found. The user-facing surface must
depend only on (scheme …), (srfi …), and other (modaliser …)
libraries — see docs/portability.md (next commit).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Write `docs/portability.md`

**Files:**
- Create: `docs/portability.md`

- [ ] **Step 1: Write the doc**

Create `docs/portability.md` with this content:

````markdown
# Portability

Modaliser's *configuration language* is portable Scheme — the same
`config.scm` and the same `(modaliser …)` library set work on any
R7RS Scheme implementation that ships SRFI 69 and has implementations
of Modaliser's native libraries available. The current build runs on
LispKit; a future Chez or Racket build would swap out the
`Sources/Modaliser/` Swift sources but leave
`Sources/Modaliser/Scheme/lib/modaliser/` untouched.

This document describes what user configurations and bundled
`(modaliser …)` libraries are allowed to assume — and what is
deliberately off-limits to keep that promise.

## The portable surface

Code under `Sources/Modaliser/Scheme/lib/modaliser/` and any
user-shipped `.sld` file may import from:

1. **R7RS standard libraries** that LispKit ships and that every
   serious R7RS host provides:
   - `(scheme base)` — core forms, numbers, lists, strings, ports.
   - `(scheme bitwise)` — `bitwise-and`, `bitwise-or`, `arithmetic-shift`.
     Used by `(modaliser dsl)` for modifier-mask construction.
   - `(scheme char)` — `char-whitespace?` and friends.
   - `(scheme file)` — `open-input-file`, `file-exists?`.
   - `(scheme write)` — `display`, `write`, `newline`.

2. **SRFI 69** (basic hash tables) — `make-hash-table`,
   `hash-table-set!`, `hash-table-ref/default`, `string-hash`. Widely
   supported across R7RS hosts.

3. **`(modaliser …)` libraries.** The full bundled set lives in
   `Sources/Modaliser/Scheme/lib/modaliser/`. The split into
   *pure-Scheme* vs *native* matters for porting:
   - *Pure-Scheme* libraries (`dsl`, `keymap`, `state-machine`,
     `event-dispatch`, `util`, `ax-hints`, `terminal`, `leader`,
     `window-actions`, `space-switching`, `apps/iterm`, `apps/safari`,
     `apps/chrome`) port verbatim across hosts.
   - *Native* libraries (`shell`, `app`, `keyboard`, `window`,
     `webview`, `input`, `accessibility`, `hints`, `fuzzy-match`,
     `http`, `pasteboard`, `lifecycle`, `clipboard-history`) are
     Swift implementations bound under `(modaliser …)` names. A port
     to a different host would re-implement these in whatever the host
     uses, keeping the same names and signatures.

## What's intentionally *not* portable

Two pieces of the bundled tree are *not* expected to port:

1. **Internal `.scm` modules** at `Sources/Modaliser/Scheme/ui/` and
   `Sources/Modaliser/Scheme/lib/web-search.scm`. These are loaded by
   `root.scm` via `(include …)` and may use `(lispkit …)` bindings
   freely. They handle overlay rendering, the chooser UI, and the
   Google-search helper — pieces that lean on LispKit's WebView and
   JSON bindings. Phase D leaves these alone by design (spec
   non-goal: "Internal pieces that are unlikely to port (e.g.
   WebView, AX) can continue to lean on Foundation / AppKit through
   the existing native libraries; only the user-facing surface needs
   to be portable.").

2. **The native libraries' Swift implementations.** Portability means
   the *names* `(modaliser shell)` etc. are stable contracts — the
   Swift code behind them is not.

User configurations that need to interoperate with those internal
pieces (e.g., to call `web-search-handler` from a selector) will be
host-specific to that extent. The bundled `default-config.scm` does
this in two places (the "Google Search" selector and the
"Applications"/"Files" selectors that use `find-installed-apps` /
`activate-app` / `reveal-in-finder`) and is itself a LispKit-only
configuration as a result. That's an accepted trade-off for the seed
config; library-izing those helpers is a possible future phase.

## The convention (for new `(modaliser …)` libraries)

Any new `.sld` file added under `Sources/Modaliser/Scheme/lib/modaliser/`
**must not** import from `(lispkit …)`. The import section can only
mention `(scheme …)`, `(srfi …)`, and other `(modaliser …)`
libraries. If you find yourself wanting a LispKit-only primitive,
the right answer is one of:

- Implement it locally in pure Scheme (as Phase D did for
  `string-split` / `string-trim`).
- Re-export it from `(modaliser util)` through a portable backend
  (as Phase D did for the hashtable primitives via SRFI 69).
- Expose it as a *new* `(modaliser …)` native library on the Swift
  side, with the contract that future hosts will re-implement it.

## How to audit

```
./scripts/check-portable-surface.sh
```

The script greps `Sources/Modaliser/Scheme/lib/modaliser/` for
`(lispkit ` and exits non-zero if it finds anything. Run it before
opening a PR that touches the library tree. CI is the long-term
home for this check.

## See also

- [`docs/user-libraries.md`](user-libraries.md) — user-side guide to
  splitting configs and shadowing libraries.
- [`docs/superpowers/specs/2026-05-16-modular-config-architecture-design.md`](superpowers/specs/2026-05-16-modular-config-architecture-design.md) — umbrella spec.
- [`docs/superpowers/prompts/2026-05-16-modular-config-kickoff.md`](superpowers/prompts/2026-05-16-modular-config-kickoff.md) — phase plan.
````

- [ ] **Step 2: Sanity-check by reading it back**

```bash
ls -la docs/portability.md
```

Confirm the file exists and is well-formed Markdown (no obvious unclosed blocks). Open it briefly to eyeball the rendered structure.

- [ ] **Step 3: Commit**

```bash
git add docs/portability.md
git commit -m "$(cat <<'EOF'
docs(modular-config): docs/portability.md — portable surface guide

Documents the portable surface that (modaliser …) libraries and user
configs can rely on: (scheme …) subset, SRFI 69, and the bundled
(modaliser …) library set. Codifies the convention that no new
.sld under Sources/Modaliser/Scheme/lib/modaliser/ may import
(lispkit …), and points to scripts/check-portable-surface.sh as
the enforcement mechanism.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Correct spec drift in `docs/user-libraries.md`

**Why:** The current `docs/user-libraries.md` ends with a "What's not in this phase" section that promises *"Phase D will library-ize chooser / overlay / web-search and the seed will switch to explicit `(import …)`."* That's inconsistent with the actual Phase D scope (the kickoff lists portability cleanup + docs + audit only; library-izing those internal modules is not a Phase D goal and is in fact a stated non-goal in the spec). The kickoff says: *"Spec drift: if a phase reveals the spec is wrong, update the spec in the same branch as the implementation."* This task fixes the drift.

**Files:**
- Modify: `docs/user-libraries.md`

- [ ] **Step 1: Replace the "What's not in this phase" section**

Edit `docs/user-libraries.md`. Locate the final section (starts with `## What's not in this phase`) and replace it with:

```markdown
## What lives outside the library tree

The user-facing tree under `Sources/Modaliser/Scheme/ui/` (overlay
rendering, chooser) and the Google web-search helper at
`Sources/Modaliser/Scheme/lib/web-search.scm` are loaded by
`root.scm` via `(include …)` rather than `(import …)`. They expose
their bindings (`web-search-handler`, `web-search-on-select`,
`find-installed-apps`, `activate-app`, `reveal-in-finder`,
`open-with`) at the top level so the bundled `default-config.scm`
seed can use them without an `(import …)` line.

These modules are intentionally *not* exposed as `(modaliser …)`
libraries: they lean on LispKit-specific bindings (WebView, JSON) and
the spec's Phase D non-goal explicitly keeps them that way — only
the user-facing **library** surface needs to be portable, not every
internal `.scm` file. See [`docs/portability.md`](portability.md)
for the formal portability contract.

If you want to use any of those top-level helpers from your own
`(import …)`-based config, you have two options:

1. Reference them directly — they're in scope after `root.scm` runs,
   so `config.scm` can call `web-search-handler` without any
   `(import …)`. (The seed config does this.) Your config becomes
   host-specific to that extent.
2. Re-implement the helper in pure Scheme inside your own library
   and import that instead.
```

- [ ] **Step 2: Read it back**

```bash
tail -30 docs/user-libraries.md
```

Confirm the replacement reads cleanly and references `docs/portability.md`.

- [ ] **Step 3: Commit**

```bash
git add docs/user-libraries.md
git commit -m "$(cat <<'EOF'
docs(modular-config): correct user-libraries.md Phase D scope claim

Replaces the inaccurate "Phase D will library-ize chooser / overlay
/ web-search" forward-reference with a description of why those
modules live outside the (modaliser …) library tree on purpose, and
links to the new docs/portability.md for the formal contract.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Final verification

**Files:** none modified. Verification only.

- [ ] **Step 1: Run the full test suite**

```bash
swift test
```

Expected: all tests PASS (no failures, no skips beyond pre-existing ones).

- [ ] **Step 2: Run the portability audit**

```bash
./scripts/check-portable-surface.sh
```

Expected:
```
check-portable-surface: OK — no (lispkit …) references in <repo>/Sources/Modaliser/Scheme/lib/modaliser
```

Exit code: 0.

- [ ] **Step 3: Run the kickoff's literal verification grep**

```bash
grep -r '(lispkit ' Sources/Modaliser/Scheme/lib/modaliser/
```

Expected: **no output** (the kickoff's stated success criterion).

- [ ] **Step 4: Confirm `docs/portability.md` exists and is accurate**

Read `docs/portability.md` end-to-end (it's short). The kickoff's second verification criterion is "the portability doc exists and is accurate." Cross-check the "portable surface" list against the actual imports in each `.sld` file:

```bash
for f in Sources/Modaliser/Scheme/lib/modaliser/*.sld Sources/Modaliser/Scheme/lib/modaliser/apps/*.sld; do
  echo "=== $f ==="
  awk '/^[[:space:]]*\(import /,/\)\)/' "$f"
done
```

Every `(import …)` line should be `(scheme …)`, `(srfi …)`, or `(modaliser …)`. If any other prefix appears, either fix it or update `docs/portability.md` to acknowledge the exception (only ever via Spec drift, not silently).

- [ ] **Step 5: Manual smoke — bundled config still loads**

Build a Modaliser app bundle and launch it:

```bash
./scripts/install.sh
```

(If the user has a custom build/install flow, follow that instead — there's a memory entry [feedback_install_flow.md] that says source changes need `./scripts/install.sh`; not "Relaunch".)

Expected:
- The app launches without errors.
- The status bar icon appears.
- Pressing the leader key (F18 by default) shows the global tree overlay with the same set of bindings as before.
- The "Settings…" → Edit binding still opens `~/.config/modaliser/config.scm`.

If anything is broken, do NOT proceed to merge — fix the regression first.

- [ ] **Step 6: Report ready for review**

Phase D implementation is complete. Hand off to `superpowers:requesting-code-review` before merging.

---

## Spec coverage self-check

Per the kickoff's Phase D scope:

| Kickoff requirement | Task covering it |
|---|---|
| Grep user-facing tree for `(lispkit `, `(import (lispkit`, and LispKit-only procedure names; replace or document each | Tasks 2 (string), 3 (hashtable), 7 (verification grep) |
| Write `docs/portability.md` summarising the assumed surface | Task 5 |
| Add a CI-style check (or documented manual procedure) | Task 4 |
| Verification: `grep -r '(lispkit ' …/modaliser/` returns nothing | Task 7 Step 3 |
| Verification: portability doc exists and is accurate | Task 7 Step 4 |
| Spec drift: update spec/docs in same branch | Task 6 (user-libraries.md) |

Out-of-scope items (deliberately not in the plan, per kickoff):
- Producing a Chez/Racket build.
- Library-izing `ui/*.scm` or `lib/web-search.scm`.
