# plan-k1

**Kind:** planning

## Goal

Diagnose why herdr workspace rename gets no keystrokes and plan the fix.

## Context

Grilling session, 2026-07-11. Root cause confirmed in code: dialog commands
raise blocking osascript dialogs from inside `modal-handle-key` with the
modal catch-all still registered; the tap thread swallows typed keys into
the blocked Scheme engine until macOS tap-timeout.

## Done when

Shared understanding reached and recorded; tree grown. Done: mechanism
(async dialogs), scope (shared portable lib, all seven sites), invariant
ownership (library-owned modal-exit), and the single test seam
(`current-dialog-runner`) all decided → ADR-0014, CONTEXT.md "Dialog
command", root brief, leaves k2 + k3.

## Notes

Rejected alternatives (see ADR-0014): blanket exit-before-action reorder
(breaks `enter-mode!` context push); exit-first-but-stay-sync (leader press
during a dialog still stalls the tap); per-command DSL annotation (new
state-machine surface that still needs the async dialog inside).
