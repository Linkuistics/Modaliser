# worktrees-surface-k6 — brief

**Kind:** planning → decomposed (this file becomes the node brief for its child
work leaves).

## Goal

Build the herdr **worktree** surface — git-worktree switch / create / remove,
herdr's tie between a workspace and a body of work. Read the root `BRIEF.md`.
Depends on the herdr backend + tree content (k2–k4); extends `build-herdr-tree`
and the `herdr-list` block, both already in `muxes/herdr.sld` /
`blocks/herdr-list.*` — same seam the agents surface (k5) extended.

## The design (settled — grilled 2026-07-07)

A top-level **`open "g" "Worktrees"`** drill (W3), mirroring the `t` Tabs and `w`
Workspaces drills exactly (`g` = git worktree; free + mnemonic, and `w` is
already Workspaces). Inside:

- **Worktrees live-list** — one row per worktree from `herdr worktree list`:
  branch (title) + path (dimmed detail). Digit `1..0` → **smart switch** (W4):
  if the worktree is **open** (`open_workspace_id` present) `workspace focus
  <that id>`, else (dormant) `worktree open --branch <branch> --focus`. Cursor
  seeds the **current** row — the one whose `open_workspace_id` equals
  `result.source.source_workspace_id` (both ride in the same `worktree list`
  payload, so the "current" row is computable purely from the JSON, no extra
  query).
- **`n` New** — prompt a branch name (AppleScript `display dialog`, the same
  `prompt-text` helper the tab/workspace rename uses) → `worktree create
  --branch <name> --focus`. Base ref = herdr's default (current HEAD); no base
  picker in v1. Empty/cancelled dialog → no-op.
- **`d` Remove** (W1 in, W2 guarded) — confirm dialog ("Remove worktree
  <branch>?", OK/Cancel), then `worktree remove --workspace <focused-ws-id>`.
  Acts on the **focused** worktree (always a valid, unambiguous target; mirrors
  close-pane/tab/workspace). **No `--force`**: a dirty worktree → herdr refuses →
  toast, no data loss; the main checkout → git refuses → toast. Cancel → no-op.

**Source-repo pinning.** All worktree ops name the source repo explicitly via
`--workspace <focused-workspace-id>` (read from `pane current`, the one-query
pattern close-tab / rename already use), not herdr's implicit
focused-workspace resolution — deterministic and matches the sibling ops.

**Explicitly out of v1:** worktree removal of a *dormant* (no-open-workspace)
worktree — herdr keys `worktree remove` on `--workspace ID`, so only worktrees
with a live workspace are removable through the CLI; `--force` removal (deleting
uncommitted work via a modal keystroke); a base-ref / git-branch fuzzy chooser
for New; worktree **chips** (worktrees have no on-screen rect — like the agents
list, the list *is* the visualization).

## Decisions (running log)

Live CLI probe (herdr 0.7.1) established the data base. `herdr worktree list
[--workspace ID | --cwd PATH] --json` → `result.worktrees[]` (each: `branch`,
`label`, `path`, flags `is_bare|is_detached|is_linked_worktree|is_prunable`, and
`open_workspace_id` **only when open**) plus `result.source.source_workspace_id`
(the source repo's currently-focused workspace). `worktree create [--branch NAME]
[--base REF] [--focus]` makes a new branch+worktree **and** opens a workspace on
it; `worktree open (--path PATH | --branch NAME) [--focus]` opens a workspace on
an **existing** worktree; `worktree remove --workspace ID [--force]` removes the
worktree tied to that workspace.

- **W1 — Scope: switch + create + remove.** All three high-value gestures, not a
  minimal switch-only. Remove is the one destructive verb → guarded (W2).
- **W2 — Remove: focused worktree, no `--force`, confirm dialog.** Always-valid
  target (the focused workspace's worktree); dirty/main-checkout failures toast
  safely instead of destroying work.
- **W3 — Placement: top-level `open "g" "Worktrees"` drill.** Mirrors `t`/`w`;
  not nested under `w` (the root brief cautioned against that nesting).
- **W4 — Switch: smart.** Jump to the live workspace when the worktree is open;
  open a fresh one only when dormant. Avoids piling duplicate workspaces on one
  worktree.
- **Extractor rules for the `worktrees` kind** (implementation seam for child 1):
  the switch **target is computed**, not a plain field read — encode
  open-workspace-id-or-branch per row (e.g. a tagged string the focus-fn parses)
  so no re-query at key-press; the **`focused` (current) row** is computed
  cross-field (`open_workspace_id == source.source_workspace_id`), unlike the
  existing kinds that read a `focused` bool. Both are pure over the parsed
  payload → fixture-testable.
- **No new ADR** — within-tree UX (placement / switch / remove-guard),
  reversible; ADR-0013 already anchors the herdr variant-tree architecture and
  this is tree *content* (same call the agents surface made).

## Decomposition (2 children)

Split at the block-content ↔ tree-wiring seam — mirrors the agents surface (k5)
and k4's content↔geometry split; child 2 consumes child 1.

1. **`worktrees-list-block` (k14)** — `herdr-list` gains the `worktrees` kind:
   `kind-spec` entry (`worktree list` / `worktrees`), the **computed switch
   target** (open-workspace-id-or-branch), the **computed current row**
   (`open_workspace_id == source.source_workspace_id`), branch title + path
   detail. Reuse the existing render (no status badge; fold any open/dormant
   hint into the detail text to avoid JS/CSS churn). Fixture-fed extractor tests
   via the exported `herdr-list-extract` (no live herdr).
2. **`worktrees-tree-wiring` (k15)** — `muxes/herdr.sld`: the smart-switch
   focus-fn (parse the computed target → `workspace focus` | `worktree open
   --branch --focus`), the **New** op (prompt branch → `worktree create --focus`,
   source-pinned), the **Remove** op (confirm dialog → `worktree remove
   --workspace <focused>`), a small confirm-dialog helper (AppleScript OK/Cancel),
   and the top-level `open "g" "Worktrees"` drill wrapping the new block
   (constructor + hidden digit key-range). `build-herdr-tree` is already spliced
   by the config, so no app-tree edit unless a new export is added. E2e: tree
   resolves; switch-target parsing unit-tested against fixtures.

## Done when

Both children built + retired: `g` opens a Worktrees drill listing worktrees
(branch + path, current row seeded), digit → smart-switch, `n` creates a new
worktree/branch, `d` removes the focused worktree behind a confirm (no `--force`).
`swift test` + `check-portable-surface.sh` green. (Docs/glossary handled by the
k7 docs leaf; the glossary `Worktree` entry was hardened with the open/dormant
distinction during this planning.)

## Pointers

- `muxes/herdr.sld` `build-herdr-tree` (add the `g` drill), `focused-workspace-id`
  (already defined), `herdr-cmd`/`herdr-json`, `prompt-text` (rename dialog to
  clone for New + the confirm helper), the `list-digit-range`/`herdr-list-block`
  wrappers, the `tab`/`workspace` drills as the shape to mirror.
- `blocks/herdr-list.{sld,js,css}` — `kind-spec`, `herdr-list-extract` (exported,
  fixture-testable), `row-title`/`row-detail`, the `focused` detection (needs a
  worktrees-specific cross-field rule), the digit-target build.
- herdr CLI: `herdr worktree list|create|open|remove`, `herdr notification show`.
- Config splice: `app-trees/com.googlecode.iterm2.scm` already splices
  `build-herdr-tree`; sync user ↔ bundled ([[feedback_config_sync]]).

## Notes
