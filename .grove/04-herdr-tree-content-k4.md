# herdr-tree-content-k4

**Kind:** work

## Goal

Fill the herdr variant trees with real bindings: herdr **panes + tabs + workspaces**
controls (the replace tree, and the herdr portion of augment), the `i` **iTerm-splits
drill** for augment, and the live-list overlay **blocks**.

## Context

Read the root `BRIEF.md`. Depends on leaves `herdr-backend-k2` and `variant-wiring-k3`
(backend + skeleton screens exist). herdr owns top-level `hjkl` (pane focus) in both
trees; augment = the herdr tree + the `i` drill.

- **Internal `build-herdr-tree`** in `muxes/herdr.sld` (R3) — construct the screen from
  internal ops so the library export surface stays small (like iterm.sld's
  `rebuild-tree!`). Panes: focus (hjkl, sticky), split (`x` → hjkl), move (`m` sticky →
  hjkl), zoom, close, digit-jump. Tabs sub-screen (list/switch by digit, new, rename,
  close). Workspaces sub-screen (list/switch, new, rename, close). Mirror the layout
  idioms in `app-trees/com.googlecode.iterm2.scm` (panels, sticky-sets, open drills).
- **`i` iTerm-splits drill** (augment only) — uses the iterm-direct ops/helper exported
  in leaf 3. hjkl focus + split + zoom for the *iTerm* splits.
- **Blocks** `blocks/herdr-{panes,tabs,workspaces}.{sld,js,css}` mirroring
  `blocks/iterm-{panes,tabs}.*` — live lists with chips + digit dispatch. Data from
  `herdr pane list` / `tab list` / `workspace list` (focused marker included).
- **Chip rects** (tmux-style, R8): herdr `pane layout` cell coords ÷ canvas × iTerm
  focused-session AX frame, **area-relative** (herdr's left sidebar offsets the
  canvas). Correct in **replace** mode (one AXScrollArea). In **augment** mode the
  first-AXScrollArea soft spot means chips may target the wrong split — **document this
  limitation** (hjkl focus still works; digit-jump is secondary). A proper fix
  (focused-iTerm-session-frame primitive) is the optional deferred leaf.

Agents + worktrees are their own leaves (5, 6) — surface hooks for them if cheap, but
don't build them here.

## Done when

- Replace tree drives herdr panes/tabs/workspaces; augment adds the `i` iTerm-splits
  drill; both usable live from Modaliser.
- Blocks render live lists with working digit-jump (chips correct in replace mode).
- Tests for the JSON-fed list rendering / any tree-shape logic; `swift test` +
  `check-portable-surface.sh` green.

## Notes
