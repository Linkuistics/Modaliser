# tmux — investigation notes

**Version probed:** `tmux 3.6b` (homebrew bottle, installed fresh
this session).
**Classification:** mux backend (full 13-op surface + detection).

## Live-probe environment

`tmux new -d -s probe-tm` creates a detached session — runs the
server in background, no client attached. Subsequent ops use
`-t probe-tm` to target it. `tmux kill-session -t probe-tm` (or
just letting the server exit when no clients remain) tears down.
This is the cleanest probe pattern of any backend — tmux is
*designed* for headless server operation.

## Op surface — full 13

### Operations

| Locked op            | tmux command                                                  | Verified |
|----------------------|---------------------------------------------------------------|----------|
| `focus-pane-h`       | `tmux select-pane -L`                                         | ✓        |
| `focus-pane-j`       | `tmux select-pane -D`                                         | ✓        |
| `focus-pane-k`       | `tmux select-pane -U`                                         | ✓        |
| `focus-pane-l`       | `tmux select-pane -R`                                         | ✓        |
| `split-pane-h`       | `tmux split-window -h -b`     (h=vertical divider; -b=before, i.e. new pane LEFT) | ✓ |
| `split-pane-j`       | `tmux split-window -v`        (v=horizontal divider; default new pane BELOW)       | ✓ |
| `split-pane-k`       | `tmux split-window -v -b`     (-b=before, i.e. new pane ABOVE)                      | ✓ (analogous to verified -h -b) |
| `split-pane-l`       | `tmux split-window -h`        (h=vertical divider; default new pane RIGHT)         | ✓ |
| `move-pane-h`        | `tmux swap-pane -s <focused> -t '{left-of}'`                  | ✓ |
| `move-pane-j`        | `tmux swap-pane -s <focused> -t '{down-of}'`                  | (analogous) |
| `move-pane-k`        | `tmux swap-pane -s <focused> -t '{up-of}'` (or `-U`)          | ✓ via `-U` |
| `move-pane-l`        | `tmux swap-pane -s <focused> -t '{right-of}'`                 | ✓ |
| `focus-pane-by-digit`| `tmux list-panes -F '#{pane_index} #{pane_id}'` to enumerate + `tmux select-pane -t %<id>` | ✓ |

**Direction-flag nomenclature confusion** (worth pinning):
tmux says **`-h` for "horizontal split"** when it means
*vertical divider, new pane on the right* — because the resulting
layout is "panes arranged horizontally." Similarly `-v` =
"vertical split" = horizontal divider, new pane below. The user-
facing op surface (focus-pane-h = leftward) follows hjkl
direction semantics, so the recipe layer maps:
- our `h` → tmux `-h -b` (left)
- our `j` → tmux `-v`    (down)
- our `k` → tmux `-v -b` (up)
- our `l` → tmux `-h`    (right)

### Detection

| What                | tmux command |
|---------------------|--------------|
| focused-pane fg cmd | `tmux display-message -p '#{pane_current_command}'` |
| focused-pane tty    | `tmux display-message -p '#{pane_tty}'` |
| pane enumeration    | `tmux list-panes -F '#{pane_id} #{pane_current_command} #{pane_tty} #{pane_left} #{pane_top} #{pane_width} #{pane_height} #{?pane_active,active,}'` — single tab-friendly format string per row |

tmux exposes **everything** as format-string fields. No JSON needed.

Pane IDs use `%N` notation (`%0`, `%1`, `%2`, …) and are *stable*
across the session — they don't renumber when panes close.
Display indices (`#{pane_index}`) DO renumber, so use `%N` for
internal references and `pane_index` only for user-visible labels.

## Chip rendering — rect derivation

Chips are `hints-show` overlays (per CONTEXT.md "Chip"). For
tmux-as-mux-inside-a-host-terminal:

1. Host terminal window AX frame.
2. Host cell-pixel dims (must be derived — not directly exposed
   by iTerm / most hosts).
3. tmux gives per-pane cell coords:
   ```
   tmux list-panes -F '#{pane_left} #{pane_top} #{pane_width} #{pane_height}'
   ```
4. `screen_rect = (host_x + pane_left*cell_w,
                   host_y + pane_top*cell_h,
                   pane_width*cell_w, pane_height*cell_h)`.

Identical computation shape to zellij. The cell-pixel-dim
derivation for the host is the cross-cutting concern.

## `tmux display-panes` — irrelevant but worth knowing

tmux ships a *native* chip-overlay (`tmux display-panes`) that
shows a digit on each pane and accepts the digit to focus it.
This is **not** Modaliser's chip mechanism — Modaliser chips are
always `hints-show` native overlay windows. `display-panes`
exists; we don't use it.

## Session disambiguation

`tmux list-clients -t <session>` shows attached clients. In a
probe environment with no attached clients the output is empty.
For real usage:
- **Single-session case:** trivial — `tmux display-message -p` with
  no target acts on the default session.
- **Multi-session case:** the host terminal's tty foreground command
  reports `tmux` regardless of which session is running inside.
  Resolution: walk `lsof` of the tmux client process to find its
  controlling tty, match against the host pane's tty. Same shape
  as zellij — hacky.

The user's typical case is one tmux session per host pane, so
single-session resolution holds in practice.

## Mux composition with iTerm (the user's host)

When iTerm's focused split runs tmux:
1. `focused-terminal-foreground-command` (`terminal.sld:55`)
   returns `"tmux"`.
2. Phase 2 routes pane ops to the tmux backend.
3. `tmux display-message -p '#{pane_current_command}'` reports
   what's inside the focused tmux pane (`nvim`, `lazygit`, etc.).

The chain extends naturally — host terminal → mux → in-mux program.

## Surprises / departures from phase-1 docs

1. Phase-1 docs said `tmux display-panes` "may serve chips."
   Updated mental model: chips are always `hints-show`;
   `display-panes` is a native tmux feature unrelated to
   Modaliser's overlay rendering. (Phase-1 doc not wrong per se,
   but the suggestion to use it is obsolete.)
2. tmux 3.6b's `swap-pane -t '{left-of}'` / `{right-of}` /
   `{up-of}` / `{down-of}` selectors give clean per-direction
   pane movement, unlike WezTerm's CLI gap. Full 13-op coverage.
3. Detection is *easier* than phase-1 portrayed — no need for
   the `list-panes -F '#{pane_current_command}'` recipe described
   in docs/reference/terminal-detection.md. Use
   `display-message -p '#{pane_current_command}'` which is one
   call, no row iteration.

## Open verification items

- `split-window -v -b` (split up) and `swap-pane -t '{up-of}' /
  '{down-of}'` were not exhaustively run in this probe — analogous
  to the verified -h -b and {left-of}/{right-of}. Spot-check
  during implementation.
- Multi-session client-to-tty disambiguation — only needed if
  users run >1 tmux session simultaneously across multiple iTerm
  splits. Defer until reported.

## Capability matrix row

| Backend | Type | Detection                                       | 13-op surface | Mechanism                       | Chip render |
|---------|------|-------------------------------------------------|---------------|---------------------------------|-------------|
| tmux    | mux  | ✓ `display-message -p '#{pane_current_command}'` (or `list-panes -F` for enumeration) | ✓ all 13       | tmux CLI (clean, format strings) | `hints-show` with screen-rects from host-AX + host cell-dims + tmux cell coords |
