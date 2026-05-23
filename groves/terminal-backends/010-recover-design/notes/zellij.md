# zellij — investigation notes

**Version probed:** `zellij 0.44.3` (`/opt/homebrew/bin/zellij`,
installed via brew, retained — daily-usable).
**Classification:** splitting backend (full 13-op surface + detection).

Phase-1 docs claimed zellij has "no per-pane tty/command query
comparable to tmux." This is **wrong as of 0.44.x.** zellij has a
rich CLI that exposes everything needed, often more cleanly than
tmux.

## Live-probe environment

A background session was launched via
`script -q /dev/null zellij attach -c probe-bg &`. From outside,
`zellij --session probe-bg action <op>` issued ops; results read via
`zellij --session probe-bg action list-panes -j -a`. Session deleted
at end of probe (`zellij delete-session probe-bg`). This is the
template for future per-backend live probes.

**First-run gotcha:** a fresh zellij install shows an "About Zellij"
floating plugin pane on first launch. It captures focus and blocks
`new-pane` until dismissed. `focus-pane-id plugin_4` + `close-pane`
clears it. Production code reading `is_focused` must filter
`is_plugin: true` AND `is_floating: true` to ignore overlays.

## Op surface — zellij implements all 13

### Operations

| Locked op            | zellij command                              | Verified |
|----------------------|---------------------------------------------|----------|
| `focus-pane-h`       | `zellij action move-focus left`             | ✓        |
| `focus-pane-j`       | `zellij action move-focus down`             | ✓        |
| `focus-pane-k`       | `zellij action move-focus up`               | ✓        |
| `focus-pane-l`       | `zellij action move-focus right`            | ✓        |
| `split-pane-h`       | `zellij action new-pane -d left`            | ✓ (despite help text claiming only `right\|down`) |
| `split-pane-j`       | `zellij action new-pane -d down`            | ✓        |
| `split-pane-k`       | `zellij action new-pane -d up`              | ✓        |
| `split-pane-l`       | `zellij action new-pane -d right`           | ✓        |
| `move-pane-h`        | `zellij action move-pane left`              | ✓ (swaps with neighbour, focus follows) |
| `move-pane-j`        | `zellij action move-pane down`              | ✓        |
| `move-pane-k`        | `zellij action move-pane up`                | ✓        |
| `move-pane-l`        | `zellij action move-pane right`             | ✓        |
| `focus-pane-by-digit`| `zellij action list-panes -j -a` (enumerate filtered) + `focus-pane-id terminal_<id>` + chip render via `write --pane-id` | ✓ ops, chip render verified shape but not visually |

**Crucial finding — zellij `new-pane -d` accepts all four
directions.** The `--help` text says `[right|down]`; the binary
accepts `left`, `right`, `up`, `down`. This is a documentation bug,
not a capability gap. All four split directions are first-class —
no swap-after-split dance like iTerm.

### Detection

| What                | zellij command |
|---------------------|----------------|
| focused-pane fg cmd | `zellij action list-panes -j -a` → JSON, find entry with `is_plugin: false, is_focused: true, is_floating: false`, read `pane_command` |
| focused-pane tty    | Not in JSON. Would need to walk the process tree starting from `pane_command`'s pid, but pid isn't exposed either. *Workaround:* `lsof -p <zellij-pid>` for ptys, correlate with which pane was last active — fragile. Better: use `pane_command` directly without going through tty. |
| pane-by-id          | Same JSON; filter by `id`. **Pane IDs are SPARSE** (sample run yielded 0, 2, 3, 4, 5 — id 1 went to a hidden plugin). Use `id` as opaque, don't assume contiguity. |

## Chip rendering — the mechanism

zellij has no native chip-overlay equivalent of `tmux display-panes`.
Two viable paths:

### (A) Write ANSI escapes via `zellij action write --pane-id`

Verified working command shape:

```scheme
;; Paint a reverse-video " N " chip at top-left of pane terminal_<id>.
;; \e[s save-cursor, \e[H home, \e[7m reverse, " N ", \e[m reset, \e[u restore.
(run-shell
  (string-append
    "zellij --session " session
    " action write --pane-id terminal_" id
    " -- 27 91 115 27 91 72 27 91 55 109 32 " digit-byte " 32 27 91 109 27 91 117"))
```

Pros: works for every visible terminal pane, no host-terminal coupling.
Cons:
- **Erasing is dirty.** After chip removal the cell at (1,1) holds
  the chip text until the pane redraws. No reliable "trigger
  redraw" action; pragmatic options are `clear` (clears whole pane,
  too destructive) or write a magic erase escape and accept the
  one-cell artefact.
- **Chip position is fixed.** Always at the pane's top-left;
  no positional choice. The user's "indirect and inexact" likely
  refers to exactly this.

### (B) Modaliser-side `hints-show` with computed screen coordinates

Replicates the iTerm path conceptually:
1. Get the *iTerm* split's AX frame (the host containing zellij).
2. Get iTerm's character cell dimensions (font width × line height).
3. For each zellij pane, JSON gives `pane_x` / `pane_y` in cells.
4. Screen position = `host_x + pane_x * cell_w`, `host_y + pane_y * cell_h`.
5. `hints-show` paints chips at those absolute positions.

Pros: matches iTerm chip UX exactly; no pane-content corruption.
Cons:
- iTerm character-cell dimensions aren't exposed in any of:
  AppleScript pane geometry, AX, environment vars. May have to
  be configured per-user or derived empirically from terminal-size
  vs AX-frame ratio.
- "Inexact" because the cell-size derivation is approximate
  (sub-pixel rounding, font hinting, ligature widths).

**Recommendation deferred to 080:** if iTerm cell-size can be
solved cleanly, prefer (B) — uniform chip UX across host backends.
Otherwise (A) is the safety floor.

## Session disambiguation (multi-session)

`zellij list-sessions` lists every session (active + exited).
`zellij --session NAME action list-clients` shows a session's
attached clients: `CLIENT_ID | ZELLIJ_PANE_ID | RUNNING_COMMAND`.

For the abstraction:
- **Single-session case** (the common one): trivial — the one
  running session is "the zellij" the user is in.
- **Multi-session case**: must correlate the iTerm split's tty
  with the zellij *client* in some session. `list-clients` doesn't
  expose client tty; walking `pgrep zellij` + `lsof -p` to find
  each client's controlling tty is the only path. Hacky.

Document the single-session common case; treat multi-session as
"undefined behaviour, falls back to the most-recent active
session" unless 080 says otherwise.

## How this composes with iTerm (the user's host)

The user's daily flow: iTerm.app is the host, zellij optionally runs
*inside* one of its splits. Composition:

1. macOS frontmost = `com.googlecode.iterm2` → iTerm backend
   handles initial dispatch.
2. iTerm's detection probe (`focused-terminal-foreground-command`,
   `terminal.sld:55`) returns `"zellij"` when zellij is the
   foreground command of iTerm's focused split.
3. Phase 2: at this point the abstraction routes pane ops to the
   zellij backend automatically (implicit composition), OR the
   user has bound a context-specific tree (explicit composition —
   the existing `set-local-context-suffix!` flow returning
   `/zellij`). 080 decides.

The detection chain extends naturally: zellij-as-frontmost can be
detected via the host terminal's tty foreground command, and once
zellij's identity is known, `zellij action list-panes -j -a` gives
the next level of "what's in the focused zellij pane" (e.g. nvim).

## Surprises / departures from phase-1 docs

1. Phase-1 said "zellij exposes no per-pane tty or command query."
   **Wrong for 0.44.x** — `list-panes -j -a` gives command directly.
   The reference doc (`docs/reference/terminal-detection.md:225-232`)
   needs updating once 080/090 lock the design.
2. Phase-1 implied chip rendering for zellij requires plugins.
   **Not true** — `write --pane-id` + ANSI escapes is enough.
3. `--help` understates `new-pane -d` direction support
   (claims `right|down`, accepts all four).

## Open verification items

- Visual confirmation of chip rendering (the `write --pane-id`
  command succeeded without error, but I couldn't see the result
  since the session was detached). Implementation phase will test
  this attached.
- Erase strategy for chips — what minimum-corruption sequence
  works reliably?
- Cell-size derivation for path (B) — needs an iTerm-side probe
  in the iTerm baseline notes.

## Capability matrix row

| Backend | Type           | Detection | 13-op surface | Mechanism                              | Chip render |
|---------|----------------|-----------|---------------|----------------------------------------|-------------|
| zellij  | mux            | ✓ list-panes -j -a | ✓ all 13 via `action` CLI | CLI (clean, no keystroke-proxy needed) | (A) ANSI escape via `write --pane-id` (dirty erase) — or (B) host-AX + cell-size if solvable |
