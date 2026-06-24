# join-filter-helpers-k35

**Kind:** work

## Goal

Land the two clear, identical-semantics extraction wins from the audit (findings
A + B in the node BRIEF). This is the "clear wins" commit.

## A — collapse separator-join re-implementations onto util `string-join`

`string-join` already exists in `(modaliser util)` and is in scope at every site
(the UI files are flat-included after `root.scm` imports util). Replace:

- `slash-join`            `dsl.sld:273-277`            → `(string-join lst "/")`
- `overlay-assets-concat` `overlay-assets.sld:48-59`   → `(string-join (map resolve-entry items) "\n")`
- `string-join-comma`     `ui/overlay.scm:660-667`     → `(string-join xs ",")` (4 callers)
- `css-rules`             `ui/css.scm:46-53`           → `(string-join rules "\n")`
- `css-properties`        `ui/css.scm:31-41`           → keep the `prop: val;` decl building; replace the join with `(string-join (map decl pairs) " ")`

Delete the now-dead local helpers (or make them thin wrappers only if a name is
load-bearing for readability — prefer deletion + direct call).

## B — add a small list-filter family to util, collapse the hand-rolled loops

Add to `(modaliser util)` by **re-exporting `(only (srfi 1) filter remove
partition filter-map)`** (mirror the existing selective SRFI-69 re-export; keep
the export list + comment tidy). Then:

- `list-filter`          `terminal.sld:155-160`   → drop; use util `filter`
- `loose-region-nodes`   `dsl.sld:548-553`        ┐ → `partition` (or filter/remove);
- `loose-region-blocks`  `dsl.sld:556-561`        ┘   these are the literal k23 partition
- `filter-fns`           `dsl.sld:393-402`        → `filter-map` (it filters AND maps)
- `filtered-rows`        `ui/overlay.scm:594-600` → `filter-map` over `entry->row-json`

Use `(only (srfi 1) …)` to avoid shadowing `(scheme base)` `map`/`assoc`/`member`
inside util's own body.

## E — record the "don't mass-swap alist-ref" decision

Add a short comment near `alist-ref` in `util.sld` noting that the ~94 bare
`(cdr (assoc …))` sites are **deliberately not** rewritten to `alist-ref` (they
assert key presence; `alist-ref` would mask missing-key errors as `#f`). Keeps a
future session from re-proposing it.

## Done when

- All A + B sites updated; dead local helpers removed.
- `(modaliser util)` exports the new filter family; docs/reference/libraries.md
  reflects the added exports if it enumerates util's surface.
- `swift test` green (Scheme behaviour is exercised through a real LispKit
  context).
- `./scripts/check-portable-surface.sh` green.

## Notes

- `(srfi 1)`'s `filter-map` exists; confirm the exact name LispKit's `srfi/1.sld`
  exports before relying on it (fall back to `(filter values (map f xs))` shape if
  absent).
- One focused commit; name it by this handle `join-filter-helpers-k35`.
