# Resolve the focused window via the frontmost app, not the system-wide AX element

## Status

accepted

## Context

`WindowManipulator.focusedWindowAndFrame()` is the single chokepoint every
window-layout op (thirds, halves, two-thirds, maximise, center, fullscreen,
restore) routes through to find the window to move. It originally resolved the
target app via `AXUIElementCreateSystemWide()` + `kAXFocusedApplicationAttribute`
— the obvious, textbook way to ask "what's the focused app right now?".

That attribute is answered by the *target app's* accessibility engine. Chromium
/ Electron apps keep that engine **dormant** until an assistive client warms it
(by setting `AXEnhancedUserInterface` / `AXManualAccessibility` true, or via
sustained AX tree queries) and let it lapse when idle. While it is dormant the
system-wide focused-application query fails (`kAXErrorNoValue (-25212)` or
`kAXErrorCannotComplete (-25204)`), so `focusedWindowAndFrame()` returned `nil`
and the layout op **silently no-op'd**. Native apps (iTerm) always expose an AX
interface, so they never hit this — which is why the failure was Electron-only,
intermittent, and per-app. Confirmed live on the broken machine: cold,
frontmost Dia → system-wide query `-25204` → nil. See grove
`window-movement-not-working-on-this-machine` (leaf 010 FINDINGS) and `CONTEXT.md`
("Cold-AX resolution gap", "EUI-settle race [refuted]").

## Decision

Resolve the target app from `NSWorkspace.shared.frontmostApplication` — a
**window-server API, independent of any app's accessibility state** — then build
the app element directly from its PID (`AXUIElementCreateApplication(pid)`) and
read `kAXFocusedWindow`, falling back to `kAXMainWindow`. Both per-app window
attributes resolve while a Chromium app is cold (010 evidence #5); only the
system-wide focused-application attribute does not.

Separately, **drop the `usleep(50_000)` settle delay** inside the EUI flip
(`withResizableApp`). 010 varied the delay across 0 / 50 / 500 ms and the writes
always landed; its original rationale (Electron drops position/size writes
mid-EUI-transition) was refuted — writes always returned `.success` and read
back at target once a window was resolved. The **EUI flip itself is kept**: apps
that honor `AXEnhancedUserInterface=true` (Slack) genuinely ignore `setFrame`
while the flag is on, so the off→write→on dance still earns its place — just
without a machine-tuned delay.

## Consequences

- Window-layout ops now move cold Electron-app windows on the first interaction,
  not just after something else has warmed the app's a11y engine.
- The fix is timing-robust by construction: no settle delay, no a11y-enable
  handshake, no polling. It adds zero latency for native apps and does not
  regress them.
- A future reader must not "simplify" resolution back to
  `AXUIElementCreateSystemWide()` + `kAXFocusedApplicationAttribute`, nor re-add
  a settle delay to fix flaky EUI-app moves — both reintroduce this bug. That is
  the whole reason this ADR exists.
- `focusWindow(ownerPID:title:)` already used the per-app element path and was
  unaffected; only *focused*-window resolution changed.
