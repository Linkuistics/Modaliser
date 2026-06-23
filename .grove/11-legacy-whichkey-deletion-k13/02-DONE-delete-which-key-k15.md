# delete-which-key-k15

**Kind:** work

## Goal

With [[migrate-callers-k14]] having emptied the gate, physically delete the legacy
which-key machinery and the old DSL container forms, swap the surviving
default-list renderer to a CSS-intrinsic column source (fork 1), and remove the now
dead `set-overlay-aspect-ratio!` (fork 3) — rewriting/removing the tests that pin
the deleted code **in the same commit** so the suite stays green. See the node
BRIEF for the resolved forks and the deletable set.

## Context

Three coupled strands (one commit):

**A. Fork 1 — default-list column source → CSS-intrinsic.** `overlay-column-count`
is shared by the dying which-key path AND the surviving default-list renderer, so
its deletion and the CSS swap are inseparable.
- `ui/overlay.scm:347` (`render-overlay-default`) and `:938`
  (`push-overlay-update-default`): stop computing `n-cols`; stop emitting
  `data-cols` / `"cols"`.
- CSS (`base.css`, `ui/css.scm`, or wherever `.overlay-entries` is styled): make
  `.overlay-entries` a `display:grid` with `repeat(auto-fit, minmax(…, 1fr))` (or a
  fixed track count). `base.css:229-230` has a comment referencing
  `overlay-column-count` / `set-overlay-aspect-ratio!` — update it.
- `overlay.js`: stop reading `data-cols` / setting `--overlay-cols`.
- Delete `overlay-column-count` + its seeds `overlay-col-width-px`,
  `overlay-row-height-px` (and the `set-overlay-aspect-ratio!`-tunable comment at
  `overlay.scm:80`).

**B. Delete the which-key path (surgical).**
- `ui/overlay.scm`: delete `which-key-payload-json` (`:551`),
  `partition-which-key-segments`, `segment-row-count`, `segments-row-count`,
  `distribute-which-key-columns`, `render-segment`, and the **`'which-key` branch**
  of `block-json` (`:437`). **Preserve** the other `block-json` branches
  (`iterm-panes`, `iterm-tabs`, `window-list`, `window-diagram`) — panel-grid embeds
  them via `block-json` at `:524`.
- **Verify `block-list-payload-json` reachability.** After `define-tree` is gone,
  check whether anything still sets `'renderer 'blocks` (grep). If nothing does, the
  `(else (block-list-payload-json current))` arm at `:464` and
  `block-list-payload-json` itself are dead → delete them too. If something still
  reaches it, leave it. **Do not assume — grep and confirm.**
- **Preserve `overlayRenderRow`.** `blocks/which-key.js` exports
  `window.overlayRenderRow`, reused by `overlay.js renderPanelRow`. Move that
  function into `overlay.js` (or a kept asset) **before** deleting `which-key.js`,
  and re-verify `renderPanelRow` still resolves it.
- `lib/modaliser/dsl.sld`: delete `define-tree`, `category`, `overlay`,
  `pack-node-runs`, `flush-node-run`, `node-form?`; remove the
  `(modaliser blocks which-key)` import and `which-key-block`; drop all of these
  from the `export` list (`:13-22`). Keep `screen`/`panel`/`open`/`fragment` and the
  dispatch atoms.
- Delete `lib/modaliser/blocks/which-key.{sld,js,css}`.

**C. Fork 3 — remove `set-overlay-aspect-ratio!`.** Delete the procedure +
`%overlay-target-aspect-ratio` (`state-machine.sld:488`); drop from
`state-machine.sld`'s export (`:35`) and the `dsl.sld` re-export (`:21`).

**Tests (same commit):** delete `BlocksWhichKeyLibraryTests`; remove the which-key
cases + the two `set-overlay-aspect-ratio!` cases (`OverlayRenderTests:206,210`)
from `OverlayRenderTests`; audit `ModaliserDslLibraryTests` /
`ModaliserWindowActionsLibraryTests` and remove the define-tree/category/which-key
cases. Keep `LayoutDslTests`, `PanelGridRendererTests`, `ListCursorDispatchTests`,
`ConfigDslTests` green.

## Done when

- `(modaliser blocks which-key)` + assets gone; `dsl.sld` no longer imports it;
  `define-tree`/`category`/`overlay`/`which-key-block`/`pack-node-runs`/
  `flush-node-run`/`node-form?` removed and dropped from exports.
- `which-key-payload-json` + its 5 helpers + the `block-json` `'which-key` branch
  gone; the iterm-panes/iterm-tabs/window-list/window-diagram branches and
  `overlayRenderRow` (relocated) **preserved and working**.
- `overlay-column-count` + seeds gone; `.overlay-entries` columns are CSS-intrinsic;
  default-list overlays (a plain `(group …)` drill-down; the migrated focus-mode
  hjkl list) still render correctly.
- `set-overlay-aspect-ratio!` + `%overlay-target-aspect-ratio` gone from both
  exports.
- `grep -rn 'which-key\|overlay-column-count\|set-overlay-aspect-ratio'
  Sources/Modaliser/Scheme` (excluding `/sys/` and remaining doc-bound comments
  k16 will clean) shows no live code references.
- `check-portable-surface.sh` green; full suite green (deletion-coupled tests
  removed/rewritten; new panel tests still pass). Skip flaky
  `ModaliserAppsItermLibraryTests` + `HttpLibraryTests` headless.

## Notes

- Commit message: name the deletion as the post-k9 **flag-day** (ADR-0012 said "no
  flag-day"; this is the user's post-k9 decision). The ADR amendment itself lands in
  [[reconcile-docs-k16]], but the commit body should already say so.
- LispKit has no `set-cdr!` — if any deletion tempts an in-place mutation, use
  return-and-merge (project memory).
- After deleting `which-key.js`, the `sys/` mirror is regenerated at production
  startup — no manual `sys/` edit needed (dev/test reads straight from `Sources/`).
</content>
