# merge-main-k9

**Kind:** work

## Goal

Merge `main` into this branch and reconcile the two live-list scoping
changes so both work: main's tabs workspace-scoping and this branch's
panes tab-scoping.

## Context

- Grilled 2026-07-13 (prev-next-nav-k4): sequenced ahead of
  prev-next-impl-k10, which must be written against the merged shape.
- The conflict is known and structural, not incidental: main's 5b2ffa1
  (sibling grove add-herdr-quit-binding) threads a
  `focused-workspace-id` param through `herdr-list-extract` /
  `snapshot!` / the block opts to scope the **tabs** kind; this branch's
  a5a51bf (pane-list-tab-local-k3) threads a `focused-tab-id` the same
  way to scope the **panes** kind. Same regions of
  `blocks/herdr-list.sld` and `muxes/herdr.sld`.
- Reconcile toward one kind-keyed scope parameter rather than two
  parallel ones if that reads cleaner — a design call for this session;
  minimal coherent shape wins over preserving either branch's literal
  text. Module-header comments must merge too (tabs workspace-scoped,
  panes tab-scoped, workspaces/agents/worktrees global).
- main also carries the `q` Quit group (3bac6c2) and its retire commits —
  expect herdr.sld tree-shape context to shift; `build-herdr-tree`'s
  top-level comment block and the root BRIEF's Done-when list may need a
  sweep (the Done-when enumerates the top level, which gains `q`).

## Done when

`main` merged into `herdr-pane-group`; both scopings verified working
(tabs list shows only the focused workspace's tabs, panes list only the
displayed tab's panes); both branches' fixture tests present and green;
full `swift test` green (modulo the pre-existing iTerm/Http crashes —
see project_iterm_tests_crash).

## Notes

A merge commit is fine (this is the grove branch; the finish cycle
merges back the other way). Don't rebase — the retired-leaf history on
this branch is already referenced by handle in commit messages.
