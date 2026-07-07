# worktrees-list-block-k14

**Kind:** work

## Goal

Give `(modaliser blocks herdr-list)` a **`worktrees`** kind: a live list of
`herdr worktree list` rows (branch + path), with a **computed switch target**
and a **computed current row**. Pure, fixture-tested; no live herdr. Consumed by
the tree-wiring sibling (k15).

## Context

Read the node `BRIEF.md` (`../BRIEF.md`) and the root `BRIEF.md`. This mirrors how
the agents surface added an `agents` kind (see the retired
`../../05-agents-surface-k5/01-DONE-agents-list-block-k12.md`). The block is a
single `kind`-parameterised constructor; the four existing kinds
(panes/tabs/workspaces/agents) each read one result-array plus a plain `id` field
and a `focused` bool. Worktrees differ in **two** ways, both pure over the parsed
JSON:

1. **Computed switch target** (not a field read). Each row's digit target must
   carry enough to drive the smart-switch in k15 without a re-query: the
   `open_workspace_id` when the worktree is **open**, else the `branch` (to open
   dormant). Encode it as a tagged string (e.g. `"ws:<id>"` / `"br:<branch>"`)
   that k15's focus-fn parses. The existing `kind-spec` id-key is a plain field
   name — generalise minimally (a per-kind target builder, or a `worktrees`
   branch in `herdr-list-extract`).
2. **Computed current row.** No `focused` bool on worktree rows. The current one
   is `open_workspace_id == result.source.source_workspace_id` (both in the same
   `worktree list` payload). Wire this into the row's `focused` slot so the
   cursor seeds it (`herdr-list-focused-index`).

Row shape: title = `branch` (fall back to `path`'s basename or `label` if a
worktree is detached and has no branch — `is_detached` / null `branch`); detail =
`path` (dimmed). **No status badge** and no reorder (unlike agents). To avoid
JS/CSS churn, fold any open-vs-dormant hint into the **detail text** rather than a
new badge — reuse the existing renderer as-is.

Data probe (herdr 0.7.1), `worktree list --json`:
`{"result":{"source":{…,"source_workspace_id":"w9"},"worktrees":[{"branch":"main",
"path":"…","label":"…","open_workspace_id":"w9",…},{"branch":"ocr-accuracy",
"path":".../.grove-worktrees/ocr-accuracy",…(no open_workspace_id)…}]}}`.

Portability: `blocks/herdr-list` stays in `lib/modaliser` → **no `(lispkit …)`**;
`check-portable-surface.sh` must stay green (and prose comments avoid the literal
parenthesised form — [[feedback_config_sync]] neighbours).

## Done when

- `herdr-list-extract` handles `'worktrees`: targets carry the tagged
  open-workspace-id-or-branch; rows carry branch/path; the current row
  (`open_workspace_id == source.source_workspace_id`) is marked `focused`.
- Fixture-fed unit tests (parsed `worktree list` JSON in — open, dormant, and
  detached rows; the current-row rule; the tagged target for each state). No live
  herdr.
- `swift test` (the herdr-list test target) + `check-portable-surface.sh` green.
- k15 not touched (it consumes this).

## Notes
