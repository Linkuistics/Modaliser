# worktrees-tree-wiring-k15

**Kind:** work

## Goal

Wire the Worktrees surface into `(modaliser muxes herdr)`: the top-level `open
"g" "Worktrees"` drill (switch / New / Remove) over the `worktrees` list block
from k14.

## Context

Read the node `BRIEF.md` (`../BRIEF.md`) and the root `BRIEF.md`. Consumes k14
(the `worktrees` kind on `herdr-list`). Mirrors the tabs/workspaces drills and the
agents-tree-wiring sibling (`../../05-agents-surface-k5/02-DONE-agents-tree-wiring-k13.md`).
All ops are **herdr-direct** (never the façade) and **source-pinned** via
`--workspace <focused-workspace-id>` (already defined; reads from `pane current`).

Build in `muxes/herdr.sld`:

- **Smart-switch focus-fn** (W4). Parse k14's tagged target: `"ws:<id>"` →
  `workspace focus <id>`; `"br:<branch>"` → `worktree open --branch '<branch>'
  --focus` (source-pinned, `sq-escape` the branch). Factor the parse as a small
  pure helper and **unit-test it** against fixture target strings.
- **New op** (`n`). Clone `prompt-text` ("New worktree branch:") → on a non-empty
  name, `worktree create --workspace <focused-ws-id> --branch '<name>' --focus`
  (`sq-escape` the name; base = herdr default HEAD). Empty/cancel → no-op.
- **Remove op** (`d`, W2). A **confirm** dialog helper (AppleScript `display
  dialog … buttons {"Cancel","OK"} default button "Cancel"`, returns #t only on
  OK — default Cancel so a stray Return doesn't delete) → on OK, `worktree remove
  --workspace <focused-ws-id>` (**no `--force`**; 2>/dev/null already swallows the
  dirty/main-checkout refusal — optionally toast via `notification show`). Read
  the focused branch for the prompt text from `worktree list` (match the row whose
  `open_workspace_id == source.source_workspace_id`) or fall back to the ws-id.
- **The drill.** `(open "g" "Worktrees" (key "n" "New" …) (key "d" "Remove" …)
  (panel "Worktrees" (worktree-list-block)))`, where `worktree-list-block` wraps
  `(make-herdr-list-block 'kind 'worktrees …)` with the cursor-fns +
  `list-digit-range` hidden `1..` range dispatching to the smart-switch focus-fn
  — exactly like `tab-list-block` / `workspace-list-block`. Add `g` to
  `build-herdr-tree`'s returned node list (after `w`, alongside `a`).

`build-herdr-tree` is already spliced by `app-trees/com.googlecode.iterm2.scm`
(both `/herdr` and `/herdr+split`), so **no config edit** unless a new export is
introduced — keep the surface internal (tree-builder only), per the root BRIEF's
"small export surface". If any config/bundled file *is* touched, sync user ↔
bundled ([[feedback_config_sync]]).

Portability: `muxes/herdr` stays `(lispkit …)`-free; `check-portable-surface.sh`
green.

## Done when

- `g` opens a Worktrees drill: digit → smart-switch (focus live workspace when
  open, else open the worktree); `n` prompts a branch and creates it; `d` removes
  the focused worktree behind a confirm (no `--force`).
- The switch-target parse helper is unit-tested (ws vs br); an e2e test resolves
  the herdr variant tree and confirms the `g` node is present (as
  agents-tree-wiring did for `b`/`a`).
- `swift test` + `check-portable-surface.sh` green. Verify the built surface in
  the installed app is left to the consolidated k11 live-verify leaf.

## Notes
