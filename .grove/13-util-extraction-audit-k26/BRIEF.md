# util-extraction-audit-k26 — brief

**Kind:** node (was a planning leaf; decomposed once the audit produced more than
one commit's worth of extraction).

## Goal

Audit the Scheme libraries for **repeated helper patterns that should be
centralised in `(modaliser util)`** (the shared base library) — and extract the
clear wins. Requested by the user on 2026-06-24 after the cxr accessors were
re-exported from `(modaliser util)` during bare-loose-rows-k23.

## Audit outcome (the findings — durable record)

Three Explore agents swept all ~30 `lib/modaliser/**.sld` + the 3 `ui/*.scm`
files by concern (strings / lists / JSON). Verified structural facts first:

- `root.scm` imports `(modaliser util)` then **flat-includes** `ui/css.scm`,
  `ui/overlay.scm`, `ui/chooser.scm` → the UI files **see every util export**
  (e.g. `string-join`) in the top-level environment.
- Nearly every `lib/modaliser/*.sld` already imports `(modaliser util)`.
- `(scheme base)` (LispKit) lacks `filter` → that's why filters are hand-rolled.
  No `(srfi 1)` is imported anywhere today.
- **LispKit bundles `srfi/1.sld`**; `check-portable-surface.sh` only forbids the
  literal `(lispkit ` token, so `(srfi …)` imports are allowed. → util can
  `(import (only (srfi 1) …))` and re-export, exactly like its existing selective
  SRFI-69 re-export.

### Decisions (user-confirmed 2026-06-25)

- **Scope:** do the clear, identical-semantics wins (A + B below) now in child
  `join-filter-helpers-k35`; decompose the riskier/larger ones (C, D) into their
  own children `escape-helper-merge-k36`, `alist-json-extract-k37`.
- **alist-ref mass-swap: NOT done — documented only** (finding E).

### Findings

**A. Separator-join re-implementations → use util's existing `string-join`**
(CLEAR WIN, identical semantics; no new export). Sites:
- `slash-join`            `dsl.sld:273-277`            → `(string-join lst "/")`
- `overlay-assets-concat` `overlay-assets.sld:48-59`   → `(string-join (map resolve-entry items) "\n")`
- `string-join-comma`     `ui/overlay.scm:660-667`     → `(string-join xs ",")` (4 callers)
- `css-rules`             `ui/css.scm:46-53`           → `(string-join rules "\n")`
- `css-properties`        `ui/css.scm:31-41`           → join part → `(string-join (map decl pairs) " ")`

**B. Hand-rolled filters → add `filter`/`remove`/`partition`/`filter-map` to util**
(re-export `(only (srfi 1) …)`). Sites:
- `list-filter`          `terminal.sld:155-160`        → util `filter`
- `loose-region-nodes`   `dsl.sld:548-553`  ┐ literal `partition` (k23's cited example)
- `loose-region-blocks`  `dsl.sld:556-561`  ┘  → `partition` or `filter`/`remove`
- `filter-fns`           `dsl.sld:393-402`             → `filter-map` (filters + maps)
- `filtered-rows`        `ui/overlay.scm:594-600`      → `filter-map` over `entry->row-json`

**C. Escape-helper family → one parameterised escaper** (→ child k36). Four
char-walk skeletons with *different* escape tables; host-specific (ui/*.scm);
correctness-sensitive (what reaches JS/HTML):
- `js-escape-overlay`  `overlay.scm:900`  (`\\ \" \n`)
- `js-escape`          `chooser.scm:362`  (`\\ \' \n \r`)
- `json-escape`        `chooser.scm:434`  (`\\ \" \n \r \t`)
- `string-replace-apos` `overlay.scm:889` (`'` → `&#39;`)

**D. `alist->json` + `every-pair-symbol-keyed?`** `overlay.scm:671/695` (→ child
k37). Generic JSON serializer that couples to the overlay escape flavor → depends
on C's outcome.

**E. ~94 bare `(cdr (assoc 'k a))` / `alist-ref` — CONSIDERED, NOT EXTRACTED.**
Two idioms were conflated by the raw grep:
- `state-machine` `node-*` accessors `(let ((e (assoc 'k n))) (if e (cdr e) DEF))`
  are *already* the single canonical accessor layer (not cross-file duplication)
  and have explicit defaults.
- bare `(cdr (assoc 'k cell))` (e.g. `window-actions` `js-cell`) has **no
  default** → errors if the key is absent; the builder guarantees presence, so the
  bare `cdr` is a deliberate *presence assertion*. Swapping to `alist-ref` would
  convert a loud crash into a silently-propagating `#f` across ~94 sites for
  near-zero value — the "extract for uniformity" anti-pattern the root note warns
  against. A short comment near `alist-ref` in `util.sld` records this so a future
  session doesn't re-propose it.

**F. Leave local (specialised, not duplication):** `entry->row-json`,
`highlight-matches`, `flatten-categories`, `expand-splices`, `label-pairs`
(already the single shared def), `footer-hints-html` / `render-header-breadcrumb`
(already shared once via the flat-include namespace), the 1-line `sigil-escape`
duplicate.

## Children

1. `01-join-filter-helpers-k35` — findings A + B (this is the "clear wins" commit).
2. `02-escape-helper-merge-k36` — finding C.
3. `03-alist-json-extract-k37` — finding D (sequence after k36).

## Promote-on-retire

When this node retires, promote nothing structural — the wins land in `util.sld`
and its callers, and the alist-ref decision lives as a code comment. Finding E's
reasoning is the only thing worth keeping discoverable, and the `util.sld` comment
carries it.

## Notes

- Codebase-health, not overlay presentation — a root-level node, not under
  overlay-polish-k19. Independent of manual-panel-order-k24 / list-cursor-k25.
- Don't extract for its own sake (see the cross-project-consistency memory note);
  only centralise genuine duplication.
