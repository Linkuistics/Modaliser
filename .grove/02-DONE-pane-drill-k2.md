# pane-drill-k2

**Kind:** work

## Goal

Relocate the herdr tree's pane surface under a single `p` "Panes" drill,
parallel to Tabs/Workspaces/Worktrees/Agents, per the plan-k1 grilling
decisions.

## Target shape (agreed 2026-07-13, plan-k1)

`build-herdr-tree` returns 6 top-level nodes, in this order:

```scheme
(open "p" "Panes"
  (panel "Focus"                      ; hjkl → focus, each 'next 'herdr-panes-focus
    …)                                ; (cross edge into the Walk, unchanged)
  (group "s" "Split" …)               ; hjkl — RENAMED from x, short label
  (group "m" "Move" …)                ; hjkl Walk 'next 'self — label was "Move Pane"
  (key "z" "Zoom" toggle-pane-zoom)   ; label was "Toggle Zoom"
  (key "d" "Close" close-pane)        ; label was "Close Pane"
  (panel "Panes" (pane-list-block 'chips? #t)))
(open "t" "Tabs" …)                   ; unchanged
(open "w" "Workspaces" …)             ; unchanged
(open "g" "Worktrees" …)              ; unchanged
(key "b" "Jump to Blocked" …)         ; unchanged
(open "a" "Agents" …)                 ; unchanged
```

Decisions this encodes:

- **hjkl focus moves fully under the drill** — no top-level duplicate. The
  "herdr owns the top-level hjkl" contract is retired (CONTEXT.md and
  ADR-0013 already reworked in the plan-k1 commit). Focus entry is now
  `<leader> p h`; the `herdr-panes-focus` Walk still latches after the
  first press, so chained movement is unchanged.
- **Inner keys renormalized**: `s` for Split (`x` retired); `m`/`z`/`d` keep
  their keys.
- **Short labels** inside the drill (Split/Move/Zoom/Close), matching the
  sibling drills' "New"/"Rename"/"Close" style.
- **Pane list + chips + digit-jump move into the drill** (`<leader> p 3`),
  matching the Tabs-drill behaviour; chips paint on drilling in.
- Grouping is explicitly provisional ("until a better hierarchy of
  interaction" — root brief); this leaf relocates, it does not redesign.

## Context

Beyond the brief chain:

- `Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld` —
  `build-herdr-tree` (the change site); also stale comments: the
  `build-herdr-tree` docstring key-map, and `focus-mode-register!`'s
  "herdr owns the top-level hjkl" line.
- `Sources/Modaliser/Scheme/app-trees/com.googlecode.iterm2.scm` — stale
  comments only (no splice change): "herdr owns the top-level hjkl pane
  focus in both" (~line 170) and "`c` is free in build-herdr-tree
  (top-level keys: x m z d t w g b a)" (~line 197; new top-level keys:
  p t w g b a). Sync the edit to `~/.config/modaliser/app-trees/`
  (feedback_config_sync).
- `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` ~line 183 —
  stale "herdr owns the top-level hjkl in both" comment.
- `docs/how-to/terminal-pane-aware-tree.md` ~line 166 — same stale claim.
- `Tests/ModaliserTests/ModaliserMuxesHerdrLibraryTests.swift` — shape
  pins to update: `(length (build-herdr-tree))` 11 → 6 (~line 274); the
  Focus-panel cross-edge test now finds Focus inside the `p` drill; the
  ADR-0015 smoke test dispatches a top-level `h` — path gains the `p`
  drill; agents/worktrees shape tests key off `b`/`g`/`a` at top level
  and should survive unchanged — verify.

## Done when

- `build-herdr-tree` matches the target shape; both variant screens get it
  for free (config splices unchanged).
- The stale-comment/doc sweep above is done (herdr.sld, iterm2 app-tree +
  live-config sync, iterm.sld, the how-to).
- Tests updated and green: `swift test --filter ModaliserMuxesHerdrLibraryTests`
  (plus the usual skips per project_iterm_tests_crash if running the full
  suite).

## Notes

`x` frees up at the herdr top level (as do h/j/k/l/m/z/d) — do not rebind
anything to them in this leaf; freed space is for future work (e.g. the
ambient agent-status grove).
