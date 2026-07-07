# Terminal pane detection

How Modaliser works out what is running in the focused terminal
split, and what each terminal makes possible.

## The model: the tty's foreground process group

From `terminal.sld` lines 1–7: the kernel truth for "what is
receiving keystrokes in the terminal" is the foreground process
group of the controlling tty. `ps -o tpgid` reports that group;
the row whose `pgid` equals the tty's `tpgid` is the foreground
process. Full-screen TUIs — vim, htop, lazygit, a plain shell —
all show up this way, so a single probe answers "is X running in
the focused pane" for any program X.

Detection is two steps:

1. Find the focused split's tty path (e.g. `/dev/ttys003`).
2. Read that tty's foreground command
   (`ps -t <name> -o pgid=,tpgid=,command=`, piped through `awk`
   to select the row where `pgid == tpgid`).

Step 2 is universal. Step 1 is per-terminal and is what
varies between hosts.

## The `(modaliser terminal)` API

`(focused-iterm-tty)`
: Returns the pty path of iTerm2's focused session (e.g.
  `/dev/ttys003`), or `#f` if iTerm2 is not running or the query
  fails. Uses AppleScript with an `is running` guard to avoid
  auto-launching iTerm via Launch Services.

`(tty-foreground-command tty)`
: Returns the command string of the foreground process on `tty`,
  or `#f` if there is none. Takes the short device name from the
  path, runs `ps -t`, and matches the row whose `pgid == tpgid`.

`(focused-terminal-foreground-command)`
: Returns the focused terminal split's foreground command, or
  `#f`. Convenience accessor over `focused-terminal-path` (below)
  — returns the innermost backend's `fg` slot, so a focused
  command inside tmux-inside-iTerm reads through cleanly.

`(focused-terminal-path)`
: Returns the structured detection primitive: an alist keyed by
  backend symbol with `#(pane <id> fg <cmd>)` vector values,
  representing the chain from the host terminal down through any
  multiplexer to the innermost foreground command. Each backend
  symbol appears at most once. Returns `'()` when no registered
  backend is frontmost. It is an alist keyed by backend symbol
  (rather than an ordered list) so callers can look up a segment
  by symbol directly.

`(in-chain? backend-sym)`
: `#t` when `backend-sym` appears in the current path. The
  predicate users reach for when writing suffix hooks
  (`(in-chain? 'tmux)`, `(in-chain? 'iterm)`). Registered
  backend symbols today: `'iterm`, `'wezterm`, `'kitty`,
  `'ghostty`, `'alacritty`, `'tmux`, `'zellij`, and `'herdr`
  (the last registered by the config's `(herdr:register!)`, not
  the library default set — it is the gate the herdr
  replace/augment classifier keys on, `(in-chain? 'herdr)`; see
  [herdr](#herdr) below).

`(list-nvim-sockets)`
: Returns a list of Unix-socket paths bound by all running nvim
  processes. Uses `pgrep -x nvim` + `lsof -p $pid -a -U -Fn`
  (filter to Unix-domain sockets, name-only output format) to
  find each process's msgpack-RPC socket.

`(nvim-server-focused? sock)`
: Returns `#t` if the nvim listening on `sock` reports
  `g:modaliser_focused == 1`. Passes `</dev/null` to prevent nvim
  attaching a UI and corrupting the terminal's focus-reporting
  state.

`(focused-nvim-socket)`
: Returns the socket of the focused nvim (direct or nested inside
  a multiplexer), or `#f` if no running nvim claims focus. O(n)
  RPC calls where n is the number of running nvim instances;
  typical n is 1–2.

`(nvim-remote-send keys)`
: Sends a keystring to the focused nvim's RPC socket. Has no
  meaningful return value; used for its side effect.

`(nvim-remote-expr expr)`
: Evaluates `expr` in the focused nvim and returns the result
  string, or `#f` if no focused nvim is found.

`modaliser-tool-path`
: The PATH prefix `/opt/homebrew/bin:/usr/local/bin:/usr/sbin`.
  GUI-launched Modaliser inherits a minimal `path_helper` PATH
  that omits Homebrew and `/usr/sbin`; prepend this before calling
  tools like `nvim`, `tmux`, or `pgrep` from `run-shell`.

## Native splits — the primary case

### iTerm2

Built-in library support. `focused-terminal-foreground-command`
queries `current session of current window` via AppleScript (the
focused split), then reads its tty's foreground command with
`tty-foreground-command`. The library handles this; no
configuration is required.

### WezTerm

Library-backed via `(modaliser apps wezterm)`. Internally the
backend drives the `wezterm cli` JSON listing below; hook authors
who want detection without going through the façade can use the
same recipe directly:

```
wezterm cli list --format json
```

The documented JSON fields per pane are `window_id`, `tab_id`,
`pane_id`, `workspace`, `size`, `title`, and `cwd`. Identifying
which pane is currently active is the part you must work out
against your own WezTerm version — the JSON field that exposes
the active pane (e.g. an `is_active` flag) is version-dependent
and not guaranteed to be present. Check `wezterm cli list` output
on your version to see what is actually available before writing
focus-detection logic. There is no `get-active-pane-id`
subcommand; do not rely on one.

```scheme
;; Backend-bypass recipe — for hook authors who want the JSON
;; listing directly. Adapt to your WezTerm version.
;; wezterm cli list --format json returns: window_id, tab_id,
;; pane_id, workspace, size, title, cwd per pane.
;; Your version may expose an active-pane flag — check the
;; actual output on your system.
;;
;; This fragment illustrates the shape; wire it to your own
;; focus-detection logic.
(define (wezterm-list-panes)
  (let ((out (run-shell
               (string-append
                 "export PATH=" modaliser-tool-path ":$PATH; "
                 "wezterm cli list --format json 2>/dev/null"))))
    out)) ; parse JSON with your preferred approach
```

### Kitty

Library-backed via `(modaliser apps kitty)`. The backend drives
the `kitty @ ls` IPC below; hook authors who want detection
without going through the façade can use the same recipe
directly. Note that `(supports-zoom?)` returns `#f` for Kitty in
v1 — Kitty has no native zoom analogue.

```
kitty @ ls
```

**Prerequisite:** add `allow_remote_control yes` to `kitty.conf`
(or launch kitty with `--listen-on`). When running inside a Kitty
window the command works without configuration, but it must be
enabled for use from an external process like Modaliser.

The JSON output is a tree: OS windows → tabs → windows. Each
window object contains `is_focused` (boolean), `pid` (int), and
`cmdline` (list of strings). For the foreground process of the
focused split, the `foreground_processes` array on each window
lists all processes in the window's process group, each with
`cmdline` and `pid`.

DIY recipe sketch:

```scheme
;; Backend-bypass recipe — for hook authors who want the JSON
;; listing directly. Adapt to your Kitty config.
;; Requires: allow_remote_control yes in kitty.conf
;; kitty @ ls returns JSON with windows containing:
;;   is_focused (bool), foreground_processes [{cmdline, pid}]
;; NOTE: The ordering of foreground_processes (outermost-first vs
;; innermost-first) is not verified here.  Run `kitty @ ls` on
;; your system and inspect the list order before selecting the
;; foreground-most process — adjust the index or slice below
;; accordingly.
(define (kitty-focused-window-command)
  (let ((out (run-shell
               (string-append
                 "export PATH=" modaliser-tool-path ":$PATH; "
                 "kitty @ ls 2>/dev/null | "
                 "python3 -c \""
                 "import json,sys; "
                 "data=json.load(sys.stdin); "
                 "# Select the foreground-most process from the list; "
                 "# verify ordering on your Kitty version first. "
                 "[print(procs[0]['cmdline'][0]) "
                 " for w in data "
                 " for t in w.get('tabs',[]) "
                 " for win in t.get('windows',[]) "
                 " if win.get('is_focused') "
                 " if (procs := win.get('foreground_processes',[]))]"
                 "\" 2>/dev/null"))))
    (let ((trimmed (string-trim out)))
      (if (string=? trimmed "") #f trimmed))))
```

### Ghostty

Ghostty 1.3.0+ ships an AppleScript SDEF
(`com.mitchellh.ghostty`). The frontmost terminal and its splits
are introspectable via `id of focused terminal` / `id of every
terminal`, and `perform action "<keybind>" on <terminal>` drives
the documented keybind actions (`new_split:<dir>`,
`goto_split:<dir>`, …). The library registers a Ghostty backend
on top of this SDEF — see the `(modaliser apps ghostty)` module.

The SDEF exposes no foreground-command/tty/pid slot today, so the
generic `tty-foreground-command` chain doesn't apply; the
backend's `detect-fg-command` falls back to the terminal's
AppleScript `name`. A focused nvim is still resolvable via the
RPC route below regardless of host terminal.

There is also a known *phantom-terminal leak* — a fresh window
with two visible splits enumerates more than two terminals in
AppleScript's tree, and the count grows monotonically with new
splits. The Ghostty backend snapshots the list and truncates to
the AX-rect count when painting chips; directional ops
(`goto_split:<dir>`) are unaffected.

### Alacritty

Alacritty 0.12+ ships an IPC CLI (`alacritty msg`) for
window-management operations (`create-window`, `config`). It has
no panes by design, so there is no focused-pane query to make —
Alacritty is always showing exactly one tty. Because there is
only one tty, you already know which tty to probe: a `ps`-based
foreground-process query against that tty works directly, with
no split-disambiguation step needed.

The library registers Alacritty as a **detection-only backend**:
every op slot is `#f`, but its `detect-fg-command` produces the
host row of `focused-terminal-path`, letting a multiplexer
running inside Alacritty take over the splitting surface.

If you need splitting under Alacritty, run a multiplexer inside
it (see next section).

## Reaching through a multiplexer

### tmux

`tmux display-message` can report the focused pane's foreground
command and tty directly, with no knowledge of the host terminal.
This is the finest-granularity tool for non-iTerm setups:

```
tmux display-message -p '#{pane_current_command}'  # foreground command
tmux display-message -p '#{pane_tty}'              # tty path
```

Ready-to-use recipe:

```scheme
;; Foreground command of the focused tmux pane, or #f if tmux isn't running.
(define (focused-tmux-command)
  (let ((out (run-shell
               (string-append
                 "export PATH=" modaliser-tool-path ":$PATH; "
                 "tmux display-message -p '#{pane_current_command}' 2>/dev/null"))))
    (let ((trimmed (string-trim out)))
      (if (string=? trimmed "") #f trimmed))))
```

Works under any host terminal — iTerm2, WezTerm, Kitty, Ghostty,
Alacritty, or anything else.

### zellij

zellij 0.40+ exposes a `zellij action` CLI for driving panes
from outside the process (`focus-next-pane`, `new-pane
--direction`, `move-focus <dir>`, …), and the library uses it to
implement the splitting ops for the zellij backend. The library
also resolves the right session in multi-session setups by
correlating each zellij client's tty with the focused host pane's
tty.

For *detection* — the focused zellij pane's foreground command —
the CLI has no equivalent to tmux's `pane_current_command`. The
library's zellij backend reports the host row of
`focused-terminal-path` plus the `zellij` segment; whether a
specific command is running *inside* the focused zellij pane is
not directly queryable from outside the process.

For a focused nvim *inside* a zellij pane, use the nvim RPC route
below — it bypasses the multiplexer entirely.

### herdr

[herdr](https://herdr.dev) is an "agent multiplexer that lives in
the terminal" — a client/server TUI the user runs *inside* a host
terminal (in practice, iTerm). Library-backed via `(modaliser
muxes herdr)`, registered by the config's `(herdr:register!)`. Its
control surface is a JSON socket-API CLI (`herdr
pane|tab|workspace|worktree|agent …`), not keystrokes.

Detection is two layers — the generic tty probe resolves *that*
herdr is running, and herdr's socket API resolves focus *inside* it:

- **Container (fg-command `herdr`).** An iTerm pane running the
  herdr *client* reports tty foreground command `herdr` — the
  generic step-2 `ps` probe resolves it and the mux match-key
  `"herdr"` matches, exactly like any mux. So `(in-chain? 'herdr)`
  is `#t` whenever the focused iTerm split runs herdr; that
  predicate is the gate the replace/augment classifier keys on.
- **Focused pane (global focus, per socket).** herdr's socket API
  scopes **per session** (one default session = one socket) with a
  single **global** focus — *not* per client / tty. `herdr pane
  current` answers from server state and reflects the sole client's
  focused pane (it answers even with no client attached), so the
  backend reads focus directly from the socket with **no tty
  correlation** (contrast the zellij multi-session tty-matching
  above). herdr emits compact single-line JSON, parsed with the
  portable `(modaliser json)` reader — the multiline `awk` parsers
  used for tmux/zellij do not transfer.

```
herdr pane current       # focused pane_id + its tab_id / workspace_id (JSON)
herdr pane process-info --current   # innermost foreground command of that pane
```

**Single-client v1 assumption.** Because focus is global per
session, two herdr clients attached to one session share one focus
and cannot be disambiguated — a documented v1 non-goal (the common
single-client case is unambiguous). No per-client tty correlation
like zellij's multi-session route (§ zellij above) is needed.

**Descent (herdr → nvim).** `herdr pane process-info --current`
reports the focused pane's innermost foreground command, so the
façade descends one level further (herdr → nvim) exactly as it does
through tmux/zellij; a plain shell pane reports `zsh`, which matches
no mux and leaves herdr the leaf backend.

For wiring herdr's replace/augment variant trees into the iTerm
tree, see the [worked example](../how-to/terminal-pane-aware-tree.md#worked-example-herdr-replaceaugment-variant-trees)
and [ADR-0013](../adr/0013-herdr-replace-vs-augment-tree.md). For the
pane-chip caveat, see [herdr pane chips](#herdr-pane-chips-replace-mode-only)
below.

### The nvim RPC route

`focused-nvim-socket` bypasses both native splits and
multiplexers: it scans every running nvim system-wide and asks
each whether it holds terminal focus via its RPC socket. Because
the check goes directly to each nvim process, a focused nvim is
found whether it is in a native split, a tmux pane, a zellij
pane, or any other container — regardless of host terminal. No
per-multiplexer glue is needed for the nvim case.

## The nvim side

`focused-nvim-socket` works only if each nvim maintains the
global `g:modaliser_focused`. The reason: when multiple nvim
instances are running (or nvim is nested inside a multiplexer),
they all bind RPC sockets. The focus flag — updated by
`FocusGained` / `FocusLost` autocmds — lets exactly one nvim
across the system report focus at any given moment.

Add one of the following to your nvim config:

`init.vim` (Vimscript):

```vim
augroup ModaliserFocus
  autocmd!
  autocmd FocusGained * let g:modaliser_focused = 1
  autocmd FocusLost   * let g:modaliser_focused = 0
augroup END
```

`init.lua` (Lua):

```lua
local grp = vim.api.nvim_create_augroup("ModaliserFocus", { clear = true })
vim.api.nvim_create_autocmd("FocusGained", {
  group = grp, callback = function() vim.g.modaliser_focused = 1 end,
})
vim.api.nvim_create_autocmd("FocusLost", {
  group = grp, callback = function() vim.g.modaliser_focused = 0 end,
})
```

The terminal must have focus reporting enabled — most modern
terminals, and the multiplexers tmux and zellij, forward the xterm
focus escapes to the active pane, so exactly one nvim reports focus
at a time. An nvim with no flag set reads as
not-focused (`get(g:, "modaliser_focused", 0)` returns 0) rather
than producing a Vim error.

## What each terminal supports

Every terminal/mux in the table has a backend module registered
with `(modaliser terminal)`; the façade exports the unified op
surface and the capability predicates that let one tree adapt to
whichever backend is frontmost
([how-to/terminal-pane-aware-tree.md](../how-to/terminal-pane-aware-tree.md)
shows the capability-predicate pattern).

| Terminal  | Library backend          | Focused-pane detection                                       | Notes                                            |
|-----------|--------------------------|--------------------------------------------------------------|--------------------------------------------------|
| iTerm2    | `apps/iterm`             | Yes — AppleScript + `tty-foreground-command`                 | Reference backend; full 14-op surface            |
| WezTerm   | `apps/wezterm`           | Yes — `wezterm cli list --format json` (active-pane flag)    | Full splitting surface                           |
| Kitty     | `apps/kitty`             | Yes — `kitty @ ls`; needs `allow_remote_control` (or `listen_on`) | No zoom op in v1 (`supports-zoom?` → `#f`)  |
| Ghostty   | `apps/ghostty`           | AppleScript SDEF (1.3.0+); `name`-based fg fallback          | No `move-pane-*` in v1 (`supports-move-pane?` → `#f`) |
| Alacritty | `apps/alacritty`         | Single tty — `ps` directly                                   | Detection-only; no native splits; run a mux inside |

| Multiplexer | Library backend | Focused-pane query                                                          | Notes                                                     |
|-------------|-----------------|-----------------------------------------------------------------------------|-----------------------------------------------------------|
| tmux        | `muxes/tmux`    | Yes — `tmux display-message -p '#{pane_current_command}'` / `#{pane_tty}` | Finest granularity; host-terminal-independent              |
| zellij      | `muxes/zellij`  | `zellij action` drives ops; no `#{pane_current_command}` equivalent       | Ops work; mid-pane command detection needs the nvim RPC route |
| herdr       | `muxes/herdr`   | Yes — `herdr pane current` (JSON socket-API, global focus per session)    | Agent multiplexer; single-client v1; registered by config `(herdr:register!)`; drives iTerm replace/augment variant trees |

## Limits

A non-nvim program in the focused pane is resolvable on iTerm,
WezTerm, and Kitty (all expose a per-pane tty + foreground
command). It is **not** resolvable inside a focused zellij pane
or a focused Ghostty split (neither exposes pane-internal
foreground commands today). For these cases, use
`(in-chain? 'zellij)` / `(in-chain? 'ghostty)` to branch on
*container* and let the nvim RPC route handle the nvim case.

nvim is always resolvable via the RPC route regardless of host
terminal or multiplexer, as long as the `FocusGained`/`FocusLost`
autocmds are in place.

### herdr pane chips: replace mode only

The herdr panes list block paints digit chips over the on-screen
herdr panes. Rects are synthesised tmux-style: `herdr pane layout`
gives each pane's cell rect and the canvas `area` (offset by
herdr's left sidebar, so the synthesis is **area-relative** —
`area.x`/`area.y` are subtracted before scaling), and the focused
iTerm `AXScrollArea` frame supplies the pixel canvas.

This is correct in **replace** mode, where herdr owns the sole
iTerm scroll area. In **augment** mode (herdr shares its iTerm tab
with other iTerm splits) the host-frame heuristic takes the *first*
`AXScrollArea`, which may be the wrong split — so chips can land on
the wrong pixels. `hjkl` focus and digit-jump are unaffected
(digit-jump focuses by `pane_id` via `herdr agent focus`, not by
chip position); only the chip *overlay* may be misplaced. The
proper fix — a focused-iTerm-session-frame primitive that returns
the herdr split's frame directly — is a deferred follow-up.

## See also

- [terminal-pane-aware-tree.md](../how-to/terminal-pane-aware-tree.md)
- [add-a-per-app-tree.md](../how-to/add-a-per-app-tree.md)
