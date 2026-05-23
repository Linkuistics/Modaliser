# Alacritty (signed direct-install) — investigation notes

**Version probed:** `Alacritty 0.17.0 (94e7c88)` — same upstream as
the brew cask (and same `Signature=adhoc`), but downloaded directly
from `https://github.com/alacritty/alacritty/releases` via `curl`
and copied to `/Applications/` without involving brew.
**Classification — confirmed from 070:** detection-only backend.
This re-investigation **live-verified** what 070 read from manpages.

## Why this works when brew's cask didn't

070's "macOS refuses to launch it for security reasons" was
*half-right* — the binary IS adhoc-signed (both via brew cask and
via the direct DMG; `codesign -dv` reports `Signature=adhoc` in both
cases). The difference is the **quarantine attribute**:

- Brew cask install → installer carries `com.apple.quarantine` →
  Gatekeeper enforces (silently kills).
- Direct `curl + hdiutil + cp` → no quarantine bit set → Gatekeeper
  doesn't trigger.

`xattr -l` on the brew-installed cask in 070 showed both
`com.apple.provenance` AND `com.apple.quarantine`. The
direct-install version shows only `com.apple.provenance`. macOS
quarantine is set by user-agents (Safari, Mail, App Store
download UI); `curl` doesn't set it.

**Recipe for users hitting the brew Gatekeeper issue:** after
`brew install --cask alacritty`, run
`xattr -d com.apple.quarantine /Applications/Alacritty.app`. The
binary then runs.

## Live-verified findings

### Binary runs

```
/Applications/Alacritty.app/Contents/MacOS/alacritty --version
→ alacritty 0.17.0 (94e7c88)
```

### IPC works

`alacritty msg <subcommand>` against an explicit `--socket` path
verified. The three subcommands from the manpages are all
present:

```
$ alacritty msg --help
Commands:
  create-window  Create a new window in the same Alacritty process
  config         Update the Alacritty configuration
  get-config     Read runtime Alacritty configuration
```

`get-config` returns a multi-KB JSON dump of the live config
(font, colors, mouse, hints, terminal, etc.). Useful for runtime
introspection of the user's actual config including any non-
defaults that affect detection (window padding, font size for
cell-pixel-dim derivation if Alacritty ever gets panes — it
doesn't, so moot).

### create-window works (multi-window in same process)

```
$ alacritty --socket /tmp/sock -e bash -c 'sleep 600' &
$ alacritty msg --socket /tmp/sock create-window -e bash -c 'sleep 600'
$ pgrep -P <alacritty-pid>
55123
55251       # ← second child shell after create-window
```

Two child shells under the same alacritty parent — confirms
"new window in same process" semantics. **Implication for
detection:** multiple Alacritty windows can share a single
parent PID; walk `pgrep -P` to enumerate children, not
`pgrep -x alacritty`.

### AppleScript surface — minimal

`sdef /Applications/Alacritty.app` returns error -192 — **no
AppleScript scripting dictionary**. The app responds to
`tell application "Alacritty"` minimally but fails on basics
like `count of windows` (error -1708: "every window doesn't
understand the count message"). Confirmed: Alacritty has **no
useful AppleScript surface**.

This is unlike Ghostty 1.3.0+ (which exposes a rich SDEF) and
iTerm (which has a comprehensive AppleScript API).

## Detection model — live-confirmed

Per `sdef`-free, no-AppleScript world, detection paths are:

1. **Single window per Alacritty instance** (simplest, most common):
   - `pgrep -x alacritty` → parent pid
   - `pgrep -P <parent>` → one child shell pid
   - `lsof -p <child> -d 0` → tty
   - `ps -t <tty> -o pgid=,tpgid=,command=` → foreground command

2. **Multiple windows in one Alacritty instance** (after
   `alacritty msg create-window`):
   - Same parent pid, multiple children from `pgrep -P`
   - **Cannot disambiguate which window is focused** without AX.

3. **Multiple Alacritty instances** (separate launches):
   - Multiple parent pids from `pgrep -x alacritty`.
   - For each, walk children as above.
   - Same focus-disambiguation problem.

The "indirect and inexact" path for multi-window:
- AX walk of NSWindow positions to find the focused/frontmost
  Alacritty window → correlate with shell title or other side
  channel. **TCC-required, untested from probe shell.**

## Op surface

Still **n/a** — Alacritty has no panes/splits by design. Users
who want panes inside Alacritty run a multiplexer (tmux/zellij)
as the shell. The mux backend takes over the 13-op surface;
Alacritty just hosts.

## Departures from 070

1. 070 said macOS "refuses to launch" the binary. **Refined:**
   it refuses to launch *quarantined* installs. The same binary
   bypassing quarantine (direct curl download) runs fine.
2. 070 was authoritative-by-manpage. **Live verification confirms
   manpages were accurate.** No surprises.
3. 070 didn't note that `sdef` returns -192 — Alacritty has no
   AppleScript dictionary at all. (Now confirmed, supporting the
   "external mechanisms only" detection story.)

## Updated capability matrix row

| Backend          | Type             | Detection                                              | 13-op surface | Mechanism                                  | Chip render |
|------------------|------------------|--------------------------------------------------------|---------------|--------------------------------------------|-------------|
| Alacritty 0.17.0 | host (no splits) | process-tree (`pgrep -P <alacritty-pid>` + `lsof -p`); AX for multi-window focus disambiguation | not applicable | `alacritty msg` (window mgmt only); no AppleScript SDEF; no pane CLI | not applicable; chips come from mux backend running inside |

## Recommendation for production install path

Modaliser docs should point Alacritty users at the GitHub
releases DMG, not the brew cask. The brew cask is
Gatekeeper-deprecated AND triggers the quarantine issue. Direct
download bypasses both. Alternatively, the docs can mention the
`xattr -d com.apple.quarantine` workaround as a brew-install
postscript.

## Open verification items

- AX hierarchy of Alacritty.app — does each NSWindow expose
  attributes that allow correlating to its child shell pid?
  Title-based correlation works if user's shell sets meaningful
  titles. Production has TCC; testing deferred.
- Whether `alacritty msg config -w -1 <opts>` (apply to all
  windows) is useful for the abstraction — probably not, since
  Alacritty has no panes to configure per-window-specifically.

## Teardown completed

- Killed all alacritty processes.
- Removed `/Applications/Alacritty.app` (manually `rm -rf`).
- Removed `/tmp/Alacritty-v0.17.0.dmg` and socket.

The machine returns to its pre-075 state.
