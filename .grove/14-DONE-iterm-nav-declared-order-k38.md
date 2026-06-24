# iterm-nav-declared-order-k38

**Kind:** work (with one clarifying question up front — see Open question)

## Goal

The user wants the iTerm **split-nav** and **tab-nav** key sets to render in
**declared order** (`'order 'declared`) rather than the default key-sort. Verbatim
request (2026-06-25): *"In my config, I want the iTerm split-nav and tab-nav to be
'order 'declared."*

Today the default key-sort (manual-panel-order-k24's `sort-key-lt?`: lowercase
before uppercase) interleaves the sets as `h H j J k K l L` — i.e. Focus Left,
Move Left, Focus Down, Move Down, … The user wants the written order instead:
Focus h/j/k/l grouped, then Move H/J/K/L grouped.

## Where these live (verified)

- `~/.config/modaliser/app-trees/com.googlecode.iterm2.scm`
  - `tab-nav`  = `(sticky-set 'iterm-tab-walk "Tabs" (key "h" …) …)`  — line ~69
  - `split-nav`= `(sticky-set 'iterm-split-walk "Splits" (key "h" …) …)` — line ~82
  - `split-nav` is spliced into `(open "s" "Splits" split-nav (group "n" …) (panel "Panes" …))` — line ~127
  - `tab-nav`  is spliced into `(open "t" "Tabs" … tab-nav (panel "Tabs" …))` — line ~142
- `sticky-set` (the shared helper) is in the repo:
  `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld:351` — returns a `'kind 'splice`
  node AND registers a sticky mode tree under MODE-ID via `register-tree!`.

## The architecture wrinkle (read before editing)

`sticky-set` returns a **splice node** (`'kind 'splice`); `expand-splices` hoists
its keys into the enclosing container. A splice node has **no `'order` slot** —
`'order` ('keys | 'declared) is a property of `screen` / `panel` / `open` / `group`
only (see `dsl.sld` panel/screen/open constructors + the resolution chain in
`ui/overlay.scm` ~line 489/563: panel-explicit `'order` > screen-order > 'keys).

There are therefore **two render surfaces** for these key sets:

1. **Entry-point list** — the keys hoisted into `(open "s")` / `(open "t")`. Order
   here is governed by the enclosing `open`'s `'order`.
2. **Latched sticky-mode tree** — the mode registered under MODE-ID
   (`'iterm-split-walk` / `'iterm-tab-walk`) by `register-tree!` inside
   `sticky-set`, shown once you latch into the walk. It currently gets
   `'sticky #t 'exit-on-unknown #t 'display-name …` but **no `'order`**, so it
   would still key-sort.

## Open question (ask the user first — one question)

Which render surface(s) should be declared-order, and so which mechanism?
- **(A) Entry-point only** — add `'order 'declared` to the `(open "s")` / `(open "t")`
  forms in the user config. Smallest change; pure user-config edit, no repo change.
  Note it reorders ALL of each open's children (the nav keys, the `New Split` group,
  the `Panes`/`Tabs` panel) into declared order — usually desirable, confirm.
- **(B) Both surfaces** — also make the latched mode declared-order. Requires
  teaching `sticky-set` to pass `'order` through to its `register-tree!` call
  (repo change in `dsl.sld` → portable surface; needs a test + reference-doc note),
  then either defaulting to declared or adding an `'order` keyword to `sticky-set`.

Recommended default: **(A)** unless the user also cares about the latched-walk
list — start by asking which they mean.

## Scope / sequencing notes

- The nav sets are defined **only in the user's config** (`~/.config/modaliser/`),
  not in the bundled tree — so option (A) is an edit OUTSIDE the grove's repo/git
  scope (the worktree is the repo; `~/.config` is not committed here). Option (B)'s
  `sticky-set` change IS a repo change and would be a normal grove commit.
- Per the config-sync convention (memory `feedback_config_sync`): user config.scm
  syncs to bundled `default-config.scm`, but these app-trees aren't mirrored in the
  bundle, so there's no default-config sync for the (A) part. Confirm whether the
  bundled default should gain an example.
- Don't write the literal `(lispkit ` token in any portable-tree file or comment.

## Done when

- The user has confirmed surface (A / B / both), the chosen edit is landed, and the
  iTerm Splits/Tabs nav renders in declared order. If (B): `sticky-set` change has a
  test, `check-portable-surface.sh` green, reference doc updated.
