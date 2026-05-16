# Modular Config Architecture — Multi-Session Kickoff

> **For agentic workers:** This is a *kickoff* prompt, not a step-by-step plan. It orchestrates a four-phase implementation across separate sessions. In each session you handle exactly **one phase**: read the spec for that phase, use `superpowers:writing-plans` to produce the phase's detailed task plan, then use `superpowers:subagent-driven-development` to execute it. Don't try to do more than one phase in a single session — each phase needs its own review/commit/merge cycle and changes the foundation the next phase builds on.

**Spec:** [`docs/superpowers/specs/2026-05-16-modular-config-architecture-design.md`](../specs/2026-05-16-modular-config-architecture-design.md)

Read it before doing anything else. The spec defines: layered architecture (core / stdlib / user), library lookup path (user-config → bundled Modaliser → host R7RS+SRFI; user-first; first-match-wins), `(prepend-library-path!)` as the only extension mechanism, builder pattern for stdlib libraries.

---

## How to use this file

A human will hand this file (or a reference to it) to a fresh Claude Code session and say something like *"start phase A"* or *"start the next pending phase."* That session must:

1. Read the spec and this kickoff file.
2. Pick the next phase to execute — by default, the first one not yet committed on `main`. Check `git log --oneline main` for `feat(modular-config)`-prefixed commits to determine status.
3. Open a worktree for the work (use `superpowers:using-git-worktrees`). Branch name: `phase-<letter>-<short-name>`, e.g. `phase-a-lookup-path`.
4. Invoke `superpowers:writing-plans` to draft a detailed per-phase plan in `docs/superpowers/plans/2026-MM-DD-modular-config-phase-<letter>-<name>.md`. The plan covers files to touch, task-by-task TDD steps, and explicit verification commands.
5. Get the human's approval on the plan (or proceed if they've delegated it).
6. Invoke `superpowers:subagent-driven-development` to execute the plan. Tasks within a phase are often parallelizable (DSL refactor + matching test updates are one example); the skill handles dispatch.
7. Verify with `superpowers:verification-before-completion`: build cleanly, tests pass, sample user-config scenarios still work.
8. Invoke `superpowers:requesting-code-review` before merging.
9. Finish with `superpowers:finishing-a-development-branch` — commit on the phase branch, merge to `main` with a `Merge: phase <letter> — <summary>` commit, remove the worktree.
10. Stop. The next session picks up the next phase.

The phases are *sequential*. Phase B's DSL wrap depends on Phase A's lookup path. Phase C's stdlib libraries depend on Phase B's `(modaliser dsl)`. Phase D depends on C. Do not parallelize across phases.

---

## Phase A — Library lookup path with user-config root

**Goal:** make `(import …)` find user-shipped `.sld` files under `~/.config/modaliser/`, with the user-config root first on the path so user libraries can shadow bundled ones.

**Scope (per spec):**
- `SchemeEngine.swift` registers the lookup path during init: user-config first via `prependLibrarySearchPath`, then the bundled Modaliser stdlib root, then LispKit's host R7RS+SRFI root (auto-added).
- Expose a Scheme primitive `(prepend-library-path! "/abs/path")` so user code can extend the path further. A non-existent path is silently skipped (matching LispKit's existing behaviour).
- Write a doc page (`docs/user-libraries.md` or similar) explaining the layout, the lookup path order, and the `(prepend-library-path!)` primitive.
- Ship a tiny example: `~/.config/modaliser/example/hello.sld` with a 5-line library and a one-line `(import …)` snippet showing it works.

**Out of scope:**
- Wrapping the Modaliser DSL into a library — that's Phase B.
- Any environment-variable or `load-path.txt` extension mechanism — explicitly deferred.

**Verification:**
- Build + full test suite green.
- New test: from a fresh `SchemeEngine`, write a temp `.sld` file under a temp user-config dir, point the engine at it, confirm `(import …)` resolves the library and an export is callable.
- Manual: drop the example `.sld` under `~/.config/modaliser/` and import it from the REPL.

**Estimated diff:** ~15 lines of Swift + tests + doc. Single short PR.

---

## Phase B — Wrap Modaliser DSL into `(modaliser dsl)` library

**Goal:** the Modaliser DSL surface (`key`, `key-range`, `group`, `selector`, `action`, `define-tree`, `set-leader!`, `set-host-header!`, `set-overlay-delay!`, `set-overlay-css!`, modifier constants) becomes a proper R7RS library importable as `(modaliser dsl)`. The library imports only `(scheme base)` and other `(modaliser …)` libraries — no `(lispkit …)` references.

**Scope (per spec):**
- Convert `Sources/Modaliser/Scheme/lib/dsl.scm` into `lib/modaliser/dsl.sld` with explicit `(define-library …)` form, `(export …)` list, and `(import (scheme base) …)`.
- Identify and convert `dsl.scm`'s pure-Scheme dependencies into libraries: at minimum `keymap.scm` → `(modaliser keymap)` (for `MOD-CMD` etc.), and the pieces of `state-machine.scm` that `dsl.scm` calls (`register-tree!`) → `(modaliser state-machine)`. Cascade as needed.
- Audit each converted file: imports must reference only `(scheme …)`, `(srfi …)`, and other `(modaliser …)` libraries. No `(lispkit …)` allowed in any file moving into a library.
- Update `root.scm` to `(import (modaliser dsl))` (and whatever other libraries it now needs to see at top level) so the bundled `default-config.scm` and the user's `config.scm` still see the DSL names at top level when their `include` splices fire.
- Update each affected test file to switch from `include`-style loading to `import`-style.

**Out of scope:**
- Carving `default-config.scm` into per-app libraries — that's Phase C.
- Refactoring the OS-primitive native libraries — they're already namespaced as `(modaliser shell)`, `(modaliser app)` etc., and stay as-is.

**Verification:**
- Full test suite green.
- A library file written under `~/.config/modaliser/<userprefix>/foo.sld` that does `(import (modaliser dsl))` can call `define-tree` / `key` / `key-range` and the tree shows up in the overlay.
- The bundled `default-config.scm` still loads at app startup.

**Estimated diff:** medium. Touches multiple internal Scheme modules + test bootstrap. Don't underestimate — the test harness changes are easy to get wrong.

---

## Phase C — Carve `default-config.scm` into stdlib libraries

**Goal:** Modaliser ships a curated stdlib of opt-in, parameterizable libraries (`(modaliser apps iterm)`, `(modaliser apps safari)`, `(modaliser apps chrome)`, `(modaliser window-actions)`, `(modaliser space-switching)`, `(modaliser leader)`). The thinned `default-config.scm` becomes an example that imports these and registers default trees — used as the first-run seed for user configs.

**Scope (per spec):**
- Builder pattern: each library exports a builder returning a tree node (e.g. `iterm-local-tree`) plus a convenience that registers it (`iterm-register-default!`). Both take keyword-style alist options.
- Move per-app definitions out of `default-config.scm` into `lib/modaliser/apps/<name>.sld`.
- Move window-management helpers, the Spaces 1..N pattern, and leader conveniences into their own libraries.
- Rewrite `default-config.scm` as a thin example: imports + a small number of calls. This file is what `root.scm` copies to `~/.config/modaliser/config.scm` on first run, so it should read as a tutorial of the library surface.

**Out of scope:**
- Deprecating the existing seeded config for users who already have one — no migration helper, no automatic rewrite of their `~/.config/modaliser/config.scm`. Users keep what they have; new installs get the new seed.

**Verification:**
- Full test suite green; tests cover each builder's defaults *and* parameterized calls.
- New user gets the seeded config, relaunches the app, sees the iTerm tree / Spaces / window helpers all working.
- Existing user (pre-Phase-C `config.scm`) still loads correctly because their file references the DSL through `(modaliser dsl)`, which is unchanged. (Document that they can optionally migrate to the new builder API for less code.)

**Estimated diff:** large. The bulk of the visible behaviour-shape work lives here.

---

## Phase D — User-facing portability cleanup

**Goal:** audit the user-facing surface — bundled `default-config.scm`, any seeded files, all stdlib libraries — for residual references to host-specific bindings. Replace `(lispkit …)` imports with `(scheme …)` / `(srfi …)` / `(modaliser …)` equivalents wherever possible. Document the "portable surface" — what configuration code can assume exists across hosts.

**Scope (per spec):**
- Grep the user-facing tree for `(lispkit `, `(import (lispkit`, and any LispKit-only procedure names that snuck in. Replace or document each.
- Write `docs/portability.md` summarising the assumed surface: R7RS standard libraries, SRFI subset, `(modaliser …)` libraries available everywhere a config runs.
- Add a CI-style check (or at minimum a documented manual procedure) that flags new `(lispkit …)` references in the user-facing tree.

**Out of scope:**
- Producing an actual Chez or Racket build of Modaliser. That's a much larger effort and lives in a separate project (APIAnyware backed). This phase only makes the *configuration language* portable; the host backend stays LispKit for now.

**Verification:**
- `grep -r '(lispkit ' Sources/Modaliser/Scheme/lib/modaliser/` returns nothing.
- The portability doc exists and is accurate.

**Estimated diff:** small. Mostly cleanup + documentation.

---

## Cross-phase conventions

- **Branch per phase, merge commit per phase**, matching the existing `git log` style on this repo.
- **Commit messages** follow conventional commits: `feat(<area>):`, `fix(<area>):`, `docs(<area>):`. Use `feat(modular-config): …` for changes specifically advancing this plan, so progress is greppable.
- **No `--no-verify`, no `--amend` of pushed commits.** If a pre-commit hook fails, fix the underlying issue and make a new commit.
- **Tests**: each phase must leave the full suite green. Don't commit a phase that breaks tests, even temporarily.
- **Spec drift**: if a phase reveals the spec is wrong, update the spec in the same branch as the implementation. Don't silently diverge.
- **Stopping point**: each session ends after one phase, on `main`, with the worktree removed.
