---
kind: planning
---

# 010 — Recover terminal-backends design

A previous conversation evidently discussed this work but left no artifacts in
the repo: no branch in the reflog, no grove tree, no design notes beyond the
phase-1 docs (`docs/how-to/terminal-pane-aware-tree.md`,
`docs/reference/terminal-detection.md`) and the memory note
`project_terminal_detection_phase2.md`. This task re-establishes the design
from those durable traces plus what the user remembers.

## Procedure

1. **Re-read phase 1.** End-to-end:
   - the spec at `docs/superpowers/specs/2026-05-22-terminal-pane-and-remote-docs-design.md`
   - the reference `docs/reference/terminal-detection.md`
   - the how-to `docs/how-to/terminal-pane-aware-tree.md`
   - the current library `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
   - the `worktree-terminal-docs` merge: `git log --grep terminal` on main
2. **Grill the user** (`grilling.md`) on the open questions in `BRIEF.md`,
   priority order: backend priority → detection contract → multiplexer
   composition → "focused" semantics → naming.
3. **Reconcile** anything the user remembers with what the phase-1 docs
   actually committed to. If the docs already answer a question, that's the
   answer unless we explicitly decide to revise them.
4. **Glossary.** Append resolved terms (e.g. "focused pane", "host terminal",
   "multiplexer", "backend") to `CONTEXT.md` inline as they harden. Create
   `CONTEXT.md` at the repo root when the first term lands; don't pre-stub it.
5. **ADRs** only for decisions that are hard to reverse or genuinely
   surprising (e.g. choosing a cascade vs. siblings shape for the public API).
   Most calls here will not warrant one.
6. **PRD, lazily.** If the grilling converges on a real agreement worth
   sharing, write `docs/prd/terminal-backends.md`. If it doesn't converge,
   don't fabricate one.
7. **Grow the tree.** Replace this leaf with an ordered set of leaves — most
   likely one per backend, possibly preceded by a `005-contract/` node if the
   detection contract needs its own design pass.

## Exit conditions

Any of:
- Tree is grown with next leaves and (if needed) a PRD — proceed to the next
  task next session.
- Design reduces to "phase 2 is not ready" — record the reason in this file,
  retire the grove, leave the memory note pointing at it.

## Notes for the next session

- Read the bootstrap context first: glossary (if any), this `BRIEF.md`, this
  file. That is the mandate.
- The user's preference is Scheme-first: shell-outs and parsing live in
  `terminal.sld`; no Swift work. See [[feedback_scheme_first]] and
  [[feedback_scheme_driven_design]].
- LispKit gotchas: no `set-cdr!`/`set-car!` ([[feedback_lispkit_no_mutable_pairs]]);
  `define-library` body can't see top-level vars
  ([[feedback_lispkit_library_scope]]).
