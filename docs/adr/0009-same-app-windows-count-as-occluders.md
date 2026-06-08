# Same-app front windows count as occluders for chip placement

## Status

accepted

## Context

`WindowLibrary.collectOccluderRects` walks `CGWindowListCopyWindowInfo`
front-to-back to find what covers a target window, so a chip can dodge
to a clear fragment. It originally stopped at the **first same-PID
entry** (treating "same app" as "the target, not an occluder"), because
`_AXUIElementGetWindow` and `CGWindowList`'s `kCGWindowNumber` disagree
for some apps, making the per-window id (`wid`) an unreliable way to
pick out *which* window is the target. Stopping at any same-PID entry
sidestepped that ambiguity.

But that rule is exactly the bug behind same-app overlap (grove
`window-chips-overlap-same-app-windows`, leaf 010): a back window of the
same app gets an **empty** occluder list, is judged unoccluded, and its
chip lands on the front window's chip. See the verified cause in the
grove brief and `Tests/ModaliserTests/SameAppChipCollisionTests.swift`.

## Decision

Reverse the rule: **same-app windows in front of the target are
occluders like any other window.** The walk stops only at the *actual
target*, identified by `wid` when reliable and otherwise disambiguated
among same-PID candidates by **rect match** against the target's known
bounds (which `findChipPositionFunction` already has). Only the matched
target — not every same-PID window — ends the front-to-back collection.

## Consequences

- A partially-visible same-app back window now relocates its chip off
  the colliding corner (the intended fix).
- A *fully* occluded same-app window flips from "visible at natural
  corner" to "no usable area" (`chipPosition` returns nil); it is then
  routed to the **chip cascade** (see
  `docs/specs/window-chip-placement-design.md`), not dropped.
- If target identification still fails (no `wid`, no rect match — e.g.
  the target is absent from the on-screen list), we keep the existing
  bias-to-visible fallback (treat as unoccluded) rather than
  over-collecting occluders and relocating a chip that did not need to
  move.
