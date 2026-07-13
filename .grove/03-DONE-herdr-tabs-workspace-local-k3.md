# herdr-tabs-workspace-local-k3

**Kind:** work

## Goal

Scope the herdr Tabs live-list — and therefore its digit-jump navigation —
to the **focused workspace**. Today the 'tabs kind in
`Sources/Modaliser/Scheme/lib/modaliser/blocks/herdr-list.sld` renders every
row of `herdr tab list` unfiltered (`kind-spec`, ~line 150), so tabs from
other workspaces appear in the `t` drill and consume digits.

## Context

- Human direction (2026-07-13, mid-grill): "the herdr tab navigation and
  listing should be local to the workspace, not global."
- Filtering precedent **in the same file**: the worktrees kind reads the
  source workspace from the list payload
  (`result.source.source_workspace_id`) and compares per-row — reuse that
  approach for tabs (each tab row carries `workspace_id`).
- First verify what `herdr tab list` actually returns (server was not
  running during planning): if it is already workspace-scoped, this leaf
  reduces to a no-op finding — report back, don't invent work. If global,
  filter rows to `workspace_id == result.source.source_workspace_id`.
- The `t` drill's other ops (`n`/`r`/`d`) are already focused-tab-scoped;
  only the list block and its digit range need the scoping.
- Tests: extractor/fixture patterns in
  `Tests/ModaliserTests/ModaliserMuxesHerdrLibraryTests.swift` and the
  herdr-list block tests — feed a fixture with tabs across two workspaces,
  assert only the source workspace's tabs become rows/digit targets.

## Done when

- With a multi-workspace fixture, the tabs block renders only the focused
  workspace's tabs, and digits map to exactly those rows.
- Existing tab tests still green; `./scripts/check-portable-surface.sh`
  passes.

## Notes

Workspace list (`w` drill) stays global by design — it is the cross-workspace
switcher. Only tabs become workspace-local.
