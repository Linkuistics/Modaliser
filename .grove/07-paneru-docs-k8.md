# paneru-docs-k8

**Kind:** impl

## Goal

Make the paneru surface documented and copyable: `docs/reference/` updates plus
a complete `examples/paneru.scm` a user can crib from.

## Context

`docs/` is the source of truth for behaviour (CLAUDE.md), and
`docs/reference/libraries.md` is ground-truthed against the `.sld` sources — so
it must describe the ops and the listing exactly as `wms/paneru.sld` exports
them, not as the spec proposed them. Reconcile against the code, not the design.

`Sources/Modaliser/Scheme/examples/*.scm` are complete, never-loaded reference
configs for setups a fresh install does not seed — exactly what a paneru screen
is. They are load-tested by `ConfigDslTests.exampleConfigsLoadWithoutErrors`, so
a broken example is a red suite rather than silent rot.

The example is where the **user-authored** half lives, and it is load-bearing
for ADR-0021: the keys, the labels, and the jump alphabet all appear here and
nowhere under `lib/modaliser`. It should show the load-time branch — paneru
screen when installed, the existing layout screen when not — because that
composition is the thing a reader most needs to see written out.

## Done when

- `examples/paneru.scm` exists, is complete, and passes the example load test.
- It shows the seven ops on keys, the strip listing with its alphabet, and the
  installed/not-installed branch.
- `docs/reference/libraries.md` documents `(modaliser wms paneru)` against the
  shipped exports.
- `docs/reference/portability.md` mentions `wms/` if it enumerates the tree's
  categories.
- The **plane rule** is stated where a user will meet it: provider edges and
  static edges share one key space and static edges match first, so any letter
  bound to an op is silently unreachable as a jump label. The library cannot
  enforce it, so the docs carrying it is the whole mitigation (spec decision 5).
- The measured come-to-rest cost is recorded, so a user choosing `'next 'self`
  knows what it costs — **≈34 ms**, and the reason the reference composition
  still omits it (spec decision 4, as rewritten by `strip-parse-cost-k10`).
  Take the numbers from the spec as it stands now, **not** from
  `paneru-strip-list-k7`: that leaf's ≈66 ms table was measured in a debug
  build and its attribution of the cost to the JSON read no longer holds.
- The **Paneru-window-management domain** in `CONTEXT.md` still matches what
  shipped — correct any term the implementation moved.

## Notes

Last leaf before the grove finishes. When retiring it, check the root brief's
`Done when` in full, and reconcile the ADR set: ADR-0024 was written during
`plan-k1` from empirical evidence, so confirm the implementation did not
invalidate any part of it — if it did, rework 0024 **in place** rather than
appending a superseding ADR.
