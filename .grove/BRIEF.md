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
