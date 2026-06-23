# migrate-callers-k14

**Kind:** work

## Goal

Migrate every **live** caller off the legacy container forms (`define-tree` /
`category`) so the which-key path has no remaining users — the **gate** that
unblocks deletion in [[delete-which-key-k15]]. The legacy forms still *exist* in
`dsl.sld` after this leaf; nothing live calls them. See the node BRIEF for the
resolved forks and the full caller inventory.

## Context

Two migration shapes (per node BRIEF, "Resolved decisions"):

- **Operational trees → `register-tree!`** (fork 2). Drop `define-tree`, call
  `(modaliser state-machine)`'s exported `register-tree!` directly with the same
  keyword head (`on-enter`/`on-leave`/`sticky`/`exit-on-unknown`/`display-name`)
  followed by the raw node children. No `'renderer` marker → the surviving
  default-list renderer handles them. All six pane-digit apps **already import**
  `(modaliser state-machine)`, so no import change.
  - `apps/iterm.sld:606` `iterm-pane-digit`, `apps/wezterm.sld:342`,
    `apps/kitty.sld:672`, `apps/ghostty.sld:289`, `muxes/tmux.sld:353`,
    `muxes/zellij.sld:406` — each is `(define-tree 'X-pane-digit 'on-enter … 'on-leave
    … (digit-range))`; `digit-range` is `(cons (cons 'hidden #t) (key-range …))`.
    Becomes `(register-tree! 'X-pane-digit 'on-enter … 'on-leave … (digit-range))`.
  - `apps/iterm.sld:544` `focus-mode-register!` — `(apply define-tree id 'sticky #t
    'exit-on-unknown #t 'display-name … (focus-mode-tree))` → `(apply register-tree!
    id 'sticky #t 'exit-on-unknown #t 'display-name … (focus-mode-tree))`.

- **Full overlays → `screen` / `panel`.**
  - `apps/iterm.sld:485` — `(apply define-tree 'com.googlecode.iterm2 'on-enter …
    'on-leave … (append (iterm-pane-bindings …) (list (key "c" …) (key "z" …)
    (category "Focus" (key "h" … 'sticky-target sticky-id) …) (group "x" "Split" …)
    (group "m" "Move Pane" …))))`. Migrate to `screen`; turn `(category "Focus" …)`
    into `(panel "Focus" …)`. **Preserve** the `'sticky-target sticky-id` props on
    the Focus keys (kept dispatch atoms; `panel` is transparent). Loose keys (`c`,
    `z`), `iterm-pane-bindings`, and the Split/Move `group`s land in the implicit
    "General" panel (ADR-0012 §Consequences) — confirm that reads acceptably in the
    overlay; wrap them in an explicit `(panel …)` if the General bucket looks wrong.
  - `apps/safari.sld:37` + `apps/chrome.sld:37` — `register!` does `(apply
    define-tree 'BUNDLE-ID (apply tree opts))`. The `tree` helper returns pure
    `group`/`key` (kept atoms). Swap `define-tree` → `screen`. Safari/Chrome import
    only `(modaliser dsl)`, which already exports `screen`.

`register-tree!` body: `state-machine.sld:104` (keyword head → opaque extras →
children; no `'renderer` ⇒ default-list). Dispatch: `overlay.scm:330`.

## Done when

- All six `*-pane-digit` trees + iTerm `focus-mode-register!` call `register-tree!`
  (no `define-tree`); behaviour unchanged (digit dispatch, chip painting, sticky
  hjkl focus all still work).
- iTerm main tree is a `screen` with a `"Focus"` `panel`; Safari + Chrome
  `register!` use `screen`. Each app's overlay still renders and dispatches.
- `grep -rn 'define-tree\|(category \|(overlay ' Sources/Modaliser/Scheme/lib/`
  (excluding `/sys/`) shows **only** the definitions in `dsl.sld` — zero live
  callers.
- Caller tests whose expected output changed (e.g. iTerm tree shape /
  `ModaliserAppsItermLibraryTests`, any window-actions assertions touching the
  migrated trees) updated to the new surface; `BlocksWhichKeyLibraryTests` and the
  other deletion-coupled tests are **left for k15**.
- `check-portable-surface.sh` green; suite green (skip flaky
  `ModaliserAppsItermLibraryTests` + `HttpLibraryTests` headless — but if the iTerm
  migration changes those, run them locally to confirm the change, per the crash
  note in project memory).

## Notes

- `register-tree!` is exported from `(modaliser state-machine)` but **not**
  re-exported by `dsl`. The six pane-digit apps already import state-machine; if any
  caller you touch does not, prefer adding the state-machine import over widening
  `dsl`'s export — these are operational registrations, not user-config surface.
- Watch the façade-cutover trap (project memory): migrating a tree that an inline
  user config overrides can silently break the inline tree. These are library trees,
  but `iterm.sld`'s rebuild path has an inline-config escape hatch (`'rebuild? #f`)
  — keep it working.
- Do **not** delete any legacy form here — that is k15's job. This leaf only stops
  *using* them.
</content>
