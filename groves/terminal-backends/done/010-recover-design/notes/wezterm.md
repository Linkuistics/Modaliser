# WezTerm — investigation notes

**Version probed:** `wezterm 20240203-110809-5046fc22` (homebrew cask,
Feb 2024 nightly tag; brew has not refreshed the cask in ~22 months).
**CLI location:** `/opt/homebrew/bin/wezterm` (cask-symlinked from
`/Applications/WezTerm.app/Contents/MacOS/wezterm`).
**Classification:** splitting backend (12/13 ops + detection — see
gap below).

## Live-probe environment

Probed headless via `wezterm-mux-server --daemonize` + `wezterm cli
--prefer-mux <op>`. The mux server is a separate binary the cask
installs; it gives the CLI a virtual session to drive without
spawning a GUI window (which would steal focus and clutter the
desktop). For real chip-rendering verification a GUI session is
needed — deferred to implementation phase, since the data model is
the same.

## Op surface — 12/13, one gap

### Operations

| Locked op            | wezterm command                                                  | Verified |
|----------------------|------------------------------------------------------------------|----------|
| `focus-pane-h`       | `wezterm cli activate-pane-direction Left --pane-id <id>`        | ✓        |
| `focus-pane-j`       | `wezterm cli activate-pane-direction Down --pane-id <id>`        | ✓        |
| `focus-pane-k`       | `wezterm cli activate-pane-direction Up --pane-id <id>`          | ✓ (also Next / Prev cycle) |
| `focus-pane-l`       | `wezterm cli activate-pane-direction Right --pane-id <id>`       | ✓        |
| `split-pane-h`       | `wezterm cli split-pane --pane-id <id> --left`                   | ✓        |
| `split-pane-j`       | `wezterm cli split-pane --pane-id <id> --bottom`                 | ✓        |
| `split-pane-k`       | `wezterm cli split-pane --pane-id <id> --top`                    | ✓        |
| `split-pane-l`       | `wezterm cli split-pane --pane-id <id> --right`                  | ✓        |
| **`move-pane-h`**    | **NOT SUPPORTED via CLI**                                        | gap      |
| **`move-pane-j`**    | **NOT SUPPORTED via CLI**                                        | gap      |
| **`move-pane-k`**    | **NOT SUPPORTED via CLI**                                        | gap      |
| **`move-pane-l`**    | **NOT SUPPORTED via CLI**                                        | gap      |
| `focus-pane-by-digit`| `wezterm cli list --format json` to enumerate + `activate-pane --pane-id <id>` | ✓ |

**`move-pane-to-new-tab` exists** but moves a pane to a new tab —
different operation. There is no swap-with-neighbour-in-direction
in the CLI surface.

Workarounds for the move-pane gap, increasing complexity:
1. **Mark unsupported.** WezTerm backend's `move-pane-{h,j,k,l}`
   return `#f` / signal unsupported. The abstraction's surface-
   split rule (per 080) determines whether this disqualifies
   WezTerm from "full splitting backend" status.
2. **Keystroke-proxy.** WezTerm doesn't ship default move-pane
   keybinds. The user must configure them in `wezterm.lua`
   (action `RotatePanes` exists in the GUI key layer). Then
   `send-keystroke` from Modaliser triggers them. Requires
   per-user `wezterm.lua` setup similar to iTerm's
   `configure-entry`.
3. **CLI workaround via `split-pane --move-pane-id`.** This flag
   moves an existing pane into a new split. Combined with
   `kill-pane` of the resulting "ghost," in theory a swap could
   be synthesised — but the layout changes (a new split point is
   introduced), so the result isn't a true swap. Probably not
   worth the complexity.

**Recommendation:** ship WezTerm as a 12-op splitting backend.
Document the move-pane gap and suggest keystroke-proxy if the user
wants the full surface. Defer the keystroke-proxy provisioning
analogue (a `wezterm:configure-entry`) to a later iteration.

### Detection

| What                | wezterm command |
|---------------------|-----------------|
| focused-pane fg cmd | `wezterm cli list --format json` → find entry with `is_active: true` → read `title` (or use `tty_name` + `tty-foreground-command`) |
| focused-pane tty    | Same JSON: `tty_name` field gives `/dev/ttysNN` directly |
| pane-by-id          | Same JSON: `pane_id` is a stable integer per pane |

WezTerm's JSON exposes **tty_name directly** — no AppleScript
probe needed. This is cleaner than iTerm.

## Chip rendering — rect-derivation for WezTerm-as-host

Chips are always `hints-show` overlays (see CONTEXT.md "Chip").
For WezTerm as a host terminal:

1. **Window screen frame** — macOS AX on the WezTerm GUI window.
   Standard NSWindow accessibility. (Untested in this session; mux
   server has no GUI.)
2. **Per-pane cell offset within window** — `list --format json`
   gives `left_col` and `top_row` per pane (cell coords from the
   window origin).
3. **Cell-pixel dimensions** — `list --format json` exposes BOTH
   cell AND pixel dimensions per pane:

   ```
   "size": {
     "rows": 24, "cols": 80,
     "pixel_width": 640, "pixel_height": 384,
     "dpi": 0
   }
   ```

   `cell_w = pixel_width / cols` and `cell_h = pixel_height / rows`
   are integer ratios in the default font. **No derivation
   guesswork** — WezTerm hands us the cell-pixel dims directly.
4. `screen_rect = (window_x + left_col*cell_w,
                   window_y + top_row*cell_h,
                   cols*cell_w, rows*cell_h)`.

The only step needing AX is (1). Steps 2-4 are all `wezterm cli`
or arithmetic. This is **better than iTerm** (where cell-pixel
dims must be derived).

Padding (border between window edge and first cell)? WezTerm draws
a configurable window padding (`window_padding` in `wezterm.lua`,
defaults to non-zero). The pixel dims above don't include padding —
they're pane-content. Adding the host window's padding offset is
the small remaining concern; assume default 0 for the initial
implementation and let users override.

## Mux-server pattern (reusable for tmux probe)

The `script -q /dev/null` trick used for zellij isn't needed for
WezTerm — the mux-server binary handles headless. The CLI prefers
the GUI socket by default; pass `--prefer-mux` to talk to the
daemon instead. The same `--prefer-mux` flag works against a
running GUI's mux endpoint, so the abstraction code can use it
unconditionally.

**Important:** the mux server is daemonised — it persists across
shell exits. Tear down with:

```
pkill -f wezterm-mux-server   # or kill the pid recorded at start
```

## Surprises / departures from phase-1 docs

1. Phase-1 said WezTerm's `active-pane` field is "version-
   dependent." In **this** cask the JSON uses `is_active`
   (boolean). Solid; not field-mining required.
2. Phase-1 hedged on `wezterm cli list` JSON shape. The reality is
   well-structured: per-pane object with `pane_id`, `is_active`,
   `left_col`, `top_row`, `size{rows,cols,pixel_width,pixel_height}`,
   `tty_name`, `title`, `cwd`, etc.
3. The `--prefer-mux` headless mode (vs `--prefer-gui`, the default)
   lets us drive CLI ops without a visible WezTerm window. This is
   the cleanest probe pattern of any backend so far.
4. The `move-pane-to-new-tab` action exists but **there is no
   in-tab `move-pane` direction action**. This is a real surface
   gap, not a phase-1 misrepresentation (phase-1 didn't claim
   move-pane support).

## Open verification items

- AX probe of an actual WezTerm GUI window — does it expose per-
  pane sub-frames, or only the top-level window frame? Determines
  whether the `(2)+(3)+(4)` arithmetic above is needed at all
  vs. AX-direct like iTerm.
- WezTerm padding query — can `wezterm cli` expose the configured
  `window_padding` value, or must we read it from `wezterm.lua`?
- `move-pane` keystroke-proxy via user-configured `wezterm.lua`
  bindings — confirm `RotatePanes`/`MoveTab`/equivalent actions
  can swap two panes by direction.

## Capability matrix row

| Backend | Type           | Detection                              | 13-op surface | Mechanism                              | Chip render |
|---------|----------------|----------------------------------------|---------------|----------------------------------------|-------------|
| WezTerm | host w/ splits | ✓ `wezterm cli list --format json` (tty_name + is_active) | 12/13 (no move-pane via CLI) | `wezterm cli` (clean); GUI for chip rect derivation | `hints-show` with window-AX + cell-pixel dims from `list` JSON |
