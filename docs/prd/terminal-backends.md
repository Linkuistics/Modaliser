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

A **single uniform surface** of 14 operations + 1 structured detection
primitive, exposed from `(modaliser terminal)` as generic procedures.
The same procedures work whether the active backend is iTerm, WezTerm,
Kitty, Ghostty, tmux, or zellij (and in any mux-inside-host composition).

**Operations (14):**

- `focus-pane-{left,right,up,down}` — move keyboard focus to an
  adjacent pane.
- `split-pane-{left,right,up,down}` — create a new pane in the named
  direction, focus follows.
- `move-pane-{left,right,up,down}` — swap the focused pane with its
  directional neighbour.
- `focus-pane-by-digit` — paint a digit chip on each pane via
  `hints-show`; selecting digit *N* focuses pane *N*.
- `toggle-pane-zoom` — stateless zoom toggle on the focused pane
  (iTerm/WezTerm/tmux/zellij/Ghostty; not Kitty in v1).

**Detection primitive (1) — focused-terminal path:**

- `(focused-terminal-path)` — alist keyed by backend symbol, value
  is a 4-element vector `#(pane <pane-id> fg <fg-cmd>)`:

  ```scheme
  ;; iTerm with zellij inside, lazygit in the focused zellij pane
  '((iterm  . #(pane "uuid-A"     fg "zellij"))
    (zellij . #(pane "terminal_3" fg "lazygit")))

  ;; iTerm alone, nvim in the focused pane
  '((iterm . #(pane "uuid-B" fg "nvim")))
  ```

- `(focused-terminal-foreground-command)` — convenience: the leaf
  frame's `fg`. Backward-compatible alias for the most common use;
  drives the existing `set-local-context-suffix!` flow.
- `(in-chain? 'zellij)` — predicate; `#t` if `'zellij` is anywhere
  in the path. Useful for "if any mux is present" / "if any layer
  is nvim" handlers.

See [ADR-0008](../adr/0008-terminal-backends-focused-terminal-path.md)
for the structure rationale and its constraint (each backend
symbol appears at most once — nested muxes can't be represented
uniquely; matches typical usage).

**Capability predicates (5):**

- `(supports-splits?)` — `#t` if the active backend implements all 12
  focus/split/move ops.
- `(supports-move-pane?)` — `#t` if the 4 `move-pane-*` ops work.
- `(supports-digit-jump?)` — `#t` if `focus-pane-by-digit` works.
- `(supports-zoom?)` — `#t` if `toggle-pane-zoom` works.
- `(supports? 'focus-pane-left)` — universal introspection by op
  symbol.

**Provisioning (per backend, day-one):**

- `(<backend>:configure-entry)` — overlay action that performs any
  user-side configuration required for the backend to reach its full
  surface (keybinds, config-file edits). Where not needed, the
  backend omits this export.

### Deferred (out of scope)

- `close-pane`, `resize-pane`, `rotate-panes` — surface isn't locked
  yet; users can already invoke these via raw keystrokes.
- **SSH'd remote tmux/zellij.** When ssh is the focused-pane
  foreground command, the host backend serves the 14 ops (against
  the host pane); Modaliser does not reach into the remote.
  Cross-host pane control would require a remote agent or
  tmux `-CC` integration — separate design, future phase.
- Swift-side changes — Phase 2 is Scheme + shell only.

## Backends

| Backend          | Type             | Detection | 14-op surface (day-one)              | Zoom | configure-entry | One-line summary |
|------------------|------------------|:---------:|:-------------------------------------|:----:|:----------------|------------------|
| iTerm2           | host, splits     | ✓ AppleScript + `ps` | **14/14**                  | ✓    | ✓ existing — provisions split/move keybinds in plist | Baseline. Keystroke-proxy ops + AX-discovered chip geometry. |
| WezTerm          | host, splits     | ✓ `wezterm cli list --format json` | **14/14** *with configure-entry* (13/14 raw — no move-pane until provisioned) | ✓ via `TogglePaneZoomState` | ✓ writes move-pane keybinds to `wezterm.lua` (keystroke-proxy invokes them) | Cleanest CLI surface; JSON exposes per-pane cell + pixel dims directly. |
| Kitty            | host, splits     | ✓ `kitty @ ls` | **13/14** *with configure-entry* (0/14 raw — IPC refused without provisioning); no zoom | — | ✓ writes `allow_remote_control yes` and `enabled_layouts splits,...` to `kitty.conf` | Full directional ops via `kitty @` IPC. No native single-pane zoom. |
| Ghostty 1.3.0+   | host, splits     | ✓ AppleScript | **13/14** (no `move-pane`)             | ✓ via `perform action "toggle_split_zoom"` | — (no provisioning helps; `move_split` doesn't exist in vocabulary) | AppleScript-driven via `split direction <dir>`, `perform action`. `move-pane` blocked upstream. |
| Ghostty < 1.3.0  | host             | external (AX walk / process tree) | detection only        | —    | — | No AppleScript surface; users add a mux for splits. |
| tmux             | mux (local only) | ✓ `display-message -p '#{pane_current_command}'` | **14/14** | ✓ via `resize-pane -Z` | — (works out of the box) | Native format-string CLI; tty-correlated session targeting for multi-session-local. |
| zellij           | mux (local only) | ✓ `action list-panes -j -a` | **14/14**                | ✓ via `action toggle-fullscreen` | — (works out of the box) | `zellij action` CLI; tty-correlated session targeting. |
| Alacritty 0.17.0 | host, no splits  | external (process tree; AX for multi-window) | not applicable | —    | optional — removes `com.apple.quarantine` if installed via the brew cask | Detection-only by design. Users add a mux inside for the 14-op surface. |

## Abstraction shape

### One public surface

All 14 ops + detection + capability predicates are exported only from
`(modaliser terminal)`. The per-backend modules (`(modaliser apps
iterm)`, `(modaliser muxes tmux)`, …) become an **implementation
layer** — their public exports retain only inherently-backend-specific
procedures (e.g. `iterm:configure-entry`, `iterm:pane-list-block`,
`iterm:focus-mode-tree`, `<backend>:register!`). They no longer
export the 12 splits-tree procedures.

```scheme
(import (prefix (modaliser apps iterm) iterm:)
        (prefix (modaliser muxes tmux) tmux:)
        (prefix (modaliser terminal) terminal:))

(iterm:register!)              ; install iTerm dispatch entry
(iterm:configure-entry)        ; one-shot keybind provisioning (if not yet run)

(tmux:register!)               ; install tmux dispatch entry

;; Generic tree — works whether iTerm only, iTerm+tmux, Alacritty+zellij, etc.
(define-tree
  ("h" "Focus left" (terminal:focus-pane-left))
  ("j" "Focus down" (terminal:focus-pane-down))
  ("k" "Focus up"   (terminal:focus-pane-up))
  ("l" "Focus right"(terminal:focus-pane-right)))
```

### Capability predicates for cross-backend trees

Trees that span backends with different surfaces gate bindings via
predicates, evaluated when the tree is built:

```scheme
(define-tree
  ("h" "Focus left" (terminal:focus-pane-left))
  ;; ... focus/split bindings always present (every splitting backend has them)

  ;; Move-pane only when supported (WezTerm needs configure-entry first;
  ;; Ghostty 1.3.1 never; tmux/zellij/iTerm/Kitty always)
  ,@(if (terminal:supports-move-pane?)
        '(("M-h" "Move left"  (terminal:move-pane-left))
          ("M-j" "Move down"  (terminal:move-pane-down))
          ("M-k" "Move up"    (terminal:move-pane-up))
          ("M-l" "Move right" (terminal:move-pane-right)))
        '())

  ;; Digit jump only when supported (false for Alacritty alone with no mux)
  ,@(if (terminal:supports-digit-jump?)
        '(("g" "Goto pane" (terminal:focus-pane-by-digit)))
        '()))
```

**Predicates evaluate at tree-build time, not at keystroke time.**
Trees built via the existing `set-local-context-suffix!` rebuild-per-
press pattern see the current active backend's capabilities; static
trees built once at config load see load-time capabilities. Use
dynamic rebuild for cross-backend portability.

### Decisions locked

| # | Decision | Where |
|---|----------|-------|
| 1 | One public surface in `(modaliser terminal)`; per-backend modules are implementation layer | [ADR-0003](../adr/0003-terminal-backends-facade-only-public-surface.md) (supersedes [ADR-0001](../adr/0001-terminal-backends-named-modules-with-facade.md)) |
| 2 | Direction-word procedure names (`focus-pane-left`, not `focus-pane-h`) | [ADR-0002](../adr/0002-terminal-backends-keep-direction-word-procedure-names.md) |
| 3 | Capability predicates: `supports-splits?`, `supports-move-pane?`, `supports-digit-jump?`, `supports-zoom?`, `supports?` | [ADR-0004](../adr/0004-terminal-backends-capability-predicates.md) |
| 4 | configure-entry per backend **from day one** wherever provisioning closes a gap | [ADR-0005](../adr/0005-terminal-backends-configure-entry-day-one.md) |
| 5 | Multi-session local muxes via tty correlation; SSH'd remote muxes explicitly out of scope | [ADR-0006](../adr/0006-terminal-backends-multi-session-and-ssh.md) |
| 6 | `toggle-pane-zoom` is part of the op surface; capability-gated for backends without zoom (Kitty in v1) | [ADR-0007](../adr/0007-terminal-backends-pane-zoom-in-op-surface.md) |
| 7 | `(focused-terminal-path)` returns an alist keyed by backend symbol with `#(pane <id> fg <cmd>)` vector values | [ADR-0008](../adr/0008-terminal-backends-focused-terminal-path.md) |

### Backend record (internal)

The `<terminal-backend>` record stays internal to `(modaliser
terminal)`. Each backend module exports its populated record via its
`register!`; the façade module aggregates them in a registry and
dispatches per `(active-backend)`.

```scheme
;; In (modaliser terminal) — not exported beyond the façade machinery
(define-record-type <terminal-backend>
  (make-terminal-backend bundle-id name
                         detect-foreground-command
                         focused-pane-id      ; for path construction
                         focus-pane-left focus-pane-right
                         focus-pane-up focus-pane-down
                         split-pane-left split-pane-right
                         split-pane-up split-pane-down
                         move-pane-left  move-pane-right
                         move-pane-up    move-pane-down
                         focus-pane-by-digit
                         toggle-pane-zoom
                         configured?)
  terminal-backend? ...)
```

- `detect-foreground-command`, `focused-pane-id`, and `configured?`
  always populated.
- 14 op fields may be `#f` when unsupported (capability predicates
  read these).
- `configured?` returns `#t` once configure-entry's prerequisites
  are satisfied; capability predicates AND it with op-presence so
  bindings appear only after provisioning runs.

### `(active-backend)` resolution

```
1. frontmost-app bundle-id → host backend (from registry).
2. host backend's `detect-foreground-command` → focused-pane fg cmd.
3. Dispatch:
     "tmux"   → tmux backend (CLI mode; tty-correlated session for
                multi-session-local).
     "zellij" → zellij backend (CLI mode; tty-correlated session).
     other    → host backend (direct ops if it supports splits;
                detection-only otherwise). "ssh", "bash", "zsh",
                "nvim", etc. all land here — Modaliser drives the
                host pane, not whatever's inside it.
```

The detection primitive always returns from the most-specific backend
that can serve it (the active local mux beats the host when one is
present).

### Module layout

```
(modaliser terminal)              -- existing module, extended:
                                     focused-terminal-path + 14 ops
                                     + capability predicates
                                     + active-backend resolution
                                     + multi-session-local tty correlation

(modaliser apps iterm)            -- existing; loses splits-tree
                                     exports; keeps configure-entry,
                                     pane-list-block, focus-mode-tree,
                                     register!
(modaliser apps wezterm)          -- new; configure-entry, register!,
                                     internal backend record
(modaliser apps kitty)            -- new; configure-entry (kitty.conf
                                     edit), register!
(modaliser apps ghostty)          -- new; register! (no configure-entry
                                     until upstream adds move_split)
(modaliser apps alacritty)        -- new; optional configure-entry
                                     (quarantine removal), register!
(modaliser muxes tmux)            -- new; register!, internal record;
                                     local-CLI implementation with
                                     multi-session tty correlation
(modaliser muxes zellij)          -- new; analogous to tmux
```

### Chip rendering

Chips are **always native macOS overlay windows** drawn by
`(modaliser hints)` `hints-show` (per glossary "Chip"). Each
backend's `focus-pane-by-digit` produces the list of
`(label, screen-rect)` pairs that `hints-show` consumes.

| Backend         | Rect derivation |
|-----------------|-----------------|
| iTerm           | AX subview frames directly |
| WezTerm         | window AX frame + per-pane `left_col/top_row` + cell-pixel dims from `list --format json` |
| Kitty           | window AX frame + topology BFS from `kitty @ ls neighbors` + derived cell dims |
| Ghostty         | window AX frame + (AX subviews if available, else adjacency-probe BFS) + derived cell dims |
| tmux            | host AX frame + host cell-pixel dims + tmux `pane_left/pane_top/pane_width/pane_height` |
| zellij          | host AX frame + host cell-pixel dims + zellij `pane_x/pane_y/pane_columns/pane_rows` |
| Alacritty       | n/a — no panes |

Host cell-pixel-dim derivation (for iTerm, Kitty, Ghostty) is the
cross-cutting concern, factored into a helper in `(modaliser
terminal)`.

## Known limitations

### Gaps the abstraction surfaces honestly via predicates

- **Ghostty 1.3.0+ `move-pane`.** Action doesn't exist in vocabulary;
  `(supports-move-pane?)` is `#f` until upstream adds `move_split`.
- **Alacritty alone (no mux).** All 14 ops are `#f`;
  `(supports-splits?)` is `#f`. Users add a mux inside for the surface.
- **Kitty zoom.** No native single-pane zoom; `(supports-zoom?)`
  returns `#f`. Generic zoom bindings simply omit on Kitty.
- **SSH'd remote muxes.** When the focused-pane fg cmd is "ssh", the
  abstraction treats it as host-pane context — the host backend
  serves ops against the host pane, not the remote. Users navigate
  remote muxes with the remote's own keybindings.

### Detection-quality compromises

- **Kitty chip geometry.** `kitty @ ls` exposes `neighbors` topology
  + per-pane `columns/lines` but not absolute cell offsets. BFS
  reconstructs a grid; chip positions are approximate within a
  cell-width. AX-subview discovery on `kitty.app` would obviate
  this; not verified yet.
- **Ghostty chip geometry.** AppleScript exposes no per-terminal
  position/size. AX-subview discovery is the cleanest path
  (untested); the fallback is BFS via `perform action goto_split:
  <dir>` adjacency probes — many AppleScript calls per render.
- **Ghostty `working directory` race.** Querying immediately after
  `split` returns `""` until the shell emits its first prompt. The
  Ghostty backend retries-on-empty.
- **Alacritty multi-window focus.** Multiple windows in one process
  share a parent pid. Without AX (TCC-required) there is no clean
  way to identify which window is focused. Single-window is the
  well-supported case.

### Multi-session resolution

Local multi-session (multiple local tmux/zellij clients in different
host panes) resolves via tty correlation:

1. Focused iTerm pane's controlling tty (existing `focused-iterm-tty`).
2. `pgrep -f '^tmux '` (or `zellij`) + `lsof -p <pid> -d 0` for each.
3. Match the mux client whose tty matches the focused pane.
4. Target CLI commands at that client/session.

This is implementation-tractable from the per-backend notes; the
"hacky/deferred" classification in those notes is overridden by ADR-
0006.

## Migration and compatibility

### Breaking change to existing iTerm callers

The user's `config.scm:157-176` currently calls `(iterm:focus-pane-
left)`, `(iterm:split-pane-right)`, … (12 procedures × ~20 sites).
ADR-0003 drops these 12 exports from `(modaliser apps iterm)` in
favour of the façade. Migration:

```diff
-(import (prefix (modaliser apps iterm) iterm:))
+(import (prefix (modaliser apps iterm) iterm:)
+        (prefix (modaliser terminal) terminal:))

-(iterm:focus-pane-left)
+(terminal:focus-pane-left)
```

`iterm:register!`, `iterm:configure-entry`, `iterm:context-suffix-
handler`, `iterm:focus-mode-tree`, `iterm:focus-mode-register!`,
`iterm:pane-list-block`, `iterm:select-session-by-id`,
`iterm:default-pane-labels`, `iterm:rebuild-tree!`,
`iterm:iterm-configured?` stay exported. Only the 12 splits-tree
procedures move to the façade.

### Phase 1 docs to update

- `docs/reference/terminal-detection.md` — "zellij has no per-pane
  tty or command query" is wrong for zellij 0.44.x; "Alacritty has
  no IPC" is wrong as of 0.12+; Ghostty section is pre-1.3.0 and
  misses AppleScript. Edits land alongside the implementation.
- `docs/how-to/terminal-pane-aware-tree.md` — examples should migrate
  to the façade calls.

## Future work

Out of scope for this PRD, captured for traceability:

- **Pane lifecycle ops:** `close-pane`, `resize-pane`,
  `equalize-panes`, `rotate-panes`. (`toggle-pane-zoom` is now in
  scope — see ADR-0007.)
- **Kitty zoom analogue.** A kitten or layout-swap workflow that
  approximates zoom for Kitty would let `(supports-zoom?)` return
  `#t` there too.
- **Nested-mux representation.** The path's alist representation
  collapses repeated backend symbols. If nested muxes (tmux inside
  zellij, or vice versa) become a real use case, the path needs to
  become an ordered list with repeatable entries.
- **Ghostty `move_split`.** When upstream lands `move_split` in the
  keybind action vocabulary, ghostty's `move-pane-*` slots fill in
  via `perform action "move_split:<dir>"` — and a Ghostty
  configure-entry becomes warranted.
- **SSH'd remote tmux/zellij — pane control across the SSH stream.**
  Would require a remote Modaliser agent or tmux `-CC` mode
  integration. v1 treats ssh as just-a-command in the host pane;
  users navigate remote muxes with native keybindings.
- **AX-subview discovery for Kitty and Ghostty.** Would obviate the
  topology-BFS chip-geometry paths and bring them up to iTerm parity.

## References

- [ADR-0001 — Named modules + façade hybrid](../adr/0001-terminal-backends-named-modules-with-facade.md) **(superseded by 0003)**
- [ADR-0002 — Keep direction-word procedure names](../adr/0002-terminal-backends-keep-direction-word-procedure-names.md)
- [ADR-0003 — Façade-only public surface](../adr/0003-terminal-backends-facade-only-public-surface.md)
- [ADR-0004 — Capability predicates](../adr/0004-terminal-backends-capability-predicates.md)
- [ADR-0005 — configure-entry day-one per backend](../adr/0005-terminal-backends-configure-entry-day-one.md)
- [ADR-0006 — Multi-session local muxes via tty correlation](../adr/0006-terminal-backends-multi-session-and-ssh.md)
- [ADR-0007 — Pane zoom in the op surface](../adr/0007-terminal-backends-pane-zoom-in-op-surface.md)
- [ADR-0008 — Focused-terminal path as the detection primitive](../adr/0008-terminal-backends-focused-terminal-path.md)
- Phase 1 reference: `docs/reference/terminal-detection.md`
- Phase 1 how-to: `docs/how-to/terminal-pane-aware-tree.md`
- Phase 1 spec: `docs/superpowers/specs/2026-05-22-terminal-pane-and-remote-docs-design.md`
- Existing implementations:
  - `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
  - `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`
  - `Sources/Modaliser/Scheme/lib/modaliser/blocks/iterm-panes.sld`
- Glossary: `CONTEXT.md`
- Recovery investigation notes (per-backend, retired):
  `groves/terminal-backends/done/010-recover-design/notes/`
