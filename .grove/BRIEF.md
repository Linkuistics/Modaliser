# window-movement-not-working-on-this-machine — brief

## Goal
Make **window-layout ops** work for **Electron apps on every machine**, not
just patch the box where they currently fail. Native apps (iTerm) are
unaffected; the fix must not regress them.

> **010 diagnosis (confirmed):** the defect is the **Cold-AX resolution gap**
> (`CONTEXT.md`), **not** the EUI-settle race originally hypothesised below.
> `focusedWindowAndFrame()` resolves the focused app via
> `AXUIElementCreateSystemWide()` + `kAXFocusedApplicationAttribute`, which
> returns `kAXErrorNoValue` for a Chromium app whose accessibility engine is
> dormant → resolution returns nil → the op silently no-ops. The failure is
> upstream of any geometry write; the `usleep(50_000)` settle delay is
> irrelevant. Fix: resolve via `NSWorkspace.frontmostApplication` → app element
> → `kAXFocusedWindow` (proven to work cold). See `010-…` FINDINGS for the
> evidence trail and the fix leaf for implementation.

## Done when
- Window-layout ops (thirds / halves / two-thirds / maximise / center /
  fullscreen / restore) reliably move Electron-app windows on the machine
  where they currently fail.
- The fix is timing-robust by construction — it does not depend on a hard-coded
  settle delay tuned to one machine's speed.
- Native (non-EUI) apps still work, with no added latency they don't need.
- The root cause is confirmed with evidence, not assumed.

## Decomposition
Diagnosis before fix (systematic-debugging). The first leaf reproduces and
*confirms* the EUI-settle race on this machine; only once the mechanism is
proven do we add the fix leaf(s). Scope is already decided (robust across
machines), so the fix is expected — but its exact shape (poll-until-applied,
verify-then-restore, retry-with-backoff, …) depends on what diagnosis shows,
so we decompose it lazily after 010.

## Pointers
- Suspect code: `Sources/Modaliser/WindowManipulator.swift` —
  `withResizableApp` (the EUI flip), `moveFocusedWindow`, `centerFocusedWindow`,
  `toggleFullscreen`, `restoreFocusedWindow`.
- Dispatch path: `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld`
  (`divisions` / `center-panel` → `move-window` / `center-window`).
- Glossary terms in play: Window-layout op, EUI flip, EUI-settle race
  (see `CONTEXT.md`).

## Notes
- Differential established by grilling: identical code + identical macOS
  version on a *different-CPU-generation* machine works for all apps; this
  machine fails for Electron apps only. That points squarely at a timing race,
  not a logic/coordinate bug.
- We are running on the *broken* machine, so live reproduction is available —
  the first leaf should exploit that rather than reason in the abstract.
- ~~`withResizableApp` restores `AXEnhancedUserInterface` to `true`
  synchronously… the restore re-arms EUI before Electron has applied the
  writes.~~ **Refuted by 010:** the writes always land once a window is
  resolved; the failure is that resolution returns nil for cold Chromium apps.
