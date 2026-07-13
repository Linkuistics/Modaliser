# window-raise-same-title-k6

**Kind:** work

## Goal

Fix global-overlay window switching so a digit chip raises exactly the
window it labels, even when two windows of the same app share a title.

## Context

- Human report (2026-07-13, mid prev-next-nav-k4 grilling): "when two
  iTerm windows have the same title, window switching from the global
  overlay (1..n corresponding to the chips) doesn't raise the correct
  window — it raises a different window of the same app."
- Root-cause candidate (located during capture):
  `WindowManipulator.focusWindow(ownerPID: pid_t, title: String)`
  (`Sources/Modaliser/WindowLibrary.swift:82` →
  `WindowManipulator.swift:40`) resolves the AX window by **PID + title
  string** — ambiguous when titles collide; first match wins.
- The window-list rows already carry a `windowId` (CGWindowID — the
  `focused-window` primitive surfaces it, and the cursor-seed matcher in
  `window-actions.sld` keys on it). Resolution should prefer `windowId`,
  falling back to title only when the id is 0/absent. AX windows expose no
  CGWindowID attribute directly — the private `_AXUIElementGetWindow` or a
  frame+title correlation are the known bridging options; pick
  deliberately.

## Done when

Two same-app windows with identical titles each raise correctly from
their own chip (verify live with two iTerm windows retitled alike); a
unit test covers the resolver's id-over-title preference; tests green.

## Notes

Off this grove's charter (window-switching domain, not herdr) — captured
here per externalize-don't-absorb; say the word and it re-homes to its own
grove instead.
