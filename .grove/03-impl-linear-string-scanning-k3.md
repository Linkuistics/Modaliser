# linear-string-scanning-k3

## Goal

Remove the quadratic scanning idiom from the paths `k2`'s measurement shows
are hot, so a leader press never holds the keyboard.

**Shaped by k2 — read its findings before planning this.** The scope below is
the agreed *approach*, not a decided edit list; k2 names the actual call site.

## Context

The idiom to remove:

```scheme
(let loop ((k 0))
  (when (< k (string-length s))   ; Θ(n) — bridges the whole string
    (let* ((c (string-ref s k))   ; Θ(n + k) — bridges it again
```

The idiom to reach for is already in the tree — `escape-string`
(`util.sld:170`) does one `string->list` and walks the list, so it is O(n)
with no `string-ref` at all. A `list->vector` + `vector-ref` variant keeps
random access at O(1) where a scanner genuinely needs to look ahead or back.

Candidates, in descending suspicion (k2 decides): `json-parse` and
`write-json-string` (`json.sld`); `string-index-of` / `string-contains?` /
`string-split` / `string-trim` (`util.sld:95-168`); then `dsl.sld`,
`web-search.sld`, `activation.sld`, `display-actions.sld`, `chooser.scm`.

## Done when

- The hot scanner(s) are O(n), demonstrated by a before/after measurement in a
  **release** build, at a payload size that reproduced the stall.
- `swift test` is green. The JSON reader's fifteen existing cases and the four
  added by `strip-parse-cost-k10` still pass untouched.
- **Correctness is not traded for speed.** Keep every `expect` and both escape
  bounds checks: `string-ref` past the end raises a *host* range error, which
  escapes the `guard` every caller wraps `json-parse` in — the one outcome the
  reader's malformed-input handling exists to prevent.
- `scripts/check-portable-surface.sh` and `scripts/check-decision-free.sh`
  both pass. Nothing under `lib/modaliser` gains a `(lispkit …)` import or a
  `…-native` import.
- A `review-impl` leaf is cut for this work (`leaf-add`, `**Reviews:**
  linear-string-scanning-k3`), and its integration cut adjacent to it.

## Notes

- **A native seam is the fallback, not the opening move.** If portable Scheme
  reaches O(n), no ADR and no new native library is needed. If measurement
  shows it cannot, that is an architectural change — a `(modaliser …-native)`
  library plus a seam plus an ADR — and it needs a design leaf, not an
  improvised edit. `strip-parse-cost-k10` already recorded that LispKit's
  native substring search sits in a host library `lib/modaliser` may not
  import, and that the SRFI re-export is backed by a Scheme KMP loop.
- Watch for the same cliff in `string-length` used as a **loop guard** — it
  bridges too, so hoisting it out of the loop is free speed even where the
  scanner stays index-based.
- If k2 finds the window-overlay symptom is a different scanner on the same
  cliff, fix it here too; if it is a different cause, `leaf-add` it rather
  than absorbing it.
