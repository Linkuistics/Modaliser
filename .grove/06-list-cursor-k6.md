# list-cursor-k6

**Kind:** work

## Goal

Add a **selection cursor** (`↑↓` / `k j` move, `⏎` activate) to embedded **live
lists** and the chooser; the `1–9` / `0` digit selectors stay **immediate**
direct-jump (spec §6).

## Context

- `blocks/window-list.sld`, `blocks/iterm-panes.sld`, `blocks/iterm-tabs.sld`:
  each block's `on-render-fn` uses return-and-merge to inject live rows; the
  `*-current-targets` alists drive the parent group's `key-range` digit dispatch
  by UUID/index (race-free, no event injection). There is **no cursor/arrow
  state today**.
- JS block renderers build `.wl-row` / `.ip-row` / `.it-row`; cursor state should
  live in the list block as a **selected index**; arrow presses dispatch to a
  handler that updates the index and pushes via `push-overlay-update`.
- The chooser (`chooser.js:28–49`) already has arrow + `⏎` + type-to-filter;
  its footer advertises `⏎ choose · ↑↓ select · ⎋ exit`. Add `k` / `j` (the user
  navigates **hjkl exclusively** — see user memory).
- Depends on [[panel-grid-renderer-k4]] (list rendered inside a panel) +
  [[layout-dsl-k3]] (live-list as a panel child).

## Done when

- Embedded live lists track a selected index; `↑↓` / `k j` move it and `⏎`
  activates the selected row; `1–9` / `0` remain immediate.
- The focused/current row is marked (accent left-bar + tint); a right-aligned
  detail column appears when width allows; the footer advertises the nav keys.
- The chooser gains `k` / `j`.
- Selection-cursor dispatch covered by state-machine / event-dispatch tests;
  `check-portable-surface.sh` green.

## Notes

- **Multi-list ownership (decided, spec §12):** the **first** live-list panel in a
  screen (declaration order) owns `↑↓` / `⏎`; `Tab` cycling between lists is a
  **non-goal** for this grove.
