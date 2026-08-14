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

`string-ref` and `string-length` remain legal against a **bounded literal** the
code owns — `parse-lit` comparing four characters against `"true"` is not a
scan. What is forbidden is indexing a string whose length comes from outside.

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
   (`(lispkit `, `-native)`). `string-ref` is not always wrong — the bounded-literal
   case above is legitimate — so a strict-zero grep would fail on correct code,
   and a grep with exceptions is a grep nobody trusts. The instrument is the
   enforcement that exists: `instrument-sample!`'s tripwire logs any site handed
   a string past its threshold, which is how this was found. Revisit if a third
   bite lands.

## Consequences

- `(modaliser json)`'s reader and writer both scan a vector. The reader's
  bounds checks are unchanged and still load-bearing: `vector-ref` past the end
  raises a **host** range error exactly as `string-ref` did, and that is not the
  guardable kind — it escapes the `guard` every caller wraps `json-parse` in.
  Speed changed; the malformed-input contract did not.
- A leader press against a herdr pane running an agent went from ~53 s of held
  keyboard to a parse cost of ~186 ms, paid twice while `walk-path` is uncached.
  The remaining halving is a caching question, not a scanning one, and is
  tracked separately.
- `util.sld`'s `string-index-of`, `string-contains?` and `string-trim` still
  carry the old idiom. `measure-hot-scan-k2` measured them **cold** on the press
  path — 108, 0 and 110 characters *in total* — so they were left alone
  deliberately rather than swept. They are the obvious next site if the
  tripwire ever names one.
- Reviewing a new scanner is now a one-line question with a one-line answer:
  *where does this string's length come from?* If the answer is "outside",
  convert first.
