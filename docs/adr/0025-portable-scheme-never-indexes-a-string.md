# Portable Scheme never scans a string by index

## Status

accepted

## Context

LispKit stores a Scheme string as an `NSMutableString` (`Expr.swift:43`), and
`Expr.asString()` is `res as String` — a **whole-string bridge and allocation**,
paid on entry to every primitive that takes one. Two of those primitives are the
ones every scanner reaches for:

```swift
func stringLength(_ expr: Expr) throws -> Expr {            // StringLibrary.swift:164
  return .fixnum(Int64(try expr.asString().utf16.count))    // Θ(n) — bridges
}
func stringRef(_ expr: Expr, _ index: Expr) throws -> Expr { // StringLibrary.swift:184
  let str = try expr.asString().utf16                        // Θ(n) — bridges again
  let i = str.index(str.startIndex, offsetBy: k)             // Θ(k) — walks
  return .char(str[i])
}
```

So `string-length` is Θ(n) and `string-ref` is Θ(n + k). The ordinary R7RS
scanner —

```scheme
(let loop ((k 0))
  (when (< k (string-length s))
    (let ((c (string-ref s k)))
      …)))
```

— therefore copies the whole payload **twice per character**: ~2n² bytes for one
pass. At 4 KB that is a few milliseconds and invisible. It is a cliff, not a
constant factor, and portable Scheme is where the tree does its scanning.

**It has bitten twice, both times on the same file.** `strip-parse-cost-k10`
rewrote `(modaliser json)`'s cursor discipline for a 1.7 KB paneru payload and
recorded the win in milliseconds — the reader stayed index-based, because at
that size nothing said it mattered. Then `measure-hot-scan-k2` instrumented a
leader press against a live herdr and read the cliff off the log: herdr's
`pane.process_info` reply was **97 360 characters** (one foreground process
carried a 47 KB command line), and `json-parse` spent **26 205 ms** on it —
twice per press, synchronously, on the thread that owns the CGEvent tap. A
leader press held the keyboard for ~53 s. That is ADR-0014's stalled-tap hazard
arriving from inside the portable tree, where ADR-0014's own instrument (a
bounded socket timeout) cannot see it.

The second bite is what makes this a rule rather than a bug report. The cost is
a property of the *host's string representation*, not of JSON: it applies
identically to `string-index-of`, `string-split`, `string-trim`, and to whatever
scanner the next library writes. And nothing about the payload was exotic —
it was a command line.

Two things are **not** the answer here. A native seam is not: ADR-0023
quarantines outward reach behind host-installed runners, and reaching for a
`…-native` library to make a *scan* fast would trade a load-bearing invariant
for a speed problem that portable Scheme can solve. And "keep payloads small" is
not: no caller controls how long someone else's `argv` is.

## Decision

**A library under `lib/modaliser` that scans a string converts it once and then
scans the conversion.** Concretely, one of two shapes, both plain
`(scheme base)`:

- **Sequential scan** — `(string->list s)`, then walk the list.
  `escape-string` (`util.sld:170`) is the in-tree example and predates the rule.
- **Random access** — `(string->vector s)`, then `vector-ref` / `vector-length`,
  and lift substrings back out with `(vector->string v start end)`.
  `json-parse` (`json.sld`) is the in-tree example: it needs lookahead and
  substring lifts, which a list cannot give.

**The forbidden shape is a loop**, and that is the whole of it. What makes the
idiom quadratic is *repeating* an O(n) primitive n times over the same string;
a constant number of indexings is a linear cost like any other, and reading
`(string-ref label 0)` or taking `(string-length path)` once is not a scan. So
the rule reads: **no `string-ref` or `string-length` inside a loop over the
string** — convert first, then loop over the conversion.

That leaves `string-ref` and `string-length` legal in two places. Against a
**bounded literal** the code owns: `parse-lit` comparing four characters
against `"true"`, or `unicode-escape` indexing its own 16-character hex table,
where n is a literal and the cliff has nowhere to grow. And in **constant-count
use** against any string at all: a length test, a first-character check, a
single `substring`.

Indices are interchangeable between the two worlds: `string->vector` walks
`asString().utf16` and LispKit's characters are `UniChar`, so an offset means
the same thing before and after conversion, and a character outside the BMP is
a surrogate pair on both sides. `ModaliserJsonLibraryTests.readsCharactersOutsideTheBmp`
pins that rather than assuming it.

The rule is **portable, not LispKit-specific**, which is why it belongs here and
not in a note about the host. It costs nothing on a host with O(1) string
indexing — one linear conversion in front of a linear scan — and it removes a
quadratic on a host without one. A future Chez or Racket build inherits correct
code either way.

## Considered options

1. **Leave the idiom and fix payloads at the source.** Rejected. It was tried
   implicitly for a year: every scanner in the tree carries a comment about the
   strings it expects to see being short, and the one that stalled was reading a
   process's command line. The size is not ours to bound.

2. **A native scanner behind a seam.** Rejected as the opening move, kept as the
   documented fallback. `strip-parse-cost-k10` already established that
   LispKit's native substring search lives in a host library `lib/modaliser` may
   not import (`check-portable-surface.sh`), and that the SRFI re-exporting the
   name is backed by a Scheme KMP loop — slower than an inline scan. Reaching
   for a `…-native` library would also re-open ADR-0023's quarantine for a
   reason that has nothing to do with outward reach. Measurement says portable
   Scheme gets there: **27 851 ms → 186 ms** on a 97 371-character payload,
   release build, same harness. Only if a future measurement says it cannot does
   a seam become a design question — and then it needs a design leaf, not an
   improvised edit.

3. **A `check-*.sh` script enforcing it.** Not taken *yet*. The two existing
   invariant checks work because they grep for a literal that is always wrong
   (`(lispkit `, `-native)`). `string-ref` is not always wrong — the
   bounded-literal and constant-count cases above are legitimate — so a
   strict-zero grep would fail on correct code, and a grep with exceptions is a
   grep nobody trusts. Catching the real shape means recognising *a loop*, which
   is a parse, not a grep. Revisit if a third bite lands.

   **So there is no enforcement, and review is what stands in for it.** The
   instrument is a *diagnostic*, not a checker, and it is worth being exact
   about how weak a one: `instrument-sample!`'s tripwire logs a site handed a
   string past its threshold, which is how this cliff was found — but it only
   fires at sites whose author called it, only when instrumentation is switched
   on, and only for input someone actually exercised. A new scanner is invisible
   to it by default, and a logged tripwire prevents nothing. What it is good at
   is answering *which* site is carrying the payload once something is already
   slow.

## Consequences

- `(modaliser json)`'s reader and writer both scan a vector. The reader's
  bounds checks are unchanged, but **what they are load-bearing for changed**,
  and the first draft of this record got it wrong. `vector-ref` bounds-checks
  before it indexes and raises a `RuntimeError.range`
  (`VectorLibrary.swift:316`) that the VM hands to Scheme's `raise` — a
  *guardable* error. `string-ref` computed its Swift index before its guard, so
  it trapped in the host and escaped the `guard` every caller wraps
  `json-parse` in. The conversion therefore made the unguardable failure mode
  go away. The checks stay because they answer with the stable domain error
  `json-parse: unterminated string` instead of LispKit's generic range message,
  and `truncationRaisesTheParsersOwnUnterminatedStringError` asserts on that
  message so the checks cannot rot out unnoticed.
- A leader press against a herdr pane running an agent went from ~53 s of held
  keyboard to a parse cost of ~186 ms, paid twice while `walk-path` is uncached.
  The remaining halving is a caching question, not a scanning one, and is
  tracked separately.
- **The tree was swept to match, rather than the rule narrowed to match the
  tree.** A "never" carrying a list of known live exceptions is not a rule, and
  "measured cold on one sample" is not the same as bounded — `string-trim` runs
  on shell-command output all over the terminal backends, and nobody bounds
  that. So the remaining loop-scanners were converted alongside the reader:
  `util.sld`'s `string-index-of`, `string-split` and `string-trim` (with an
  unexported `vector-index-of` so a split pays one conversion, not one per
  separator hit); `activation.sld`'s `fg->exe` and `zellij.sld`'s `basename`,
  both walking process command lines; and `web-search.sld`'s two response
  scanners. What is left in the tree under `string-ref` / `string-length` is
  bounded-literal or constant-count, both legal above.
- Reviewing a new scanner is now a one-line question with a one-line answer:
  *where does this string's length come from?* If the answer is "outside",
  convert first.
