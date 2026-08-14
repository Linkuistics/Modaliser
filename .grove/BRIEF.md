# Modaliser.local-tree-in-herdr-locks-up — brief

## Goal

Make the leader press fast again. Pressing the local leader (F17) with herdr
focused locks the keyboard for ~30 s before the overlay appears; the window
overlay that paints chips is reported slow too, and both worsen with more
panes/windows.

The cause is established (see Notes): **LispKit's `string-ref` is Θ(n) per
character**, so the ordinary Scheme scanning idiom is O(n²) with a very large
constant, and it runs synchronously on the thread that owns the CGEvent tap.
The remaining unknown is *which* string.

## Done when

- The herdr local leader comes to rest without a perceptible stall, and the
  keyboard is never held by a leader press.
- The quadratic scanning idiom is gone from the paths that carry it, with the
  win recorded as a before/after measurement in a **release** build (a debug
  number misattributed this cost once already — see `strip-parse-cost-k10`).
- Correctness is preserved: the JSON reader's malformed-input handling still
  holds, including the bounds checks that stop `string-ref` raising a *host*
  range error past the end (which escapes the `guard` every caller wraps
  `json-parse` in).

## Decomposition

1. **measure-hot-scan-k2** — instrument the leader-press path and *name* the
   string, instead of deducing it. Ends the guesswork; shapes k3.
2. **linear-string-scanning-k3** — remove the quadratic idiom where the
   measurement says it is hot. Cuts its own `review-impl` chain.

## Pointers

- `Sources/Modaliser/Scheme/lib/modaliser/json.sld` — 24 `string-ref` sites;
  `json-parse` (:90) and `write-json-string` (:341).
- `Sources/Modaliser/Scheme/lib/modaliser/util.sld` — `string-index-of` (:95),
  `string-contains?` (:137), `string-trim` (:157), and `escape-string` (:170),
  which is the **O(n) shape to copy**: one `string->list`, then walk the list.
- `Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld:1308` —
  `herdr-jump-provider`, the on-enter gather; `paint-jump-chips!` (:1179).
- ADR-0014 (interactive commands never block), ADR-0023 (native reach is
  host-installed), ADR-0021 — and `scripts/check-portable-surface.sh`, which
  is what makes "just write it in Swift" expensive.
- Prior art: `strip-parse-cost-k10` (jj change `onwkwpqzyrny`) fought this same
  cost class in `json.sld` and recorded that a native substring search is not
  reachable under the portability contract.

## Notes

**Proven** (LispKit source, not inference): `Expr.swift:43` stores Scheme
strings as `NSMutableString`; `asString()` is `res as String`, a full bridge
per call; `stringRef` bridges then walks a UTF-16 index; `stringLength`
bridges too. So `(when (< k (string-length s)) … (string-ref s k) …)` does
**two whole-string bridges per character** — ~2n² bytes copied per scan.

**Profile** (release app, PID 3417, 240 s at ~1.14 ms): 97 % of a 27 s press
inside `StringLibrary.stringRef`, under `fireHotkeyHandler` →
`Evaluator.execute`, on the main thread.

**Disconfirmed** — do not re-investigate: the herdr fork (installed, serving,
`ui.layout` in 0.1 ms); the socket transport (4.3 KB/enter, 0.1–0.6 ms); iTerm
AppleScript (80 ms); the AX tree walk (absent from the profile); paneru (not
installed here); the JSON-reader rewrite (the old reader indexed too); the
media-key work; the simplify-project commit (docs only).

**Agreed approach** (with the user, this session): measure first, then fix the
scanning *idiom* — because that fixes JSON, `string-split`, `string-trim` and
whatever else sits on the cliff, including the window-overlay symptom.
Moving the chip/AX code to Swift is explicitly **not** the fix (that code does
not appear in the profile at all); a native seam stays the fallback, taken only
if measurement shows portable Scheme cannot get there.

## On the horizon

- The **window-overlay** symptom ("slows with a lot of windows") is reported
  but not yet diagnosed. Likely the same cliff on a different scanner; confirm
  during k2 rather than assuming.
- A second unbounded reach seen in passing, unrelated to this stall:
  `AppLibrary.resolveApplicationURL` (`AppLibrary.swift:284`) spawns `mdfind`
  and `waitUntilExit`s on the main thread with no timeout — the same shape
  ADR-0014 exists to prevent. Worth its own leaf if it ever bites.
- Possible ADR once the fix lands: *portable Scheme must not scan strings by
  index*. This cost class has now bitten twice. Raise it only if the fix
  proves it is a standing rule rather than a one-off.
