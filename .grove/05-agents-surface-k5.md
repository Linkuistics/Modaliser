# agents-surface-k5

**Kind:** planning

## Goal

Design and build the **agent-status** surface — herdr's differentiator: per-pane AI
agent state (idle/working/blocked/unknown), e.g. "jump to a blocked agent" and an
at-a-glance status view.

## Context

Read the root `BRIEF.md`. Depends on the herdr backend + tree content (leaves 2–4).
This is a **planning** leaf: open with a grilling session — the UX is genuinely open.

Data source: `herdr pane list` carries `agent_status` per pane (`idle|working|blocked|
unknown`) plus `pane_id`/`tab_id`/`workspace_id`/`focused`. herdr also has `herdr agent
…` and `herdr notification …` subcommands and a `report-agent` API — explore what's
queryable before designing.

Open questions for the grilling (not exhaustive):
- What's the primary action? Jump-to-next-blocked-agent (a single key), a status
  chooser/list, status chips over panes, or a passive indicator?
- Cross-workspace/tab or current-view only? (a blocked agent may be in another workspace)
- How does this compose with the pane/tab/workspace trees from leaf 4 — a top-level
  `a` key in the herdr tree, its own overlay, or a chooser?
- Does Modaliser want to *surface* status ambiently (e.g. menu bar / overlay), beyond
  on-demand? (Watch scope creep — could be its own grove.)

Decompose into work leaves as the design settles.

## Done when

Grilled to shared understanding; agent-status controls designed, decomposed, and (via
child leaves) built + tested; docs/glossary updated.

## Notes
