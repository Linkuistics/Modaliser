# pane-split-to-new-k7

**Kind:** work

## Goal

In the herdr Panes drill, rename the split group: `s` "Split" becomes
`n` "New", matching the iTerm splits drill's naming.

## Context

- Human direction (2026-07-13, verbatim, mid prev-next-nav-k4 grilling):
  "Pane -> Split should be Pane -> New, like iterm."
- The iTerm precedent: `build-iterm-splits-drill`
  (`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld:199`) uses
  `(group "n" "New Split" …)`. In the Panes drill the noun is already
  "pane", so the label is plain "New" (the user's words); the key is `n`.
- Target: `build-herdr-tree`'s `(group "s" "Split" …)`
  (`Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld`). `n` is free
  in the Panes drill (taken only in Tabs/Workspaces, which are separate
  key contexts).
- This reverses part of the plan-k1 grilling ("`s` replaces `x` for
  Split") — the root BRIEF's Done-when needs its "`s` Split" mention
  updated in the same commit, and any doc/test asserting the `s` key.

## Done when

Panes drill shows `n` New (h/j/k/l direction children unchanged); root
BRIEF Done-when updated; docs mentioning the `s` Split key swept; tests
asserting the old key updated; tests green.

## Notes

Check whether prev-next-nav-k4's key decisions (in flight) claim `n` in
the Panes drill — if the grilling lands on `n` for anything else, the
two leaves must reconcile before either commits.
