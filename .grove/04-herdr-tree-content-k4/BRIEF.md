# herdr-tree-content-k4 — brief

Fill the herdr variant trees with real bindings: herdr **panes + tabs + workspaces**
controls (the replace tree, and the herdr portion of augment), the `i` **iTerm-splits
drill** for augment, and the live-list overlay **blocks** — then the pane **chips**.

Read the root `BRIEF.md`. Depends on leaves `herdr-backend-k2` and `variant-wiring-k3`
(backend + skeleton screens exist). herdr owns top-level `hjkl` (pane focus) in both
trees; augment = the herdr tree + the `i` drill.

## Decomposition (2 children)

Split at the natural seam between **mechanical modal-tree/list content** (well-trodden
iTerm idioms, JSON-verifiable) and the **chip geometry** (area-relative rects, needs
visual verification in the installed app — the same deferral leaf 3 made):

1. `herdr-controls-k9` — the herdr control surface as modal trees + list blocks, **no
   chips**: `build-herdr-tree` (panes focus/split/move/zoom/close/digit-jump + tabs +
   workspaces sub-screens), `blocks/herdr-{panes,tabs,workspaces}.{sld,js,css}` (row
   lists + digit dispatch, focused marker), the `i`-drill zoom, config splice, tests.
2. `herdr-pane-chips-k10` — `blocks/herdr-panes.sld` gains the `'chips?` path: rects
   from `herdr pane layout` (tmux-style, area-relative), painted via `hints-show` in
   **replace** mode; the augment-mode wrong-split limitation **documented** (the proper
   fix — a focused-iTerm-session-frame primitive — stays the optional deferred leaf).

## Load-bearing findings (validated live against the user's herdr-in-iTerm, k4 session)

- **Universal pane focus is already solved.** `herdr agent focus <pane_id>` focuses
  **any** pane by id — verified p1/p2/p3 cross-tab — returning a cosmetic
  `agent_not_found` for a non-agent pane but **still focusing it** (the focus
  side-effect fires before the agent-resolution error). So leaf 2's worry ("harmless
  no-op on a shell pane → digit-jump only agent-correct") is **wrong**: digit-jump as
  shipped in leaf 2 already works on every pane. No `pane neighbor` geometric walk
  needed. `herdr tab focus <tab_id>` / `workspace focus <id>` are clean (no cosmetic
  error) and are the right primitives for the tabs/workspaces blocks.
- **herdr JSON shapes** (compact single-line; parse with `(modaliser json)`):
  - `pane list` → `result.panes[]`: `pane_id` (`w9:p1`), `focused` (bool), `agent`
    (opt, e.g. `"claude"`), `agent_status` (idle/working/blocked/unknown), `cwd`,
    `tab_id`, `workspace_id`.
  - `tab list` → `result.tabs[]`: `tab_id` (`w9:t1`), `label` (`"1 claude"`),
    `number`, `focused`, `pane_count`, `agent_status`, `workspace_id`.
  - `workspace list` → `result.workspaces[]`: `workspace_id` (`w9`), `label`
    (`"TestAnyware"`), `number`, `focused`, `tab_count`, `pane_count`, `active_tab_id`.
  - `pane layout` → `result.layout`: `area` `{x,y,width,height}` (x≥26: herdr's left
    sidebar offsets the canvas — the area-relative offset for chips), `focused_pane_id`,
    `panes[]` (`pane_id`, `rect {x,y,width,height}`, `focused`), `splits[]`, `zoomed`.
- **Pane vs tab model.** A tab holds ≥1 pane; `pane layout` shows only the *current
  tab's* splits. In the user's current layout each tab has exactly one pane, so its
  three "panes" are really three tabs — digit-jump over panes must therefore focus by
  `pane_id` (cross-tab safe via `agent focus`), not assume same-tab splits.

## CLI surface (mutating ops for the tree content)

- Panes: `pane split --current --direction right|down --focus`; left/up = split-then-swap
  (leaf 2, race-free); `pane swap --direction <dir> --current` (move); `pane zoom
  --current --toggle`; `pane close <pane_id>`; focus by id via `agent focus <pane_id>`.
- Tabs: `tab focus <id>`, `tab create [--focus]`, `tab rename <id> <label>`,
  `tab close <id>`.
- Workspaces: `workspace focus <id>`, `workspace create [--focus]`, `workspace rename
  <id> <label>`, `workspace close <id>`.
- All PATH-prefixed (`/opt/homebrew/bin`; GUI Modaliser has minimal PATH).

## Pointers

- Mirror layout idioms in `app-trees/com.googlecode.iterm2.scm` (panels, `sticky-set`,
  `open` drills) and the block shape in `blocks/iterm-{panes,tabs}.*` (+ the shared
  `on-render-fn` protocol, `cursor-targets-fn`/`cursor-initial-index-fn` for the
  selection cursor). herdr blocks are **simpler** — JSON gives id + focused + label
  directly, no AX walk / UUID correlation / fallback labels.
- `i` drill helper `iterm:build-iterm-splits-drill` already exists (leaf 3); it needs
  the zoom key added (iterm-direct `toggle-pane-zoom`).
- Config sync: user `~/.config/modaliser/` ↔ bundled `Sources/Modaliser/Scheme/`
  ([[feedback_config_sync]]).

## Done when

- Replace tree drives herdr panes/tabs/workspaces; augment adds the `i` iTerm-splits
  drill; both usable live from Modaliser. Blocks render live lists with working
  digit-jump; pane chips correct in replace mode. `swift test` +
  `check-portable-surface.sh` green.
