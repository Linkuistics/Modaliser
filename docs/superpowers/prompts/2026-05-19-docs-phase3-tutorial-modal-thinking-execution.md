# Modal Thinking Tutorial — Fresh-Session Execution Prompt

> **For agentic workers:** This is a *kickoff* prompt for a fresh
> Claude Code session whose job is to **execute** an already-written
> implementation plan, not to brainstorm or design. Read it
> end-to-end before touching anything.

## What you're doing

Executing the Phase-3 docs slice for Modaliser: writing
`docs/tutorials/modal-thinking.md`, cross-linking it, link-checking,
running `swift test`, getting code review, and merging to `main`.

All the upstream design work is done. **Do not re-brainstorm and do
not re-write the plan.** Your job is to follow the plan task by task,
on the live system, with the user in the loop.

## Where the artefacts live

- **Spec (design):**
  `docs/superpowers/specs/2026-05-19-docs-phase3-tutorial-modal-thinking-design.md`
- **Plan (the thing you execute):**
  `docs/superpowers/plans/2026-05-19-docs-phase3-tutorial-modal-thinking.md`

Both are committed on `main`. The brainstorm/planning worktree they
were drafted in has been removed; you start from clean `main`.

## How to run

1. **Open a fresh worktree.** Use `EnterWorktree` with a new name
   (suggested: `docs-phase3-tutorial-modal-thinking`). The harness
   default base is `origin/main`; if local `main` is ahead, fast-
   forward with `git merge --ff-only main` before starting.
2. **Invoke `superpowers:executing-plans`.** Point it at the plan file
   above. The plan is structured for inline execution: tasks are
   small, each has explicit checkboxes, and commits happen frequently.
   Subagent-driven execution is *not* recommended here because Tasks
   4–10 require user-facing prompts ("please relaunch and report what
   you see") that a subagent can't run.
3. **Work the plan top-down.** Tasks are numbered 1–19. Each task's
   "Files" header lists what gets touched; each step is a single
   2–5-minute action.

## Things you must know before starting

These are loaded as auto-memory but worth restating because they are
load-bearing for this slice:

- **Modaliser goes public around 2026-W21.** The tutorial is written
  for external readers, not single-user future-self. See memory
  `project_public_release`.
- **Selector Tab-to-show-actions does not work.** The plumbing exists
  in `chooser.scm` / `launchers.sld` but is broken. The tutorial must
  not mention Tab, `'actions`, or "press Tab to see what you can do
  with the highlighted item" anywhere. See memory
  `project_selector_actions_broken` and the spec's *Known broken*
  section.
- **Reload = Relaunch.** Every config edit gets a "Pick **Relaunch**
  from the menu bar icon" prompt. Never imply hot-reload or in-place
  config reload. See memory `feedback_no_in_place_reload`.
- **Source changes need `./scripts/install.sh`, config changes don't.**
  This plan is config-only — `Relaunch` from the menu bar icon is
  enough between snippets. See memory `feedback_install_flow`.

## Human-in-the-loop expectations

Tasks 4–10 each have a step where you write a snippet to the user's
live `~/.config/modaliser/config.scm`, then ask the user (in chat) to
relaunch + press F18 + describe what they see. **Wait for the user's
reply before writing the prose for that step.** If a verification
beat doesn't behave as the plan predicts, fix the snippet first —
don't paper over and don't write prose that documents behaviour you
couldn't observe.

Concretely, when prompting the user, use the wording in the plan
(or close to it). For example, Task 4 Step 2 reads:

> "I've replaced `~/.config/modaliser/config.scm` with the Step-1
> snippet. Please:
> 1. Pick **Relaunch** from the menu bar icon.
> 2. Position any window so you can tell if it maximises.
> 3. Press **F18 w**.
> 4. Did the window maximise?"

The user may answer briefly ("yes", "did nothing", "centred not
maximised"). Adjust accordingly. If they say "did nothing", the snippet
is wrong — likely the wrong primitive name from Task 1 Step 3. Fix
that *before* moving on.

## What "done" looks like

Definition of done lives in the spec (`## Definition of done`), but
the short version is:

- `docs/tutorials/modal-thinking.md` exists, written verify-then-write.
- `docs/quickstart/index.md` has a *Tutorial* bullet above the how-to
  bullet in *What's next*.
- `docs/how-to/index.md` mentions the tutorial near its introduction.
- Internal link checker green for
  `docs/{quickstart,reference,how-to,tutorials}/`.
- `swift test` green.
- Code review run via `superpowers:requesting-code-review` and
  feedback addressed.
- The user's `~/.config/modaliser/config.scm` is restored from
  backup, the backup file is removed, and the user confirmed their
  pre-tutorial config is back.
- The kickoff prompt for the brainstorm
  (`docs/superpowers/prompts/2026-05-19-docs-phase3-tutorials-kickoff.md`)
  is dropped in a separate housekeeping commit (precedent: `86ac695`).
- **This** execution prompt is also dropped in the same housekeeping
  commit once the work is merged — it's a single-use kickoff, not a
  long-lived doc.
- Branch merged to `main` via `superpowers:finishing-a-development-branch`.
  Project convention is local merge → push to main; not a PR.

## If the plan is wrong

The plan was written before any step was actually run on the user's
machine. Two things might prove wrong during execution:

1. **Identifier names.** Steps 1, 6, 7 reference primitives like
   `window:maximise` and `focus-window-direction`. If those don't
   exist in `window-actions.sld`, substitute whatever does export —
   per the plan's Task 1 Step 3 fallback rules. The *shape* of each
   step is what matters, not the specific call.
2. **Verification beats.** If pressing the documented keys doesn't
   reproduce what the plan describes (and the snippet is correct),
   investigate. The likely culprit is a misunderstood semantic in
   `state-machine.sld` — re-read Task 1 Step 5 against the actual
   code.

In either case, fix the spec and the plan inline (`docs/superpowers/
specs/` and `docs/superpowers/plans/`) **and** mention the correction
in the commit message so this kickoff and its descendants don't drift.

## What's out of scope for this execution

- New libraries. If a tutorial step surfaces missing functionality,
  log a follow-up note in `docs/superpowers/plans/` and proceed with
  whatever shape the existing libraries support.
- More tutorials. Phase 3 ships *one* tutorial (Modal Thinking) by
  design; additional tutorials are deferred. The Diátaxis restructure
  closes as "3 quadrants written + 1 deferred by intent".
- Reference revisions, how-to additions, theming changes, or anything
  outside `docs/tutorials/`, `docs/quickstart/`, `docs/how-to/index.md`.
- Source-code changes. `swift test` should be a no-op verification at
  the end. If you touch `Sources/`, you've gone off-plan; stop and
  reassess.

## Final note

The previous session's brainstorm and plan-writing have been merged
to `main` and that working branch was deleted. You're picking up
cold from a clean `main`. Read the plan first (it's ~1500 lines, but
most of it is task bodies you'll consume one at a time), then start
with Task 1.
