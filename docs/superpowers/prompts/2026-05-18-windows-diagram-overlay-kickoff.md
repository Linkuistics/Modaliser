# Windows Diagram Overlay — Implementation Kickoff

> **For agentic workers:** Read this whole file plus the linked spec and plan before doing anything. The plan is fully written and bite-sized; your job is to execute it task-by-task using `superpowers:subagent-driven-development`, with review checkpoints between tasks.

## Inputs

- **Spec:** [`docs/superpowers/specs/2026-05-18-windows-diagram-overlay-design.md`](../specs/2026-05-18-windows-diagram-overlay-design.md)
- **Plan:** [`docs/superpowers/plans/2026-05-18-windows-diagram-overlay.md`](../plans/2026-05-18-windows-diagram-overlay.md)
- **Visual mockup (canonical):** `.superpowers/brainstorm/26594-1779079825/content/layout-v19.html` — open in a browser to see the exact pixel target. If that session directory has been cleaned up, the spec's prose description plus the brainstorming history in the original PR thread is the next-best reference. Reproduce the mockup by reading the diagram-panel.css + diagram-panel.js code from the plan.

## What this work delivers

A diagrammatic which-key panel for the Windows group: keys laid out on mini screen-rectangles in the positions they target. Plus a numbered current-space window picker (`1..`) that paints chips like the iTerm pane selector. Plus a generalisation: any group can declare `'renderer 'TYPE` and ship its own JS/CSS via a new `add-overlay-asset!` API; SysSync widens to mirror the whole `Sources/Modaliser/Scheme/` tree into `~/.config/modaliser/sys/scheme/` so every bundled non-Swift file is discoverable and shadowable.

## How to use this file

A human hands this file to a fresh Claude Code session and says *"start the windows-diagram implementation"* or *"continue the windows-diagram plan from where it stopped."* That session must:

1. **Verify branch state.** Check `git log --oneline main` for any commits with the prefix `feat(windows-diagram):` or matching the plan's task commit messages. Determine which tasks (if any) are already done. The plan tasks are numbered 1-10, each producing exactly one commit. Skip completed tasks; resume at the next pending one.
2. **Open a worktree** for the work using `superpowers:using-git-worktrees`. Suggested branch name: `windows-diagram-overlay`.
3. **Read the spec end-to-end.** Then read the plan. Don't skip the self-review notes at the bottom of the plan — there's a type-consistency note about `col-span`/`row-span` (Scheme convention) vs `colSpan`/`rowSpan` (JS convention) that gets fixed in Task 8.
4. **Execute tasks via `superpowers:subagent-driven-development`.** Dispatch one subagent per task. The plan's task structure (Files / Step 1: write test / Step 2: run failing / Step 3: implement / Step 4: run passing / Step 5: commit) is the exact contract — pass it to each subagent verbatim. Review after each task before launching the next.
5. **Verify with `superpowers:verification-before-completion`** at the end: full `swift test` green, smoke verification per Task 10 done.
6. **Code review pass with `superpowers:requesting-code-review`** before merge.
7. **Finish with `superpowers:finishing-a-development-branch`** — merge to `main` with a `Merge: windows diagram overlay panel` commit and cleanup the worktree.
8. Update memory if anything surprising surfaced. The `feedback_diagrams.md` (prefer Mermaid over ASCII), `feedback_webview_display_server.md` (Display PostScript pattern), and `feedback_no_in_place_reload.md` memories are relevant context.

## Task order (read top-to-bottom; later tasks depend on earlier)

1. Broaden SysSync — mirror full Scheme tree into `sys/scheme/`
2. Wire SchemeEngine to the new sys/scheme path
3. `add-overlay-asset!` API + extra-css/js threading
4. Renderer dispatch — typed payload in Scheme, registry in JS
5. Diagram-panel library — Scheme constructors + matrix parser
6. Diagram-panel library — CSS + JS renderer assets
7. Swift `list-current-space-windows` with bounds
8. `window-actions.sld` — matrix-based default layout, rename `s` → `n`
9. Dynamic `1..` selector with chip painting (iTerm pane pattern applied to windows)
10. End-to-end smoke verification (build, install, exercise live)

Tasks 1-2 are pure infrastructure with no behaviour change visible to the user — land them first, they unblock everything else. Tasks 3-4 add plumbing with no consumers. Tasks 5-6 add the diagram-panel library that consumes the plumbing. Task 7 is an independent Swift change. Tasks 8-9 wire window-actions to the new infrastructure. Task 10 verifies.

Parallelism opportunities (dispatch in same message):
- Tasks 1 and 7 are independent (Swift-only changes, different files).
- Tasks 5, 6 can be split — Task 5 is the .sld + tests; Task 6 is the .css + .js + integration tests.

Most tasks should NOT be parallelized — they depend on each other in the listed order.

## Cross-task conventions

- **Branch:** one worktree `windows-diagram-overlay`, one commit per task (as the plan specifies), merge commit at the end. Match the existing repo style (`Merge: <short summary>` on the merge commit).
- **Commit messages:** the plan provides exact `git commit -m "..."` blocks. Use them verbatim — they include the `Co-Authored-By` trailer and conform to conventional-commits prefixes (`sync:`, `engine:`, `overlay:`, `diagram-panel:`, `window:`, `window-actions:`).
- **TDD discipline:** every task starts with a failing test. Don't skip the "run to verify failure" step — it catches typos in test names, missing imports, etc. that would otherwise hide.
- **No `--no-verify`, no `--amend` of pushed commits.** If a pre-commit hook fails, fix the underlying issue and make a new commit.
- **Spec drift:** if a task reveals the spec is wrong, update the spec in the same branch as the implementation. Don't silently diverge. Same for the plan.
- **The visual target is v19.** If the rendered output doesn't match the v19 mockup, the rendered output is wrong (not the mockup). Read the mockup's CSS to confirm fine details (stroke widths, panel size, arrow geometry).

## Stopping points

You can stop after any task (each task is a self-contained commit). The plan's task boundaries are sized so the next session can pick up cleanly from `git log`. If you stop mid-task — finish the current Step in the plan, commit, and explicitly note where you stopped in the session summary.
