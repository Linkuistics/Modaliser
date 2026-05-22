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
   (`ps -t <name> -o pgid=,tpgid=,command=`).

Step (b) is universal. Step (a) is per-terminal and is what
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
  `#f`. Composes the two functions above. **iTerm2-only today.**

`(list-nvim-sockets)`
: Returns a list of Unix-socket paths bound by all running nvim
  processes. Uses `pgrep -x nvim` + `lsof -p $pid -U` to find
  each process's msgpack-RPC socket.

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
: Sends a keystring to the focused nvim's RPC socket.

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
`tty-foreground-command`. Nothing to write — it just works.

### WezTerm

No library support. WezTerm exposes a CLI that lists panes in
JSON:

```
wezterm cli list --format json
```

The documented JSON fields per pane are `window_id`, `tab_id`,
`pane_id`, `workspace`, `size`, `title`, and `cwd`. To identify
which pane is active and read its foreground process, a recipe
must query WezTerm's Lua API or combine `pane_id` with
`wezterm cli get-text` / process-tree inspection. The sketch
below uses `pane_id` to find the active pane via the JSON output
and then shells out to `ps` against the pane's tty obtained
through the Lua API:

```scheme
;; DIY recipe — no library support.  Adapt to your WezTerm version.
;; wezterm cli list --format json returns: window_id, tab_id,
;; pane_id, workspace, size, title, cwd per pane.
;; The active pane can be identified from the pane_id that
;; matches wezterm's current focus (query via wezterm cli
;; get-active-pane-id or the Lua mux API).
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

This is a recipe to adapt, not a supported API.

### Kitty

No library support. Kitty exposes an IPC that lists windows in
JSON:

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
;; DIY recipe — no library support.  Adapt to your Kitty config.
;; Requires: allow_remote_control yes in kitty.conf
;; kitty @ ls returns JSON with windows containing:
;;   is_focused (bool), foreground_processes [{cmdline, pid}]
(define (kitty-focused-window-command)
  (let ((out (run-shell
               (string-append
                 "export PATH=" modaliser-tool-path ":$PATH; "
                 "kitty @ ls 2>/dev/null | "
                 "python3 -c \""
                 "import json,sys; "
                 "data=json.load(sys.stdin); "
                 "[print(p['cmdline'][0]) "
                 " for w in data "
                 " for t in w.get('tabs',[]) "
                 " for win in t.get('windows',[]) "
                 " if win.get('is_focused') "
                 " for p in win.get('foreground_processes',[])[:1]]"
                 "\" 2>/dev/null"))))
    (let ((trimmed (string-trim out)))
      (if (string=? trimmed "") #f trimmed))))
```

This is a recipe to adapt, not a supported API.

### Ghostty / Alacritty

No native-split introspection in either terminal.

**Ghostty** has no control CLI; pane state is not queryable from
outside the process.

**Alacritty** has no IPC and no splits by design — it is a
single-pane terminal. There is no focused pane to query;
Alacritty is always showing exactly one tty. If you need
splitting under Ghostty or Alacritty, delegate to a multiplexer
(see next section).

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

zellij exposes no per-pane tty or command query comparable to
tmux. You can detect "zellij is running" (it will be the host
tty's foreground command via `tty-foreground-command`), but the
focused zellij pane's contents are not directly queryable from
outside the process.

For a focused nvim *inside* a zellij pane, use the nvim RPC route
below — it bypasses the multiplexer entirely.

### The nvim route bypasses both

`focused-nvim-socket` scans every running nvim system-wide and
asks each whether it holds terminal focus via its RPC socket.
Because the check goes directly to each nvim process, a focused
nvim is found whether it is in a native split, a tmux pane, a
zellij pane, or any other container — regardless of host
terminal. No per-multiplexer glue is needed for the nvim case.

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

The terminal must have focus reporting enabled — modern terminals
(iTerm2, WezTerm, Kitty) and multiplexers (tmux, zellij) forward
the xterm focus escapes to the active pane, so exactly one nvim
reports focus at a time. An nvim with no flag set reads as
not-focused (`get(g:, "modaliser_focused", 0)` returns 0) rather
than producing a Vim error.

## What each terminal supports

| Terminal  | Native-split focused-pane detection               | Notes                                   |
|-----------|---------------------------------------------------|-----------------------------------------|
| iTerm2    | Yes — AppleScript (`focused-terminal-foreground-command`) | Only terminal with library support today |
| WezTerm   | Yes — `wezterm cli list` (pane_id per pane)       | DIY recipe                              |
| Kitty     | Yes — `kitty @ ls`; needs `allow_remote_control`  | DIY recipe, opt-in                      |
| Ghostty   | No external pane API                              | Delegate splitting to a multiplexer     |
| Alacritty | No IPC; no splits by design                       | Single pane only; process-tree walk     |

| Multiplexer | Focused-pane query                                              | Notes                                              |
|-------------|-----------------------------------------------------------------|----------------------------------------------------|
| tmux        | Yes — `tmux display-message -p '#{pane_current_command}'` / `#{pane_tty}` | Finest granularity; host-terminal-independent |
| zellij      | No per-pane tty/command query comparable to tmux                | Detect "zellij running" + nvim-via-RPC; a non-nvim focused zellij pane is not resolvable |

## Limits

A non-nvim program in a focused **native iTerm2 split** *is*
resolvable: `focused-terminal-foreground-command` reads it via
AppleScript plus `tty-foreground-command`. The same program in a
focused **zellij pane** is *not* resolvable: zellij has no
per-pane query. Ghostty and Alacritty have no native-split
introspection at all.

nvim is always resolvable via the RPC route regardless of host
terminal or multiplexer, as long as the `FocusGained`/`FocusLost`
autocmds are in place.

## Related

- [terminal-pane-aware-tree.md](../how-to/terminal-pane-aware-tree.md)
- [add-a-per-app-tree.md](../how-to/add-a-per-app-tree.md)
