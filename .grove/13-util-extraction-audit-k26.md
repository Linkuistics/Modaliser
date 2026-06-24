# util-extraction-audit-k26

**Kind:** planning

## Goal

Audit the Scheme libraries for **repeated helper patterns that should be
centralised in `(modaliser util)`** (the shared base library) — and extract the
clear wins. Requested by the user on 2026-06-24 after the cxr accessors were
re-exported from `(modaliser util)` during bare-loose-rows-k23.

## Context

- bare-loose-rows-k23 established the precedent: `(modaliser util)` now
  re-exports the R7RS `(scheme cxr)` accessor family (caddr / cadddr / …), which
  LispKit's `(scheme base)` omits, so `(modaliser …)` libraries get them from
  one base library without each importing `(scheme cxr)` and risking
  inconsistent-import conflicts.
- `(modaliser util)` already holds `alist-ref`, `props->alist`, `string-join`,
  `read-file-text`, `log`, the SRFI-69 hashtable surface, and local
  `string-split` / `string-trim` / `string-contains?`.
- The portability contract (docs/reference/portability.md,
  check-portable-surface.sh) constrains `lib/modaliser` to `(scheme …)`,
  `(srfi …)`, and other `(modaliser …)` — so any extraction target stays
  portable.

## Candidates to investigate (non-exhaustive)

- **JSON / JS-string escaping & joining** in `ui/overlay.scm`:
  `js-escape-overlay`, `string-join-comma`, `string-replace-apos`, `alist->json`
  — but note `ui/*.scm` is host-specific (not the portable tree); judge whether
  a shared JSON helper belongs in a `(modaliser …)` library or stays UI-local.
- List/alist helpers duplicated across `dsl.sld`, `state-machine.sld`, blocks,
  and app libraries (e.g. ad-hoc `assoc`-then-`cdr`, filter/partition loops like
  k23's `loose-region-nodes` / `loose-region-blocks`, `filter-fns`).
- String helpers beyond the current three.

## Done when

- A findings list of genuine duplication / extraction candidates, each with a
  recommendation (extract → util, leave local, or out of scope).
- The clear, low-risk wins extracted into `(modaliser util)` (or the right base
  library) with call sites updated; tests green; `check-portable-surface.sh`
  green.
- Larger or riskier extractions decomposed into their own child leaves rather
  than forced into one commit.

## Notes

- This is codebase-health, not overlay presentation — hence a root-level leaf,
  not under overlay-polish-k19.
- Independent of manual-panel-order-k24 and list-cursor-initial-focus-k25.
- Don't extract for its own sake — see the memory note on preferring the
  simpler local design over uniformity; only centralise genuine duplication.
