# agents-list-block-k12

**Kind:** work

## Goal

Give `(modaliser blocks herdr-list)` a fourth `kind`, `'agents`, that renders the
**agent-status list**: one row per agent (source `herdr agent list` — agent-only,
never bare shells), a color-coded **status badge**, ordered **blocked → working →
idle → unknown**. Block only — the tree wiring + jump op are the sibling
`agents-tree-wiring-k13`.

## Context

Read the node `BRIEF.md` (design + D1–D9) and the root `BRIEF.md`. This extends
the existing `kind`-parameterised block; mirror the `panes`/`tabs`/`workspaces`
paths already there. The block stays **UI-only** — it never shells a mutating op
(focus actions live in `muxes/herdr.sld`, added by k13).

`herdr agent list` row shape (probed live, herdr 0.7.1):
`{"agent":"claude","agent_status":"idle","cwd":…,"focused":true,"pane_id":"w9:p1",
"tab_id":"w9:t1","workspace_id":"w9",…}`. Envelope `result.agents[]`. Every agent
row carries `agent` (name, always present) + `agent_status` (idle/working/blocked/
unknown) + ids.

## What to build

- **`kind-spec`** (`blocks/herdr-list.sld`): add
  `((eq? kind 'agents) (list "agent list" "agents" "pane_id" #f))`. Title-key `#f`
  makes `row-title` fall back to the `agent` name then id — already correct.
- **Row `status`** — surface `agent_status` into each agents-kind row as a new
  alist field (e.g. `(cons 'status status)`). Populate it **only for `'agents`**
  so the panes/tabs/workspaces lists stay visually unchanged (scope: this leaf is
  the agents list; badges elsewhere are a non-goal).
- **Status-priority ordering** — for `'agents`, sort rows `blocked(0) → working(1)
  → idle(2) → unknown(3)`, stable by `pane_id` within a band, **before** labels
  are assigned (so digit 1 = the first blocked agent, per D7). Keep the other
  kinds' input order. Consider factoring an `agent-status-rank` helper.
  (LispKit has no `set-car!`/`set-cdr!` — [[feedback_lispkit_no_mutable_pairs]];
  build sorted lists, don't mutate.)
- **Detail = workspace/tab** for agents (D2 cross-scope annotation) — e.g.
  `workspace_id`/`tab_id` or the label; keep it terse. (`row-detail` currently
  hard-codes cwd for panes; branch it for agents.)
- **Badge render** (`herdr-list.js`): when a row has `status`, render a badge span
  (glyph or short word) carrying a per-status class. Don't disturb the existing
  key/arrow/label/detail layout or the `.current`/`.is-focused` classes.
- **Badge colors** (`herdr-list.css`): one class per status — blocked =
  attention/red, working = accent/amber, idle = calm/green, unknown = dim/grey.
  Pull from the overlay theme tokens where they exist; match the existing block's
  visual language (see `blocks/iterm-*.css` / `herdr-list.css`).

## Tests

- Extend `Tests/ModaliserTests/ModaliserMuxesHerdrLibraryTests.swift` (already
  fixture-tests `herdr-list-extract`, no live herdr): feed an `agent list`
  fixture with mixed statuses; assert (a) rows carry the right `status`, (b)
  targets/rows are **blocked-first** with stable `pane_id` within a band, (c)
  titles fall back to the agent name.
- `swift test` + `./scripts/check-portable-surface.sh` green (block stays inside
  `lib/modaliser`; no `(lispkit …)` — write "the LispKit … library" in prose).

## Done when

`herdr-list` renders an `'agents` list with status badges, blocked-first, from
`agent list`; extractor/ordering unit-tested; portable surface + `swift test`
green. Tree wiring is k13.

## Notes
