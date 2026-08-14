# linear-string-scanning-k6

**Integrates:** linear-string-scanning-k4

## Goal

Apply the actionable findings from the `linear-string-scanning-k4`
inspection of producer `linear-string-scanning-k3`. Keep the vector scan and
its measured performance win; repair the contract, evidence, and remaining
known violations around it.

## Context

Producer change: `luwlmnrmnzrm` / `5c73437be8f6`.

### Finding 1 — the malformed-input rationale and test pin are false after conversion

`Sources/Modaliser/Scheme/lib/modaliser/json.sld:254`,
`Tests/ModaliserTests/ModaliserJsonLibraryTests.swift:195`, and
`docs/adr/0025-portable-scheme-never-indexes-a-string.md:122` all say an
out-of-range `vector-ref` raises the same unguardable host failure as the old
`string-ref`.

It does not. LispKit's `VectorLibrary.vectorRef` checks `i` before indexing and
throws `RuntimeError.range`
(`.build/checkouts/swift-lispkit/Sources/LispKit/Primitives/VectorLibrary.swift:316`).
The VM catches `RuntimeError` and applies Scheme's `raise` procedure
(`.build/checkouts/swift-lispkit/Sources/LispKit/Runtime/VirtualMachine.swift:229`),
so a Scheme `guard` can catch it. The old `StringLibrary.stringRef` computes
the Swift index before its guard, which is why its out-of-range failure had a
different, unguardable shape.

This also means the last two cases in
`raisesGuardablyOnStructurallyMalformedInput` no longer prove the explicit
escape bounds checks are present: deleting a check can fall into `vector-ref`
and still satisfy the test's only assertion, "some guardable error occurred."

Choose and record the real contract. Recommended: retain the parser's explicit
bounds checks because they produce the stable domain error
`json-parse: unterminated string`, revise the false host-error rationale, and
make the truncation tests distinguish that domain error from LispKit's generic
range error (for example through `error-object-message`). Reconcile the root
brief's matching Done-when wording too.

### Finding 2 — ADR-0025 declares an invariant while preserving known violations

ADR-0025's decision (`:65-78`) and `docs/reference/portability.md:135` say
portable library code never indexes an externally sized string. But the ADR's
own consequences (`:131-135`) deliberately retain exactly that shape in
`util.sld`:

- `string-index-of` indexes arbitrary `haystack` and `needle` values
  (`Sources/Modaliser/Scheme/lib/modaliser/util.sld:128-148`);
- `string-trim` indexes arbitrary `str` values (`:171-183`);
- `string-split` reaches the former and is exported with both.

"Cold on this leader-press sample" does not make those strings bounded.
`string-trim` alone is used throughout terminal backends on shell-command
output, so these are user-facing, externally sized inputs. The implementation
therefore contradicts the new current-state ADR on the same commit that raises
it.

Recommended: convert these known scanners in this integration so the tree
actually satisfies the rule, preserving their indices/substrings against one
converted representation and adding focused behavior tests. If that work proves
too large for this focused leaf, narrow the ADR honestly and externalize the
sweep as a producer/review chain; do not keep "never" plus a list of known live
exceptions justified only by one cold path.

The same section overstates the tripwire as "the enforcement that exists"
(`ADR-0025:111-118`). Instrumentation is opt-in and site-local; a future scanner
is invisible unless its author adds `instrument-sample!`, and no tripwire
prevents a violation. Describe it as a diagnostic, with review as the current
enforcement, unless a real checker is added.

### Finding 3 — the advertised grep count is not literal

`json.sld:83-84` says grepping `json-parse` for `string-ref` finds exactly one
site. It finds two occurrences, both in `parse-lit` (`:173` and `:177`). Both
are safe under the bounded-owned-literal carve-out; this is not a behavior bug.
Change the checkable claim to "only in `parse-lit`" or otherwise make its count
match what the stated grep returns. `unicode-escape` has two additional safe
bounded-literal occurrences outside `json-parse` (`:423-424`).

## Done when

- The `vector-ref` error-path rationale matches LispKit's implementation, and
  the malformed-input tests genuinely pin whichever parser error contract is
  retained.
- The root brief, ADR-0025, JSON comments, and test comments agree about why
  the escape bounds checks remain.
- ADR-0025 and the live utility scanners no longer contradict each other;
  instrumentation is described as diagnostic rather than automatic
  enforcement unless enforcement is actually added.
- The `json-parse` grep claim is mechanically true.
- Post-fix `swift test`, `scripts/check-portable-surface.sh`, and
  `scripts/check-decision-free.sh` are green. Review the existing k3 release
  benchmark as the performance evidence; rerun it only if the JSON conversion
  itself changes.

## Notes

No finding on the core conversion: old `string-ref` and new
`string->vector` both read `asString().utf16`, and `vector->string` rebuilds
from those same `UniChar` code units. The literal astral, escaped surrogate
pair, and BMP-non-ASCII tests cover the behavior boundary that changed. A lone
escaped surrogate is not a conversion-specific gap: `parse-escaped-string`
still finishes through the same `list->string` path it used before.

No finding on `write-json-string`: the diff adds one conversion/length binding
around an otherwise branch-identical loop, and arbitrary request strings make
the writer a legitimate instance of the same rule despite its cold k2 sample.

ADR-0025 earns its own record rather than being merged into ADR-0014 or
ADR-0023: it governs an in-process data-structure choice; those records govern
blocking action semantics and native outward reach. The recorded release
benchmark is credible because its before side reproduces the in-app reading on
the same-sized payload and both sides used the same release harness. The missing
installed-app F17 check should not have blocked k3; it remains a root-grove
Done-when and is sensibly deferred until reviewed code is ready to install.
