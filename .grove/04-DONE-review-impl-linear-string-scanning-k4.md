# linear-string-scanning-k4

**Reviews:** linear-string-scanning-k3

## Goal

Adversarially read the k3 commit: `(modaliser json)` moved from indexing the
source *string* to indexing a vector converted once up front, and ADR-0025
turned that into a standing rule for `lib/modaliser`.

Inspection only. Do not run builds, tests, formatters or linters, and do not
edit code — findings go to an `integrate-review-impl` leaf you cut yourself.

## Where to look, hardest first

1. **Index equivalence.** The whole change rests on `string->vector` and
   `substring`/`string-ref` agreeing about what an offset *is*.
   `string->vector` walks `asString().utf16` and LispKit characters are
   `UniChar`, so k3's claim is that every offset survives. `parse-escaped-string`
   is where to press: it mixes vector indices with a `vector->string` lift for
   the `\uXXXX` hex digits, and it is the one scanner that conses code units
   individually. `readsCharactersOutsideTheBmp` covers a literal astral
   character, a surrogate-escaped one and a BMP-but-non-ASCII one — ask what
   it does *not* cover. A lone unpaired surrogate is the obvious candidate.

2. **The malformed-input contract.** k3 asserts the bounds checks are
   untouched in force because `vector-ref` past the end raises the same
   unguardable host range error `string-ref` did. Check that claim against
   LispKit's `VectorLibrary`, not against the comment. Every `expect`, every
   `(>= j n)`, and both escape bounds checks should still be present and still
   reachable; the four `raisesGuardablyOnStructurallyMalformedInput` cases and
   the four truncation cases are the pins.

3. **The one remaining `string-ref`.** `parse-lit` still indexes its own
   `word` literal. k3 argues this is bounded (4–5 characters the code owns)
   and documents it as the single expected hit. Confirm the count is exactly
   one and that ADR-0025's "bounded literal the code owns" carve-out is
   stated tightly enough that it cannot be read as a general licence.

4. **`write-json-string`.** Converted too, though k2 measured it cold
   (35 calls, 249 characters). Ask whether that was in scope or scope creep,
   and check the re-indentation did not change any branch — the `cond` moved
   a level deeper inside a new `let*`.

5. **The ADR.** ADR-0025 is new. Judge it against the minimum-coherent-set
   rule: does it overlap ADR-0023 (native reach) or ADR-0014 (never block)
   enough that one of them should absorb it or be reworked? Its "no check
   script" reasoning is the part most likely to be wrong.

6. **What was deliberately left.** `util.sld`'s `string-index-of`,
   `string-contains?` and `string-trim` still carry the old idiom, on the
   argument that k2 measured them cold on the press path. ADR-0025 records
   that as a decision. Test whether "cold on *this* path" generalises — these
   are user-facing stdlib.

## Evidence k3 recorded, to check rather than trust

- Release micro-benchmark, identical harness, identical 97 371-character
  real `pane.process_info` payload: **27 851 ms → 186 ms** (3 runs each,
  ±1 %). The "before" reproduces k2's in-app 26 205 ms, which is what makes
  the harness credible — verify that reasoning holds.
- `swift test`: 1169 tests green. `check-portable-surface.sh` and
  `check-decision-free.sh` both green.
- **Not** verified end-to-end: nobody has installed the fixed app and pressed
  F17. That is deliberate (unreviewed code, and it replaces the user's running
  Modaliser) but it means the root brief's "comes to rest without a
  perceptible stall" is still unmeasured. Say so if you think it should have
  blocked the leaf.

## Cutting the next step

If you find something worth acting on, cut
`integrate-review-impl` with the same stem. **`05-impl-walk-path-press-cache-k5`
sits between this leaf and the parent's end**, so `leaf-add` would drop your
integration *after* it and let it move the lines your findings cite. Use
`leaf-insert` targeting that leaf instead. If you find nothing, cut nothing
and retire.
