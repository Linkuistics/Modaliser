# window-chips-overlap-same-app-windows — brief

## Goal
Make **window chips** readable and selectable when multiple windows of the
*same app* overlap on screen. Today their digit chips land on top of each
other (seen with iTerm and Dia), making window-by-digit switching unusable
for that cluster.

## Done when
The **strong invariant** holds for any arrangement of on-screen windows,
including several same-app windows stacked or fully occluding each other:

1. **No two window chips ever overlap.** Label readability wins; a chip may
   leave its window's natural corner to honor this.
2. **Every listed window keeps exactly one chip.** A fully-occluded window
   does not lose its chip — it is placed in free space so it stays selectable.

Verified by reproducing the original iTerm/Dia symptom and seeing all chips
distinct and aimable.

## Decomposition
Verify-first, then design. Implementation leaves are grown by 020, not
guessed now (`don't over-plan`).

- `010` — reproduce the same-app overlap and **confirm the real cause**. The
  same-PID occluder-shortcut is a *hypothesis* from code reading, not yet a
  verified fact; 010 settles it before any fix is designed.
- `020` — *planning*: design the **hybrid chip-placement** strategy (on-window
  dodge where a window has visible area; cascade fallback for the heavily/
  fully-occluded), prove termination + the no-overlap invariant, then grow the
  implementation sub-tree.

## Pointers
- Glossary terms in play: Window chip, Same-app overlap, Chip placement,
  and the pane **Chip** they share machinery with (see CONTEXT.md,
  "Window-switching domain").
- Key files (from a code map; treat line-level claims as unverified until 010):
  - `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld` — labelling,
    visibility annotation, Scheme-side dodge.
  - `Sources/Modaliser/WindowLibrary.swift` — `list-current-space-windows`,
    `find-chip-position`, occluder collection.
  - `Sources/Modaliser/ChipPlacement.swift` — geometric rect-subtraction stage.
  - `Sources/Modaliser/WindowCache.swift` — AX window enumeration + spatial sort.
  - `Sources/Modaliser/HintsLibrary.swift` — the shared `hints-show` overlay.
  - `Sources/Modaliser/Scheme/default-config.scm` — `(window:list-block 'chips? #t)`.

## Notes
- Chips reuse the pane-chip `hints-show` overlay machinery, so this is a
  *placement* problem (where the `(label, rect)` pairs go), not a rendering one.
- Open question deferred to 020: how the user identifies *which* same-app
  window a relocated chip refers to when the windows are visually
  indistinguishable. May be acceptable to ignore; flag it during design.

## Verified cause (leaf 010 — confirmed, design against this)

The same-app overlap symptom has **two interlocking causes**. Both verified by
close reading + a deterministic reproduction through the real production
geometry (`Tests/ModaliserTests/SameAppChipCollisionTests.swift`, all green).
The hypothesis in 010 (Cause 1) is **confirmed**; Cause 2 is the new corollary
020 must also design for.

**Cause 1 — occluder blindness (the hypothesis, confirmed).**
`WindowLibrary.collectOccluderRects` (Sources/Modaliser/WindowLibrary.swift:268)
walks `CGWindowListCopyWindowInfo` front-to-back and `return`s on the *first*
same-PID entry (line 283: `if targetPid > 0 && entryPid == targetPid { return occluders }`).
For a back window B of the same app, the *front* same-app window A is that
first entry → B's occluder list comes back **empty**. This is the deliberate
"same-app windows count as the target, not as occluders" rule (docstring
line 224) — but it means B is judged fully unoccluded and its chip stays at
its natural top-left, the same corner A's chip uses.

**Cause 2 — no visible↔visible dodge (corollary, also verified).**
Because B's occluders are `[]`, `ChipPlacement.chipPosition` returns the
natural origin (non-nil) → B is classified *visible* (`#t`) in
`paint-and-snapshot!` (window-list.sld:209-228). The Scheme reactive dodge
`resolve-occluded-against-visible` (window-list.sld:115) **only relocates
chips classified _occluded_** (`#f`); two *visible* chips are never
de-collided against each other. So even the second stage cannot rescue the
overlap — the back chip is mislabelled visible, and the dodge skips it.

**Reproduction evidence (real `ChipPlacement`, chip = 88×88, host-pad 12):**
Front window F `(200,150,500,400)`, larger same-app window B `(200,150,1200,800)`
behind it (top-left aligned — two iTerm windows):
- BUGGY input `occluders=[]` for B → front chip `(212,162,88,88)`,
  back chip `(212,162,88,88)` → **identical rects, overlap = true**.
- CORRECT input `occluders=[F]` for B → back chip relocates to `(712,162)` →
  **no overlap**. Only the occluder list changed ⇒ Cause 1 is causal.
- Fully-stacked identical frames: `occluders=[]` → `(312,262)` non-nil
  (**classified visible, skips dodge**); `occluders=[frame]` → `nil`
  (**classified occluded, would enter the dodge**) ⇒ Cause 2 demonstrated.

**Implications for 020's design.**
- Fixing Cause 1 alone (count same-app front windows as occluders) is
  *necessary but not sufficient*: a partially-visible back window then
  relocates correctly, but a *fully* occluded back window flips to `nil`
  (occluded) and is handed to the existing dodge — which currently stacks
  occluded chips in a cascade. So the cascade-fallback path 020 designs is
  exactly what catches the heavily/fully-stacked case.
- The "natural corner" collision happens entirely in the **Swift geometric
  stage**; whichever stage 020 makes own same-app occlusion, the invariant
  "no two *visible* chips overlap" needs a guard that today's pipeline lacks
  (the dodge never compares visible chips to each other).
