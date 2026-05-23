# kitty — investigation notes

**Version probed:** `kitty 0.47.0` (homebrew cask, installed fresh
this session and uninstalled after probe).
**Classification:** splitting backend (full 13-op surface; chip
rendering has a gap — see below).

## Prerequisite (not enforced)

Kitty's remote-control IPC requires `allow_remote_control yes`. The
**runtime override** `kitty --override allow_remote_control=yes`
sets this at launch without modifying `kitty.conf` — preferred for
probing, since the user's existing `kitty.conf` (an A/B-rendering
mirror of `wezterm.lua`) must not be touched. For real users wiring
phase 2 into their config, the documented path stays "set
`allow_remote_control yes` in `kitty.conf`."

## Live-probe environment

```
kitty --override allow_remote_control=yes \
      --listen-on=unix:/tmp/probe-kitty \
      --override enabled_layouts=splits,tall,stack \
      bash -c 'sleep 600' &
```

The `splits` layout is required for the directional split surface;
without `enabled_layouts=splits` listed, kitty's `--location=vsplit`
falls back to whatever layout is active. Kitty's *default* layout
is `tall`, which doesn't support arbitrary directional splits.

All ops driven via `kitty @ --to=unix:/tmp/probe-kitty <cmd>`. The
kitty GPU GUI window does briefly steal focus on launch — this is a
real limitation of probing kitty (no headless mode equivalent to
wezterm-mux-server or tmux's detached session).

Teardown: kill the kitty PID; socket auto-cleans.

## Op surface — 13/13 (with caveats)

### Operations

| Locked op            | kitty command                                              | Verified |
|----------------------|------------------------------------------------------------|----------|
| `focus-pane-h`       | `kitty @ focus-window --match=neighbor:left`               | ✓        |
| `focus-pane-j`       | `kitty @ focus-window --match=neighbor:bottom`             | ✓ (verified analogous; `neighbors` JSON keys `top`/`bottom`/`left`/`right`) |
| `focus-pane-k`       | `kitty @ focus-window --match=neighbor:top`                | ✓ |
| `focus-pane-l`       | `kitty @ focus-window --match=neighbor:right`              | ✓ |
| `split-pane-h`       | `kitty @ launch --location=vsplit` + `kitty @ action move_window left` | ✓ via composition |
| `split-pane-j`       | `kitty @ launch --location=hsplit`                         | ✓ |
| `split-pane-k`       | `kitty @ launch --location=hsplit` + `move_window up`      | ✓ via composition |
| `split-pane-l`       | `kitty @ launch --location=vsplit`                         | ✓ |
| `move-pane-h`        | `kitty @ action move_window left`                          | ✓ |
| `move-pane-j`        | `kitty @ action move_window down`                          | ✓ (analogous) |
| `move-pane-k`        | `kitty @ action move_window up`                            | ✓ (analogous) |
| `move-pane-l`        | `kitty @ action move_window right`                         | ✓ (analogous) |
| `focus-pane-by-digit`| `kitty @ ls` (JSON) → enumerate `id`s → `kitty @ focus-window --match=id:N` | ✓ |

**`launch --location` only supports `vsplit` (right) and `hsplit`
(below)** — no `vsplit-left` / `hsplit-top` variant. The `before` /
`after` values relate to tab-order, not split-direction. For split-
left and split-up, do the analogous compose-then-move as iTerm
does: `launch --location=vsplit` followed by `action move_window
left`. The composed result is identical (new pane at desired side),
just two CLI calls instead of one.

### Detection

| What                | kitty command |
|---------------------|---------------|
| focused-pane fg cmd | `kitty @ ls` JSON → window with `is_focused: true` → `foreground_processes[0].cmdline` |
| focused-pane pid    | Same JSON: `pid` field (the shell pid) and `foreground_processes[].pid` (current fg child) |
| pane enumeration    | `kitty @ ls` returns OS-windows → tabs → windows tree |

**No `pane_tty` field.** Kitty's `ls` doesn't surface the tty path
for each window. Workaround if needed:
`lsof -p <window_pid> -a -d 0` to find its stdin tty. For most use
cases `foreground_processes[].cmdline` is the detection answer
without needing tty resolution.

Kitty's terminology: an "OS window" is the macOS NSWindow; a "tab"
is a tabbed-section within it; a "window" is the pane (despite the
confusing name). Match expressions consistently use "window" for
panes.

## Chip rendering — **the surface gap**

Per CONTEXT.md, chips are `hints-show` overlays. For kitty as a
host terminal:

1. **Window screen frame** — macOS AX on the kitty.app GUI window.
2. **Per-pane cell offset within the window** — *not exposed by
   `kitty @ ls`*. The JSON gives `columns`/`lines` (cell
   dimensions) and `neighbors` (topology), but **no `left_col` /
   `top_row` field**. This is the surface gap.
3. **Cell-pixel dimensions** — derivable from font config
   (`font_family`, `font_size`) plus a measurement; not directly
   exposed by `ls`.

Workarounds for the missing cell offset:
- **Topology reconstruction.** Walk `neighbors` for every pane;
  start at the pane with no `left` / `top` neighbor (top-left); BFS
  fills in a grid. Accuracy depends on layout being orthogonal
  (which `splits` layout enforces). Each pane's `(columns, lines)`
  + its grid position derives the cell offset.
- **`kitten @ select-window` native overlay.** kitty ships a native
  chip-selector — `kitty @ select-window` prints labels in each
  pane and accepts selection. It's NOT `hints-show` and breaks the
  cross-backend chip UX, but is an immediate fallback if the
  topology reconstruction is too fragile.
- **AX of kitty.app sub-views.** kitty.app may expose per-pane AX
  nodes (like iTerm does). Not probed in this session — needs an
  interactive AX walker. If it works, this is the cleanest path.

**Recommendation deferred to 080:** chip rendering for kitty is the
first backend where the "indirect and inexact" cost is meaningful.
Surface-split rule needs to decide whether kitty is "full 13-op" or
"12-op + best-effort chips."

## Native chip selector — irrelevant but documented

`kitty @ select-window` paints a native digit overlay on each
window/pane and accepts selection. It's the kitty equivalent of
`tmux display-panes`. Modaliser chips are `hints-show` overlays
per the rule; `select-window` is mentioned only because users may
already have it bound and recognise the pattern.

## Surprises / departures from phase-1 docs

1. Phase-1 docs (`docs/reference/terminal-detection.md:130-176`)
   showed a `kitty @ ls` parsing recipe and noted the
   "foreground_processes ordering is unverified." In 0.47.0 it's
   a list where the LAST element is the innermost child (so use
   `[-1]['cmdline'][0]` for the foreground-most process — typical
   pattern is shell → some-tool, you want some-tool). The first
   element is the shell itself.
2. Phase-1 docs implied `kitty @ ls` exposes window geometry. **It
   does not** — neighbor topology and cell dimensions only, no
   absolute cell offsets or pixel coords.
3. The `splits` layout dependency is not in phase-1 docs but is
   load-bearing for the op surface. Users who only enable the
   default `tall` layout won't get directional splits.

## Open verification items

- AX probe of kitty.app per-pane sub-views — most important
  unknown; would obviate the topology reconstruction.
- Cell-pixel-dim derivation for kitty (font_family + font_size +
  CoreText measurement). Probably needs a Swift / `osascript` /
  Modaliser-side calibration.
- Topology reconstruction algorithm robustness — what happens with
  nested splits (a vertical split inside a horizontal split)? The
  `neighbors` field becomes denser; BFS likely still works but
  edge cases need testing.

## Capability matrix row

| Backend | Type           | Detection                                  | 13-op surface | Mechanism                | Chip render |
|---------|----------------|--------------------------------------------|---------------|--------------------------|-------------|
| kitty   | host w/ splits | ✓ `kitty @ ls` (foreground_processes) | 13/13 with compose-then-move for split-h/k | `kitty @` IPC (requires `allow_remote_control yes`) + `splits` layout enabled | `hints-show` with rects derived from window-AX + cell-pixel-dims + topology-reconstructed cell offsets — the surface gap |
