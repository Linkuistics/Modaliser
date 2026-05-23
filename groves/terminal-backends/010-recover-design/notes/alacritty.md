# Alacritty — investigation notes

**Version probed:** `Alacritty 0.17.0` (homebrew cask, installed
fresh this session; binary couldn't be executed because **macOS
refuses to open it for security reasons** — confirmed by the user.
Findings derived from manpages, which are installed-and-authoritative).
**Classification:** detection-only backend.
**Brew cask deprecation note:** `brew info` warns the cask will be
disabled 2026-09-01 because the binary "does not pass the macOS
Gatekeeper check." The cask installs an adhoc-signed binary that
the user's macOS refuses to launch. Even right-click-open won't
bypass this on a sufficiently locked-down system.

## Live-probe environment — limited

`/Applications/Alacritty.app/Contents/MacOS/alacritty --version`
returns empty (Gatekeeper kills it). The cask installs cleanly
but the binary is unusable from the shell without removing the
quarantine attribute (admin operation) or right-click-opening the
.app via Finder (interactive). Probe shifted to reading the
manpages:

```
man -P cat alacritty       # alacritty(1)
man -P cat alacritty-msg   # alacritty-msg(1) — IPC surface
```

For real Modaliser usage in production, the user removes the
quarantine bit when they install Alacritty themselves; the binary
works. The cask's Gatekeeper issue is a *brew packaging* problem,
not an Alacritty capability gap.

## Op surface — none (by design)

Alacritty has no panes, no splits, no tabs. The 13-op pane surface
is **not applicable**. Users who want panes inside Alacritty
configure tmux or zellij as the shell program in
`~/.config/alacritty/alacritty.toml`:

```toml
[shell]
program = "/opt/homebrew/bin/tmux"
args = ["new-session", "-A", "-s", "default"]
```

The 13-op surface then comes from the tmux/zellij backend, not
from Alacritty.

## IPC surface — present but NOT for pane queries

Phase-1 docs claimed "Alacritty has no IPC." **This is outdated.**
Alacritty has had `alacritty msg` since at least 0.12. In 0.17.0
the surface is:

| Message | Purpose |
|---------|---------|
| `create-window` | Spawn a new window in the same Alacritty process. Inherits or overrides config. |
| `config` | Update Alacritty's configuration at runtime. `-w / --window-id` to target one window or `-1` for all. |
| `get-config` | Read Alacritty's current configuration. |

These are **window-management** messages, not pane-query messages.
There's no `get-foreground-command`, no `list-windows`, no way to
query which window is focused. Pane queries remain impossible by
design (no panes to query).

## Detection — external mechanisms only

Same approach as Ghostty 1.3.1, simpler in practice because each
Alacritty window has *exactly one* pty:

1. **Single-window case** (the typical one): `pgrep -x alacritty`
   returns one pid. `lsof -p <pid> -d 0,1,2` finds its tty(s).
   `ps -t <name> -o pgid=,tpgid=,command=` reads foreground
   command. No focus disambiguation needed.
2. **Multi-window case** ("indirect and inexact"): each Alacritty
   window is a separate child process (or same parent with
   distinct ptys after `create-window`). To find the focused one:
   - **AX walk** (TCC required) — find the focused Alacritty
     NSWindow via AX, correlate with its child shell pid via
     window title or AX hierarchy. Modaliser production has TCC.
   - **Activity proxy** — among all alacritty ptys, the one with
     the most recent stat-mtime is *probably* the focused one.
     Hacky; cited by the user's "indirect and inexact" recall.
   - **Window-title trick** — set the shell to write a unique
     marker to the title; correlate macOS frontmost window's
     title with the pty. Requires user buy-in.

## Chip rendering — not applicable

Alacritty has no panes → `focus-pane-by-digit` doesn't apply.
When users run tmux/zellij inside Alacritty, chip rendering uses
the mux backend's path (Alacritty window AX frame as the host
frame + mux's cell coords + host cell-pixel dims).

## Capability matrix row

| Backend         | Type             | Detection                                                       | 13-op surface | Mechanism                               | Chip render |
|-----------------|------------------|-----------------------------------------------------------------|---------------|-----------------------------------------|-------------|
| Alacritty 0.17.0| host (no splits) | process-tree + lsof (single-window); AX or activity-proxy (multi) | not applicable | `alacritty msg` for window mgmt; no pane CLI by design | not applicable; chips come from mux backend running inside |

## Surprises / departures from phase-1 docs

1. Phase-1 docs (`docs/reference/terminal-detection.md:181-194`)
   said Alacritty has "no IPC." **Outdated as of 0.x and earlier
   for 0.17.0** — `alacritty msg` exists for window/config mgmt.
   The "no splits" half remains true.
2. The current brew cask is **deprecated for Gatekeeper failure**.
   By 2026-09-01 the cask disappears. Modaliser users installing
   Alacritty post-disable will install from source or another
   channel; the binary itself is fine, brew's packaging isn't.

## Recommendation deferred to 080

Ship Alacritty as a **detection-only backend with single-window
optimisation**. Multi-window case uses AX (Modaliser production
has TCC); the activity-proxy hack is the no-TCC fallback.

Phase-2 docs should encourage Alacritty users to run a mux inside,
matching what phase-1 already documents.

## Open verification items

- Live confirmation of `alacritty msg` is **not possible on this
  user's machine** — macOS refuses to launch Alacritty for security
  reasons. Confirmation must come from a different machine or a
  signed Alacritty build (the Alacritty project ships a Mac binary;
  brew's adhoc-signed cask is the problem, not the upstream).
- AX hierarchy of Alacritty.app — same blocker (can't run it).

## Caveat on this audit's authority

Because the binary cannot be executed on the user's machine, all
findings here are from manpages + Alacritty source documentation,
not from live verification. The manpage's authority is high
(maintained alongside the binary, ships in every release), but
runtime quirks (does `alacritty msg create-window` actually behave
as documented?) are unverified.

The user's recall ("we found solutions for every terminal/mux,
sometimes hacks") implies the prior session DID verify Alacritty
live — possibly on a machine with looser security settings, or
with a signed Alacritty build sourced outside brew. Phase 2
implementation will need a Mac that can actually run Alacritty
for end-to-end testing.
