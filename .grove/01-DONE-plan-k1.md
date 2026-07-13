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

Grilled 2026-07-13. Decision log (human's calls):

1. hjkl pane-focus moves **fully** under the Panes drill — no top-level
   duplicate. Retires "herdr owns the top-level hjkl" (ADR-0013 + the
   CONTEXT.md Replace/Augment entry reworked inline to the splice-identity
   formulation, which is layout-independent).
2. Drill row: `p` → "Panes" (plural, parallel to the sibling drills).
3. Inner keys **renormalized**: `s` Split (against the keep-`x`
   recommendation — human explicitly chose the redesign), `m`/`z`/`d` kept.
4. Short inner labels: Split / Move / Zoom / Close.
5. Panes list + chips + digit-jump move into the drill (`<leader> p 3`).

New glossary term: **Panes drill (herdr)**. Tree grown: pane-drill-k2
(work) carries the full target shape + reconciliation sweep.

Mid-session, the human raised two further concerns — externalized as
leaves per the Decompose rule, not absorbed: pane-list-tab-local-k3
(work: panes list scoped to the displayed tab, precedent 5b2ffa1) and
prev-next-nav-k4 (planning: prev/next cycling for the four groups —
keys/wrap/walk semantics need their own grilling).
