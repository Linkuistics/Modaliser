# add-herdr-in-iterm-controls — brief

Add **herdr** modal controls to Modaliser, in the manner of the existing iTerm /
tmux / zellij terminal controls. This brief is the grove's design charter — every
leaf reads it. Detailed grilling rationale (D1–D10, R1–R11) is in the retired
`01-DONE-plan-k1.md`; the load-bearing conclusions are promoted here.

## What herdr is

`herdr` (herdr.dev, v0.7.1, `/opt/homebrew/bin/herdr`) — an "agent multiplexer that
lives in your terminal": a client/server TUI run **inside** a host terminal (the user
runs it in **iTerm**), no GUI/Electron. Manages **workspaces → tabs → panes**, git
**worktrees**, and is **agent-aware** (per-pane `agent_status`
idle/working/blocked/unknown). See `CONTEXT.md` "Terminal-pane domain" for the
glossary (herdr, workspace, worktree, agent status, replace tree / augment tree).

Control surface = a **JSON socket-API CLI** (drive via PATH-prefixed `run-shell`,
parse JSON — *not* keystrokes/AppleScript):
- `herdr pane focus|swap --direction left|right|up|down`; `herdr pane split
  --direction right|down [--focus]` (left/up = split down/right `--focus` then
  `swap`, targeting the **pane_id returned by split** to avoid a race); `herdr pane
  zoom --toggle`, `close <id>`, `list`, `current`, `layout`, `process-info`.
- `herdr tab list|create|focus|rename|close`; `herdr workspace …`; `herdr worktree …`;
  `herdr agent …`.
- IDs `w<N>:p<M>` / `w<N>:t<M>` / `w<N>`. herdr emits **compact single-line** JSON
  (zellij's multiline awk parser does NOT transfer — needs a net-new compact/nested
  extractor; check for an existing portable JSON helper first).

## The design (the core requirement)

**Context-sensitive tree composition inside the iTerm tree.** On each local-leader
press the iTerm context-suffix hook picks a variant tree by the herdr situation in the
frontmost iTerm window:
- **Replace** (`/herdr`) — herdr is the **sole** iTerm split in the current tab →
  a **herdr-only** tree (zero iTerm controls; herdr owns the whole window).
- **Augment** (`/herdr+split`) — the focused iTerm pane runs herdr but the current tab
  has **other** iTerm splits → the herdr tree **plus an `i` drill** for iTerm splits.
- (No herdr → today's plain `com.googlecode.iterm2` tree, unchanged.)

**herdr owns the top-level `hjkl`** (pane focus) in *both* trees → identical muscle
memory; augment = replace tree + the `i` iTerm-splits drill.

**Surface (all of herdr):** panes (focus/split/move/zoom/close/digit-jump), tabs,
workspaces — then agents (status + jump-to-blocked) and worktrees as their own leaves.

## Architecture (how it slots in)

- `(modaliser terminal)` façade: `<terminal-backend>` record + host→mux
  `focused-terminal-path` walk. Register herdr as a **`'mux`** backend (match-key
  `"herdr"`) for detection completeness (`in-chain? 'herdr`, generic capability
  trees). BUT the herdr variant trees bind **backend-DIRECT** ops, never the façade:
  when the focused iTerm pane runs herdr the façade's `active-backend` resolves to
  herdr, so façade ops would drive the wrong layer in augment mode. iTerm-splits drill
  = **iterm-direct** ops; herdr = **herdr-direct** ops.
- Keep the library export surface small: herdr.sld exposes **tree-builders** (using
  ops internally), `register!`, `backend`, context-suffix contribution, block helpers
  — mirroring `apps/iterm.sld`'s internal `rebuild-tree!`. Not dozens of named ops.

## Load-bearing risks — VALIDATED (herdr-backend-k2, live herdr-in-iTerm client)

1. **CONFIRMED.** An iTerm pane running the herdr *client* reports tty foreground
   command `herdr` → the mux match-key `"herdr"` resolves it; detection approach holds.
2. **CONFIRMED (single-client).** `herdr pane current` answers from the server's
   *global* focus and reflects the sole client's focused pane (answers even with no
   client attached).
3. **RESOLVED.** The socket API scopes **per session (per socket)**, NOT per client /
   tty — so **multi-herdr-client-on-one-session is a documented v1 non-goal** (common
   case = one client, unambiguous). No tty correlation needed for herdr.
   Detail + the "no universal focus-pane-by-id" follow-up (→ leaf 4) in the
   `herdr-backend-k2` leaf Notes and the `muxes/herdr.sld` header.

Corrections the adversarial review forced (details R1–R11 in the plan leaf):
- **Classifier = current-tab session count via AppleScript**, NOT `ax-find-elements`
  AXScrollArea count (which spans all tabs). == 1 → replace, > 1 → augment.
- iTerm-direct pane ops are **not exported** from `apps/iterm.sld` today (internal
  defines) — export them / add a splits-drill helper.
- Variant-tree lookup has **never been exercised in production** (no `/nvim`,
  `/zellij` screen is registered in the shipping config); herdr is the first real
  user. Config must switch to `(iterm:register! 'install-tree? #f
  'install-context-suffix? #f)` + a composed `set-local-context-suffix!` delegating
  the iTerm branch to `iterm:context-suffix-handler`. Test that lookup *resolves*.
- Chip rects: tmux-style (herdr `pane layout` cell coords ÷ canvas × iTerm session AX
  frame) — **area-relative** (herdr paints a left sidebar; canvas `area` is offset).
  Correct in replace mode; **augment-mode chips target the wrong split** (the `(car
  panes)` soft spot) — documented v1 limitation until a focused-session-frame
  primitive lands.

## Validated live (promoted from the retired herdr-tree-content-k4 node)

Findings from k9/k10, kept here for the agents / worktrees / docs siblings (their
brief chain is this root only). Full detail lives in the `muxes/herdr.sld` /
`blocks/herdr-list.sld` headers and the retired `04-herdr-tree-content-k4/BRIEF.md`.

- **`herdr agent focus <pane_id>` is a UNIVERSAL cross-tab pane focus** (not agent-
  only): it focuses ANY pane by id; on a bare shell pane it also emits a cosmetic
  `agent_not_found`, but the focus fires first. So jump-to-blocked (k5) and digit-
  jump both focus by id — no `pane neighbor` geometric walk needed. `tab focus <id>`
  / `workspace focus <id>` are clean (no cosmetic error).
- **JSON shapes (compact single-line; parse with `(modaliser json)`).** `pane list`
  → `result.panes[]` (`pane_id`, `focused`, `agent` opt, `agent_status`
  idle/working/blocked/unknown, `cwd`, `tab_id`, `workspace_id`); `tab list` /
  `workspace list` similar with a `label`; `pane layout` → `result.layout` (`area`
  `{x,y,width,height}` with `x≥26` sidebar offset, `panes[].rect`, `focused_pane_id`,
  `zoomed`). `agent_status` (k5's core datum) rides on each `pane list` row.
- **Pane vs tab model.** A tab holds ≥1 pane; `pane layout` shows only the *current
  tab's* splits, while `pane list` spans all tabs — so anything keyed to on-screen
  panes (chips) is a subset of the full pane list, matched by `pane_id`.
- **Chips are replace-mode-correct only.** Augment-mode chips may target the wrong
  split (first-`AXScrollArea` soft spot); documented, deferred to a focused-iTerm-
  session-frame primitive. hjkl focus + digit-jump work in both modes.
- **Worktrees surface (k6, done) — settled shape + v1 boundaries** (for the docs
  k7 / live-verify k11 siblings). Top-level `open "g" "Worktrees"` drill (g = git
  worktree; w is Workspaces): digit → **smart-switch** (open worktree → `workspace
  focus <open_workspace_id>`; dormant → `worktree open --branch <b> --focus`); `n`
  New (prompt branch → `worktree create --branch <b> --focus`); `d` Remove the
  **focused** worktree behind an OK/Cancel confirm (default Cancel). All three
  **source-pinned** via `--workspace <focused-ws-id>` (from `pane current`).
  `worktree list` → `result.worktrees[]` (`branch`, `label`, `path`,
  `open_workspace_id` **only when open**) + `result.source.source_workspace_id`
  (the current row's key). **Deliberate v1 exclusions:** removing a *dormant*
  worktree (herdr keys remove on `--workspace`, so only open worktrees are
  removable via CLI); `--force` removal (no destroying uncommitted work by a
  keystroke); a base-ref / branch fuzzy picker for New; worktree **chips**
  (worktrees have no on-screen rect — the list *is* the visualization, like
  agents). Detail in the `muxes/herdr.sld` / `blocks/herdr-list.sld` headers and
  the retired `06-worktrees-surface-k6/BRIEF.md`.

## Done when

herdr controls are usable from Modaliser: backend + detection validated, variant trees
switch replace/augment correctly, panes+tabs+workspaces controls work, agents +
worktrees surfaces built, tests green (`swift test`, and `check-portable-surface.sh`
stays green — no `(lispkit …)` in `lib/modaliser`), docs/glossary/ADR updated.

## Decomposition (7 leaves; see per-leaf briefs)

1. herdr mux backend **+ detection validation (#1/#2/#3 first)** + JSON extractor.
2. Replace/augment classifier + variant-tree wiring + config compose + ADR-0013.
3. herdr tree content (panes/tabs/workspaces) + `i` iTerm drill + `blocks/herdr-*`.
4. Agents surface (planning+work) — agent-status UX.
5. Worktrees surface (planning+work) — worktree UX.
6. Docs + reference (+ PRD if earned).
7. Prune dangling terminal-backends ADR/PRD refs (pre-existing debt).
8. herdr-live-verify (k11) — one consolidated installed-app visual pass over the
   whole path (variant switch + controls + chips); added on the k4 retire because
   the on-screen check was deferred through leaves 3 / k9 / k10.

## Pointers

- Façade `lib/modaliser/terminal.sld`; mux models `muxes/{tmux,zellij}.sld`; host
  `apps/iterm.sld` + user config `app-trees/com.googlecode.iterm2.scm`.
- Variant trees: `docs/how-to/terminal-pane-aware-tree.md`; detection
  `docs/reference/terminal-detection.md`. Blocks `blocks/iterm-{panes,tabs}.*`.
- herdr CLI: `herdr pane|tab|workspace|worktree|agent --help`; socket
  `~/.config/herdr/herdr.sock`; `herdr --default-config` for its keybindings.
- Config sync: user `~/.config/modaliser/` ↔ bundled `Sources/Modaliser/Scheme/`
  (`default-config.scm` + `app-trees/`) — [[feedback_config_sync]].
- NOTE: the terminal-backends ADRs 0002–0008 and `docs/prd/terminal-backends.md`
  cited across the code **no longer exist** (deleted at that grove's finish); live
  ADRs are `0009`–`0012`, new ones are `docs/adr/0013-…`. Leaf 7 prunes the refs.
