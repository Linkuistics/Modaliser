# herdr-pane-group — brief

## Goal

Reorganize the herdr tree so pane-level operations live under a single
`Pane` item, parallel to `Tabs`, `Workspaces`, `Agents`, `Worktrees` —
instead of scattered at the top level.

## Done when

Not yet decided — first leaf grills the target hierarchy.

## Decomposition

One planning leaf (grilling) to work out where pane ops belong and what
groups under `Pane`, then likely a follow-up work leaf to implement.

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
