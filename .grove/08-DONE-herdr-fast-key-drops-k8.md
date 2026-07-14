# herdr-fast-key-drops-k8

**Kind:** work

## Goal

Make a fast `<local-leader> w <digit>` sequence (herdr-in-iTerm focused)
dispatch reliably — today the digit (or the whole tail) is lost unless
the user types slowly.

## Context

- Human report (2026-07-13, verbatim, mid prev-next-nav-k4 grilling):
  "When herdr in iterm is focused, hitting the local trigger then w then
  a workspace number doesn't work unless I do it slowly. Somehow it seems
  the keys aren't being queued?"
- Diagnose before fixing (systematic-debugging); candidate mechanisms,
  in suspicion order:
  1. **Synchronous shell-outs stall the event tap.** The leader press
     runs the composed suffix hook (herdr `in-chain?` socket query + the
     tab-scoped AppleScript split count, ADR-0013) synchronously, and
     each drill render shells `herdr <x> list`. Keys arriving during
     those windows may be dropped rather than queued — ADR-0014
     documents the stalled-tap failure mode (macOS disables/bypasses a
     tap that doesn't return fast enough); this would be it biting on
     the *query* path ADR-0014 explicitly left synchronous.
  2. **Digit-before-snapshot race** — has an existing mitigation
     (`herdr-list-refresh!`'s on-demand re-snapshot in
     `list-digit-range`, `muxes/herdr.sld`); if that path worked, the
     slow-vs-fast asymmetry would be invisible, so verify whether it is
     even reached (the drop may be upstream, at the tap).
- Instrument first: os.Logger timestamps at tap-callback entry/exit
  around a fast sequence will show whether events arrive at all
  (feedback_nslog_invisible_in_unified_log — use os.Logger, not NSLog).

## Done when

Root cause identified and stated (not assumed); fast `F17 w <digit>`
focuses the right workspace reliably in a live herdr session; any fix
keeps ADR-0014's never-block contract; tests green.

## Notes

If the cause is the synchronous query path, the fix likely generalizes
beyond the `w` drill (every herdr drill render shells out) — scope the
fix to the mechanism, not the one reported sequence, but keep it one
focused session (decompose if it balloons).
