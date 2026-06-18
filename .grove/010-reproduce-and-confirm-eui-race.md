# 010-reproduce-and-confirm-eui-race

**Kind:** work

## Goal
Reliably reproduce the failure on this machine and produce *evidence* that
confirms (or refutes) the **EUI-settle race** as its mechanism — before any fix
is designed.

## Context
- We are on the broken machine — reproduce live, don't reason in the abstract.
- Failing surface: Electron-app window-layout ops do nothing; iTerm (native)
  works. See `WindowManipulator.swift:withResizableApp` and the per-op callers.
- Use the `systematic-debugging` skill for the loop (reproduce → minimise →
  hypothesise → instrument → confirm).

## Done when
- A repeatable repro is written down: exact app(s), exact op, observed result
  ("window does not move"), contrasted with a native app that works.
- Instrumentation/experiments have produced evidence that discriminates the
  hypotheses, at minimum:
  - Does lengthening the `usleep` settle delay make it work? (timing race)
  - Does deferring the `AXEnhancedUserInterface` restore until *after* the
    geometry writes are observed to apply make it work? (restore-too-early race)
  - Are the AX writes returning `.success` while the window stays put? (silent
    drop vs. hard error)
- The root cause is stated as a confirmed finding with the evidence behind it,
  captured where the next leaf can read it (this file's Notes, or a short
  `docs/` diagnosis note if it earns one).
- A recommendation for the timing-robust fix mechanism is recorded — enough to
  decompose the fix leaf(s).

## Notes
- Do NOT ship a fix in this leaf. Its deliverable is a confirmed diagnosis and
  a fix recommendation; the fix is the next leaf, decomposed lazily once we
  know the mechanism.
- Likely instrumentation: log AX call return codes and read-back the window
  position/size immediately after writing to see whether the write took effect,
  varying the settle delay and the restore timing as independent knobs.

## FINDINGS (confirmed diagnosis)

**Root cause — REFUTES the EUI-settle-race hypothesis.** The failure is in
focused-window *resolution*, upstream of any geometry write.

`WindowManipulator.focusedWindowAndFrame()` resolves the target window via
`AXUIElementCreateSystemWide()` → `kAXFocusedApplicationAttribute`. For a
Chromium/Electron app whose accessibility engine is **dormant ("cold")**, that
system-wide attribute returns `kAXErrorNoValue (-25212)`, so `focusedApp` is
`nil`, `focusedWindowAndFrame()` returns `nil`, and `moveFocusedWindow` /
`centerFocusedWindow` hit their `guard … else { return }` and **silently
no-op**. The window never moves; no error surfaces.

Chromium keeps a11y off until an assistive client activates it (by setting
`AXEnhancedUserInterface`/`AXManualAccessibility` true, or via sustained tree
queries), and lets it lapse when idle. Native apps (iTerm) always expose an AX
interface, so the system-wide attribute always resolves → they always work.
This is why the failure is Electron-specific, intermittent, and per-app, and
**not** a CPU-speed settle race.

**Evidence (live, on the broken machine; standalone Swift harnesses in /tmp
replicating the exact production logic against live apps — Dia, Slack, Teams,
iTerm):**
1. Replicating `withResizableApp` across settle = 0 / 50ms / 500ms, restore
   immediate / deferred / poll, EUI true / false: the window **always moves**
   once a window element is in hand. Settle delay is irrelevant. → refutes
   "lengthening usleep helps" and "deferring EUI restore helps".
2. AX position/size writes return `.success` **and** read back at target in
   every case where a window is resolved. → the write is never the failure;
   "silent drop vs hard error" is neither — the writes simply never run because
   resolution returned nil.
3. **Dia fails with `EUI=false`** and rejects EUI writes (`-25208`
   NotImplemented), so `withResizableApp` never even enters the flip path for
   Dia. A failure that occurs with the flip disabled cannot be caused by the
   flip's settle delay. → independently refutes the EUI-settle race.
4. **Caught cold:** freshly-restarted Teams, frontmost, `EUI=false` —
   `systemWide kAXFocusedApplicationAttribute` → `axErr=-25212` (NoValue) →
   "FOCUSED APP UNRESOLVED". After `set AXEnhancedUserInterface=true` (+300ms),
   the same systemWide read → `axErr=0`, resolves to Teams, window moves.
   This is the user's observation made mechanical: "once your test runs it then
   works" — the probes set EUI=true, warming Chromium's a11y.
5. **Fix path validated cold:** on cold Teams, resolving via the *app element*
   (`AXUIElementCreateApplication(pid)`) → `kAXFocusedWindow` (axErr=0),
   `kAXMainWindow` (axErr=0), `kAXWindows` (count=1) **all resolve cold**.
   `NSWorkspace.frontmostApplication` (window-server API) returns the frontmost
   app correctly regardless of a11y state.

**Discriminator summary:** native apps expose AX always → work; Chromium apps
expose AX only when warm → the system-wide focused-app lookup is the single
point that fails cold.

## FIX RECOMMENDATION (for the next leaf)
Change `focusedWindowAndFrame()` to stop using
`AXUIElementCreateSystemWide()` + `kAXFocusedApplicationAttribute`. Instead:
resolve the frontmost app via `NSWorkspace.shared.frontmostApplication` →
`AXUIElementCreateApplication(pid)` → `kAXFocusedWindow` (fallback
`kAXMainWindow`). This path is proven to work cold (evidence #5), is
timing-robust by construction (no settle delay, no a11y-enable handshake, no
polling), adds zero latency for native apps, and does not regress them.
The `withResizableApp` EUI flip + `usleep(50_000)` are orthogonal to this
failure; the fix leaf should decide whether they are still needed at all
(see glossary: **Cold-AX resolution gap**, **EUI-settle race [refuted]**).
