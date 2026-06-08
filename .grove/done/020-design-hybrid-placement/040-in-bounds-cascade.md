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

## Verification outcome (2026-06-08 — CONFIRMED, "works perfectly")

In-bounds cascade placement verified live post-`install.sh`; user
confirmed occluded-window chips sit over their own windows and no two
chips touch ("That works perfectly").

A first live pass surfaced a **touching-chips** defect: the in-bounds
lattice was anchored at the window's raw origin (a half-cell off the
natural-corner grid the chips use), and the free-cell test only checked
overlap, so a cascade cell could sit flush against the front chip.
Fixed by (1) anchoring the in-bounds lattice at the natural chip corner
and (2) a clearance free-cell test (chip inflated by `chipHostPadding`)
so chips keep a full padding gap, not merely avoid overlap.

**Hard evidence** — `os.Logger` chip-rect dump (subsystem
`dev.antony.Modaliser`, category `chip-placement`), real overlay runs:
- `4 chips, NO overlaps — 1@(112,43) 2@(12,43) 3@(1718,43) 4@(1818,43)`
  → within each cluster the gap is exactly one padding (112−(12+88)=12;
  1818−(1718+88)=12).
- `3 chips, NO overlaps — 1@(12,43) 2@(1719,43) 3@(1718,143)`
  → 143−(43+88)=12.
- Every dump line reads "NO overlaps" (the `.error` self-check for an
  overlap never fired). Pre-fix runs flung a cascade chip to `(3424,43)`
  off across the second monitor — the off-window behaviour this leaf
  removed.

Unit tests (real Scheme `assign-chips` via `SchemeEngine`): the in-bounds,
padding, and overflow-spill guards plus the unchanged invariant — full
suite green (564 tests).
