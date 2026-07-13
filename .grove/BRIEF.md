# herdr-pane-group — brief

## Goal

Reorganize the herdr tree so pane-level operations live under a single
`Pane` item, parallel to `Tabs`, `Workspaces`, `Agents`, `Worktrees` —
instead of scattered at the top level.

## Done when

`build-herdr-tree`'s top level is exactly `p` Panes / `t` Tabs /
`w` Workspaces / `g` Worktrees / `b` Jump to Blocked / `a` Agents, with the
whole pane surface (Focus hjkl, `s` Split, `m` Move, `z` Zoom, `d` Close,
panes list + chips) inside the `p` drill; stale "herdr owns the top-level
hjkl" claims swept from code comments and docs; tests green.

## Decomposition

Grilled 2026-07-13 (plan-k1): everything pane moves under the drill — no
top-level hjkl duplicate (the ADR-0013 muscle-memory claim is reworked to
splice-identity), `s` replaces `x` for Split, short inner labels, digits/
chips behind the drill. pane-drill-k2 (work) implements and carries the
agreed target shape. Two concerns raised mid-grilling grew the tree
further: pane-list-tab-local-k3 (work — scope the panes list to the
displayed tab, mirroring the tabs/workspace scoping of 5b2ffa1) and
prev-next-nav-k4 (planning — grill prev/next cycling for the
Workspaces/Tabs/Agents/Panes groups). The grouping is explicitly
provisional — a future interaction-hierarchy rethink is out of scope here.

## Pointers

- `Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld` —
  `build-herdr-tree`; today's top-level tree (Move Pane, Close Pane,
  Split, the pane list + hjkl focus ops live at the top level, not under
  a group); the existing `open "t" "Tabs"` / `open "w" "Workspaces"` /
  agents / worktrees drills are the precedent for a parallel `Pane` item.
- ADR-0013 (variant trees, herdr owns the top-level `hjkl` in both).

## Notes

Raised 2026-07-13 during the sibling grove `add-herdr-quit-binding`, mid
verification of the tabs workspace-scoping leaf — deliberately deferred
to its own grove rather than absorbed inline.
