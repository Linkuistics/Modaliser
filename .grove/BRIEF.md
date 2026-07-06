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

## Load-bearing risks — VALIDATE FIRST (leaf 1, needs a live herdr-in-iTerm client)

1. An iTerm pane running herdr reports tty foreground command `herdr` (the client) —
   drives all detection. *Unverified at planning (no client was attached).*
2. The herdr server's focused pane (`herdr pane current`) tracks the OS-focused iTerm
   client — drives targeting.
3. Does herdr's socket API scope **per client / tty / session**? If not, the
   multi-herdr-client augment case is a **documented v1 non-goal** (common case = one
   client, unambiguous); do not pretend it's merely deferred.

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
