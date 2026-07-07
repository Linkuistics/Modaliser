# agents-surface-k5 — brief

**Kind:** planning → decomposed (this file becomes the node brief for its
child work leaves).

## Goal

Build the **agent-status** surface — herdr's differentiator: reach the AI agent
that needs you (`jump to a blocked agent`) and see everyone's state at a glance.
Read the root `BRIEF.md`. Depends on the herdr backend + tree content (k2–k4);
extends `build-herdr-tree` and the `herdr-list` block, both already in
`muxes/herdr.sld` / `blocks/herdr-list.*`.

## The design (settled — grilled 2026-07-07)

Two affordances on the herdr variant tree, both driving `herdr agent focus`
(the universal cross-tab pane focus validated in k4):

- **Top-level `b` — jump to next blocked agent.** One keystroke from the leader.
  Round-robin, **non-sticky**: focus the next `blocked` agent *after* the
  currently-focused pane (order by `pane_id`, wrap), then dismiss the overlay so
  the user interacts immediately. Stateless — keyed on current focus, no cursor
  to track. Zero blocked → a herdr `notification show` toast, no focus change.
- **Top-level `a` — Agents drill** (an `open`, mirroring `t`/`w`). Holds the
  **agents live-list**: one row per agent, a color-coded **status badge**
  (`idle`/`working`/`blocked`/`unknown`), agent name, dimmed workspace/tab.
  Ordered **status-priority (blocked → working → idle → unknown)** so `a 1` hits
  the most-urgent agent. Digit-jump focuses by `pane_id`; cursor seeds row 0.

**Data source: `herdr agent list`** (agent-only rows — never land the user on a
bare shell), NOT `pane list`. Both `b` and `a` range over **all agents,
server-wide** (D2) — the blocked agent you can't see is the one worth jumping to.

**Explicitly out of v1:** per-agent actions beyond focus (`send`/`read`/
`explain`/`start`/`rename`), agent-status **chips**, and **ambient** surfacing
(menu bar / background notify) — the last is its own future grove (D9).

## Decisions (running log)

Live CLI probe (herdr 0.7.1) established the data base: `agent list` = agent-only
rows (panes with a detected agent); `pane list` = all panes w/ `agent_status`;
statuses `idle|working|blocked|unknown` (`done` only in `wait`); status
**aggregates onto tabs + workspaces**; `agent focus <target>` is universal
cross-tab focus; read-only `agent get|read|explain`, mutating `agent send`, and
`notification show <title>` also exist.

- **D1 — Surface shape: BOTH jump + list.** One-key jump (differentiator) *and* an
  Agents list (at-a-glance). List reuses the `herdr-list` block via a new
  `'agents` kind, mirroring the `t`/`w` drills.
- **D2 — Scope: ALL agents, server-wide.** herdr data is server-global; `agent
  focus` is cross-tab. No scoping filter. List annotates workspace/tab.
- **D3 — Placement: `b` = jump, `a` = Agents drill.** Jump stays 1 keystroke.
  List lives *inside* the `a` drill (not a 2nd top-level panel) — `herdr-list`'s
  single-render invariant shares one module cell across kinds; two lists on one
  frame would clobber it.
- **D4 — Jump repeat: round-robin, non-sticky.** Next blocked after current
  focus, wrap; dismiss overlay to interact. Stateless.
- **D5 — Zero blocked: herdr `notification show` toast** "No blocked agents".
- **D6 — No agent-status chips in v1** (replace-mode-only + can't reach
  cross-workspace agents, contra D2). The list is the visualization.
- **D7 — List: status badge + name + workspace/tab; order status-priority
  (blocked first); cursor seeds row 0.**
- **D8 — v1 actions: focus-only.** `send`-to-unblock is the top future candidate
  (needs free-text dialog + carries wrong-target risk).
- **D9 — Ambient surfacing: OUT of scope; future grove.**
- **No new ADR** — within-tree UX (placement/ordering/jump), reversible;
  ADR-0013 already anchors the tree architecture (this is tree *content*).

## Decomposition (2 children)

Split at the block-content ↔ tree-wiring seam (mirrors k4's content↔geometry
split); child 2 consumes child 1.

1. **`agents-list-block`** — `herdr-list` gains the `'agents` kind: `kind-spec`
   entry (`agent list` / `agents` / `pane_id`), a per-row **status** field
   surfaced from `agent_status`, **status-priority ordering**, workspace/tab in
   the detail, and the JS/CSS **badge** render. Fixture-fed extractor + ordering
   tests (uses the exported `herdr-list-extract`; no live herdr).
2. **`agents-tree-wiring`** — `muxes/herdr.sld`: the round-robin **jump-to-blocked
   op** (`agent list` → filter blocked → next-after-focus → `agent focus`, else
   `notification show`), the top-level `b` key, the `a` **Agents drill** wrapping
   the new block (agents-list-block constructor + hidden digit key-range focusing
   by `pane_id`). Verify the config splice carries `b`/`a` (build-herdr-tree is
   already spliced). E2e: tree resolves; jump logic unit-tested against fixtures.

## Done when

Both children built + retired: `b` jumps to the next blocked agent (server-wide,
round-robin, toast when none); `a` opens an Agents drill listing all agents with
status badges, blocked-first, digit-jump by id. `swift test` +
`check-portable-surface.sh` green. (Docs/glossary handled by the k7 docs leaf.)

## Pointers

- `muxes/herdr.sld` `build-herdr-tree` (add `b` + `a`), `focused-pane-id`,
  `herdr-cmd`/`herdr-json`, the `list-digit-range`/`herdr-list-block` helpers.
- `blocks/herdr-list.{sld,js,css}` — `kind-spec`, `herdr-list-extract` (exported,
  fixture-testable), `row-title`/`row-detail`, the `.js` row renderer, `.css`.
- herdr CLI: `herdr agent list|focus`, `herdr notification show <title>`.
- Config splice: `app-trees/com.googlecode.iterm2.scm` (already splices
  `build-herdr-tree`); sync user ↔ bundled ([[feedback_config_sync]]).
- Future-grove seed: **ambient agent-status surfacing** (menu bar / background
  notify) — D9, out of scope here.

## Notes
