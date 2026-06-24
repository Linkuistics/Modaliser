# reconcile-source-comments-k18

**Kind:** work

## Goal

Reconcile **shipped Scheme source comments** that still reference the
authoring forms deleted in [[delete-which-key-k15]] (`define-tree` /
`category` / `overlay` / `which-key-block`). [[delete-which-key-k15]]
removed the *code* but left its own *comments* across the library tree;
[[reconcile-docs-k16]] (reference docs) and [[migrate-secondary-docs-k17]]
(how-tos/tutorial/quickstart/example) never covered source comments.
Several are not merely stale — they **teach the deleted form as the way
to use a library** (e.g. `launchers.sld`'s quick-start shows
`(define-tree 'global …)`), and users browse these via the `sys/`
mirror ahead of the public release.

Discovered during k17's verification; the user chose (2026-06-24) to
spin it into this follow-up leaf rather than bleed scope into k17 or
finish the grove with the debris in place.

## Context

This is **not** a blind find-and-replace. Two names survived the
deletion as *lowering targets / IR*, even though the **authoring forms**
of the same name were deleted:

- **`category` the authoring form is gone**, but the lowered
  **`category` node kind survives** — a `panel` lowers to a `category`
  node (see `dsl.sld` `(panel …)`, ADR-0012). So comments about the
  `category?` predicate, `flatten-categories`, or "the children of a
  category node" describe the **operational IR** and are **correct —
  keep them** (optionally reword `(category …)` → "category node" to
  avoid implying the form). Only fix comments that present
  `(category …)` as something a *user authors*.
- **`which-key`**: the block/renderer is gone. **Historical, past-tense
  notes** ("the which-key block-list path *was removed* in the flag-day
  deletion") are correct records — **keep them**. Fix only comments that
  describe which-key as a *current* path or that name a "which-key
  panel/strip/overlay" as present surface.

Migration map (same as k17): `define-tree 'scope` → `screen 'scope`;
`(category "L" …)` *the form* → `(panel "L" …)`; `(key K L (overlay …))`
/ `(overlay …)` → `(open …)`; `(which-key-block …)` → a panel's rows;
the `(modaliser blocks which-key)` import → drop it. Ground new example
snippets against `docs/reference/dsl.md` and `default-config.scm`.

**Inventory (re-grep at execution — line numbers drift).** Grep used:
`grep -rn 'define-tree\|which-key\|(category ' Sources/Modaliser/Scheme/lib/ Sources/Modaliser/Scheme/ui/`

*FIX — teaches / states a deleted **form** as current usable surface:*
- `lib/modaliser/launchers.sld` — header "Quick start" shows
  `(define-tree 'global …)` (~:13-16) and "inside a define-tree" (~:21).
- `lib/modaliser/web-search.sld` (~:251) — header usage `(define-tree 'global …)`.
- `lib/modaliser/settings-menu.sld` (~:9) — header usage `(define-tree 'global …)`.
- `lib/modaliser/window-actions.sld` (~:7,:10,:14) — header example imports
  `(modaliser blocks which-key)`, writes `(define-tree 'global …)`, uses
  `(which-key-block …)`. Drop the which-key import line; convert to
  screen/panel. (`:167` "neither the default list renderer nor the
  which-key block surfaces…" — reword the which-key-as-present clause.)
- `lib/modaliser/apps/iterm.sld` (~:559,:647,:690) — "if your config
  inlines its own `(define-tree 'com.googlecode.iterm2 …)`" etc. →
  `screen`. (`:696`,`:779` "the which-key strip suppresses this row" →
  renderer/panel-grid wording.)
- `lib/modaliser/muxes/tmux.sld` (~:401), `muxes/zellij.sld` (~:456),
  `apps/wezterm.sld` (~:395), `apps/ghostty.sld` (~:340) — "define-tree
  replaces any prior tree of the same id." The kept substrate is
  `register-tree!`; reword to the substrate these actually call
  (verify each: they're describing `rebuild-tree!` → `register-tree!`).
- `lib/modaliser/list-cursor.sld` (~:3) — "A which-key panel can embed a
  live list" → "A panel can embed a live list".
- `lib/modaliser/dsl.sld` — `:343` "Placing it in a parent (define-tree /…"
  → screen/panel/open; `:375` "run by screen / panel / open and the
  legacy define-tree /…" → drop the now-removed define-tree branch;
  `:527`,`:561`,`:577` "like define-tree" / "as define-tree composes" /
  "define-tree (on-enter…)" → screen (or "the layout forms").
  (`:450` is historical past-tense — **keep**, see below.)
- `lib/modaliser/state-machine.sld` — `:267` "register-tree!/define-tree
  root. Hooks on (overlay …)" → screen/open; `:468`
  "(set-overlay-delay! …) — set the which-key overlay delay." →
  "overlay delay". `:120` (blocks renderer) — judge: stale vs historical.
- `ui/overlay.scm` — `:109` "which-key block render the same…" — judge
  (likely reword: default-list renderer / panel-grid row renderer).

*KEEP — historical past-tense or IR-accurate (do NOT rewrite):*
- `lib/modaliser/dsl.sld:450` — "the define-tree / category / overlay
  forms these replaced **were removed** in the flag-day deletion."
- `ui/overlay.scm:376` — "the which-key block-list path **was removed**…".
- `ui/overlay.js:191` — "**Previously** shared via window.overlayRenderRow
  with the which-key block's JS…".
- `state-machine.sld:167,168,175` and `ui/overlay.scm:455` — these
  describe the **`category` node kind** / `flatten-categories` /
  nested-category filtering (the IR a `panel` lowers to), not the
  authoring form. Keep; reword `(category …)` → "category node" only if
  it reads as the form.

## Done when

- No shipped source comment under `Sources/Modaliser/Scheme/lib/` or
  `ui/` presents `define-tree` / `(category …)`-the-form / `(overlay …)`
  / `which-key-block` as *current usable* authoring surface; usage
  examples in library headers teach `screen` / `panel` / `open`.
- Historical past-tense notes and IR-accurate `category`-node comments
  are preserved (the distinction above held).
- Re-grep returns only intentional references (historical records;
  the `category` node kind / `category?` / `flatten-categories`).
- `./scripts/check-portable-surface.sh` stays green — **do not** write
  the literal `(lispkit ` in any `lib/modaliser` comment (CLAUDE.md
  portability contract; write "the LispKit … library").
- `swift build` succeeds (comment-only edits, but a fat-fingered `.sld`
  comment can still break a paren/datum — verify). Full suite need not
  be re-run for comment-only changes, but a build must pass.

## Notes

- Scope is **source comments only** — no behavioural code change. If a
  comment edit tempts a code change, that is a separate concern.
- After this leaf retires, the `legacy-whichkey-deletion-k13` node has
  no live leaf → the grove root has none → the **Finish** cycle runs
  (deferred from k9, k16, and k17). `main` was at the branch point
  `2d1709e` at k17's retirement → clean fast-forward of all commits;
  **re-check** `git merge-base --is-ancestor main visual-refresh` before
  merging.
- Pointers: `docs/reference/dsl.md` (authoritative surface),
  `Sources/Modaliser/Scheme/default-config.scm` (panel-model exemplar),
  ADR-0012 (`category` lowers from `panel`; the flag-day amendment).
