# Modular Config — Phase A: Library Lookup Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `~/.config/modaliser/` and the bundled Modaliser stdlib directory onto LispKit's library lookup path (user-first), and expose `(prepend-library-path! "/abs/path")` so user Scheme can extend the path further. After this phase, `(import (foo bar))` resolves `<user-config>/foo/bar.sld`. No DSL refactoring yet — that's Phase B.

**Architecture:** LispKit's `FileHandler` already maintains an ordered `librarySearchUrls` list consulted by R7RS `import`. We prepend two new roots to it during `SchemeEngine.init`: first the bundled stdlib root (`<scheme-dir>/lib/`), then the user-config root (`~/.config/modaliser/`, or an override for tests). Prepend order matters — prepending bundled then user-config yields final order `[user-config, bundled, host-auto]`, so user files win against bundled, which wins against the host's R7RS+SRFI libraries. A tiny new `LibraryPathLibrary` (Swift NativeLibrary, namespace `(modaliser library-path)`) exposes `prepend-library-path!` as a one-procedure surface; the procedure forwards to `FileHandler.prependLibrarySearchPath`, which silently returns `#f` for non-existent paths and is therefore safe to call unconditionally.

**Tech Stack:** Swift 5.9, LispKit (`prependLibrarySearchPath`, `NativeLibrary`), Swift Testing (`@Test`, `#expect`). No new dependencies.

---

## File Structure

**Create:**
- `Sources/Modaliser/LibraryPathLibrary.swift` — new `NativeLibrary` subclass exporting `prepend-library-path!`. Mirrors the shape of `PasteboardLibrary.swift`. Single responsibility: expose the path-extension primitive.
- `Tests/ModaliserTests/LibraryPathTests.swift` — Swift Testing suite. One `@Suite("Library Path")` struct containing three `@Test`s: procedure presence, forgiving missing-path behaviour, and an end-to-end user-config-root resolution test using a tmp dir.
- `docs/user-libraries.md` — user-facing doc explaining `~/.config/modaliser/` layout, the lookup path order, and `(prepend-library-path! …)`. Includes a 5-line example library users can drop in.

**Modify:**
- `Sources/Modaliser/SchemeEngine.swift` — add `userConfigDir: String? = nil` init parameter; after Scheme dir resolution, call `prependLibrarySearchPath` for `<scheme-dir>/lib/` and then for the user-config dir (resolved tilde or override); register `LibraryPathLibrary` alongside the other native libraries.

**Untouched (Phase A explicitly defers):**
- `Sources/Modaliser/Scheme/root.scm` and `default-config.scm` — Phase B/C territory.
- `Sources/Modaliser/Scheme/lib/*.scm` — still loaded via `(include …)` from `root.scm`.

---

## Task 1: Expose `(prepend-library-path! …)` as a native primitive

**Files:**
- Create: `Sources/Modaliser/LibraryPathLibrary.swift`
- Modify: `Sources/Modaliser/SchemeEngine.swift` (register + import the new library)
- Create: `Tests/ModaliserTests/LibraryPathTests.swift`

- [ ] **Step 1.1: Write the failing test**

Create `Tests/ModaliserTests/LibraryPathTests.swift` with this exact content. We assert (a) the primitive is bound as a procedure and (b) calling it with a non-existent path is safe — both pin down the contract.

```swift
import Foundation
import Testing
@testable import Modaliser

@Suite("Library Path")
struct LibraryPathTests {

    @Test func prependLibraryPathIsExportedProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? prepend-library-path!)") == .true)
    }

    @Test func prependLibraryPathSilentlySkipsMissingDir() throws {
        let engine = try SchemeEngine()
        // Must not throw — LispKit's prependLibrarySearchPath returns false for
        // missing paths, and we surface that as a Scheme #f rather than an error.
        let result = try engine.evaluate(
            "(prepend-library-path! \"/definitely/does/not/exist/abc123\")"
        )
        #expect(result == .false)
    }
}
```

- [ ] **Step 1.2: Run the test to verify it fails**

Run: `swift test --filter LibraryPathTests`

Expected: compile failure or test failure with `unbound variable: prepend-library-path!` / `procedure? prepend-library-path!` returning `#f`. Either signals the primitive doesn't exist yet — that's the point.

- [ ] **Step 1.3: Create the native library**

Create `Sources/Modaliser/LibraryPathLibrary.swift` with this exact content. Mirrors `PasteboardLibrary.swift` precisely so it slots into the existing pattern.

```swift
import Foundation
import LispKit

/// Native LispKit library exposing library-path extension.
/// Scheme name: (modaliser library-path)
///
/// Provides: prepend-library-path!
final class LibraryPathLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "library-path"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("prepend-library-path!", prependLibraryPath))
    }

    /// (prepend-library-path! path) → boolean
    /// Adds `path` to the front of LispKit's library search list.
    /// Returns #t if the path exists and was added; #f if the path
    /// is missing (silently skipped, matching LispKit's behaviour).
    private func prependLibraryPath(_ path: Expr) throws -> Expr {
        let raw = try path.asString()
        let expanded = NSString(string: raw).expandingTildeInPath
        let added = self.context.fileHandler.prependLibrarySearchPath(expanded)
        return .makeBoolean(added)
    }
}
```

- [ ] **Step 1.4: Register the library in `SchemeEngine`**

In `Sources/Modaliser/SchemeEngine.swift`, find the block of `try context.libraries.register(libraryType: …)` / `try context.environment.import(… .name)` calls (currently lines ~42–68). Add the two lines below for `LibraryPathLibrary`. Place them near the top of the block (just below the `LifecycleLibrary` registration) so the primitive is available before anything else runs.

```swift
try context.libraries.register(libraryType: LibraryPathLibrary.self)
try context.environment.import(LibraryPathLibrary.name)
```

- [ ] **Step 1.5: Run the test to verify it passes**

Run: `swift test --filter LibraryPathTests`

Expected: both `prependLibraryPathIsExportedProcedure` and `prependLibraryPathSilentlySkipsMissingDir` pass.

- [ ] **Step 1.6: Commit**

```bash
git add Sources/Modaliser/LibraryPathLibrary.swift Sources/Modaliser/SchemeEngine.swift Tests/ModaliserTests/LibraryPathTests.swift
git commit -m "$(cat <<'EOF'
feat(modular-config): expose (prepend-library-path! …) primitive

Phase A step 1 of the modular-config plan. Adds LibraryPathLibrary,
a one-procedure native library wrapping LispKit's
prependLibrarySearchPath. Forgiving by design: a missing path returns
#f rather than throwing, so user code can call it unconditionally.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Prepend bundled-stdlib + user-config roots to the library search path

**Files:**
- Modify: `Sources/Modaliser/SchemeEngine.swift` (add `userConfigDir` init param; prepend both roots during init)
- Modify: `Tests/ModaliserTests/LibraryPathTests.swift` (add the end-to-end resolution test)

- [ ] **Step 2.1: Write the failing test**

Append this `@Test` to the existing `LibraryPathTests` struct in `Tests/ModaliserTests/LibraryPathTests.swift`. It builds a fresh tmp directory, writes a tiny `(foo bar)` library under it, points a new `SchemeEngine` at that tmp dir, and checks that `(import (foo bar))` resolves and the exported procedure is callable.

```swift
    @Test func userConfigRootResolvesUserLibrary() throws {
        // Build a tmp user-config root: <tmp>/foo/bar.sld
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modaliser-libpath-test-\(UUID().uuidString)",
                                   isDirectory: true)
        let fooDir = tmpRoot.appendingPathComponent("foo", isDirectory: true)
        try FileManager.default.createDirectory(at: fooDir,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let libBody = """
        (define-library (foo bar)
          (export greet)
          (import (scheme base))
          (begin
            (define (greet) "hello-from-foo-bar")))
        """
        try libBody.write(to: fooDir.appendingPathComponent("bar.sld"),
                          atomically: true, encoding: .utf8)

        let engine = try SchemeEngine(userConfigDir: tmpRoot.path)
        try engine.evaluate("(import (foo bar))")
        #expect(try engine.evaluate("(greet)").asString() == "hello-from-foo-bar")
    }
```

- [ ] **Step 2.2: Run the test to verify it fails**

Run: `swift test --filter LibraryPathTests.userConfigRootResolvesUserLibrary`

Expected: compile error — `SchemeEngine` has no `userConfigDir:` initializer. That's what we'll add next.

- [ ] **Step 2.3: Add `userConfigDir` init parameter and prepend both roots**

In `Sources/Modaliser/SchemeEngine.swift`, modify `init()` as follows.

**(a)** Change the signature on line 12 from:

```swift
    init() throws {
```

to:

```swift
    init(userConfigDir: String? = nil) throws {
```

**(b)** Find the block (currently lines ~33–38) that resolves the Scheme directory:

```swift
        schemeDirectoryPath = SchemeEngine.resolveSchemeDirectory()
        if let schemePath = schemeDirectoryPath {
            _ = context.fileHandler.addSearchPath(schemePath)
            try evaluate("(define *scheme-directory* \"\(schemePath)\")")
            NSLog("SchemeEngine: Scheme directory at %@", schemePath)
        }
```

Replace the entire `if let schemePath = schemeDirectoryPath { … }` body with:

```swift
        if let schemePath = schemeDirectoryPath {
            _ = context.fileHandler.addSearchPath(schemePath)
            try evaluate("(define *scheme-directory* \"\(schemePath)\")")
            // Prepend the bundled Modaliser stdlib root so (import (modaliser …))
            // resolves to files under <scheme>/lib/. Auto-added LispKit
            // R7RS+SRFI root remains last on the list.
            let bundledLibRoot = (schemePath as NSString).appendingPathComponent("lib")
            _ = context.fileHandler.prependLibrarySearchPath(bundledLibRoot)
            NSLog("SchemeEngine: Scheme directory at %@", schemePath)
        }

        // Prepend the user-config root LAST, so it ends up FIRST on the
        // library search path — user libraries shadow bundled ones.
        // Missing path is silently skipped by prependLibrarySearchPath.
        let resolvedUserConfigDir = userConfigDir
            ?? NSString(string: "~/.config/modaliser").expandingTildeInPath
        _ = context.fileHandler.prependLibrarySearchPath(resolvedUserConfigDir)
```

- [ ] **Step 2.4: Run the test to verify it passes**

Run: `swift test --filter LibraryPathTests.userConfigRootResolvesUserLibrary`

Expected: PASS. The `(import (foo bar))` form resolves `<tmp>/foo/bar.sld` because that tmp dir is now at the front of `librarySearchUrls`.

- [ ] **Step 2.5: Run the full test filter to confirm Task 1 tests still pass**

Run: `swift test --filter LibraryPathTests`

Expected: all three tests in `LibraryPathTests` pass.

- [ ] **Step 2.6: Commit**

```bash
git add Sources/Modaliser/SchemeEngine.swift Tests/ModaliserTests/LibraryPathTests.swift
git commit -m "$(cat <<'EOF'
feat(modular-config): user-config + bundled stdlib on library lookup path

Phase A step 2 of the modular-config plan. SchemeEngine now prepends
two roots to LispKit's library search list during init: the bundled
<scheme>/lib/ dir (so future (modaliser …) libraries resolve), then
~/.config/modaliser/ (so user libraries shadow bundled ones). Order
on the final list: [user-config, bundled, host-auto-added].

A new userConfigDir: init parameter lets tests point the engine at a
tmp directory and observe (import …) resolving against it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Document the user-library surface

**Files:**
- Create: `docs/user-libraries.md`

- [ ] **Step 3.1: Create the documentation page**

Create `docs/user-libraries.md` with this exact content. The doc covers the layout, the lookup path order, the `prepend-library-path!` primitive, and ships a copy-pasteable 5-line example.

```markdown
# User libraries

Modaliser ships with R7RS `import` wired up so you can split your
configuration across multiple files under `~/.config/modaliser/`.

## File layout

The only fixed name is `~/.config/modaliser/config.scm` — the entry
point Modaliser loads at startup. Everything else is your choice:

- **Plain `.scm` files** are pulled in via `(include "path/to/file.scm")`.
  Paths resolve relative to the file containing the `include` form.

- **Library files** are R7RS `define-library` definitions in `.sld`
  files. Their location is dictated by the library name: a library
  called `(my-prefix helpers)` lives at `my-prefix/helpers.sld` under
  `~/.config/modaliser/`.

You pick the first segment of your library names. Recommended: anything
except `scheme`, `srfi`, or `modaliser` (those have well-known meanings).

## Lookup path order

`(import …)` consults this ordered list of roots, first match wins:

1. `~/.config/modaliser/` — your config
2. `<Modaliser.app>/Contents/Resources/Scheme/lib/` — bundled `(modaliser …)`
3. The host's R7RS + SRFI directory — auto-registered by LispKit

User-first ordering means you can shadow any bundled library by
dropping a same-named file under `~/.config/modaliser/`. Useful for
local patches; otherwise stay clear of the `modaliser` prefix.

## Extending the path

Need an additional root (a sibling checkout, a team-shared directory)?
Call this from `config.scm`:

\`\`\`scheme
(prepend-library-path! "/abs/path/to/extra/libraries")
\`\`\`

The path is prepended in front of the user-config root, so additional
roots win against everything. A path that doesn't exist is silently
skipped — safe to call unconditionally.

## Example

Save this as `~/.config/modaliser/example/hello.sld`:

\`\`\`scheme
(define-library (example hello)
  (export greet)
  (import (scheme base))
  (begin
    (define (greet) "hello from example/hello")))
\`\`\`

Then from `~/.config/modaliser/config.scm`:

\`\`\`scheme
(import (example hello))
(display (greet)) (newline)
\`\`\`

When Modaliser starts, it logs `hello from example/hello` to Console.

## What's not in this phase

The `(modaliser …)` prefix is reserved for libraries Modaliser ships.
In this phase the prefix is wired up but no `(modaliser …)` libraries
are published yet — that comes in later phases (DSL wrapping, stdlib
carve-out). For now, all DSL forms (`key`, `group`, `define-tree`, …)
remain top-level globals exactly as before.
```

Note: in the file above, the four `\`\`\`` fences are written as literal three-backtick fences — the backslash escapes are only here to keep this plan file's outer fences balanced. When you write the file, use plain three-backtick fences without backslashes.

- [ ] **Step 3.2: Verify the file renders sensibly**

Run: `head -40 docs/user-libraries.md`

Expected: clean markdown, headings render as headings, code fences are three plain backticks.

- [ ] **Step 3.3: Commit**

```bash
git add docs/user-libraries.md
git commit -m "$(cat <<'EOF'
docs(modular-config): user-libraries.md for Phase A

Documents the user-config layout, library lookup path order, the
(prepend-library-path! …) primitive, and a copy-pasteable example.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Final verification — full suite green

**Files:** none (verification only)

- [ ] **Step 4.1: Run the full test suite**

Run: `swift test`

Expected: all 348+ pre-existing tests pass; 3 new `LibraryPathTests` tests pass. Total ~351 tests, zero failures.

If anything fails, do not paper over it — read the failure, decide whether the cause is in this phase's changes or a pre-existing flake, and either fix it or report the discrepancy and stop.

- [ ] **Step 4.2: Build the release binary as a final sanity check**

Run: `swift build -c release 2>&1 | tail -20`

Expected: build succeeds. No warnings introduced by the new file.

- [ ] **Step 4.3: Spot-check the bundled-stdlib path is non-fatal even when empty**

This is a one-shot REPL check, useful because `<scheme>/lib/` currently has no `modaliser/` subdir — we want to confirm registering the path doesn't crash at startup.

Run: `swift test --filter LibraryPathTests.prependLibraryPathIsExportedProcedure`

Expected: PASS. (This test instantiates `SchemeEngine()` with no overrides, exercising the default path-registration code.)

---

## Self-review checklist (run after writing — done)

- [x] **Spec coverage.** Phase A scope per kickoff: (1) lookup path registration via `prependLibrarySearchPath` — Task 2. (2) `(prepend-library-path! …)` primitive — Task 1. (3) Doc page — Task 3. (4) Tiny example — embedded in Task 3's doc. (5) Test that a tmp `.sld` under a tmp user-config dir resolves via `import` — Task 2 test. (6) Build + suite green — Task 4. All covered.
- [x] **No placeholders.** Every code block is concrete and copy-pasteable; no TODO/TBD; no "similar to" references.
- [x] **Type consistency.** `prepend-library-path!` returns Bool throughout (Swift `prependLibraryPath` returns `Expr` via `.makeBoolean`; tests assert `== .false` / `.true`). `userConfigDir: String? = nil` consistent between `SchemeEngine.init` signature and the test call site.
- [x] **Phase boundary respected.** No DSL wrapping (Phase B), no stdlib carve-out (Phase C), no portability cleanup (Phase D). Only path registration + primitive + docs.

---

## Out of scope for Phase A (deliberate non-goals)

- Wrapping the Modaliser DSL in `(modaliser dsl)` — Phase B.
- Creating any bundled `(modaliser …)` `.sld` libraries — Phase B/C.
- Env-var (`MODALISER_PATH`) or config-file (`load-path.txt`) extension mechanisms — explicitly deferred per spec.
- Migrating existing users' `~/.config/modaliser/config.scm` — no migration in any phase; new installs get the new seed.
