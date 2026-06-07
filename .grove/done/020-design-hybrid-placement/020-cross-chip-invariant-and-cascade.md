# 020-cross-chip-invariant-and-cascade

**Kind:** work

## Goal
Make Stage B enforce the strong invariant for *all* chips and place
no-usable-area chips into the lattice cascade — removing the bail-prone
dodge. This fixes Cause 2 and gives the termination + no-overlap guarantee.

## Context
- Authoritative: `docs/specs/window-chip-placement-design.md` §"Stage B"
  (slot lattice, assignment, proof, degenerate guard).
- Replace in `window-list.sld`: `resolve-chips-with-visibility` and
  `resolve-occluded-against-visible` (the latter has the
  `chip-resolve-max-attempts` bail). `paint-and-snapshot!` calls the new
  assignment; it already has each window's natural corner (`wx,wy`) and the
  visible/occluded verdict (`car` of each `annotated` pair).
- Depends on leaf 010: a fully-occluded window now arrives as
  `chipPosition == nil` → occluded/faded → cascade candidate.

## Done when
- A single assignment pass over all chips, in label order:
  1. on-window chips (Stage-A position) committed iff clear of all
     prior commits, else demoted to the cascade pool;
  2. cascade + demoted chips assigned the nearest free **slot-lattice**
     cell to their own window's natural corner.
- No `chip-resolve-max-attempts` / retry-bail remains; placement is a
  bounded, total function.
- Occluded chips keep the faded background (as today).
- Pure placement logic is unit-tested for the worst case from the spec:
  **10 same-app windows fully stacked** → 10 chips, all pairwise
  non-overlapping, all present. Also the two-iTerm symptom → distinct,
  non-overlapping chips. Reuse/extend `SameAppChipCollisionTests`.
- `swift test` green (Scheme placement verified via its test harness or a
  mirrored Swift helper, whichever the repo already uses for this stage).

## Notes
- Keep the ≤10-chip cap (`default-window-labels`) central to the tests —
  it is the basis of the no-overlap proof.
- Anchor each cascade chip's slot search at *its own* window corner; do not
  build an explicit "cluster" object (the spec explains why co-located
  windows self-cluster).
- Honour LispKit constraints (no `set-cdr!`/`set-car!`; return-and-merge) —
  see memory notes; the existing helpers already follow this.
