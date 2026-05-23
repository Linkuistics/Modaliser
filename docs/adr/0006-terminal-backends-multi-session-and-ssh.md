# Terminal-backends: multi-session local muxes via tty correlation

Multiple local tmux/zellij clients running in different host panes
(e.g. one iTerm pane attached to tmux session "work", another to
session "personal") is a **day-one case**, not undefined behaviour.
The notes from the recovery investigation (notes/tmux.md,
notes/zellij.md, retired into `groves/terminal-backends/done/`)
classified multi-session as "hacky, defer"; this ADR overrides that.

## Tty correlation

For multiple local tmux clients:

1. Detect focused iTerm pane via existing AX path (`terminal.sld`).
2. Read that pane's controlling tty via `focused-iterm-tty` (existing).
3. Enumerate local mux clients: `pgrep -f '^tmux '` → for each pid,
   `lsof -p <pid> -d 0` returns its controlling tty.
4. Match the mux client whose tty matches step 2's tty.
5. Read the matched client's session via `tmux list-clients -F
   '#{client_tty} #{session_name}'` (or by inspecting its argv).
6. Target CLI commands at that session:
   `tmux -t <session> select-pane -L` &c.

Zellij is analogous: `pgrep -f '^zellij '` + `lsof` + `zellij
list-sessions` + `zellij --session NAME action ...`.

The correlation result is cached per leader-press (the existing
rebuild-per-press pattern), so the `pgrep`/`lsof` cost is amortised
across all dispatches in one leader sequence.

## SSH'd muxes — explicitly out of scope

When `focused-terminal-foreground-command` returns `"ssh"`, the
abstraction treats ssh as any other host-pane foreground command:
the host backend (iTerm, WezTerm, …) serves the 13 ops, applied to
the host pane that ssh is running in. Modaliser does **not** try to
reach into the remote to drive a remote tmux/zellij.

Users SSH'd into a remote mux navigate that remote mux using its
own native keybindings (tmux prefix `C-b`, zellij defaults). The
abstraction is silent on what's inside the ssh stream — that's the
user's domain, not Modaliser's.

This keeps the v1 scope tight. Cross-host pane control via SSH is
explicitly future work; if it's ever in scope, it likely requires a
remote Modaliser agent or tmux `-CC` control-mode integration, which
is a substantial separate design.

## Trade-off

The alternative was treating multi-session-local as undefined
behaviour (the original recovery-investigation stance). Given the
user has confirmed multi-session-local is a real day-one usage,
undefined behaviour would mean the abstraction silently broke for
common setups. Tty correlation is the only mechanism that solves it
without per-pane configuration.

The cost is `pgrep`/`lsof` walking per leader press, which is fast
enough on macOS to be invisible.
