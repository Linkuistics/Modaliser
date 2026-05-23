# Terminal-backends: multi-session and SSH'd muxes as day-one cases

Multi-session tmux/zellij (multiple local clients in different host
panes) and SSH'd remote muxes (tmux/zellij running on remote hosts via
ssh) are **common from day one**, not edge cases. The notes from the
recovery investigation (notes/tmux.md, notes/zellij.md, retired into
`groves/terminal-backends/done/`) classified multi-session as "hacky,
defer"; this ADR overrides that.

## Local multi-session — tty correlation

For multiple local tmux/zellij clients (e.g. three iTerm panes each
running `tmux attach -t <session-N>`):

1. Detect focused iTerm pane via existing AX path (`terminal.sld`).
2. Read that pane's controlling tty via `focused-iterm-tty` (existing).
3. Enumerate local mux clients: for tmux, `pgrep -f '^tmux '` →
   each pid's controlling tty via `lsof -p <pid> -d 0`. Match tty to
   step 2's tty. The matched process tells us its session via
   `tmux list-clients -t '#{session_name}'` or by inspecting its
   argv.
4. Target CLI commands at the matched session: e.g.
   `tmux -t <session> select-pane -L`.

Zellij is analogous (`pgrep -f '^zellij '` + `lsof` + `zellij list-
sessions` + `zellij --session NAME action ...`).

## SSH'd muxes — keystroke-proxy

For tmux/zellij running on a remote host accessed via ssh:

- `focused-terminal-foreground-command` returns `"ssh"` (the local
  fg cmd in the iTerm pane), not `"tmux"`/`"zellij"`.
- The local CLI cannot reach the remote mux server. CLI mode is
  unavailable.
- **Directional ops (focus / split / move)** use keystroke-proxy
  targeted at the focused iTerm pane. The keystroke flows through
  ssh to the remote shell to the remote mux, which processes it
  natively. Default tmux prefix `C-b` and default zellij keybinds
  are assumed; users override per remote context via config.
- **`focus-pane-by-digit`** is **not supported** over ssh.
  Enumeration requires querying the remote mux, which we cannot do
  from the local side. `(supports-digit-jump?)` returns `#f` when
  the active backend is "ssh + assumed-mux".

## Composite backend resolution

The dispatch flow in `(active-backend)` ([ADR-0003](0003-terminal-
backends-facade-only-public-surface.md)) extends:

```
1. frontmost-app bundle-id → host backend
2. focused-terminal-foreground-command →
   "tmux"   → local tmux backend (CLI mode, tty-correlated session)
   "zellij" → local zellij backend (CLI mode, tty-correlated session)
   "ssh"    → ssh-proxy backend (keystroke-proxy with user-declared
              remote context: tmux / zellij / shell)
   other    → host backend
```

The ssh-proxy backend takes a per-host (or per-context) declaration
of what's running on the remote. Default is "assume tmux with C-b
prefix"; users override:

```scheme
(import (prefix (modaliser terminal) terminal:))

(terminal:declare-remote!
  '(("user@host-a" . tmux)
    ("user@host-b" . zellij)
    ("user@host-c" . shell)))
```

Without a matching declaration, the ssh-proxy backend defaults to
"assume tmux"; users with shell-only remotes opt out by declaring
`shell`.

## Trade-off

The alternative was treating multi-session and ssh as undefined
behaviour (the original recovery-investigation stance). Given the
user has confirmed both are common from day one, undefined behaviour
would mean the abstraction silently broke for the most common
real-world setup. Tty-correlation for local multi-session and ssh-
proxy with declarations for remote muxes are the cleanest paths
that don't require remote agents or screen scraping.

The cost is implementation: two mux backends each have local-CLI and
keystroke-proxy modes; tty correlation needs `pgrep`/`lsof` walking
on every dispatch (cached per leader press).
