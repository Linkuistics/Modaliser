# strip-parse-cost-k10

**Kind:** impl

## Goal

Make reading paneru's state payload cheap enough that `'next 'self` is a
defensible default on the repeatable ops — or establish that it cannot be, and
close the question.

## Context

Surfaced by measurement in `paneru-strip-list-k7`, which had the obligation to
measure the come-to-rest cost and rule on `'next 'self`. It measured **≈66 ms**
on an 11-window strip and ruled `'next 'self` out of the reference composition.
The full table is in `docs/specs/paneru-window-management.md` decision 4; the
one number that matters here:

> **`parse-strip-windows`: 36 ms of the 66** — the `(modaliser json)` read over
> a 1689-byte payload, in interpreted Scheme, ~21 µs per character.

Decision 4 had predicted the subprocess spawn and the AX sweep would dominate
and named two levers accordingly (`list-windows` instead of the current-space
sweep; dropping `'next 'self`). Both levers are real and neither touches the
dominant term. Worse, the parse scales **linearly with strip length** — a
20-window strip roughly doubles it — so the cost grows with exactly the thing
the listing exists for.

What is already ruled out, so nobody re-measures it:

- **A smaller payload from paneru.** `paneru query state` emits the same JSON
  with or without `--json` (the flag is a no-op on the live daemon), and the
  narrower subcommands — `query virtual-workspaces`, `query active` — do not
  carry less per-window data.
- **A host JSON primitive.** `lib/modaliser` may not import a host library
  (portability contract, `docs/reference/portability.md`), and `(modaliser
  json)` is portable by construction.

So the room is inside the reader, or in not building a full parse tree at all.
Two shapes worth weighing, neither yet chosen:

1. **Make `(modaliser json)` faster.** It is character-at-a-time over a Scheme
   string with a mutable cursor, consing a list per string literal. It has one
   other consumer (`muxes/herdr-socket`), which would benefit equally.
2. **Extract without parsing.** The listing needs six fields per window from one
   array. A scanner that walks to the active workspace and pulls fields directly
   would skip building the tree — at the cost of a second, weaker reader beside
   the real one, which is a genuine argument against it.

## Done when

- The come-to-rest cost is re-measured the same way (method recorded in the
  spec's decision 4) and the new number recorded beside the old.
- Either `'next 'self` is restored to the reference composition with the cost
  that justifies it, or the spec records why the read cannot be made cheap and
  the ruling stands unchanged.
- If `(modaliser json)` changed, `ModaliserJsonLibraryTests` still passes
  unchanged — the reader's behaviour is contract, including its guardable
  raises on malformed input.
- Both check scripts pass; `swift test` green and still fully offline.

## Notes

Sequenced **ahead of `paneru-docs-k8`** deliberately: the reference docs and the
example config both state the `'next 'self` ruling, so settling it first saves
rewriting them.

Do not treat a faster reader as automatically worth it. 66 ms → 30 ms is still
not free, and the honest outcome may be that `'next 'self` stays out and this
leaf closes having established that. Recording *that* is a result.
