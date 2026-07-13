# pane-list-tab-local-k3

**Kind:** work

## Goal

Scope the herdr panes live-list to the currently displayed tab, mirroring
how the tabs list is already local to the focused workspace.

## Context

- Human direction (2026-07-13, verbatim, raised mid plan-k1): "The list of
  panes should only be those in the currently displayed tab, just like the
  tabs are local to the currently displayed workspace."
- **Direct precedent — commit 5b2ffa1**
  (`feat(herdr-tabs-workspace-local-k3)`, the sibling grove): `tab list`
  is global, so `focused-workspace-id` (a `pane current` read in
  `muxes/herdr.sld`) is threaded into `blocks/herdr-list.sld` as an
  optional `'focused-workspace-id-fn` block opt, and the pure extractor
  `herdr-list-extract` drops non-matching rows in phase 1 (before digit
  labels are assigned), degrading to unfiltered on `#f`. Mirror that shape
  for panes: `pane list` rows carry `tab_id`; `focused-tab-id` already
  exists in `muxes/herdr.sld` (~line 209, same `pane current` read).
  Confirm first whether `pane list` is server-global or already
  tab/workspace-scoped (the tabs leaf confirmed `tab list` global before
  building — do the same probe).
- Filtering before labels means digits map to exactly the displayed tab's
  panes, and chips (rects from `pane layout`, current-tab-only by nature)
  can no longer disagree with the list rows.
- Fixture-fed extractor tests exist
  (`ModaliserMuxesHerdrLibraryTests.swift`, extended by 5b2ffa1) — extend
  the same way; no live herdr needed.

## Done when

- The Panes drill's list, digit-jump, and selection cursor all cover only
  the displayed tab's panes; `#f` focused-tab-id degrades to unfiltered
  (same failure posture as the tabs kind).
- Agents/workspaces/worktrees kinds remain global (agents are deliberately
  cross-workspace — the list is the visualization).
- Extractor fixture tests cover the filtered + degraded paths; suite green.

## Notes

- `list-pane-ids` in `muxes/herdr.sld` (the chip-less `herdr-pane-digit`
  façade digit tree) snapshots the *global* `pane list` too. The shipping
  variant tree uses the block instead, so it's near-dead surface — decide
  in-session whether to scope it identically for consistency or leave a
  comment pointing here.
- Sequencing: independent of pane-drill-k2 (this filters the block's rows;
  k2 moves the block), but landing after k2 keeps test churn linear.
