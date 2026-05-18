# Block-List Overlay — Fresh-Session Kickoff

> **For agentic workers:** This is a *kickoff* prompt for a fresh Claude Code session. The previous session brainstormed the design end-to-end and committed it to the plan doc; don't re-litigate the architecture, follow it. Read the plan first, draft a detailed TDD plan with `superpowers:writing-plans`, then execute with `superpowers:subagent-driven-development` (most tasks are independent and parallelizable).

**Plan:** [`docs/superpowers/plans/2026-05-18-block-list-overlay.md`](../plans/2026-05-18-block-list-overlay.md)

Read it before doing anything else. The plan defines: the block-list renderer architecture, the initial block types (`window-diagram`, `which-key`, `window-list`), the category-wrapping form for `which-key` (with misc-vs-category render rules), the chip-painting effect contract, and a 6-task migration path with the windows overlay as the validation target.

---

## How to use this file

A human will hand this file (or a reference to it) to a fresh Claude Code session — likely with a prompt like *"start the block-list overlay redesign"*. That session must:

1. Read the plan in full. The design decisions captured under "Design decisions (settled during brainstorm)" are settled — don't re-debate them, follow them.
2. Open a worktree for the work (use `superpowers:using-git-worktrees`). Branch name: `block-list-overlay`.
3. Invoke `superpowers:writing-plans` to expand the 6 tasks into detailed per-task TDD step lists. Save the expanded plan back to `docs/superpowers/plans/2026-05-18-block-list-overlay.md` (replacing the high-level task descriptions with the detailed checklists), or to a sibling `*-detailed.md` if you'd rather keep the original as-is.
4. Get the human's approval on the expanded plan if anything changed structurally.
5. Invoke `superpowers:subagent-driven-development` to execute the plan. Tasks 1, 2, 3, 4 have independent file scopes (different blocks/ subdirs) and can be parallelized; Task 5 must wait for 1–4; Task 6 is optional (defer if time-constrained).
6. Verify with `superpowers:verification-before-completion`: `swift test` should remain green at every commit; manual smoke test of leader → `w` must reproduce identical behavior to today (panel grid + n/r entries + windows list with chips + HazeOver still skipped + deterministic ordering).
7. Invoke `superpowers:requesting-code-review` before merging — block-type protocol is new public surface.
8. Finish with `superpowers:finishing-a-development-branch` — merge to `main` with a single merge commit summarizing the architecture shift; remove the worktree.

---

## Pre-work context (already done, don't redo)

The previous session in worktree `windows-diagram-overlay` shipped these changes that this plan builds on:

- **HazeOver visibility fix** — `windowVisibleAtFunction` skips translucent windows (`alpha < 1.0`) when scanning for occluders. Diagnosis: HazeOver-class dimming utilities draw a full-screen overlay between focused and unfocused windows; the chip should still read as visible because the user sees through the tint.
- **Deterministic window ordering** — `listCurrentSpaceWindows` sorts by (y, x) instead of focus recency. Same arrangement → same digits across leader presses, enabling muscle memory.
- **Diagram-panel reflow** — `repeat(auto-fill, …)` instead of fixed 3 columns; overlay widens to its widest sibling and the grid fills the available space.
- **Hidden range-command** — `(cons (cons 'hidden #t) …)` on `window-range` suppresses its row in the entries strip; the `'hidden` flag is honored by the entries JSON builder in `ui/overlay.scm`. The which-key block in the new architecture obviates this, but the flag is general and can stay.
- **Padding/sizing polish** — diagram body 8px top/bottom, row-gap 0.5rem, entries-stack 14px margin, sticky-marker `+4px` font size with `top: -1px` nudge.

All committed; the working tree at the start of the new session will be on `main` with these landed.

---

## Stopping point

End on `main`, worktree removed, full test suite green. The new `'blocks` renderer is the canonical mechanism for the windows overlay; iTerm migration is optional follow-up.
