# Window-chip placement — hybrid design

Status: design (grove `window-chips-overlap-same-app-windows`, leaf 020).
Implemented by the leaves under `.grove/020-design-hybrid-placement/`.

## Problem

Window chips must satisfy the **strong invariant** (see `CONTEXT.md`):

1. **No two chips overlap.**
2. **Every listed window keeps exactly one chip** — a fully-occluded
   window is relocated, never dropped.

Today neither holds for **same-app overlap**. The verified cause (leaf
010, and `Tests/ModaliserTests/SameAppChipCollisionTests.swift`) has two
parts:

- **Cause 1 — occluder blindness.** `collectOccluderRects` stops at the
  first same-PID window, so a same-app back window gets `occluders=[]`,
  is judged unoccluded, and keeps its natural top-left — the same corner
  the front window's chip uses.
- **Cause 2 — no visible↔visible dodge.** Because its occluders are
  `[]`, the back window is classified *visible*; the Scheme dodge
  `resolve-occluded-against-visible` only relocates *occluded* chips, so
  two visible chips are never de-collided against each other.

A third latent gap: even the dodge that does run can **bail** after
`chip-resolve-max-attempts` (64) and leave a chip overlapping — so there
is currently no invariant, only best-effort.

## The ≤10-chip lever

`default-window-labels` is `"1".."0"` — **at most 10 chips ever exist.**
The brief's worst case ("N same-app windows fully stacked") is N ≤ 10.
This turns the no-overlap guarantee into a *counting* argument: any
screen-covering lattice of chip-sized cells has far more than 10 cells,
so a free, non-overlapping slot always exists. The design leans on this
throughout.

## Two stages, two responsibilities

The pipeline stays two-stage, because the stages can see different
things:

| Stage | File | Sees | Owns |
|---|---|---|---|
| A — geometric, per-window | `ChipPlacement.swift`, `WindowLibrary.collectOccluderRects` | one window + its occluders | correct occlusion; on-window position or "no usable area" |
| B — reactive, all chips | `window-list.sld` (`paint-and-snapshot!`) | every chip together | the cross-chip invariant + the cascade |

Stage A is structurally blind to other chips' final positions
(`find-chip-position` is one window at a time). Therefore **the
"no two chips overlap" invariant must be enforced in Stage B** — the
only place that holds all chips at once. Stage A's job shrinks to
"correct per-window placement + an honest visible/no-area verdict."

## Stage A — correct occlusion (Cause 1)

Fix `collectOccluderRects` per **ADR-0009**: stop the front-to-back walk
only at the *actual target* (matched by `wid`, else by rect against the
target's known bounds), collecting same-app front windows as occluders
like any other. Pass the target rect through `findChipPositionFunction`
so rect-matching is possible.

Outcome per window, unchanged in shape — `ChipPlacement.chipPosition`
returns either:

- a **position** (natural corner, or relocated to the top-left-most
  clear fragment) → the window has usable visible area → *on-window
  chip*; or
- **nil** → no chip-sized clear fragment exists → *cascade candidate*.

### Dodge→cascade threshold

The switch is the **existing implicit threshold**: a window goes to
cascade exactly when `ChipPlacement.chipPosition` returns nil — i.e. no
fragment of size `chip + 2·padding` survives occluder subtraction. No
new tunable is introduced; this reuses logic already characterised by
leaf 010's tests.

## Stage B — invariant + cascade (Cause 2, termination)

`paint-and-snapshot!` replaces `resolve-chips-with-visibility` /
`resolve-occluded-against-visible` with a single assignment pass over
**all** chips that guarantees the strong invariant.

### The slot lattice

Define a lattice of chip-sized cells tiling the screen:
`step = chipSide + chipHostPadding`; cell `(i,j)` has origin
`(i·step, j·step)` clamped on-screen. The lattice covers the screen, so
it has `⌊sw/step⌋ · ⌊sh/step⌋` cells — for any normal display (e.g.
1280×800, step ≈ 100) that is ~96 cells ≫ 10.

### Assignment

Process chips in a fixed priority order (label order — stable and
user-meaningful):

1. **On-window chips first.** Commit each chip at its Stage-A position
   **iff** it does not overlap any already-committed chip. If it
   collides, demote it to the cascade pool (it will get a lattice slot).
2. **Cascade chips** (Stage-A nil) **and demoted chips**: assign each
   the **nearest free slot to its own window's natural corner**,
   measured by cell-centre distance, skipping cells that overlap any
   committed chip. The slot is sought **in two tiers**:
   1. an **in-bounds lattice** — chip-sized cells tiling the window's
      own rect (∩ screen), anchored at the *window's* origin so cells
      align to the window. Preferring these keeps a cascaded chip
      **over its own window** (drawn on the occluder, still faded),
      instead of flung to empty screen space.
   2. only if no in-bounds cell is free, the **screen-covering lattice**
      of §"The slot lattice" — the overflow spill.
   Commit it at the chosen cell.

Searching the window's own rect first realises the approved
**lattice-at-the-cluster** anchor directly: several same-app windows
share ~one rect, so their in-bounds lattices coincide and their cascade
chips fill adjacent cells *inside the cluster*, reading as a local stack
over the occluding window — with no explicit cluster detection. The
screen lattice remains as the spill tier for the rare case where a small
window is more deeply stacked than its own bounds can host
non-overlapping chips.

Occluded chips still receive the *faded* background (as today) so a
relocated/cascaded chip is visually distinct from an on-window one.

### Why the invariant holds (proof sketch)

- *No overlap.* Every committed chip is either an on-window chip checked
  clear of all prior commits, or a lattice slot checked clear of all
  prior commits — whether that slot came from the in-bounds tier or the
  screen tier, it is rejected unless disjoint from every committed chip.
  Inductively, the committed set is pairwise non-overlapping. ∎
- *A slot always exists.* The in-bounds tier may legitimately be empty;
  that is why it falls through to the screen tier, which is the tier the
  existence argument rests on. At most 10 chips commit. An on-window chip
  (size ≈ one cell) overlaps at most a 2×2 block = 4 cells. So ≤10
  commits block ≤40 cells; with ~96 cells, ≥56 remain free — strictly
  more than the ≤10 chips needing slots. So the screen tier never runs
  out, and step 2 always places. ∎
- *Termination.* Both steps are a single bounded loop over ≤10 chips;
  step 2's "nearest free slot" scans two finite lattices (in-bounds then
  screen). No retry loop, no bail. ∎

This removes the old `chip-resolve-max-attempts` bail entirely: the
guarantee is structural, not iteration-bounded.

### Degenerate guard

If a pathological tiny screen yields fewer than 10 lattice cells, fall
back to shrinking `step` toward `chipSide` (drop inter-chip padding
before chip size) so ≥10 cells exist; chips may then touch edges but
still not overlap (overlap uses strict inequality). This case cannot
arise on any supported display and exists only to keep the proof total.

## Deferred open question — punted

*How does the user tell apart relocated chips of visually
indistinguishable same-app windows?* **Punted by decision (020
grilling).** The overlay already renders a row list of `label + app +
title`, and typing a digit raises the target window, so trial-and-error
is cheap. No leader lines or tints are added. Revisit only if the row
list proves insufficient in live verification (leaf 030).

## Verification

Leaf 030 reproduces the original iTerm/Dia symptom live (two iTerm
windows, two Dia windows, overlapped) after `./scripts/install.sh`, and
confirms all chips are distinct and aimable. The pure placement logic of
both stages is unit-tested (extending `SameAppChipCollisionTests`) so
the invariant is checked against the worst case (10 same-app windows
fully stacked) without needing a live screen.
