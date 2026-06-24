# escape-helper-merge-k36

**Kind:** work

## Goal

Collapse the four near-duplicate char-by-char escapers (audit finding C) into one
parameterised escaper, preserving each call site's exact escape table.

## The duplication

All in the host-specific `ui/*.scm`; each walks `(string->list str)` accumulating
a reversed result, differing only in the escape table:

- `js-escape-overlay`   `overlay.scm:900`  escapes `\\ \" \n`
- `js-escape`           `chooser.scm:362`  escapes `\\ \' \n \r`
- `json-escape`         `chooser.scm:434`  escapes `\\ \" \n \r \t`
- `string-replace-apos` `overlay.scm:889`  maps `'` → `&#39;` (single substitution)

## Approach (to settle when picked)

A generic `(escape-string str table)` where `table` is an alist of
`char → replacement-string`, factoring the shared walk. The first three become
calls with their own tables; `string-replace-apos` is a degenerate one-entry
table. Open question to decide then: **does the generic escaper go to `(modaliser
util)` (it's pure `(scheme base)`, so portable-eligible) or stay UI-local?** The
tables themselves stay at the call sites either way.

## Risk / why its own leaf

Correctness-sensitive: these strings are emitted into JS string literals and HTML
attributes; an off-by-one in the table changes what reaches the WebView. Verify
each table is preserved exactly (the three JS/JSON variants genuinely differ —
`js-escape-overlay` does NOT escape `'`, `json-escape` adds `"` and `\t`).

## Done when

- One escaper mechanism; the four sites call it with their preserved tables.
- Overlay + chooser still render correctly (exercise via tests / a real run if
  rendering isn't unit-covered).
- `swift test` + `./scripts/check-portable-surface.sh` green.

## Notes

- Don't write the literal `(lispkit ` token in any portable-tree file or comment.
- Independent of k37 except that k37's `alist->json` consumes the overlay escaper
  — settle this leaf's escaper home first so k37 can reference it.
