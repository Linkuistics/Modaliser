# legacy-whichkey-deletion-k13 — brief

## Goal

Physically **delete** the legacy which-key / auto-layout overlay path that
[[docs-tests-k9]] could only **deprecate** (ADR-0012 kept the old forms working;
k9 marked them deprecated in the docs but left the code in place because it was
still reachable from live shipped libraries). The user explicitly asked for the
deletion after k9 retired, in preference to finishing the grove on
deprecation-only. This is the **flag-day** ADR-0012 §Consequences said would not
happen — a post-k9 user decision (record it as such; see `reconcile-docs-k16`).

This node was planned in a grilling session that settled the three design forks
below and decomposed the work into three child leaves.

## Resolved decisions (settled by grilling 2026-06-23)

1. **Default-list column source → CSS-intrinsic auto-fit.** The default-list
   renderer (`render-overlay-default` / `push-overlay-update-default` in
   `ui/overlay.scm`) is NOT legacy — it serves every plain `(group …)` drill-down
   and every operational tree registered without a renderer — so it survives. But
   its column source `overlay-column-count` (a target-aspect-ratio search) is
   deleted: the two call-sites (`overlay.scm:347` initial render, `overlay.scm:938`
   incremental update) swap to a **CSS Grid `auto-fit` / fixed-track** layout on
   `.overlay-entries`. Scheme stops emitting `data-cols` / `"cols"`; `overlay.js`
   stops setting `--overlay-cols`. `overlay-column-count` + its seeds
   (`overlay-col-width-px`, `overlay-row-height-px`) are deleted. *(Rejected:
   migrating ALL plain groups to panels and deleting the default-list renderer —
   far heavier; operational trees would need panels too.)*

2. **Operational trees → reduce to `register-tree!` (no panel-grid).** The 6
   `*-pane-digit` trees (hidden key-range, render empty) and the iTerm focus-mode
   sticky tree (a 4-key hjkl list) are operational registrations, not authored
   presentation. They drop `define-tree` (which forces `'renderer 'blocks` →
   which-key) and call the kept, portable substrate **`register-tree!`** directly
   (no `'renderer` marker → they render through the surviving default-list
   renderer: pane-digit empty, focus-mode the hjkl list). Lifecycle hooks
   (`on-enter`/`on-leave`/`sticky`/`exit-on-unknown`/`display-name`) pass straight
   through `register-tree!`. **No new import needed** — all 6 pane-digit apps
   already import `(modaliser state-machine)`. *(Rejected: authoring them as
   `screen`/`panel` — panel-grid is overkill for a 4-key list and an empty panel
   grid for a hidden range reads oddly.)*

3. **`set-overlay-aspect-ratio!` → removed entirely.** Once fork 1 deletes
   `overlay-column-count`, this knob has no reader (it only set
   `%overlay-target-aspect-ratio`, which fed the column search). No live config
   calls it (default-config.scm + the user config are clean; only
   `OverlayRenderTests` does, and that is rewritten). Pre-release, so nothing to
   keep compatible. Delete the procedure + `%overlay-target-aspect-ratio`; drop
   from `state-machine.sld` and the `dsl.sld` re-export. *(Rejected: a no-op stub
   — documented cruft for a feature that no longer exists.)*

## Context (investigated during docs-tests-k9, re-verified during this planning)

The overlay has **three** live render paths (`ui/overlay.scm`), dispatched in
`render-overlay-body` (`:330`): a node with **no** `'renderer` → default-list;
with `'renderer` → custom (blocks or panel-grid).

1. **default list** — `render-overlay-default` / `push-overlay-update-default`.
   **Survives** (fork 1). Used by every renderer-less group/tree.
2. **block-list** — `block-list-payload-json` / `block-json`. `block-json`'s
   **`'which-key` branch** is the legacy path (deleted). The **other** `block-json`
   branches — `iterm-panes`, `iterm-tabs`, `window-list`, `window-diagram` — are
   live (panel-grid embeds them via `block-json` at `overlay.scm:524`) and **must
   be preserved**. So this is *surgical* branch deletion, not whole-path deletion.
   `block-list-payload-json` (the `'renderer 'blocks` payload) likely becomes dead
   once nothing sets `'renderer 'blocks` — **verify reachability before deleting**.
3. **panel-grid** — `panel-grid-payload-json`, the shipped default. Untouched.

**Deletable set (the legacy which-key whole-overlay packing):**
- `ui/overlay.scm`: `which-key-payload-json`, `partition-which-key-segments`,
  `segment-row-count`, `segments-row-count`, `distribute-which-key-columns`,
  `render-segment`, and the `'which-key` branch of `block-json`.
- `lib/modaliser/dsl.sld`: the `(modaliser blocks which-key)` import +
  `which-key-block`; `pack-node-runs` / `flush-node-run` / `node-form?`; and the
  old container forms `define-tree` / `category` / `overlay`. Drop all from the
  export list.
- `lib/modaliser/blocks/which-key.{sld,js,css}` — the library + assets. **NB**
  `which-key.js` also exports `window.overlayRenderRow`, which the **panel-grid**
  key-row renderer reuses (`overlay.js renderPanelRow`) — that row renderer must be
  **preserved** (move it into `overlay.js` before deleting `which-key.js`).
- `overlay-column-count` + seeds — deletable once fork 1's CSS swap lands.
- `set-overlay-aspect-ratio!` + `%overlay-target-aspect-ratio` (fork 3).

**Live legacy-form callers (the gate — re-verified; SMALLER than k9's list).**
The provisional `window-actions` / `web-search` / `launchers` / `settings-menu`
matches were all **comments** — those are already migrated. `(overlay …)` has
**no** live callers. The actual live `define-tree` / `category` callers:
- **Operational (fork 2 → `register-tree!`):** six `*-pane-digit` define-trees
  (`apps/iterm.sld:606`, `apps/wezterm.sld:342`, `apps/kitty.sld:672`,
  `apps/ghostty.sld:289`, `muxes/tmux.sld:353`, `muxes/zellij.sld:406`) + the iTerm
  focus-mode tree (`apps/iterm.sld:544`, `focus-mode-register!`).
- **Full overlays (→ `screen`/`panel`):** iTerm main tree
  (`apps/iterm.sld:485`, `define-tree 'com.googlecode.iterm2`) holding the lone live
  `(category "Focus")` (`:502`); Safari `register!` (`apps/safari.sld:37`); Chrome
  `register!` (`apps/chrome.sld:37`). Safari/Chrome bodies are pure kept atoms
  (`group`/`key`) — only `register!`'s `define-tree` call changes.

**Tests that pin the legacy paths (rewrite/remove WITH the code that breaks them,
to keep the suite green per-commit):**
- `BlocksWhichKeyLibraryTests` (the heaviest) — deleted with the library (k15).
- `OverlayRenderTests` — which-key cases + `set-overlay-aspect-ratio!` cases
  (`:206`, `:210`) removed (k15).
- `ModaliserWindowActionsLibraryTests`, `ModaliserDslLibraryTests` — audit each;
  define-tree/category/which-key cases removed (k15) or migrated (k14).
- Keep green: `LayoutDslTests`, `PanelGridRendererTests`, `ListCursorDispatchTests`,
  `ConfigDslTests`.

## Decomposition

Dependency-ordered (callers gate deletion; the shared `overlay-column-count`
forces fork-1's CSS swap into the same commit as the which-key deletion):

1. **`migrate-callers-k14`** — migrate every live legacy-form caller off
   `define-tree`/`category` (fork 2 for operational trees; `screen`/`panel` for the
   full overlays). The legacy forms still *exist* afterwards; nothing live *uses*
   them. Gate: no live `define-tree`/`category`/`overlay` outside `dsl.sld`'s own
   definitions.
2. **`delete-which-key-k15`** — delete the legacy machinery: fork-1 CSS column swap
   + delete `overlay-column-count`; delete the which-key helpers + `block-json`
   `'which-key` branch (preserve the list-block branches + `overlayRenderRow`);
   delete the dsl forms + the `(modaliser blocks which-key)` library/assets; fork-3
   removal of `set-overlay-aspect-ratio!`. Rewrite/remove the pinning tests in the
   same commit. `check-portable-surface.sh` + full suite green.
3. **`reconcile-docs-k16`** — reconcile docs the way k9 left "deprecated, still
   present": `dsl.md` legacy-forms section + `set-overlay-aspect-ratio!` entry,
   which-key mentions in `renderer-protocol.md` / `theming.md` / `libraries.md` /
   `library-system.md`, `CONTEXT.md` glossary, and a short **ADR-0012 amendment**
   recording the post-k9 flag-day deletion.

## Pointers

- Design spec: `docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md`.
- ADR-0012 (`docs/adr/0012-layout-dsl-surface-screen-panel-open-over-unchanged-atoms.md`)
  — its §Consequences said "no flag-day"; k16 amends that.
- Glossary terms already present: `panel`, `screen`, `open`, `span`, `live-list`
  (`CONTEXT.md`).

## Notes

- After `reconcile-docs-k16` retires, this node has no live leaf → the grove root
  again has none → the **Finish** cycle the user deferred from k9 runs (promote =
  likely no-op; FF-merge `visual-refresh` → `main`; remove worktree + branch). At
  k9's retirement `main` was still at the branch point (`2d1709e`) → clean
  fast-forward; re-check before merging.
- Project memory: façade cutovers can silently break inline-tree configs; LispKit
  has no `set-cdr!` (return-and-merge only); install via `./scripts/install.sh` to
  test the real `.app`; skip the pre-existing flaky `ModaliserAppsItermLibraryTests`
  + `HttpLibraryTests` in headless runs.
</content>
</invoke>
