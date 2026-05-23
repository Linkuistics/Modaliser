---
kind: work
---

# 030 — Investigate WezTerm

**Surface:** full (13 ops + detection).
**Install state:** cask present today. CLI at
`/Applications/WezTerm.app/Contents/MacOS/wezterm` (not on PATH —
either invoke via full path or symlink into `/opt/homebrew/bin`).
No install needed.

## Probe — operations

WezTerm exposes a rich `wezterm cli` surface. Confirm each:

- `wezterm cli activate-pane-direction Left|Right|Up|Down` →
  focus-pane-{h,j,k,l}
- `wezterm cli split-pane --top-bottom` (vertical split) and
  `--left-right` (horizontal split), plus `--top|--bottom|--left|--right`
  flags to control which side the new pane goes →
  split-pane-{h,j,k,l}
- Movement (rearranging panes within a tab): WezTerm has
  `wezterm cli move-pane-to-new-tab` and key-table-based pane swap;
  verify whether a direct "move pane left within same tab" exists
  or whether move-pane-* is keystroke-only.
- `focus-pane-by-digit` — `wezterm cli list --format json` lists
  panes with `pane_id`; `wezterm cli activate-pane --pane-id N`
  focuses one. Chip rendering: `wezterm cli send-text --pane-id N`
  can write to a pane's input; combined with terminal escape codes
  this paints a label.

## Probe — detection

Phase-1 docs hedged on the active-pane field in `wezterm cli list
--format json` being version-dependent. Probe:
- `wezterm cli list --format json` — what fields exist in this
  cask's version? Is there `is_active` or similar?
- `wezterm cli get-pane-direction` (if exists).
- Worst case: parse the JSON tree-shape — there's exactly one
  active pane and panes usually carry timestamps or activity flags.

## Capture

Write `notes/wezterm.md` with:
- Exact CLI version (`wezterm --version`) and macOS app build.
- One Scheme snippet per op.
- Detection recipe.
- Limitations.
- Capability matrix row.
