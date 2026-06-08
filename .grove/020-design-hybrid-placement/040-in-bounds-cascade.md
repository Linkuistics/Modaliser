# 040-in-bounds-cascade

**Kind:** work

## Goal
Refine the Stage-B cascade so a *fully-occluded* window's chip is placed
**within that window's own bounds** (over the occluder, still faded)
instead of in free screen space — keeping the chip "aimed at" its window.
Strong invariant (no two chips overlap; every window keeps one chip) is
preserved; in-bounds placement is best-effort with off-window spill.

## Context
- Surfaced by leaf 030 live verification (user feedback). Design approved
  in-session; spill-off-window chosen for the overflow case.
- Authoritative spec to update: `docs/specs/window-chip-placement-design.md`
  §"Stage B" (the slot-lattice cascade) — describe the in-bounds-first
  lattice + screen-lattice spill.
- Only the cascade/demoted pass of `assign-chips` changes. Stage A and the
  partial-occlusion path (Stage-A relocation to a visible fragment) are
  untouched — they already keep chips on-window.

## Design (approved)
- For each cascade/demoted chip, search an **in-bounds lattice** first =
  the window's rect ∩ screen, tiled into chip-sized cells
  (step = chip side + `chip-host-padding`). Take the nearest free cell to
  the window's natural corner, skipping cells overlapping committed chips.
- **Only if no in-bounds cell is free**, fall back to the existing
  screen-covering lattice (the overflow spill). This keeps the existence
  + termination proof intact: the screen lattice is still the backstop.
- Co-located same-app windows share ~one rect ⇒ their in-bounds lattices
  coincide ⇒ chips pack into adjacent cells *inside the cluster* (a local
  faded stack over the occluder), with no explicit cluster object.

## Plumbing
- Extend each `annotated` entry in `paint-and-snapshot!` from
  `(visible? chip nat-x nat-y)` to `(visible? chip nat-x nat-y wx wy ww wh)`
  so `assign-chips` can build the per-window lattice (`wx wy ww wh` already
  in scope there).
- Add a region tiler (window rect ∩ screen) alongside `build-lattice`;
  the window lattice needs no degenerate min-cells guard (it is allowed to
  be small/empty — that is exactly the spill trigger).

## Done when
- A fully-occluded window whose rect can host a free chip-cell gets its
  cascade chip **inside its own bounds** (verified by a unit test asserting
  the placed chip rect ⊆ window rect).
- Small-stacked overflow spills to the screen lattice (unit test: more
  fully-stacked windows than in-bounds cells ⇒ the surplus land off-window,
  still pairwise non-overlapping, all present).
- The 10-fully-stacked invariant test still passes (no-overlap + all
  present). No `chip-resolve-max-attempts`/retry-bail reintroduced.
- `docs/specs/window-chip-placement-design.md` §"Stage B" updated to the
  in-bounds-first lattice + spill.
- `swift test` green.
- Live re-verification post-`install.sh`: chips for occluded windows now
  sit over their own windows; confirm via the `os.Logger` chip-rect dump
  (now persisted at `.notice`) and/or user observation.

## Notes
- ≤10-chip cap (`default-window-labels`) stays central to the tests.
- Honour LispKit constraints (no `set-cdr!`/`set-car!`; return-and-merge).
- Clamp in-bounds cells to on-screen so a window straddling the screen
  edge can't produce an off-screen chip (intersect with screen rect).
