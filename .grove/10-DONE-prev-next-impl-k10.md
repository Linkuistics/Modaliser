# prev-next-impl-k10

**Kind:** work

## Goal

Add `[` Prev / `]` Next cycling to the herdr Panes, Tabs, Workspaces and
Agents drills, per the prev-next-nav-k4 grilling (see its Decisions
running log for the full rationale).

## Context

Agreed spec (grilled 2026-07-13/14, prev-next-nav-k4):

- **Keys:** `[` prev / `]` next, uniform in all four drills, as loose
  walk keys (`'next 'self`) so presses chain and the drill re-renders
  (fresh list snapshot) after each step. Labels "Prev"/"Next".
- **Domain:** cycle the drill's *displayed rows* — panes tab-local, tabs
  workspace-local (post merge-main-k9), workspaces global (`number`
  order), agents in the displayed status-banded blocked-first order
  (mid-walk reshuffle on a status flip accepted). This mirrors herdr's
  own cycle semantics (prefix+n/p tabs, navigate-mode workspaces,
  prefix+Tab panes; agents have no herdr binding).
- **Wrap:** ring — wrap at both ends.
- **Focused row:** `herdr-list-focused-index` over the block's
  snapshotted rows; `#f` index seeds `]` → first row, `[` → last row
  (Agents: most-urgent-first). On-demand re-snapshot when pressed before
  the first render, mirroring `list-digit-range`'s refresh path.
- **Fire:** the same focus verbs the digit path uses — panes/agents
  `agent focus <pane_id>`, tabs `tab focus`, workspaces
  `workspace focus`. Zero new herdr queries: read the already-
  snapshotted targets.
- **Also:** add `[`/`]` to the registered `herdr-panes-focus` walk so
  cycling stays available mid-focus-walk (veto-able detail — drop if it
  reads badly in the walk overlay).
- **Test seam (agreed, the one new seam):** a pure exported helper in
  `muxes/herdr.sld` — (targets focused-index direction) → target id |
  `#f` — fixture-tested like `next-blocked-pane-id` /
  `worktree-switch-command`: wrap both directions, empty list → `#f`,
  `#f` index seeding, single row. Tree-shape assertions ride the
  existing end-to-end suite.
- **Key availability (verified):** `[`/`]` are keyCodes 33/30 in
  `KeyboardLibrary.keyCodeToCharacter` — bindable today, no Swift work.

## Done when

`[`/`]` cycle correctly in all four drills in a live herdr session
(walk feel: press-press-press tours the ring with the list updating);
pure-helper fixture tests + tree-shape assertions green; the glossary's
Panes-drill entry and any doc enumerating drill keys swept; full test
suite green.

## Notes

Sequenced after merge-main-k9 (tabs scoping arrives with it) and after
pane-split-to-new-k7 in pick order (no key clash — `n` vs `[`/`]` — but
tree-shape tests touched by both). Worktrees drill deliberately gets no
`[`/`]` (the human direction named four groups); no ADR (decisions are
cheap to reverse — running log + this spec carry them).
