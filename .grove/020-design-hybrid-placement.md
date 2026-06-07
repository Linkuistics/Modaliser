# 020-design-hybrid-placement

**Kind:** planning

## Goal
Design the **hybrid chip-placement** strategy that satisfies the strong
invariant (no chip overlap; every window keeps a chip), then grow the
implementation sub-tree. Deliverable is *more tree*, not the fix itself.

## Context
- Reads the confirmed cause from leaf 010 — design against verified fault.
- Hybrid target (agreed during root grilling):
  - Use real on-window placement (nearest-free-space dodge) whenever a window
    has enough visible area for a readable chip.
  - Fall back to a **cascade stack** (z-ordered legend anchored at the cluster)
    only for windows with no usable visible area.

## Done when
- A design exists (inline here, or a `docs/specs/*-design.md` if it earns it)
  covering: the visible-area threshold that switches a window from dodge to
  cascade; the cascade anchor + ordering (z-order vs. spatial); a **termination
  guarantee** for placement; and how the two existing stages (Swift geometric,
  Scheme dodge) are changed or which one owns the new logic.
- The deferred open question is resolved or explicitly punted: how the user
  tells apart relocated chips of visually-indistinguishable same-app windows.
- An ADR is raised **only if** the placement approach is hard to reverse,
  surprising, or a genuine trade-off (else skip it).
- The leaf is replaced by a `020-design-hybrid-placement/` node: a `BRIEF.md`
  plus ordered implementation (and verification) leaves.

## Notes
- Grill before designing (`grilling.md`); update CONTEXT.md inline as terms
  harden.
- Keep the invariant primary: any proposed algorithm must be checkable against
  "no two chips overlap" and "every window keeps one chip" for the worst case
  (N same-app windows fully stacked).
