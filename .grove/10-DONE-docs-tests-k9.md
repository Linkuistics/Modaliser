# docs-tests-k9

**Kind:** work

## Goal

Reconcile the source-of-truth **docs** to the layout DSL + panel-grid renderer,
close the **portability** gate, and round out the **cross-cutting tests**. This is
the final sweep before the grove finishes.

## Context

- `docs/reference/{dsl,theming,renderer-protocol,libraries}.md` +
  `docs/how-to/customise-theme.md` are ground-truthed against the `.sld` sources.
- The committed design spec
  `docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md` §4–§5 describe
  the **old** operational-first / auto-layout primacy; the planning commit added
  only a pointer to **ADR-0011** — this leaf reconciles §4–§5 in full.
- `CONTEXT.md` gained the **Overlay-presentation domain** terms (panel / screen /
  layout spec / operational IR / span / live list) during planning — verify they
  still match the shipped surface.
- `scripts/check-portable-surface.sh` must stay green; **prose** in `lib/modaliser`
  must avoid the literal `(lispkit ` string (write "the LispKit … library").
- Repo convention: behavioural `.sld` changes need tests — most land in their
  feature leaf; this leaf catches the cross-cutting snapshot / EndToEnd coverage.
- Audience: docs assume **external readers** (public release ~2026-W21 — see
  project memory), not future-self.

## Done when

- `dsl.md` documents the layout DSL (screens / panels / spans / live-list /
  fragments) and notes the operational tree is now an **IR**.
- `renderer-protocol.md` documents the `panel-grid` payload + the two-tier
  renderer registry.
- `theming.md` + `customise-theme.md` document the new token vocabulary.
- The design spec §4–§5 reconciled to the inversion; `CONTEXT.md` terms verified.
- `check-portable-surface.sh` green; an EndToEnd **panel** snapshot/dispatch test
  exists for the global tree + an app tree.

## Notes

- **Legacy auto-layout deletion — deferred from [[config-migration-k8]] to here.**
  k8's brief folded in deleting the which-key whole-overlay column packing
  (`which-key-payload-json`, `partition-which-key-segments`,
  `distribute-which-key-columns`, `segment-row-count`, `segments-row-count`,
  `render-segment`), `overlay-column-count` (+ its `overlay-col-width-px` /
  `overlay-row-height-px` seeds), the `'which-key` branch of `block-json`, and the
  `(modaliser blocks which-key)` library + `.js`/`.css`. **k8 verified its
  preconditions are NOT met by the config migration alone**, so it migrated only
  (user-approved) and left the deletion here:
    - `overlay-column-count` still backs `render-overlay-default` /
      `push-overlay-update-default` (`ui/overlay.scm`) — the **default list
      renderer**, which still serves every plain nested `(group …)` in the
      migrated configs (Finder View/Go, iTerm Split/Move, the sticky walks).
      Delete it only after migrating those callers or swapping in a CSS-intrinsic
      column count.
    - `which-key-block` is still called by `pack-node-runs` / `flush-node-run`
      (`dsl.sld:604,606`), which back the **old `define-tree` / `category` /
      `overlay` forms** ADR-0012 keeps working "until docs-tests-k9". Deleting the
      library breaks them — so retiring/neutralising those old forms (and the
      ~10 test suites + `BlocksWhichKeyLibraryTests` / the `OverlayRenderTests`
      cases that pin the targets) is the gate. `overlay.js`'s `renderPanelRow`
      already carries the fallback for `which-key.js`'s `window.overlayRenderRow`,
      so the JS side is ready.
  k8 *did* land the one genuinely-unblocked piece: dropped the dead
  `(modaliser blocks which-key)` import from the bundled default (it imported but
  never constructed a which-key block).
- k8 already added the EndToEnd **panel** snapshot/dispatch coverage this leaf's
  Done-when calls for (global + iTerm render as panel-grid, dispatch unchanged):
  `ConfigDslTests.defaultGlobalTreeRendersAsPanelGrid` /
  `defaultWindowsScreenEmbedsDiagramAndHidesItsKeys` /
  `defaultItermTreeRendersAsPanelGrid`. Extend rather than duplicate.
- **Pre-existing flaky crash (not visual-refresh):** running
  `ModaliserAppsItermLibraryTests` (with its native AX/iTerm/hints calls) crashes
  the test process with signal 10 on this machine, reproducibly on the pre-k8
  baseline too. Unrelated to the layout DSL; flagged so a future green-suite check
  knows to `--skip ModaliserAppsItermLibraryTests` (and the `HttpLibraryTests`
  network test) in headless runs.
- After this leaf retires, the grove root has **no live leaf** → trigger the
  **Finish** cycle (promote ADR-0011 / docs / glossary already live; delete
  `.grove/`; merge `visual-refresh` → `main`).
- Token-vocabulary cleanup carried over from [[chooser-restyle-k7]]: the chooser
  no longer defines `--chooser-selected-bg` / `--chooser-selected-border` — its
  selected result row is now a shared `.list-row.is-focused`, themed by
  `--list-focus-bg` / `--list-focus-bar` (one selection knob across the chooser
  and the embedded live lists). Drop those two rows from the `theming.md` token
  table + the `customise-theme.md` examples and document `--list-focus-*` /
  `--list-bg` / `--list-border` instead.
