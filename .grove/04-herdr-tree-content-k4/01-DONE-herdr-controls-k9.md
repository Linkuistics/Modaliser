# herdr-controls-k9

**Kind:** work

## Goal

Build the herdr control surface as real modal trees + live-list blocks — **no chips
yet** (chips are `herdr-pane-chips-k10`). After this, the `/herdr` (replace) and
`/herdr+split` (augment) screens drive herdr panes, tabs and workspaces from Modaliser,
and augment adds the iTerm `i`-drill.

## Context

Read this node's `BRIEF.md` (JSON shapes, the universal-focus finding, CLI surface) and
the root `BRIEF.md`. Backend ops (focus/split/move/zoom, digit-jump via `agent focus
<pane_id>`) already exist in `muxes/herdr.sld`; the skeleton `build-herdr-tree` is just
a Focus panel. Mirror `app-trees/com.googlecode.iterm2.scm` idioms and
`blocks/iterm-{panes,tabs}.*`.

Build:

- **`build-herdr-tree`** (`muxes/herdr.sld`, internal ops → small export surface):
  - **Panes panel**: `hjkl` focus (sticky, `sticky-set` like iTerm's split-nav); `x`
    Split → `hjkl` (new split each direction); `m` Move (sticky, exit-on-unknown) →
    `hjkl`; `z` Toggle Zoom; `d` Close pane (new `close-pane` op via `pane close
    <focused-pane-id>`); a Panes list block with digit-jump.
  - **Tabs sub-screen** (`open "t"`): tabs list block (digit → `tab focus <id>`), `n`
    New (`tab create --focus`), `r` Rename, `d` Close (`tab close <id>`). Sticky
    focus-walk optional (herdr tabs are a flat list; a digit-jump list is the primary
    path — a Prev/Next `hjkl` walk via `tab focus` on the neighbour id is a nice-to-have,
    keep it simple).
  - **Workspaces sub-screen** (`open "w"`): workspaces list block (digit → `workspace
    focus <id>`), `n` New, `r` Rename, `d` Close.
  - Rename: herdr takes the new label as a CLI arg (`tab rename <id> <label>`), unlike
    iTerm's menu-click. Needs a text-input path — check what Modaliser offers (a prompt
    block / chooser) before inventing one; if there's no cheap in-overlay text input,
    ship rename as a documented follow-up rather than a half-built path.
- **Blocks** `blocks/herdr-{panes,tabs,workspaces}.{sld,js,css}` — row lists only (no
  chips). Each: `on-render-fn` snapshots `herdr <x> list`, exposes
  `*-current-targets` (`(label . id)`) for the parent digit key-range, marks the
  `focused` row, and wires `cursor-targets-fn` + `cursor-initial-index-fn` (focused
  row) like the iTerm blocks. herdr-panes rows show agent/cwd (or pane_id); herdr-tabs
  and -workspaces show `label`. Register css/js via `add-overlay-asset-file!`.
- **`i` drill zoom**: add `z` Toggle Zoom (iterm-direct `toggle-pane-zoom`) to
  `iterm:build-iterm-splits-drill` in `apps/iterm.sld`.
- **Config**: splice the blocks into `(screen 'com.googlecode.iterm2/herdr …)` and
  `…/herdr+split` — either by `build-herdr-tree` returning the fuller node list, or by
  the config appending `(herdr:pane-list-block)` etc. Keep the export surface small
  (block wrapper helpers on `herdr.sld`, mirroring `iterm:pane-list-block`). Sync
  bundled ↔ user `~/.config/modaliser/` ([[feedback_config_sync]]).

Digit-jump focus uses `agent focus <pane_id>` (universal — node BRIEF finding);
`herdr.sld` already does this, so no change needed beyond the list block feeding ids.

## Done when

- `/herdr` drives herdr panes (focus/split/move/zoom/close/digit-jump) + tabs +
  workspaces; `/herdr+split` adds the `i` iTerm-splits drill (now incl. zoom). Verified
  live where cheap (op dispatch against the running herdr; full F17→overlay visual is
  the installed-app step, may defer with chips per leaf-3 precedent).
- Blocks render live JSON-fed lists with working digit-jump (no chips yet).
- Tests: block list rendering / target snapshotting + tree-shape (mirror
  `Muxes*`/block tests). `swift test` + `check-portable-surface.sh` green
  (mind [[project_iterm_tests_crash]] pre-existing skips).

## Notes
