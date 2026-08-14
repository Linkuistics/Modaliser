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
  symbol appears at most once. Returns `'()` when no configured
  backend is frontmost. It is an alist keyed by backend symbol
  (rather than an ordered list) so callers can look up a segment
  by symbol directly.

`(call-with-pinned-chain thunk)`
: Calls `thunk` with the chain **pinned** for its dynamic extent:
  the first chain read inside walks, and every later one —
  `focused-terminal-path`, `active-backend`, `in-chain?`, an op
  shim — is served from that walk. Returns `thunk`'s value.
  Nesting joins the outer extent rather than opening a second one,
  so a caller may pin without knowing whether its own caller
  already did; a probe that raises pins nothing.
  Outside an extent nothing is cached, which is the point: there
  is no invalidation to get wrong, because focus moves between
  extents and nothing here observes that (CONTEXT.md "Pinned
  chain"). The leader handler wraps a press in it — a press reads
  the chain twice, once to resolve activation and once in the
  landing's visit snapshot, and those two reads are one instant.

`(in-chain? backend-sym)`
: `#t` when `backend-sym` appears in the current path. The
  predicate to reach for in a custom detection gate
  (`(in-chain? 'tmux)`, `(in-chain? 'iterm)`) — activation itself no
  longer needs one; the Terminal context map's chain walk covers it.
  Backend symbols come from the records your configuration carries:
  `'iterm`, `'wezterm`, `'kitty`, `'ghostty`, `'alacritty` (host
  fragments), `'tmux`, `'zellij`, `'herdr` (mux context entries; see
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
: The PATH prefix to prepend before calling tools like `nvim`, `tmux`,
  or `pgrep` from `run-shell`. GUI-launched Modaliser inherits a
  minimal `path_helper` PATH that omits Homebrew and `/usr/sbin`.
  Derived once at `(modaliser terminal)` load time (ADR-0017): the
  user's login shell is spawned (`/bin/zsh -lc 'echo $PATH'`) and its
  `$PATH` is unioned with the hardcoded floor
  `/opt/homebrew/bin:/usr/local/bin:/usr/sbin` via `merge-tool-path`,
  login-shell entries first so a relocated tool resolves there before
  falling through to the floor. Any spawn failure degrades to the
  floor alone. `merge-tool-path` is a pure function (login PATH
  string, floor PATH string) → merged PATH string, exported and unit
  tested independently of the load-time spawn.

## Backend tool health

Layer 2 of ADR-0017. Deriving `modaliser-tool-path` (above) fixes *most*
tool-resolution breakage, but a tool can still go missing entirely — moved,
uninstalled, or never installed on this machine. Every backend guard
degrades that to `#f` (a leader press must never raise), which makes "tool
not on the path" indistinguishable from "nothing running right now." Backend
tool health closes that gap by tracking, per backend symbol, whether its CLI
tool last resolved — and surfacing the difference instead of staying silent.

This applies to the **CLI-native** backends — tmux, zellij, kitty, wezterm.
**herdr does not participate**: it is reached over a Unix socket (ADR-0020),
its backend record carries no `tool-name`, and it needs none, because the
ambiguity Layer 2 exists to resolve does not arise there. A reachable herdr
that has nothing to list answers a perfectly good
`{"result":{"panes":[]}}`, and one with an objection to raise answers an
`error` envelope; only an unreachable, timed-out or unparseable exchange
answers `#f`. The query result *is* the reachability verdict, consumed
directly by the caller that surfaces it (see
[herdr reachability](#herdr-reachability)).

`(terminal-install-backends! backends)`
: The handoff's engine-install point for the records a configuration
  value carries. Installing is also the **backend-install
  probe**: for each backend whose `tool-name` field (a string, or `#f` for a
  backend with no separate CLI tool — iTerm2, Ghostty, and Alacritty are all
  driven without one) is non-`#f`, it runs `command -v <tool-name>` through
  the derived tool path immediately and records the result. This catches a
  broken tool path at every relaunch, before any op fires.

`(note-backend-query-result! symbol ok?)`
: The **lazy, memoized re-probe**. A backend's own query wrapper (e.g.
  `display-message` in `(modaliser muxes tmux)`, `list-panes-raw` in the
  zellij/kitty/wezterm backends) calls this after every query, passing
  whether the raw result
  was real (`#t`) or the query's own empty/unparseable sentinel (`#f`). A
  successful result is itself proof the tool exists — a genuinely-missing
  binary can never produce real output through `run-shell` — so success
  just clears a stale flag with **no probe, no extra subprocess spawn**. A
  failure is the ambiguous moment ("tool gone" vs. "nothing running"), so
  it re-probes; if the tool is truly gone, the backend is flagged and a
  `log-line` fires (`(modaliser log)`, readable via `log show --predicate
  'subsystem == "dev.antony.Modaliser"'`). The same re-probe is what lets a
  tool that comes back mid-run clear its flag without a relaunch.

`(backend-tool-missing? symbol)`
: What a caller consults to render state instead of silence. A backend with
  no matching entry (never probed, or `tool-name` `#f`) reads as healthy —
  the fail-open default a leader press needs.

`current-tool-probe-runner`
: Test seam (a `make-parameter`, mirroring `current-herdr-query-runner`)
  wrapping the `command -v` probe — a test hands back a canned
  present/absent verdict instead of shelling out.

Memoization is per app run: a relaunch re-probes every tracked backend at
backend-install time regardless of prior state, so there's no persisted "missing"
verdict to go stale across restarts.

### herdr reachability

herdr's equivalent needs no table and no probe. `herdr-query` (the one read
seam, `(modaliser muxes herdr-socket)`) returns the parsed response envelope
or `#f`, where **`#f` means herdr did not answer** — unreachable socket,
timeout, an unparseable reply, or no socket path configured at all (the
transport is inert until the host installs one at bootstrap — ADR-0020), each
already logged with its reason by the transport or the `unix-socket-request`
primitive. So the caller reads the response directly:

- `blocks/herdr-list.sld`'s `snapshot!` replaces the normal row list with a
  single message row ("herdr is not responding") when its query answers
  `#f`. Targets stay empty too, so no digit dispatches into it.
- A reachable herdr with an empty list is *not* that case — the envelope
  parses truthy and flows into the pure extractor as zero rows.
- Nor is a structured `error`. herdr answering `worktree.list` with
  `not_git_worktree` (the focused workspace is not inside a git work tree) is
  an ordinary condition, not silence, so the envelope comes back truthy and
  logged. It simply carries no `result`, so the extractor yields zero rows
  and the drill renders an empty list — exactly what the CLI era did, and
  without the row claiming herdr is unresponsive when it plainly is not.

This is what the shell-out could not do: `run-shell "herdr … 2>/dev/null"`
returned the same empty string for a missing binary, a dead server and an
empty list alike, and Layer 2's `command -v` re-probe existed to recover the
difference. Post-cutover that probe would answer the wrong question (the
binary's presence says nothing about whether the socket is reachable) and
would spawn a subprocess on precisely the path ADR-0020 de-subprocessed.

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
`goto_split:<dir>`, …). The library's backend record is built
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

Alacritty's record is a **detection-only backend**:
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
muxes herdr)`, composed via `(herdr:wiring)` in the config's
`terminal-contexts` — integration only, the screen being the config's
own (ADR-0021). Its control surface is a **JSON-RPC Unix
socket**, not keystrokes and — unlike every other backend here — not
a CLI either: herdr's own `herdr …` commands are a thin wrapper over
the same socket, so Modaliser dials it directly (ADR-0020). tmux and
zellij stay on the CLI because they are genuinely CLI-native.

Detection is two layers — the generic tty probe resolves *that*
herdr is running, and herdr's socket resolves focus *inside* it:

- **Container (fg-command `herdr`).** An iTerm pane running the
  herdr *client* reports tty foreground command `herdr` — the
  generic step-2 `ps` probe resolves it and the mux match-key
  `"herdr"` matches, exactly like any mux. So `(in-chain? 'herdr)`
  is `#t` whenever the focused iTerm split runs herdr; that
  predicate is the herdr entry point's detection gate (ADR-0013).
- **Focused pane (global focus, per socket).** herdr's socket
  scopes **per session** (one default session = one socket) with a
  single **global** focus — *not* per client / tty. `pane.current`
  answers from server state and reflects the sole client's
  focused pane (it answers even with no client attached), so the
  backend reads focus directly from the socket with **no tty
  correlation** (contrast the zellij multi-session tty-matching
  above). herdr answers with compact single-line JSON, parsed with
  the portable `(modaliser json)` reader — the multiline `awk`
  parsers used for tmux/zellij do not transfer.

```
pane.current       {}   # focused pane_id + its tab_id / workspace_id
pane.process_info  {}   # innermost foreground command of that pane
```

Every method is checkable against `herdr api schema --json`
(protocol 18). The transport itself — socket path, timeout, envelope,
and the one `herdr-query` read seam every herdr caller shares — lives
in `(modaliser muxes herdr-socket)`, separate from the backend
because the herdr *blocks* need it too and `(modaliser muxes herdr)`
imports those.

**Single-client v1 assumption.** Because focus is global per
session, two herdr clients attached to one session share one focus
and cannot be disambiguated — a documented v1 non-goal (the common
single-client case is unambiguous). No per-client tty correlation
like zellij's multi-session route (§ zellij above) is needed.

**Descent (herdr → nvim).** `pane.process_info` reports the focused
pane's innermost foreground command, so the façade descends one
level further (herdr → nvim) exactly as it does through
tmux/zellij; a plain shell pane reports `zsh`, which matches no mux
and leaves herdr the leaf backend.

For wiring herdr's nested entry point into the iTerm tree, see the
[worked example](../how-to/terminal-pane-aware-tree.md#worked-example-herdr)
and [ADR-0013](../adr/0013-nested-context-entry-points.md). For the
pane-chip caveat, see [herdr pane chips](#herdr-pane-chips) below.

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

Every terminal/mux in the table has a backend module whose record a
configuration value carries; the façade exports the unified op
surface and the capability predicates that let shared actions adapt to
whichever backend owns the focused pane
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
| herdr       | `muxes/herdr`   | Yes — `pane.current` (JSON-RPC Unix socket, global focus per session)    | Agent multiplexer; single-client v1; composed via `(herdr:wiring)`; drives the herdr context entry; socket-only, never the CLI (ADR-0020) |

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

### herdr pane chips

The herdr panes list block paints digit chips over the on-screen
herdr panes. Rects are synthesised tmux-style: `pane.layout`
gives each pane's cell rect and the `area` — herdr's left sidebar
means `area.x`/`area.y` offset that sub-region, but pane rects are
already absolute cells within the *full* canvas (sidebar included),
matching the focused iTerm `AXScrollArea` frame that supplies the
pixel canvas. So the synthesis is **canvas-relative**: pane rects
need no offset subtraction, and the per-cell pixel size divides by
the total canvas (`area.x + area.width` × `area.y + area.height`),
not by `area.width`/`area.height` alone — verified live (2026-07-14,
herdr 0.7.3) against the session's own column/row count.

This is correct when herdr owns the sole iTerm scroll area in its
tab. When the iTerm tab holds other splits too, the host-frame
heuristic takes the *first* `AXScrollArea`, which may be the wrong
split — so chips can land on the wrong pixels. `hjkl` focus and
digit-jump are unaffected (digit-jump focuses by `pane_id` via
`pane.focus`, not by chip position); only the chip *overlay* may be
misplaced — a plain pane-chip-pipeline geometry concern (ADR-0013's
Consequences), not a tree-model one now that there is only one herdr
tree. The proper fix — a focused-iTerm-session-frame primitive that
returns the herdr split's frame directly — is a deferred follow-up.

### herdr tab / space reorder: the insert-index model

The `T` Tabs drill's `m` Move walk (`h` Left / `l` Right) reorders the
focused tab within its workspace's bar; the `S` Spaces drill's (`k` Up /
`j` Down) reorders the focused space in the sidebar. Each direction key
re-arms, so presses chain. Both go through `herdr-cmd` on herdr 0.7.5's
`tab.move {tab_id, insert_index}` / `workspace.move {workspace_id,
insert_index}`.

Three properties of herdr's wire contract shape the implementation
(read out of herdr 0.7.5's `app/api/tabs.rs`, `app/api/workspaces.rs`,
`workspace.rs::move_tab` and `app/actions.rs::move_workspace`):

- **`insert_index` is a *gap* index into the list *before* the target is
  removed**, valid `0…len` inclusive — `> len` answers a
  `tab_move_failed` / `workspace_move_failed` error envelope. The server
  removes then inserts, so the resulting position is
  `source < insert ? insert - 1 : insert`. The two directions are
  therefore **not symmetric**: one place later is `pos + 2`, one place
  earlier is `pos - 1`. That conversion is
  `reorder-insert-index` in `(modaliser muxes herdr)`, a pure tested
  function; the ops around it are thin shells.
- **Display order is the `<kind>.list` array order.** A tab's `number` is
  *not* its display order — it is a stable public identity that rides
  through a reorder unchanged (pinned by herdr's own
  `tab_info_number_uses_stable_public_tab_number` test), which is also
  why a `tab_id` stays valid across a move. Earlier revisions of this
  document described `number` as display order; that was wrong.
- **Exactly one row in a whole `tab.list` payload is `focused`** — the
  active workspace's active tab — and likewise one across
  `workspace.list`. So one query yields the target's id, its position
  *within its own scope*, and that scope's length; no `pane.current`
  round-trip is needed. `tab.list` returns every tab in the session, so
  the position must be counted among rows sharing the focused row's
  `workspace_id`, not over the whole array.

Two behaviours follow from those, both deliberate:

- **The op reads its own index fresh on every press**, rather than
  reusing the drill's live-list snapshot the way digit-jump and `[`/`]`
  do. The line is: reuse the snapshot when the user is *choosing* among
  rows they can see; read fresh when *mutating*. Reuse would also lose
  presses — the Move keys re-arm, so a fast `l l l` that outran the
  panel's re-render would recompute one index three times and advance the
  tab once.
- **Either end is a no-op, not a wrap.** `[`/`]` ring cycling wraps, but
  that moves focus; this moves content, and its nearest neighbour `m`
  Move Pane (`pane.swap`) no-ops at the edge of the layout. The edge is
  expressed as `#f` from the pure arithmetic, so no request goes out at
  all.

Historical note: this was a v1 exclusion blocked upstream — herdr 0.7.1
exposed only `list · create · get · focus · rename · close` for tabs, and
reordering was mouse-drag-only in the TUI
([ogulcancelik/herdr#770](https://github.com/ogulcancelik/herdr/issues/770),
"Add tab.reorder to socket API + CLI", closed not-planned). herdr 0.7.5
shipped the verbs anyway.

## See also

- [terminal-pane-aware-tree.md](../how-to/terminal-pane-aware-tree.md)
- [add-a-per-app-tree.md](../how-to/add-a-per-app-tree.md)
