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

Chips are **native macOS overlay windows** drawn by Modaliser's
existing `hints-show` (`(modaliser hints)`), exactly as for iTerm.
The per-backend job is producing the list of
`(label, screen-rect)` pairs `hints-show` consumes.

For zellij-as-mux-inside-a-host-terminal, the screen-rect for each
zellij pane is computed:

1. Host terminal window's screen frame — via macOS AX on the host
   (iTerm gives AX-discoverable per-pane frames; for a mux running
   inside an iTerm pane, that iTerm-pane's frame is the host frame).
2. Cell-pixel dimensions of the host terminal — `cell_w`, `cell_h`.
   Not directly exposed by iTerm; must be derived. Candidate paths:
   - Window pixel-size ÷ window cell-count (requires both, may
     have padding to subtract).
   - Empirical calibration once per session (paint a probe glyph,
     measure where it lands via AX).
   - User-supplied in config.
3. zellij gives `pane_x`, `pane_y`, `pane_columns`, `pane_rows`
   for each pane (cell coordinates within the host pane), via
   `list-panes -j -a`.
4. `screen_rect = (host_x + pane_x*cell_w, host_y + pane_y*cell_h,
                   pane_columns*cell_w, pane_rows*cell_h)`.
5. Hand `((label, rect), …)` to `hints-show`.

**Why "indirect and inexact":**
- Cell-pixel dimensions require derivation, which is approximate
  (sub-pixel rounding, font hinting, ligatures, retina scaling).
- iTerm padding (the gap between window edge and the first cell)
  is not exposed; small constant offset per host terminal.
- Off-by-a-few-pixels chip positions are acceptable so long as the
  digit lands clearly inside the right pane.

**The text-injection path is NOT the chip-rendering mechanism.**
`zellij action write --pane-id` does send raw bytes to a pane's
tty, but that paints text *inside* the terminal stream and is not
how Modaliser chips work. Mentioning the capability here only
because it's available for other purposes (probing, debugging).

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
2. `--help` understates `new-pane -d` direction support
   (claims `right|down`, accepts all four).

## Open verification items

- Cell-pixel dimensions for the host terminal hosting zellij —
  derive from pixel-window-size ÷ cell-window-size, calibrate
  empirically, or take from user config? Not a zellij question
  per se; lands in the iTerm baseline notes (or 080).
- iTerm padding offset (window edge to first cell) — small constant
  to subtract from the host AX frame before adding mux-pane cell
  offsets. Verify empirically.

## Capability matrix row

| Backend | Type           | Detection | 13-op surface | Mechanism                              | Chip render |
|---------|----------------|-----------|---------------|----------------------------------------|-------------|
| zellij  | mux            | ✓ list-panes -j -a | ✓ all 13 via `action` CLI | CLI (clean, no keystroke-proxy needed) | `hints-show` with screen-rects computed from host-AX frame + cell-pixel dims + zellij's per-pane cell coords |
