# Terminal-backends abstraction — PRD

**Status:** proposed (awaiting implementation).
**Phase 1 (merged):** per-backend recipes documented in
`docs/reference/terminal-detection.md` and `docs/how-to/terminal-pane-
aware-tree.md`.
**Phase 2 (this PRD):** lift those recipes into Scheme modules behind a
uniform abstraction.

## Why

Today, Modaliser ships pane-aware bindings only for iTerm2
(`(modaliser apps iterm)`). The behaviour users get from the iTerm
module — focus/split/move panes with hjkl, chip-overlay digit jump,
context-aware tree variants — is general-purpose and should work the
same way against WezTerm, Kitty, Ghostty, tmux, and zellij. Until
this PRD ships, every non-iTerm user has to assemble recipes by
hand from the Phase 1 docs.

## Scope

### In

A **single uniform surface** of 13 operations + 1 detection primitive,
implemented per-backend, callable in two ways:

**Operations (13):**

- `focus-pane-{left,right,up,down}` — move keyboard focus to an
  adjacent pane.
- `split-pane-{left,right,up,down}` — create a new pane in the named
  direction, focus follows.
- `move-pane-{left,right,up,down}` — swap the focused pane with its
  directional neighbour.
- `focus-pane-by-digit` — paint a digit chip on each pane via
  `hints-show`; selecting digit *N* focuses pane *N*.

**Detection primitive (1):**

- `detect-foreground-command` — the command currently running in the
  focused pane (typically `bash` / `zsh` / `nvim` / `tmux` / `zellij`
  / etc.). Drives the existing `set-local-context-suffix!` flow that
  selects a variant tree per context.

### Deferred (out of scope)

- `close-pane`, `resize-pane`, `zoom-pane`, `rotate-panes` — surface
  isn't locked yet; users can already invoke these via raw keystrokes.
- Cross-host pane control over SSH.
- Swift-side changes — Phase 2 is Scheme + shell only.
- Multi-session disambiguation for tmux / zellij — single-session-per-
  host is the documented common case; multi-session is treated as
  undefined behaviour.

## Backends

| Backend          | Type             | Detection | 13-op surface | Prerequisite / gate | One-line summary |
|------------------|------------------|:---------:|:-------------:|---------------------|------------------|
| iTerm2           | host, splits     | ✓ AppleScript + `ps` | **13/13** | — (defaults work; `(iterm:configure-entry)` provisions split/move keybinds the user's plist may lack) | Baseline; reference implementation. Keystroke-proxy ops + AX-discovered chip geometry. |
| WezTerm          | host, splits     | ✓ `wezterm cli list --format json` (`tty_name`, `is_active`) | **12/13** (no `move-pane`) | mux-server installed by the cask; `--prefer-mux` works for headless ops | Cleanest CLI surface of any host. JSON exposes per-pane cell + pixel dims directly — no chip-geometry derivation. |
| Kitty            | host, splits     | ✓ `kitty @ ls` (`foreground_processes`) | **13/13** (with compose-then-move for `split-pane-{left,up}`) | `allow_remote_control yes` in `kitty.conf`; `enabled_layouts` must include `splits` | Full ops via `kitty @` IPC. Chip-geometry has a gap — `ls` JSON does not expose per-pane cell offsets, so topology is BFS'd from `neighbors`. |
| Ghostty 1.3.0+   | host, splits     | ✓ AppleScript (`focused terminal of selected tab of front window`) | **12/13** (no `move-pane` — same gap as WezTerm) | Ghostty ≥ 1.3.0 (brew's 1.3.1 already qualifies) | AppleScript-driven: `split direction <dir>`, `focus <terminal>`, `perform action "<keybind>" on <terminal>`. The `perform action` boolean return doubles as a free adjacency probe. |
| Ghostty < 1.3.0  | host             | external (AX walk / process tree) | detection only | — | No AppleScript surface; treat as detection-only. Users add a mux for splits. |
| tmux             | mux              | ✓ `display-message -p '#{pane_current_command}'` | **13/13** | tmux running in a host terminal's pane | Format-string CLI is the cleanest probe pattern of any backend. `swap-pane -t '{left-of}'` &c gives all four moves. |
| zellij           | mux              | ✓ `action list-panes -j -a` (filter `is_focused`, `!is_plugin`, `!is_floating`) | **13/13** | zellij running in a host terminal's pane | `zellij action` CLI exposes the full surface. Pane IDs are sparse — treat as opaque. First-run "About Zellij" floating plugin must be filtered. |
| Alacritty 0.17.0 | host, no splits  | external (process tree; AX for multi-window) | not applicable | brew cask install needs `xattr -d com.apple.quarantine /Applications/Alacritty.app`, or use the direct GitHub-releases DMG | Detection-only by design. `alacritty msg` exists but is window-mgmt only; no AppleScript SDEF. Users add a mux inside for the 13-op surface. |

### Capability spectrum

The 13-op surface is uniformly defined; backends populate what they
can:

- **Full (13/13):** iTerm2, Kitty, tmux, zellij.
- **Partial (12/13, missing `move-pane`):** WezTerm, Ghostty 1.3.0+.
  Workarounds documented per-backend (keystroke-proxy via user
  config); not enforced by the abstraction.
- **Detection-only (0/13):** Alacritty (always), Ghostty < 1.3.0
  (legacy). The detection primitive is always supplied.

## Abstraction shape

### Two binding styles, both first-class

Phase 2 is **purely additive** to the Phase 1 iTerm pattern. Users
get two valid wiring styles and can mix them in the same config:

**Explicit** (Phase 1 pattern, preferred when different *trees* are
wanted per context):

```scheme
(import (prefix (modaliser apps iterm) iterm:)
        (prefix (modaliser muxes tmux) tmux:))

(set-leader! 'normal "Space")
(set-local-context-suffix! iterm:context-suffix-handler)

;; iTerm-context tree
(define-tree
  ("h" "Focus left" (iterm:focus-pane-left))
  ;; ... etc.
  )

;; iTerm+tmux context tree (different bindings entirely)
(define-tree "/tmux"
  ("h" "Focus left" (tmux:focus-pane-left))
  ;; ... etc.
  )
```

**Implicit** (Phase 2 new, preferred when one tree should work
across all backends):

```scheme
(import (prefix (modaliser pane) pane:))

(define-tree
  ("h" "Focus left" (pane:focus-pane-left))
  ;; ... etc.
  )
```

`(pane:focus-pane-left)` resolves `(active-backend)` at call time
(probes frontmost-app + `detect-foreground-command`) and routes to
the right backend's `focus-pane-left`. One tree, works under
`iTerm`, `iTerm+tmux`, `Alacritty+zellij`, …

### Decisions locked

| # | Decision | Where |
|---|----------|-------|
| 1 | Mechanism: per-backend named modules **+** additive `(modaliser pane)` façade | [ADR-0001](../adr/0001-terminal-backends-named-modules-with-facade.md) |
| 2 | Naming: keep direction-words (`focus-pane-left`, not `focus-pane-h`) | [ADR-0002](../adr/0002-terminal-backends-keep-direction-word-procedure-names.md) |
| 3 | Surface as one `<terminal-backend>` record with **nullable op fields**; `detect-foreground-command` always populated | (see "Backend record" below) |
| 4 | Mux-inside-host composition: both **explicit** (existing) and **implicit** (façade) supported | (see "Two binding styles" above) |

### Backend record

```scheme
(define-record-type <terminal-backend>
  (make-terminal-backend bundle-id name
                         detect-foreground-command
                         focus-pane-left focus-pane-right
                         focus-pane-up focus-pane-down
                         split-pane-left split-pane-right
                         split-pane-up split-pane-down
                         move-pane-left  move-pane-right
                         move-pane-up    move-pane-down
                         focus-pane-by-digit)
  terminal-backend?
  ;; accessors elided
  )
```

- `detect-foreground-command` is always a procedure (every backend
  has detection — that's the floor).
- The 13 op fields are procedures **or `#f`** when unsupported.
- The façade does `(or (terminal-backend-focus-pane-left b) (error 'unsupported))`.

### Module layout

```
(modaliser pane)                  -- new: façade + active-backend resolver + backend registry
(modaliser apps iterm)            -- existing
(modaliser apps wezterm)          -- new
(modaliser apps kitty)            -- new
(modaliser apps ghostty)          -- new
(modaliser apps alacritty)        -- new (detection-only)
(modaliser muxes tmux)            -- new (subdir keeps mux vs host visible)
(modaliser muxes zellij)          -- new
```

Each `apps/*` and `muxes/*` module exports:

- The 13 op procedures (direction-words; `#f` if the backend lacks
  the op).
- `detect-foreground-command`.
- `backend` — the populated `<terminal-backend>` record.
- `register!` — installs the dispatch entry in `(modaliser pane)`'s
  registry, and (optionally, controlled by an `'install-context-
  suffix? <bool>` keyword) installs a `set-local-context-suffix!`
  handler keyed by the backend's bundle-id.

### `(active-backend)` resolution

1. Frontmost-app bundle-id → host backend record from the registry.
2. Host backend's `detect-foreground-command` returns the focused-
   pane fg command.
3. If that command matches a registered mux backend's command-name
   field (`"tmux"`, `"zellij"`), the mux backend overrides the host
   for the 13-op surface. The detection primitive always returns
   from the most-specific backend that can serve it (mux beats host
   when a mux is present).

Host backends without splits (`Alacritty`; `Ghostty < 1.3.0` if
treated as detection-only) supply `#f` for the 13 ops — the façade
only succeeds for the 13 ops when a splitting backend (the inside-
mux or a splitting host) is in scope.

### Chip rendering

Chips are **always native macOS overlay windows** drawn by
`(modaliser hints)` `hints-show` (per glossary "Chip"). Each
backend's `focus-pane-by-digit` is responsible for producing the
list of `(label, screen-rect)` pairs that `hints-show` consumes.
Rendering itself is uniform; geometry derivation differs:

| Backend | Rect derivation |
|---------|-----------------|
| iTerm   | AX subview frames directly (`ax-find-elements-named ... AXScrollArea AXStaticText`) |
| WezTerm | window AX frame + per-pane `left_col/top_row` + cell-pixel dims from `list --format json` (`pixel_width/cols`, `pixel_height/rows`) |
| Kitty   | window AX frame + topology BFS from `kitty @ ls neighbors` + derived cell-pixel dims (best-effort; AX-subview discovery is the better path if available) |
| Ghostty | window AX frame + (AX subviews if available, else `perform action goto_split:<dir>` adjacency probe) + derived cell dims |
| tmux    | host AX frame + host cell-pixel dims + tmux `pane_left/pane_top/pane_width/pane_height` |
| zellij  | host AX frame + host cell-pixel dims + zellij `pane_x/pane_y/pane_columns/pane_rows` from `list-panes -j -a` |
| Alacritty | n/a (no panes; the inside-mux backend's chips are used) |

The shared concern is **host cell-pixel-dim derivation** when the
host doesn't expose cell dims directly (iTerm, Kitty, Ghostty). A
helper `(host-cell-pixel-dims bundle-id window-id)` lands in
`(modaliser pane)` (exact location TBD at implementation time);
each backend's `focus-pane-by-digit` calls it as needed.

## Known limitations

### Per-backend gaps the abstraction does not paper over

- **WezTerm / Ghostty 1.3.0+ — no `move-pane`.** The CLI / AppleScript
  surface lacks a swap-with-neighbour-in-direction op. The
  abstraction's record sets these fields to `#f`. Users wanting move-
  pane can configure keybinds in `wezterm.lua` / `~/.config/ghostty/
  config` and bind keystroke-proxy procedures themselves; a backend-
  level "configure-entry" analogue (parallel to iTerm's) is future work.
- **Kitty `split-pane-{left,up}`.** Kitty's `launch --location` only
  supports `vsplit` (right) and `hsplit` (below). Left/up splits are
  implemented as `launch --location=vsplit/hsplit` followed by
  `action move_window left/up`. Two CLI calls instead of one; result
  is identical.
- **Kitty chip geometry.** `kitty @ ls` does not expose per-pane cell
  offsets — only the `neighbors` adjacency graph and per-pane
  `columns/lines`. The abstraction does a BFS over `neighbors` to
  reconstruct a grid; chip positions are approximate within a
  cell-width. AX-subview discovery on `kitty.app` would obviate
  this; not verified yet.
- **Ghostty chip geometry.** AppleScript does not expose per-terminal
  position or size. AX-subview discovery on `Ghostty.app` is the
  cleanest path (untested); the fallback is BFS via `perform action
  goto_split:<dir>` adjacency probes — many AppleScript calls per
  render.
- **Ghostty `working directory` race.** Querying `working directory`
  immediately after `split` returns `""`; the cwd populates after
  the underlying shell emits its first prompt. The Ghostty backend
  must retry-on-empty or wait.
- **Ghostty `terminal.name` is whatever set the title last.** Default
  Ghostty shows the cwd; right after `split` it can show `👻` until
  shell init runs. Detection via `name` is unreliable on its own.
- **Alacritty multi-window focus disambiguation.** Multiple Alacritty
  windows in one process (after `alacritty msg create-window`) share
  a parent pid. Without AX (TCC-required) there is no clean way to
  identify which window is focused. Single-window is the well-
  supported case; multi-window detection falls back to AX or an
  "activity proxy" (most-recently-active pty).
- **tmux / zellij multi-session.** When more than one tmux or zellij
  session is running inside different host panes, correlating "which
  client am I" requires walking `lsof` of the client process to find
  its controlling tty. Not implemented — single-session-per-host is
  the documented behaviour.

### Cross-cutting

- **Host cell-pixel-dim derivation.** Required for muxes (tmux/zellij)
  hosted in iTerm/Kitty/Ghostty and for the host backends that don't
  expose cell dims natively. Sub-pixel rounding, font hinting,
  ligatures, and retina scaling all introduce approximation. Chip
  positions can be off by a few pixels; the digit always lands
  inside the right pane, which is the operative requirement.
- **iTerm window-padding.** The gap between the iTerm window edge
  and the first cell is not exposed by AX or AppleScript. Treated as
  a small constant per host terminal; users can override.

## Migration and compatibility

### What does NOT change

- The existing `(modaliser apps iterm)` module keeps all its current
  exports (`focus-pane-left`, `split-pane-right`, etc.) with the
  same semantics.
- The existing `set-local-context-suffix!` flow continues to work.
- The user's `config.scm:157-176` bindings (12 pane procedures × ~20
  call sites) keep working untouched.

### What is new

- New libraries `(modaliser apps {wezterm,kitty,ghostty,alacritty})`
  and `(modaliser muxes {tmux,zellij})`, each following the
  iTerm-module conventions.
- New façade library `(modaliser pane)` exporting the 13 ops + a
  registry of backends.
- The `<terminal-backend>` record type and constructor (probably
  exported from `(modaliser pane)`).

### Breaking changes

**None planned.** Phase 2 is additive. ADR-0002 explicitly rejects
the hjkl rename to preserve the user's existing bindings.

If a future ADR adds hjkl aliases (e.g. `focus-pane-h`), they will
be exposed by the façade, not by replacing the direction-word names
on the backends.

### Phase 1 docs

Two phase-1 documents have stale claims that should be updated when
this PRD is implemented:

- `docs/reference/terminal-detection.md` — "zellij has no per-pane
  tty or command query" is wrong for zellij 0.44.x; "Alacritty has
  no IPC" is wrong as of 0.12+ (`alacritty msg` exists, even though
  it's window-mgmt only).
- `docs/reference/terminal-detection.md` — Ghostty section is
  written against pre-1.3.0; AppleScript surface added in 1.3.0
  should be documented.

These edits land alongside the implementation, not before.

## Future work

Out of scope for this PRD, captured for traceability:

- **Pane lifecycle ops:** `close-pane`, `resize-pane`, `zoom-pane`,
  `equalize-panes`, `rotate-panes`.
- **`configure-entry` parallel for non-iTerm backends.** WezTerm,
  Kitty, and Ghostty all need user-side config for some operations
  (move-pane keybinds for WezTerm/Ghostty; `allow_remote_control` +
  `enabled_layouts=splits` for Kitty). A one-shot overlay action
  parallel to `(iterm:configure-entry)` would surface this to users.
- **Cross-host (SSH) pane control.** Requires either a remote
  Modaliser agent or backend-specific tunnelling (tmux's
  `-CC` mode, mosh, etc.).
- **Multi-session tmux/zellij.** Client-to-tty correlation via
  `lsof` walking. Currently treated as undefined behaviour.
- **Ghostty `move_split`.** If Ghostty adds a `move_split` keybind
  action upstream, `(ghostty:move-pane-left)` and friends become
  one-line additions via `perform action "move_split:<dir>"`.
- **AX-subview discovery for Kitty and Ghostty.** Would obviate the
  topology-BFS chip-geometry paths and bring them up to iTerm parity.
- **Phase 1 doc updates.** Mentioned in "Migration" above.

## References

- [ADR-0001 — Per-backend named modules with additive façade](../adr/0001-terminal-backends-named-modules-with-facade.md)
- [ADR-0002 — Keep direction-word procedure names](../adr/0002-terminal-backends-keep-direction-word-procedure-names.md)
- Phase 1 reference: `docs/reference/terminal-detection.md`
- Phase 1 how-to: `docs/how-to/terminal-pane-aware-tree.md`
- Phase 1 spec: `docs/superpowers/specs/2026-05-22-terminal-pane-and-remote-docs-design.md`
- Existing implementations:
  - `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
  - `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`
  - `Sources/Modaliser/Scheme/lib/modaliser/blocks/iterm-panes.sld`
- Glossary: `CONTEXT.md` (terms `Pane`, `Backend`, `Splitting backend`,
  `Detection-only backend`, `Chip`, `Suffix hook`).
