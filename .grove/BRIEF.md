# Modaliser.local-tree-in-herdr-locks-up — brief

## Goal

Make the leader press fast again. Pressing the local leader (F17) with herdr
focused locks the keyboard for ~30 s before the overlay appears; the window
overlay that paints chips is reported slow too, and both worsen with more
panes/windows.

The cause is established (see Notes): **LispKit's `string-ref` is Θ(n) per
character**, so the ordinary Scheme scanning idiom is O(n²) with a very large
constant, and it runs synchronously on the thread that owns the CGEvent tap.

**`measure-hot-scan-k2` named the string.** It is herdr's
`pane.process_info` reply — 97 360 characters — parsed by `json-parse` in
26.2 s, *twice* per press because `walk-path` is uncached. It is 97 KB
because one process entry carries a 47 KB command line (a grove-launched
`claude`), so it does **not** scale with pane count. Full reading, and what
it means for the fix, in `03-impl-linear-string-scanning-k3.md`.

## Done when

- The herdr local leader comes to rest without a perceptible stall, and the
  keyboard is never held by a leader press.
- The quadratic scanning idiom is gone from the paths that carry it, with the
  win recorded as a before/after measurement in a **release** build (a debug
  number misattributed this cost once already — see `strip-parse-cost-k10`).
- Correctness is preserved: the JSON reader's malformed-input handling still
  holds. Note that `linear-string-scanning-k6` corrected the reasoning here —
  the vector conversion *removed* the unguardable-host-error hazard, because
  `vector-ref` bounds-checks before indexing where `string-ref` trapped. The
  reader's explicit bounds checks stay for a narrower reason: they answer with
  the stable domain error `json-parse: unterminated string` rather than
  LispKit's generic range message, and a test now asserts on that message.

## Decomposition

1. **measure-hot-scan-k2** — *done*. Instrumented the leader-press path and
   named the string. Left `(modaliser instrument)` behind as a standing
   diagnostic (`docs/how-to/measure-a-leader-press.md`).
2. **linear-string-scanning-k3** — *done*. `(modaliser json)` now converts
   the source once with `string->vector` and scans the vector; the reader
   and the writer both. Release micro-benchmark on the real 97 371-character
   `pane.process_info` payload, identical harness both sides:
   **27 851 ms → 186 ms** (the "before" reproduces k2's in-app 26 205 ms).
   ADR-0025 turns the shape into a standing rule for `lib/modaliser`.
   **Not yet verified end-to-end** — nobody has installed the fixed app and
   pressed F17.
3. **linear-string-scanning-k4** — `review-impl` of the above. *Done*; it
   found three things, integrated as k6.
4. **linear-string-scanning-k6** — *done*. Corrected the reader's error-path
   rationale (`vector-ref` is guardable; `string-ref` was not), replaced the
   "some error raised" truncation assertions with a pin on the domain message
   `json-parse: unterminated string`, and **swept the tree to match ADR-0025**
   rather than narrowing the rule to match the tree: `util.sld`'s
   `string-index-of` / `string-split` / `string-trim`, `activation.sld`'s
   `fg->exe`, `zellij.sld`'s `basename`, and `web-search.sld`'s two response
   scanners all convert once now. ADR-0025's rule is sharpened to name the
   *loop* as the forbidden shape, and its tripwire is described as the
   diagnostic it is rather than as enforcement.
5. **walk-path-press-cache-k5** — *done*. `(modaliser terminal)` gained
   `call-with-pinned-chain`, a dynamic extent in which the chain is walked
   once and every later read is served from that walk; the leader handler
   wraps a press in it. Scoped to an extent, never a global with
   invalidation, so outside a press nothing is cached and there is no stale
   window. **The second walk turned out to be conditional**: it happens only
   when the landing root carries the derived `.` step-in edge — a
   terminal-like host screen or a mux-backed context tree, which is what a
   herdr press lands on. A press landing on a tree-only context (nvim)
   already walked once. `CONTEXT.md` gains **Pinned chain**.

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

**Corrected by k2's reading**: the ~54 s in that profile was **one** press,
not two. A press pays 26.2 s twice, because `walk-path` is uncached and both
`focused-terminal-path` and `modal-activate!`'s visit snapshot walk the
chain. Reading the profile as "~27 s per press" understated it by half.

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

- ~~The end-to-end press has still never been taken.~~ **Leafed at k8**
  (`observe-the-press-k8`), which is where that reading now lives. k3, k6 and
  k5 all landed with `swift test` green and no installed-app reading, so
  "Done when" bullet 1 — *comes to rest without a perceptible stall* — stays
  argued, not observed, until k8 runs. It is HITL, not AFK-reachable.
- ~~The iTerm host leg is now the biggest single item in a press.~~
  **Promoted** to `docs/how-to/measure-a-leader-press.md`, with the window
  overlay reading below, so the number outlives this tree. Whether the leg is
  worth attacking is still a question for a reading taken after k5 — which
  k8 will produce.
- ~~The ADR-0025 sweep was deliberately not done.~~ **Done at k6.** The
  review's point stood: "cold on one sample" is not "bounded", and a `never`
  carrying known live exceptions is not a rule. The sweep turned out wider than
  the three `util.sld` sites the review named — `activation.sld`, `zellij.sld`
  and `web-search.sld` each carried a loop over an unbounded string too — and
  all of it fit this leaf. What is left under `string-ref` / `string-length` in
  the tree is bounded-literal or constant-count, both legal under the sharpened
  rule. The sweep was for contract, not speed; no benchmark is claimed for it.

- ~~The **window-overlay** symptom.~~ **Promoted** to
  `docs/how-to/measure-a-leader-press.md` alongside the iTerm leg: 133 ms end
  to end, no string past the 4 KB tripwire, not the same cliff, and left
  undiagnosed deliberately because it was never reproduced *as a stall*.
- ~~A second unbounded reach seen in passing.~~ **Promoted** to ADR-0014's
  Consequences as a named live exception: `AppLibrary.resolveApplicationURL`
  (`AppLibrary.swift:284`) spawns `mdfind` and `waitUntilExit`s with no
  timeout, on the Scheme thread via both launch callers (`:104`, `:118`) —
  the shape that ADR exists to prevent. Recorded, not fixed; it is the
  fallback leg and has not been observed to bite.
- ~~Possible ADR once the fix lands: *portable Scheme must not scan strings by
  index*.~~ **Raised at k3 as ADR-0025** and sharpened at k6 to name the loop,
  not the primitive, as the forbidden shape.
