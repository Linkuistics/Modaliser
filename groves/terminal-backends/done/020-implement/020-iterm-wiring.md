---
kind: work
---

# 020 — Wire iTerm into the façade

## Goal

Implement the iTerm internal backend record + `iterm:register!` so
that `(terminal:focus-pane-left)` etc. route correctly to iTerm
when iTerm is frontmost. Add `toggle-pane-zoom` as a new keystroke-
proxy op. Keep the existing 12 `iterm:focus-pane-*` / `iterm:split-
pane-*` / `iterm:move-pane-*` exports alive as aliases — **this
leaf is non-breaking.** The drop happens at 090.

## Context

- Recovery notes: `groves/terminal-backends/done/010-recover-design/
  notes/iterm.md` (the authoritative reference for iTerm's current
  ops, AppleScript patterns, and AX/chip mechanics).
- Existing module: `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`
  — the 12 splits-tree procs already exist and stay exported until
  090. `focus-by-digit` (file:line per notes/iterm.md) and
  `pane-list-block` already implement the digit-jump machinery.
- `iterm-configured?` (existing) becomes the backend record's
  `configured?` field.

## Done when

- New: iTerm `<terminal-backend>` record populated and registered
  via `(iterm:register!)`.
  - All 12 directional ops point at the existing `focus-pane-left`
    etc. (the same procedures; no rewrites).
  - `focus-pane-by-digit` wraps the existing `focus-by-digit` +
    `pane-list-block` machinery into a single procedure callable
    from the façade.
  - `toggle-pane-zoom` (new) is a keystroke-proxy of `cmd+shift+enter`
    (iTerm's default zoom toggle). No new AppleScript needed.
  - `focused-pane-id` returns the focused session's UUID (existing
    AppleScript path via `id of current session of current tab of
    current window`).
  - `configured?` calls existing `iterm-configured?`.
- Existing `iterm:focus-pane-*` / `iterm:split-pane-*` /
  `iterm:move-pane-*` exports remain — no breakage to user's
  `config.scm`.
- `(iterm:register!)` updated to also `register-backend!` with the
  façade (in addition to its existing tree/mode/suffix wiring).
- Hand-verify: in a Modaliser session with `(iterm:register!)`,
  pressing leader → call to `(terminal:focus-pane-left)` moves
  focus correctly across iTerm panes. `(terminal:toggle-pane-zoom)`
  zooms the focused pane. `(focused-terminal-path)` returns
  `'((iterm . #(pane "<uuid>" fg "zsh")))`.

## Notes

- The user's recall and the iTerm baseline note both flag that
  iTerm's `cmd+shift+enter` zoom is the existing pattern from the
  user's tree ("z Toggle Zoom"). The `toggle-pane-zoom` op is the
  same keystroke proxy with a stable name.
- The dual-export-of-the-same-procs pattern (`iterm:focus-pane-left`
  AND `terminal:focus-pane-left`) is intentional and temporary.
  Don't try to optimise — 090 removes the duplicates by dropping
  the iterm-prefixed exports.
- This leaf is the **first real test of the façade design from 010**.
  If the façade needs adjustments (record shape, registry API),
  revise 010 in place and rerun — that's a planning iteration, not
  a new leaf.
