# linear-string-scanning-k3

## Goal

Remove the quadratic scanning idiom from the path `k2`'s measurement showed
is hot, so a leader press never holds the keyboard.

**k2 has run. The scope below is a fact now, not a suspicion list.**

## What k2 measured

Instrument: `(modaliser instrument)`, installed release build
(`/Applications/Modaliser.app`, PID 97264), marker file enabled, one F17
press with a herdr pane focused. Read back from the unified log.

**One press, 53.2 s** (18:58:29.932 → 18:59:23.176), and all of it is in one
place:

```
span leader/frontmost-bundle-id        0 ms
span leader/focused-terminal-path 26550 ms   ← walk #1
  walk backend iterm  … 333 ms  (osascript ×2 + ps, 37/13/5 chars out)
  walk backend herdr
    herdr pane.current       wire 1 ms  parse    7 ms   (701 chars)
    herdr pane.process_info  wire 1 ms  parse 26205 ms  (97 360 chars)   ←
span leader/resolve-activation         0 ms
span leader/modal-activate!        26694 ms   ← walk #2, identical
report leader-press
- json-parse  calls 7  total-chars 198702  max-chars 97360
- herdr-reply calls 7  total-chars 198702  max-chars 97360
- write-json-string calls 35  total-chars 249   max-chars 17
- string-index-of   calls 10  total-chars 108   max-chars 21
- string-split      calls  6  total-chars  60   max-chars 21
- string-trim       calls  6  total-chars 110   max-chars 37
- run-shell-output  calls  6  total-chars 110   max-chars 37
- walk-path         calls  2
```

Tripwire, naming the string:

```
big json-parse len 97360 head {"id":"modaliser","result":{"type":"pane_process_info","process_info":{"
```

### The four facts this settles

1. **The hot scanner is `json-parse`, and nothing else is close.** Every
   other counted site is three orders of magnitude smaller — `string-split`
   saw 60 characters *in total*, `string-index-of` 108. The `util.sld`
   scanners are not on this path in any quantity that matters. Fix
   `json-parse`; leave the rest alone unless something else argues for it.

2. **The string is herdr's `pane.process_info` reply: 97 360 characters.**
   Fetched by `detect-fg-command` (`muxes/herdr.sld:469`), which reads
   exactly one field out of it — the `name` of the last entry in
   `foreground_processes`.

3. **It is paid TWICE per press, because `walk-path` is not cached.**
   `walk-path calls 2`: once for the handler's own `focused-terminal-path`,
   once inside `modal-activate!` when the visit snapshot re-probes the
   chain. `walk-path`'s own comment already flags this ("Not cached. Future
   work: memoise per leader press…") — the measurement is what makes it a
   present cost rather than a future note.

4. **Nothing here scales with panes.** The 97 KB is *one process entry* of
   six: a `claude` process whose `cmdline` is 47 227 characters, because
   grove passes its whole mandate as an argv element — duplicated in the
   `argv` array, so ~97 KB of JSON. The other five entries total under
   1 KB. So the requirements session's outstanding question ("does it stall
   at 3 panes, or only with many?") is answered: **pane count is
   irrelevant**. It stalls whenever the focused pane's foreground process
   group contains any process with a large command line. That is also the
   step change nobody could find in the Modaliser history between 07-27 and
   08-13 — there wasn't one. The user started running grove sessions inside
   herdr panes.

### The second symptom: NOT the same bug

The window overlay was measured in the same session (`epoch leader-press` at
19:00:31, global mode so no chain walk):

```
span leader/modal-activate!        4 ms
span show-delayed/on-enter         1 ms
span show-delayed/show-overlay   133 ms
- escape-string calls 197 total-chars 3101 max-chars 2128
- string-join   calls  68 total-chars 1053 max-chars 139
```

**133 ms, no string anywhere near the threshold, no tripwire.** It is not a
scan cliff; `escape-string` is already the O(n) shape. Do **not** absorb it
here. If it still feels slow at a higher window count, `leaf-add` it — and
take a reading first, at that window count.

## Done when

- `json-parse` is O(n): demonstrated by a before/after in a **release**
  build against a payload that reproduced the stall. The reproduction is
  reliable and cheap now — any herdr pane running a `claude`/`grove` session
  gives you a ~100 KB `pane.process_info`, and
  `docs/how-to/measure-a-leader-press.md` is the procedure.
  **Baseline to beat: 26 205 ms for 97 360 chars.**
- `swift test` is green. The JSON reader's fifteen existing cases and the
  four added by `strip-parse-cost-k10` still pass untouched.
- **Correctness is not traded for speed.** Keep every `expect` and both
  escape bounds checks: `string-ref` past the end raises a *host* range
  error, which escapes the `guard` every caller wraps `json-parse` in — the
  one outcome the reader's malformed-input handling exists to prevent.
- `scripts/check-portable-surface.sh` and `scripts/check-decision-free.sh`
  both pass. Nothing under `lib/modaliser` gains a `(lispkit …)` import or a
  `…-native` import.
- A `review-impl` leaf is cut for this work (`leaf-add`, `**Reviews:**
  linear-string-scanning-k3`), and its integration cut adjacent to it.

## The fix, and why one edit is probably not enough

The idiom to remove — the whole of `json-parse`'s scanning surface, 24
`string-ref` sites plus the `(< k (string-length str))` guards:

```scheme
(let loop ((k 0))
  (when (< k (string-length s))   ; Θ(n) — bridges the whole string
    (let* ((c (string-ref s k))   ; Θ(n + k) — bridges it again
```

The shape to reach for is in the tree: `escape-string` (`util.sld:170`)
does one `string->list` and walks the list. `json-parse` needs random access
(it does `substring` lifts and lookahead), so a `list->vector` +
`vector-ref` variant is the closer fit — O(1) indexed access, one bridge
total. Note that the `substring` lifts in `parse-string` become
`list->string` over a vector slice, which is a real rewrite of that
procedure, not a search-and-replace of `string-ref`.

**Extrapolate before you decide you are finished.** Fitting the measured
parse times (452 ch → 2 ms, 1427 ch → 12.5 ms, 97 360 ch → 26 205 ms) to
`a·n + b·n²` puts the *linear* term at roughly 2.4 µs/char. So a perfectly
linear reader still costs **~230 ms** at 97 KB — and ~460 ms per press while
`walk-path` runs twice. That is 100× better and still perceptible.

So expect this leaf to need two of these three, and to be explicit about
which it took:

1. **Make `json-parse` linear.** Necessary; alone it gets ~53 s → ~0.5 s.
2. **Stop walking the chain twice.** `walk-path` memoised per press. Halves
   whatever remains, and the comment in `terminal.sld` already asks for it —
   but "per press" needs an epoch hook the leader layer does not expose yet,
   so check whether that is this leaf or its own.
3. **Stop fetching 97 KB to read one process name.** `detect-fg-command`
   wants one string. If herdr's socket API has a narrower method (or
   `pane.process_info` takes a field/verbosity param), this removes the cost
   rather than dividing it — and it is the only one of the three that also
   helps the wire and the allocator. Check the fork's method list before
   assuming it does not.

Option 3 is a herdr-side question and may not be available; options 1 and 2
are entirely in this tree. **Option 1 is not optional either way** — the
cliff is the tree's, and the next 100 KB payload will not be
`pane.process_info`.

## Notes

- **The instrument is committed and stays.** `(modaliser instrument)`,
  `touch ~/.config/modaliser/instrument` + relaunch, read back with
  `log show`. Procedure in `docs/how-to/measure-a-leader-press.md`, terms in
  `CONTEXT.md` (Press-diagnostics domain). Use it for the before/after
  rather than building a new one; it is inert when the marker is absent and
  `swift test` never enables it.
- **A native seam is the fallback, not the opening move.** If portable
  Scheme reaches O(n), no ADR and no new native library is needed. If
  measurement shows it cannot, that is an architectural change — a
  `(modaliser …-native)` library plus a seam plus an ADR — and it needs a
  design leaf, not an improvised edit. `strip-parse-cost-k10` already
  recorded that LispKit's native substring search sits in a host library
  `lib/modaliser` may not import, and that the SRFI re-export is backed by a
  Scheme KMP loop.
- The `~1 s` of `ShellLibrary.runShellFunction` the original profile showed
  is now fully accounted for and is **not worth chasing**: the iTerm leg of
  the walk costs ~333 ms (two `osascript` calls + one `ps`), paid twice per
  press. It is the second-largest cost in the press and it is 1.2 % of the
  first.
