# 020-design-hybrid-placement — brief

## Goal
Implement the hybrid chip-placement strategy designed in
`docs/specs/window-chip-placement-design.md` so the **strong invariant**
holds for same-app overlap: no two chips overlap, and every window keeps
exactly one chip.

## Done when
- Stage A collects same-app front windows as occluders (per ADR-0009),
  identifying the target by `wid`-then-rect.
- Stage B enforces the cross-chip no-overlap invariant for all chips and
  places no-usable-area chips into the lattice cascade — no `max-attempts`
  bail remains.
- Unit tests assert the invariant for the worst case (10 same-app windows
  fully stacked) and the original two-iTerm symptom.
- The live iTerm/Dia symptom is reproduced post-`install.sh` and shows all
  chips distinct and aimable (leaf 030).

## Decomposition
Sequenced by data flow: fix the occluder *input* first (Stage A), then the
all-chips *guarantee* that consumes it (Stage B), then verify live.

- `010` — Stage A: same-app occluder collection fix (Cause 1, ADR-0009).
- `020` — Stage B: cross-chip invariant + lattice cascade (Cause 2 +
  termination), replacing the bail-prone dodge.
- `030` — live reproduction + verification of the strong invariant.
  **Outcome: invariant CONFIRMED fixed live** (user-observed + tests).
  Surfaced a placement-quality follow-up → `040`.
- `040` — in-bounds cascade: a fully-occluded window's cascade chip stays
  within its own bounds (over the occluder, faded) rather than off-window,
  with screen-lattice spill on overflow. Strong invariant preserved.

## Pointers
- ADRs: `docs/adr/0009-same-app-windows-count-as-occluders.md`.
- Design spec: `docs/specs/window-chip-placement-design.md` (authoritative).
- Glossary: Window chip, Same-app overlap, Chip placement, Chip cascade,
  Slot lattice, Strong invariant (see `CONTEXT.md`).
- Key files: `Sources/Modaliser/WindowLibrary.swift`
  (`collectOccluderRects`, `findChipPositionFunction`),
  `Sources/Modaliser/ChipPlacement.swift`,
  `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld`
  (`paint-and-snapshot!`, `resolve-chips-with-visibility`),
  `Tests/ModaliserTests/SameAppChipCollisionTests.swift`.

## Notes
- ≤10 chips total (`default-window-labels`) is load-bearing for the
  termination/no-overlap proof — keep tests at that worst case.
- Build/run: source changes need `./scripts/install.sh` ("Relaunch" only
  restarts the stale bundle). Diagnostics via `os.Logger`, not `NSLog`.
- Deferred question (telling apart relocated same-app chips) is **punted**
  — row list + raise-on-select suffices; see the spec. Revisit only if 030
  shows the row list is insufficient.
