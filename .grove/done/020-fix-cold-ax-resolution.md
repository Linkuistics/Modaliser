# 020-fix-cold-ax-resolution

**Kind:** work

## Goal
Make window-layout ops reliably move Electron-app windows on this machine by
fixing the **Cold-AX resolution gap** (`CONTEXT.md`) confirmed in 010 — without
regressing native apps and without depending on any hard-coded settle delay.

## Context
- Confirmed root cause (see `010-…` FINDINGS): `WindowManipulator
  .focusedWindowAndFrame()` resolves the focused app via
  `AXUIElementCreateSystemWide()` + `kAXFocusedApplicationAttribute`, which
  returns `kAXErrorNoValue (-25212)` for a Chromium app whose accessibility
  engine is dormant. Resolution returns nil → `moveFocusedWindow` /
  `centerFocusedWindow` silently no-op.
- The geometry writes themselves are never the problem; they always land once a
  window is resolved (10's evidence). So this is a resolution fix, not a
  timing/retry fix.

## Done when
- `focusedWindowAndFrame()` resolves the target app via
  `NSWorkspace.shared.frontmostApplication` → `AXUIElementCreateApplication(pid)`
  → `kAXFocusedWindow` (fallback `kAXMainWindow`), a path proven in 010 to work
  while the app is cold. No reliance on the system-wide focused-application
  attribute.
- Verified **live on this (broken) machine**: restart an Electron app (Dia /
  Slack / Teams) so it is cold, then run a layout op (thirds / half / maximise /
  center) as the *first* interaction — the window moves. Re-verify across the
  full op set incl. fullscreen / restore.
- Native apps (iTerm) still work, with no added latency.
- Decide the fate of the `withResizableApp` EUI flip + `usleep(50_000)`: 010
  showed it is orthogonal to this failure. Keep it only if it still earns its
  place for EUI-honoring apps (Slack) once resolution is fixed; otherwise note
  why. If kept/removed is a real trade-off, raise an ADR.

## Notes
- Throwaway diagnostic harnesses from 010 live in `/tmp` (`euiprobe2`,
  `colddrop`, `prodresolve`, `altresolve2`, `enable`) and can re-confirm the
  cold/warm behaviour while iterating; they are not part of the repo.
- Use `systematic-debugging` Phase 4 discipline: write the failing check first
  (cold-app layout op), then the minimal fix, then verify.
- `focusWindow(ownerPID:title:)` already uses the per-app element path and is
  unaffected; only the *focused*-window resolution needs changing.

## VERIFIED (live, on the broken machine)

Fix shipped in `WindowManipulator.focusedWindowAndFrame()` (resolve via
`NSWorkspace.frontmostApplication` → `AXUIElementCreateApplication(pid)` →
`kAXFocusedWindow` ?? `kAXMainWindow`) and `withResizableApp` (EUI flip kept,
`usleep(50_000)` removed). Decision recorded in `docs/adr/0010`.

End-to-end harness `/tmp/resolvecheck.swift` mirrors the OLD vs NEW resolution
exactly and moves the window via the new element:
- **Cold Electron, frontmost (Dia, freshly relaunched, first AX interaction):**
  OLD `systemWide.kAXFocusedApplication` → `axErr=-25204`, resolved=false →
  **nil (the production bug)**. NEW → frontmost=Dia, `kAXFocusedWindow` axErr=0,
  window resolves, MOVE `applied=YES`. `EUI=false` (flip not even entered).
- **Warm Electron (Dia):** NEW resolves + moves (`applied=YES`).
- **Native (iTerm2, frontmost):** NEW resolves + moves (`applied=YES`).

All window-layout ops route through the single `focusedWindowAndFrame()`
chokepoint, so the resolution fix covers thirds/halves/two-thirds/maximise/
center/fullscreen/restore alike. EUI-honoring app (Slack) not running this
session; flip structure unchanged save the delay, and 010 evidence #1 already
covered delay-irrelevance for EUI apps.

Caveat: `swift test` does not compile in this toolchain (pre-existing
`no such module 'Testing'` in unrelated test files, commit 138230b); the
product target (`swift build`) builds clean. Focused-window resolution is
live-AX behaviour with no unit coverage.
