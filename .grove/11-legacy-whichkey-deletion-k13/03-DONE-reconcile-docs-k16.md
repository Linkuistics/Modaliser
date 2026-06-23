# reconcile-docs-k16

**Kind:** work

## Goal

Reconcile the docs, glossary, and ADR record to the *removal* that
[[delete-which-key-k15]] performed — closing the gap [[docs-tests-k9]] left when it
could only mark the legacy forms "deprecated, still present." This is the final
leaf of the node; after it retires the grove proceeds to its **Finish** cycle (see
node BRIEF Notes).

## Context

k9 left the docs describing the legacy which-key / `define-tree` / `category` /
`overlay` forms and `set-overlay-aspect-ratio!` as *deprecated but available*. They
are now **gone**, so the docs must stop describing them as usable surface. Known
touch-points (re-grep at execution — line numbers drift):
- `docs/reference/dsl.md` — the "Legacy forms (deprecated)" section (`define-tree` /
  `category` / `overlay`) and the `(set-overlay-aspect-ratio! ratio)` entry
  (`:114`, `:128`) + its mention in the settings list (`:51`).
- `docs/reference/theming.md` — the `--overlay-cols` row (`:152`) referencing
  `overlay-column-count` / `set-overlay-aspect-ratio!`; reframe to CSS-intrinsic
  columns (matching fork 1).
- `docs/reference/renderer-protocol.md` — the `set-overlay-aspect-ratio!` column
  search prose (`:87`, `:246`) and any which-key payload description.
- `docs/reference/libraries.md` — which-key block mentions.
- `docs/reference/library-system.md` — `set-overlay-aspect-ratio!` reference
  (`:110`).
- `docs/how-to/customise-theme.md` — check for aspect-ratio / column guidance.
- `CONTEXT.md` — prune any which-key / legacy-form glossary entry (keep `panel` /
  `screen` / `open` / `span` / `live-list`).
- The design spec (`docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md`)
  — its §49 still frames the aspect-ratio search as governing the default list
  renderer; add a closing note that the flag-day removed it (or leave the spec as a
  historical record and note the divergence — judgement call; the spec is a dated
  snapshot, so a one-line "superseded by k13" note is usually enough).

**ADR-0012 amendment.** ADR-0012 §Consequences says the old forms "keep working …
deprecated in `docs-tests-k9`. No flag-day." Add a short amendment (a dated note at
the end, or a `Status:` line update) recording that `legacy-whichkey-deletion-k13`
performed the flag-day deletion as a **post-k9 user decision** — so a future reader
isn't confused that the "no flag-day" consequence was reversed.

## Done when

- No reference doc presents `define-tree` / `category` / `overlay` /
  `which-key-block` / `set-overlay-aspect-ratio!` as available surface; the
  `--overlay-cols` / aspect-ratio prose is reframed to CSS-intrinsic columns.
- `CONTEXT.md` carries no stale which-key / legacy-form term.
- ADR-0012 carries the flag-day amendment.
- `grep -rn 'which-key\|define-tree\|set-overlay-aspect-ratio\|overlay-column-count'
  docs/ CONTEXT.md` returns only intentional historical references (e.g. the dated
  design spec, ADR history) — no live "you can use this" guidance.
- Docs prose avoids the literal parenthesized `(lispkit …)` form (portability
  comment rule) where it touches portable-tree files.

## Notes

- Docs-only leaf — no Swift/Scheme code changes, so the test suite is unaffected;
  still run `check-portable-surface.sh` if any portable-tree comment was edited.
- The audience is external readers (public release ~2026-W21, project memory) — write
  for someone meeting the panel surface fresh, not for future-self.
- Use Mermaid, never ASCII art, for any diagram (project memory).
</content>
