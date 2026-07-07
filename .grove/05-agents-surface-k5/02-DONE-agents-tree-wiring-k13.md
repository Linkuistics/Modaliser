# agents-tree-wiring-k13

**Kind:** work

## Goal

Wire the agent-status surface into the herdr variant tree: a top-level **`b` =
jump to next blocked agent** and a top-level **`a` = Agents drill** holding the
`'agents` list block (from sibling `agents-list-block-k12`). Both drive `herdr
agent focus`. Consumes k12; do it after k12 lands.

## Context

Read the node `BRIEF.md` (design + D1–D9) and the root `BRIEF.md`. All ops are
**herdr-DIRECT** (never the façade — ADR-0013: in augment mode the façade
resolves to herdr anyway, but directness is the contract). `build-herdr-tree` is
already spliced into both variant screens by
`app-trees/com.googlecode.iterm2.scm` (`(apply screen …/herdr (build-herdr-tree))`
and the augment `append`), so `b`/`a` added to `build-herdr-tree` ride into both
trees for free — verify, don't re-splice.

## What to build (`muxes/herdr.sld`)

- **Agents list-block constructor** — add `agent-list-block` beside
  `pane-list-block`/`tab-list-block`/`workspace-list-block`: wraps
  `make-herdr-list-block 'kind 'agents`, focus-fn `(lambda (id) (herdr-cmd
  (string-append "agent focus " id)))`. Reuses the generic `herdr-list-block` +
  `list-digit-range` already there (digit → focus by `pane_id`).
- **Jump-to-next-blocked op** — factor a **pure, exported** helper
  `next-blocked-pane-id(agents, focused-pane-id) → pane_id | #f`:
  from the parsed `agent list` (`result.agents[]`), take agents with
  `agent_status == "blocked"`, order by `pane_id`, and return the first whose
  `pane_id` sorts **after** `focused-pane-id` (wrap to the first if none after; #f
  if no blocked agents). Keeping it pure makes it fixture-testable with no live
  herdr. (pane_id compare: string compare is acceptable for v1 — note that
  `p10` < `p2` lexically; fine to defer numeric-aware ordering.) Then the op:
  read `agent list` + `focused-pane-id`; `#f` → `herdr-cmd "notification show 'No
  blocked agents'"` (D5); else `herdr-cmd (string-append "agent focus " id)` and
  the overlay dismisses (non-sticky, D4 — a plain `key`, not a sticky mode).
- **Tree entries** in `build-herdr-tree` — add:
  - `(key "b" "Jump to Blocked" jump-to-next-blocked)` at the top level.
  - `(open "a" "Agents" (panel "Agents" (agent-list-block)))` — v1 focus-only
    (D8), so the drill is just the Agents list panel + its digit-jump; no
    `send`/`read`/`explain`. Place near `t`/`w` for discoverability.
- No new exports needed for the tree (block constructor is internal); export
  `next-blocked-pane-id` for the test only.

## Config + sync

- Confirm `app-trees/com.googlecode.iterm2.scm` still splices `build-herdr-tree`
  into both `…/herdr` and `…/herdr+split` (it does) — `b`/`a` appear in both.
- Sync user `~/.config/modaliser/` ↔ bundled `Sources/Modaliser/Scheme/`
  ([[feedback_config_sync]]) if the config file itself changed (likely no change —
  the surface grows inside `build-herdr-tree`).

## Tests

- `Tests/ModaliserTests/ModaliserMuxesHerdrLibraryTests.swift`: unit-test
  `next-blocked-pane-id` against fixtures — no blocked (→ #f/notification path),
  one blocked, several blocked with focus mid-ring (wrap), focus on a
  non-agent/absent pane_id. And assert `build-herdr-tree` now yields nodes keyed
  `b` and `a` (tree-shape assertion like the existing ones).
- `swift test` + `./scripts/check-portable-surface.sh` green.

## Done when

`b` jumps to the next blocked agent server-wide (round-robin, toast when none);
`a` opens an Agents drill listing all agents with status badges, blocked-first,
digit-jump by id; both in replace and augment trees. Jump helper + tree shape
unit-tested; `swift test` + portable surface green. Retiring k13 empties the
`agents-surface-k5` node → check the parent chain (docs are the separate k7 leaf).

## Notes
