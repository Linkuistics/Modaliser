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

## What this session did, and what it decided

**Option 1 only, and it was enough to take the cliff out.** Of the three
levers the brief listed, this leaf took the first and cut the second as its
own leaf (`walk-path-press-cache-k5`); the third is unavailable.

### 1 — `json-parse` is linear

The fix is one conversion, not a rewrite. LispKit's `substring` takes
`asMutableStr()` (an NSRange lift, no bridge) and `string->vector` /
`vector->string` bridge exactly once — only `string-ref` and `string-length`
bridge *per call*. So the cliff is specific to per-character **string**
indexing, and `(string->vector str)` at the top of `json-parse` buys O(1)
`vector-ref` for the whole scan without touching the reader's cursor
discipline, its `expect` grammar points, or either escape bounds check.
Literal lifts moved from `substring str k j` to `vector->string chars k j`
so the source string is never indexed again after the conversion.

`write-json-string` got the same treatment. k2 measured it cold (35 calls,
249 characters), so this is not the fix that mattered — it is the same cliff
removed while it is still three lines, on the reasoning that the writer's
inputs are whatever a caller puts in a request and nothing bounds them.

One `string-ref` survives, in `parse-lit`, indexing its own 4–5 character
`"true"` / `"false"` / `"null"` constant. Bounded literal, no cliff to grow;
documented as the single expected hit so the grep stays a usable check.

**Measurement** — release build, real 97 371-character `pane.process_info`
captured from a live herdr pane running a grove session, identical throwaway
harness on both sides (warm-up parse then three timed), same extracted value
(`"grove"`) both sides:

| | parse of 97 371 chars |
|---|---|
| before | 27 851 / 27 956 / 27 542 ms |
| after | 186 / 188 / 185 ms |

**150×.** The "before" reproduces k2's in-app 26 205 ms for 97 360 chars,
which is what makes the harness like-for-like rather than a second opinion.
(The harness needed a 64 MB thread stack: a deep parse overflows a
cooperative-pool thread's default. Same both sides, so it does not affect the
comparison — but it is why the bench was not simply a `@Test` body.)

**Correctness.** `swift test` 1169 green, both invariant checks green. The
one place the change could have shifted behaviour rather than speed is
character representation, so that is now checked rather than argued:
`readsCharactersOutsideTheBmp` pins a literal astral character, the same
character as two `\uXXXX` surrogate escapes, and a BMP-non-ASCII string,
each through parse and through a parse→write→parse round trip. Both worlds
work in UTF-16 code units, so every offset means what it did.

### 2 — the walk-path memo went to its own leaf

The brief asked this leaf to check whether that was its work. It is not:
it is a caching question with a lifetime contract, touching two libraries
and the leader handler, where this leaf's concern was a scanning idiom in
one file. Cut as `05-impl-walk-path-press-cache-k5`, with the post-k3 press
budget written into it — that budget is what makes the memo worth doing now
and was rounding error before.

### 3 — no narrower herdr method exists

Checked the fork's source rather than assuming (`~/Development/herdr`,
`src/api/schema.rs`, `src/app/api/panes.rs`). `pane.process_info` takes only
an optional `pane_id`; `PaneProcessInfoParams` has no field or verbosity
selector, and the handler always builds the full `argv` + `cmdline` for every
process in the group. There is no narrower read to switch to. Making one is a
herdr-side change in another repo — out of scope here, and no longer needed
at this cost.

### ADR-0025 was raised

The root brief made this conditional: raise it "only if the fix proves it is
a standing rule rather than a one-off". It does. The cost is a property of
the host's *string representation*, not of JSON, so it applies to every
scanner in the tree; it has now bitten twice in the same file; and the fix is
portable rather than LispKit-specific, so writing it down costs a future host
nothing. ADR-0025 states it, `portability.md` gains it as a fourth semantic
constraint, `CONTEXT.md` gains **Converted scan** beside the existing **Scan
cliff**, and `measure-a-leader-press.md` now says what its worked example is
a reading *of*.

### Two things deliberately not done

- **No end-to-end press measurement.** The leaf's own Done-when is a
  before/after in a release build against a payload that reproduced the
  stall, and that is met. Installing the fixed app to `/Applications` would
  put unreviewed code on the user's machine, replace their running Modaliser
  mid-session, and needs a focus-stealing F17 press. That belongs after the
  review chain, and the root brief's "comes to rest without a perceptible
  stall" stays open until it happens.
- **No integrate step cut.** The leaf's Done-when asked for the review's
  integration to be cut here too. Grove's methodology says the review cuts
  its own integration — created late, so it can carry the actual findings —
  so only `04-review-impl-linear-string-scanning-k4` was cut, and it carries
  the `leaf-insert` instruction it needs to land adjacent.

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
