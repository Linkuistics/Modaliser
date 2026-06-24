# list-cursor-initial-focus-k25

**Kind:** planning

## Goal

When an overlay opens onto a screen with a live list that picks tabs / splits /
windows (e.g. the iTerm Tab list, the iTerm Panes list, the global Windows
list), the selection cursor should **start on the currently-focused item** —
the focused tab / split / window — not on the first row (index 0). Requested by
the user on 2026-06-24.

## Context

- The selection cursor is list-cursor-k6 (`(modaliser list-cursor)`). The
  renderer brackets a render pass (`renderer-body-json` in ui/overlay.scm):
  each live-list block offers its `cursor-targets-fn` via `block-json` →
  `list-cursor-offer!`; the first offer wins, and the selected index rides into
  the payload as `"selected"` (JS marks it `.is-focused`).
- The cursor's selected index initialises to **0** today, so the highlight
  lands on the first row regardless of which item is actually focused in the
  app. The blocks DO know the focused row — the live lists render a "focused"
  detail / marker per row (iterm panes/tabs mark the focused session/tab; the
  window list marks the frontmost window).
- The migrated Windows overlay (bare-loose-rows-k23) now hosts its list loose;
  iTerm Tab/Panes lists live in their panels. All route through the same
  block-json cursor-offer path, so a single mechanism should cover them.

## Design / investigation — to settle (grill first)

- **How the focused index reaches the cursor.** Options: the block's
  targets-fn (or a sibling `cursor-initial-index-fn` / a flag on a target row)
  reports which row is focused; `list-cursor` seeds the initial index from it on
  the pass that first claims the cursor (vs. only when the index is unset, so a
  user's arrow-key move isn't overridden on re-render).
- **Re-render semantics.** Seed the focus index only on the FIRST claim (overlay
  open), not on every push-update — otherwise moving the cursor then triggering
  a re-render would snap it back to the focused item. Confirm with the list-
  cursor pass/generation model.
- **Scope.** iTerm tabs + panes + the global windows list (all `cursor-targets-fn`
  carriers). A static (no-chips) list has no cursor, so n/a.

## Done when

- Opening an overlay whose live list has a focused item highlights THAT item;
  `⏎` activates it; arrow-key moves still work and are not clobbered by
  re-renders.
- Verified live for the iTerm Tab list and Panes list (and the Windows list).
- Tests cover the initial-index seeding; `check-portable-surface.sh` green.

## Notes

- Files: `lib/modaliser/list-cursor.sld`, `ui/overlay.scm` (`block-json` cursor
  offer + `"selected"` emit), the live-list blocks
  (`blocks/window-list.sld`, `apps/iterm.sld` pane/tab lists) to expose the
  focused row's index.
- Independent of manual-panel-order-k24 and util-extraction-audit-k26.
