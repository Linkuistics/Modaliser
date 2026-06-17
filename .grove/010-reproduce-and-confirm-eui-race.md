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
