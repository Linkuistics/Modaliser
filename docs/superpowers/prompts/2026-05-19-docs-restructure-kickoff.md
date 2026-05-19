# Docs Restructure — Fresh-Session Kickoff

> **For agentic workers:** This is a *kickoff* prompt for a fresh Claude Code session. The previous session settled the structure and migration plan; don't re-litigate it, execute it. Read the plan first.

**Plan:** [`docs/superpowers/plans/2026-05-19-docs-restructure.md`](../plans/2026-05-19-docs-restructure.md)

Read it before doing anything else. The plan defines: the target Diátaxis layout (`docs/{quickstart,tutorials,how-to,reference}/`), the per-file migration of existing docs, what changed in the DSL since the legacy docs were written (so you don't re-mislead), the concrete write-list for Phase 1, and the stopping points to check in with the user.

---

## Scope of this session

- **Phase 1 only.** Quick-start + Reference (DSL + libraries + state-machine + theming + renderer protocol). Tutorials and how-tos are explicitly deferred.
- Don't write tutorials.
- Don't write how-tos.
- Don't start a theming refactor — `reference/theming.md` documents the *current* CSS vocabulary; the refactor is its own slice later.

---

## Workflow

1. **Open a worktree** (use `superpowers:using-git-worktrees`). Branch name: `docs-restructure`.
2. **Read the plan in full.** The migration table and the "What's currently true about the DSL" section are load-bearing — do not skip.
3. **Create the directory skeleton** (`docs/quickstart/`, `docs/tutorials/`, `docs/how-to/`, `docs/reference/`).
4. **Migrate the stable files** first (move, light-edit). `user-libraries.md`, `keyboard.md`, `portability.md` go straight into `docs/reference/`. Stop here and show the user `tree docs/` for confirmation before writing fresh prose.
5. **Write `quickstart/index.md`.** Single page, ~150 lines. Use current DSL. Stop and show the user for tone-check before continuing.
6. **Write `reference/dsl.md`.** Ground every signature against `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld`. Stop and show the user for review before writing the rest of `reference/`.
7. **Write the remaining `reference/` files** in roughly this order: `libraries.md`, `state-machine.md`, `renderer-protocol.md`, `theming.md`.
8. **Rewrite `README.md` light** to point at the new structure (the existing install / quick-start blocks mostly stand; only the doc-link list changes).
9. **Delete `docs/configuration.md` and `docs/scheme-api.md`** after confirming with the user (decision gate 4 in the plan).
10. **Verify**: `swift test` (in case anything moved or a code stub got tweaked), open every relative link in the new docs, render-check the markdown.
11. **Code review**: invoke `superpowers:requesting-code-review` — even for docs, a fresh pair of eyes will catch stale-DSL leakage that the writer's eyes glide past.
12. **Finish**: `superpowers:finishing-a-development-branch`.

---

## Anti-traps

The single biggest failure mode for this work is copying snippets from the legacy `configuration.md` / `scheme-api.md` without re-checking against current code. Every snippet that touches the DSL must be cross-checked against `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld` and the current `~/.config/modaliser/config.scm`. Specific forms that have changed and are easy to get wrong:

- `(selector "k" "label" …)` → **WRONG**. Now `(key "k" "label" (selector 'prompt … 'source … 'on-select …))`.
- `(make-which-key-block …)` → **WRONG**. Now `(which-key-block …)`.
- `(overlay 'key "w" 'label "Windows" …)` → still valid, but the idiomatic form is `(key "w" "Windows" (overlay …))` so `key`/`label` flow through `decorate-node`.
- `'renderer 'diagram` → **WRONG**. The diagram renderer was retired; window-diagram is now a block (`window-diagram-block`) inside the `'blocks` renderer.
- `(space:switch-actions)` → **WRONG**. `(modaliser space-switching)` is deleted. Use `(keys '("1" ..) "Goto Space <n>" (λ (k i ks) (send-keystroke '(ctrl) k)))` directly.
- Any reference to `lambda` in `(key K L …)` examples should also show `λ` as the Unicode shorthand (or vice versa) — both work; the bundled seed uses `λ`.

If you find yourself reaching for the legacy doc as a template, stop and re-read the relevant `.sld` file. That's the trap this whole refactor exists to fix.

---

## Stopping points (from the plan)

Stop and check with the user at these checkpoints:

1. After directory skeleton + migrations of stable files. Show `tree docs/`.
2. After `quickstart/index.md` is drafted. Tone-check.
3. After `reference/dsl.md` is drafted. Largest single piece.
4. Before deleting `configuration.md` / `scheme-api.md`. Confirm nothing external links to them.

---

## Pre-work context (already done, don't redo)

The previous session shipped the DSL overhaul this refactor exists to document, plus the LispKit-binding fix and category support. All on `main` as of `22365b2`. Memory files updated:

- `feedback_config_sync.md` — `~/.config/modaliser/config.scm` is canonical, bundled seed is a literal `cp` of it.
- `feedback_lispkit_library_scope.md` — top-level `.scm` files can't reliably read library-exported mutable cells; use accessor procedures.

Nothing to re-implement. Just write the docs against the current code.

---

## Definition of done (Phase 1)

- `docs/quickstart/index.md` exists and walks a new user from install → first-edit → relaunch in under 5 minutes of reading.
- `docs/reference/dsl.md` documents every form exported from `(modaliser dsl)` with a current signature and at least one example.
- `docs/reference/libraries.md` documents every user-facing `(modaliser …)` library with imports, exports, defaults, and one example per useful export.
- `docs/reference/state-machine.md` covers transient/sticky semantics, `modal-stack`, `'sticky-target`, `'exit-on-unknown`, `on-enter`/`on-leave` gating, category transparency.
- `docs/reference/renderer-protocol.md` describes the block protocol (`'type`, `'block-children`, `'on-render-fn`, `'on-enter-fn`, `'on-leave-fn`) and the which-key payload shape.
- `docs/reference/theming.md` inventories the current CSS variables and class names, and shows a worked override example.
- `docs/reference/library-system.md`, `docs/reference/keyboard.md`, `docs/reference/portability.md` exist as light edits of their predecessors.
- `docs/configuration.md` and `docs/scheme-api.md` are deleted.
- `README.md` links into the new structure.
- All cross-links resolve.
- `swift test` is green.
