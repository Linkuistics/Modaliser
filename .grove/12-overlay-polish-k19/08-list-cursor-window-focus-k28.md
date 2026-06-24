# list-cursor-window-focus-k28

**Kind:** planning

## Goal

Extend the selection-cursor initial-focus mechanism (built in
list-cursor-initial-focus-k25 for the iTerm Tab and Panes lists) to the **global
Windows list** (`window:list-block 'chips? #t`): when the Windows overlay opens,
the cursor should start on the **currently-focused window**, not row 0. Split out
of k25 on 2026-06-24 because the windows list is materially harder than tabs/panes
and its design needs settling on its own.

## What already exists (k25, retired)

- The cursor seeds its initial index from an optional **`cursor-initial-index-fn`**
  — a thunk on the live-list block returning the focused row index (or `#f`). It is
  consulted **once**, on the pass that first claims the cursor (overlay open), so
  the probe is lazy and a later arrow-move survives its own re-render. Mechanism
  lives in `lib/modaliser/list-cursor.sld` (`list-cursor-offer!` + `seed-index`)
  and `ui/overlay.scm` (`block-json` threads the thunk). An out-of-range or `#f`
  seed falls back to row 0 (read-clamp handles the upper bound).
- So this leaf only needs to **supply a `cursor-initial-index-fn` for the windows
  list** and wire it into `window-actions.sld`'s `list-block` wrapper — the same
  one-line append the iTerm wrappers got. No cursor-core change.

## Why windows is the hard one (settle these — grill first)

1. **No focus marker today.** Unlike iTerm tabs (which carry a `current` flag) the
   window rows carry only `label`/`app`/`title`/`visible` — nothing says which
   window has OS focus. (`blocks/window-list.sld` `windows-data`; JS marks no
   "current" row.)
2. **Spatial sort, so row 0 ≠ focused.** `list-current-space-windows`
   (`WindowCache.listCurrentSpaceWindows`, WindowCache.swift:64) sorts **row-major
   (y major, x minor)** for stable digit muscle-memory — deliberately *not* focus
   order. So the focused window can be at any index.
3. **No primitive returns the focused window.** `WindowLibrary` exposes
   `list-current-space-windows`, `focus-window`, geometry ops — but nothing that
   names the frontmost/focused window's id. `WindowManipulator.focusedWindowAndFrame`
   (resolves via `NSWorkspace.frontmostApplication` → AX focused window) is the
   Swift-side notion; `WindowEnumerator.getWindowOrder` gives CGWindow z-order
   (0 = frontmost). One of these likely needs a thin Scheme-facing primitive.
4. **AX window-id matching is documented as flaky.** `_AXUIElementGetWindow`
   disagrees with CGWindowList's `kCGWindowNumber` for some apps — see the
   fallback note in `WindowLibrary.swift` `window-visible-at?` (~line 132). So
   matching the focused window by `windowId` may be unreliable; a PID-based or
   PID+z-order match may be more robust.
5. **Semantics worth a sanity check.** A window switcher is usually used to go to a
   *different* window, so "start on the current window" is less obviously useful
   than for adjacent tabs/panes. Confirm the user still wants it (they did at k25
   commission time) and that ⏎-on-current as a no-op is acceptable.

## Likely approach (to confirm)

Add a Scheme-facing way to get the focused window's identity (id and/or
owner-PID), e.g. a `focused-window-id` / `focused-window` primitive in
`WindowLibrary` built on `WindowManipulator`/`WindowEnumerator`. The
`cursor-initial-index-fn` then finds that window's row in
`window-list-current-targets` (best-effort: by id, falling back to owner-PID +
topmost z-order); `#f` (→ row 0) when no robust match. Verify live, because the
AX-id flakiness only shows up against the real window server.

## Done when

- Opening the Windows overlay highlights the currently-focused window; `⏎`
  activates it; arrow-key moves still work and survive re-renders.
- Verified **live** for the Windows list (`./scripts/install.sh` then Relaunch);
  detection failure degrades to row 0, never worse than today.
- Tests cover the windows focused-index derivation (and any new Swift primitive);
  `check-portable-surface.sh` green.

## Notes

- Files: `WindowLibrary.swift` (+ `WindowManipulator`/`WindowEnumerator`) for a
  focused-window primitive; `lib/modaliser/window-actions.sld` (`list-block`
  wrapper) to attach the `cursor-initial-index-fn`; `blocks/window-list.sld` if the
  focused row is better derived inside the block's snapshot.
- Independent of elide-general-panel-k27 and util-extraction-audit-k26.
