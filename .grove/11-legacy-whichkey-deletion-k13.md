# legacy-whichkey-deletion-k13

**Kind:** planning

## Goal

Physically **delete** the legacy which-key / auto-layout overlay path that
[[docs-tests-k9]] could only **deprecate** (ADR-0012 kept the old forms working;
k9 marked them deprecated in the docs but left the code in place because it is
still reachable from live shipped libraries). The user explicitly asked for the
deletion after k9 retired, in preference to finishing the grove on
deprecation-only. This leaf **plans** that deletion — settling the one real
design fork, then growing work leaves — because it is a sizeable, cross-cutting
migration with a genuine scoping decision, not a single mechanical sweep.

Open with a short grilling on the fork in **Design forks** below, then decompose
into work leaves (likely: migrate live callers → swap/retire the default list
renderer → delete the which-key library + helpers + old DSL forms → fix tests).

## Context (investigated during docs-tests-k9 — do not re-derive)

The overlay has **three** live render paths (`ui/overlay.scm`):

1. **default list** — `render-overlay-default` / `push-overlay-update-default`,
   used by any group with **no** `'renderer` (every plain `(group …)` drill-down
   and registered sticky/focus-mode tree). Uses `overlay-column-count`
   (+ `overlay-col-width-px` / `overlay-row-height-px` seeds), `max-key-chars`,
   `flatten-categories`, `sort-children`, `render-entry`.
2. **block-list** — `block-list-payload-json` / `block-json`, the
   `'renderer 'blocks` path produced by the legacy `define-tree` / `overlay`.
   `block-json`'s `'which-key` branch → `which-key-payload-json`.
3. **panel-grid** — `panel-grid-payload-json`, the `'renderer 'panel-grid` path
   produced by the new `screen` / `open` (the shipped default).

**Deletable set (the legacy which-key whole-overlay packing):**
- `ui/overlay.scm`: `which-key-payload-json`, `partition-which-key-segments`,
  `segment-row-count`, `segments-row-count`, `distribute-which-key-columns`,
  `render-segment`, and the `'which-key` branch of `block-json`.
- `lib/modaliser/dsl.sld`: `which-key-block` import + `pack-node-runs` /
  `flush-node-run`, and the old container forms `define-tree` / `category` /
  `overlay` (they pack node-runs into which-key-blocks).
- `lib/modaliser/blocks/which-key.{sld,js,css}` — the `(modaliser blocks
  which-key)` library + assets. NB `which-key.js` also exports
  `window.overlayRenderRow`, which the **panel-grid** key-row renderer reuses
  (`overlay.js renderPanelRow`) — that row renderer must be **preserved**
  (move it into `overlay.js` or another asset before deleting which-key.js).
- `overlay-column-count` (+ seeds) — see the fork; only deletable once the
  default list renderer no longer needs it.

**Live callers that BLOCK deletion until migrated (the gate k9 confirmed):**
- Six `*-pane-digit` `define-tree`s: `apps/iterm.sld:606`, `apps/wezterm.sld:342`,
  `apps/kitty.sld:672`, `apps/ghostty.sld:289`, `muxes/tmux.sld:353`,
  `muxes/zellij.sld:406`. Each is a flat tree with one hidden digit key-range +
  on-enter/on-leave chip painting (renders empty — the range is `'hidden`).
- `apps/iterm.sld`: `(category "Focus" …)` (~502) in the transient iTerm tree, and
  `focus-mode-register!` (~545) which calls `(define-tree id 'sticky #t …)`.
- `define-tree` / `overlay` usage in `window-actions.sld`, `web-search.sld`,
  `launchers.sld`, `settings-menu.sld` (confirm each — some matches were
  comments). `default-config.scm` is already fully migrated (no live old forms).

**Tests that pin the legacy paths (must be rewritten/removed):**
- `BlocksWhichKeyLibraryTests` (22 which-key refs) — the heaviest.
- `OverlayRenderTests` (7 which-key refs) — has which-key cases.
- `ModaliserWindowActionsLibraryTests` (8), `ModaliserDslLibraryTests` (5) —
  reference which-key / define-tree / category. Audit each.
- Keep green: `LayoutDslTests`, `PanelGridRendererTests`, `ListCursorDispatchTests`,
  `ConfigDslTests` (the new panel surface).

## Design forks (settle by grilling first)

1. **Default list renderer + `overlay-column-count`.** Plain `(group …)` and
   sticky/focus-mode trees are NOT legacy — `group` is a kept dispatch atom — so
   their renderer must survive. The user's endorsed scope included "remove
   `overlay-column-count`," which means the default list renderer needs a new
   column source. Options: (a) swap it to a **CSS-intrinsic** column count
   (e.g. `columns: auto` / a fixed track count), dropping `overlay-column-count`
   + the aspect-ratio search + `set-overlay-aspect-ratio!`'s effect; or
   (b) migrate ALL plain groups to `open`/panels and **delete** the default list
   renderer entirely (heavier — and registered focus-mode/sticky trees still
   render, so they'd need panels too). **Recommend (a).**
2. **Pane-digit + focus-mode trees.** These render empty (hidden range) or as a
   tiny hjkl list. Do they migrate to `screen`/`panel` (panel-grid), or is a
   minimal non-which-key registration enough? They only need a registered tree +
   on-enter/on-leave hooks + a hidden range — they may not need ANY visible
   renderer. Settle whether they become `screen`s or stay on a thin primitive.
3. **`set-overlay-aspect-ratio!`** — keep as a (now no-op-ish) stub for config
   compatibility, or remove from the DSL surface? (It currently only feeds
   `overlay-column-count`.)

## Done when (provisional — refine during planning)

- The `(modaliser blocks which-key)` library + assets are gone; `dsl.sld` no
  longer imports it; `define-tree` / `category` / `overlay` / `which-key-block` /
  `pack-node-runs` / `flush-node-run` removed (or reduced to the minimum the
  surviving callers need).
- `which-key-payload-json` + its 5 helpers and the `'which-key` `block-json`
  branch removed; the shared panel key-row renderer (`overlayRenderRow`)
  preserved.
- All live callers migrated; `default-config.scm` + user config still load.
- `overlay-column-count` resolved per fork 1.
- `check-portable-surface.sh` green; the full suite green (legacy tests removed/
  rewritten, panel tests still pass). Skip the pre-existing flaky
  `ModaliserAppsItermLibraryTests` + `HttpLibraryTests` in headless runs.
- Docs re-checked: dsl.md's "Legacy forms (deprecated)" section and the
  which-key mentions in renderer-protocol.md / theming.md / libraries.md updated
  to reflect removal (k9 left them as "deprecated, still present").

## Notes

- After this leaf's subtree retires, the grove root again has **no live leaf** →
  the **Finish** cycle the user deferred from k9 runs then (promote = likely
  no-op; FF-merge `visual-refresh` → `main`; remove worktree + branch). At k9's
  retirement `main` was still at the branch point (`2d1709e`) → clean
  fast-forward.
- ADR-0012 framed the old forms as "deprecated in docs-tests-k9, no flag-day."
  This leaf is the **flag-day** the user opted into afterwards — note in the
  commit / an ADR amendment that the deletion was a post-k9 user decision, so the
  record stays coherent.
- Project memory: façade cutovers can silently break inline-tree configs; LispKit
  has no `set-cdr!` (return-and-merge only); install via `./scripts/install.sh`
  to test the real .app.
