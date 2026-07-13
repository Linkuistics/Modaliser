# plan-k1

**Kind:** planning

## Goal

Grill the target hierarchy for herdr's pane-level operations and grow the
tree accordingly.

## Context

- Human direction (2026-07-13, verbatim): "In the herdr tree, Move Pane,
  Close Pane, and Split all belong under a 'Pane' item, parallel to
  'Tabs', 'Workspaces', 'Agents' etc. Also, the pane list at the top
  level and pane focus operations should be under there as well until we
  work out a better hierarchy of interaction."
- Explicitly *not* a settled design — the human flagged "until we work
  out a better hierarchy of interaction," so the grilling should surface
  open questions (does hjkl pane-focus move under `Pane` too, or stay
  top-level since herdr "owns the top-level hjkl" per ADR-0013 /
  CONTEXT.md's Replace/Augment glossary entry? does the panes live-list's
  digit-jump/chips move with it?) rather than assume the answer.
- See the parent brief's Pointers for the current tree shape
  (`build-herdr-tree` in `muxes/herdr.sld`) and the Tabs/Workspaces/
  Agents/Worktrees drills as the existing `open "<key>" "<Label>"`
  pattern to mirror.

## Done when

Shared understanding reached on the target hierarchy (grown into the
tree as child leaves — see the Decompose step in the grove skill);
CONTEXT.md/ADR-0013 updated inline if the grilling changes what "herdr
owns the top-level hjkl" means.

## Notes
