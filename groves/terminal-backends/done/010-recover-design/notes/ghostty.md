# Ghostty — investigation notes

**Version probed:** `Ghostty 1.3.1` (homebrew cask, current as of
2026-05-23).
**Classification — for THIS version:** detection-only backend
(no IPC, no AppleScript scriptability for panes, no usable
external query for focused-pane state).
**User recall:** workarounds were gated on **v1.4+**. Brew currently
ships 1.3.1 — the workarounds the prior investigation found are
**not available in this cask**.

## Live-probe environment

`brew install --cask ghostty` installs the .app. No CLI binary is
symlinked to `/opt/homebrew/bin` — invoke via
`/Applications/Ghostty.app/Contents/MacOS/ghostty`. The CLI accepts
**no pane-control subcommands**: only configuration-passing,
`-e <command>` for one-shot execution, and `+actions` (version,
help, list-fonts, list-keybinds, list-themes, list-actions).

Probing Ghostty's UI state from outside requires either macOS AX
(TCC-gated; my probe shell lacks Accessibility permission with
error `-25211`) or process-tree walking. Modaliser production code
holds the required TCC permissions; this audit defers the AX-walk
result to implementation.

## Op surface — 1.3.1 is severely limited

### Actions exist in the action vocabulary (config-file level)

Ghostty exposes these split-related actions for users to bind in
`~/.config/ghostty/config`:

- `new_split:right`, `new_split:down` (confirmed via defaults
  cmd+d / cmd+shift+d)
- `new_split:left`, `new_split:up` — **untested in this probe;
  may or may not be valid action args.** No default keybind ships
  for them.
- `goto_split:up`, `goto_split:down`, `goto_split:left`,
  `goto_split:right`, `goto_split:next`, `goto_split:previous`
  (defaults cmd+alt+arrow + alt+hjkl)
- `toggle_split_zoom`, `resize_split:<dir>,<amount>`,
  `equalize_splits` (out of scope for the 13-op surface)

**Notably absent:** `move_split` (swap pane), `select_split`
(focus by digit/id). Ghostty 1.3.1 has **no swap-pane equivalent
of any kind**.

### Mapping to the 13-op surface

| Locked op            | 1.3.1 path                                | Verified |
|----------------------|-------------------------------------------|----------|
| `focus-pane-h`       | keystroke-proxy cmd+alt+left (default goto_split:left) — or alt+h | confirmed default keybind exists |
| `focus-pane-j`       | keystroke-proxy cmd+alt+down — or alt+j   | confirmed |
| `focus-pane-k`       | keystroke-proxy cmd+alt+up — or alt+k     | confirmed |
| `focus-pane-l`       | keystroke-proxy cmd+alt+right — or alt+l  | confirmed |
| `split-pane-h`       | **NO DEFAULT KEYBIND**. User must add `keybind = super+something=new_split:left` if `:left` action arg is valid (untested). Otherwise keystroke-proxy cmd+d (new_split:right) followed by... nothing — no swap exists. **GAP.** | gap |
| `split-pane-j`       | keystroke-proxy cmd+shift+d (new_split:down) | confirmed |
| `split-pane-k`       | gap (same as split-pane-h)                | gap |
| `split-pane-l`       | keystroke-proxy cmd+d (new_split:right)   | confirmed |
| `move-pane-{h,j,k,l}`| **NO ACTION EXISTS.** No workaround in 1.3.1. | gap |
| `focus-pane-by-digit`| **NO ACTION EXISTS.** No `select_split` by id; `goto_split:next/previous` cycles only. No chip overlay. | gap |

### Honest verdict for 1.3.1

Operations: maybe 6/13 with luck (4 focus directions + 2 verified
splits + maybe 2 more splits if `new_split:left/up` are valid
args). Move-pane and focus-by-digit are entirely missing.

**For phase 2 against 1.3.1: treat Ghostty as a detection-only
backend.** Users add a mux (tmux/zellij) inside Ghostty for the
13-op surface.

### Detection in 1.3.1

No native query — must use external mechanisms:

1. **AX walking (TCC-required).** Ghostty.app is an AX-accessible
   macOS app. Modaliser walks AX subviews of the frontmost
   Ghostty window to find the focused split. Untested from probe
   shell (no TCC); presumed to work in production.
2. **Process-tree walking.** `pgrep -x ghostty` → ghostty pid →
   `lsof -p <pid>` → ptys held by that process → for each pty,
   `ps -t <name> -o tpgid=,...` for foreground command. The
   *focused* pty among multiple is the hard part; correlate with
   AX (which window is frontmost) or fall back to "most recently
   active" heuristic.

Phase-1 docs (`docs/reference/terminal-detection.md:179-186`) said
"Ghostty has no control CLI; pane state is not queryable from
outside the process." For 1.3.1 this remains correct.

## What the user's "1.4+ workaround" might be

Reasoning from Ghostty's roadmap and release notes (which I can't
verify from this shell):
- Ghostty has been adding a **`+inspect` action** for runtime
  introspection.
- There has been **discussion of a control socket / SwiftUI
  inspector** in the project.
- The user's recall is consistent with 1.4 adding *one of these*.

When 1.4 lands on brew, a future task revisits.

## Chip rendering

Same scaffolding as kitty/iTerm: `hints-show` with screen rects
from AX. But Ghostty 1.3.1 has no way to enumerate per-pane cell
coordinates from outside — so even with AX subview discovery,
chip-rendering for >1 pane is the same difficulty as kitty's
without `ls` JSON.

For detection-only classification: chip rendering doesn't apply
(no pane enumeration → no `focus-pane-by-digit`). When users add
a mux inside Ghostty, the mux backend's chip rendering handles
it, using Ghostty's window AX frame as the host frame.

## Side effect — Ghostty was auto-launched by probe

`osascript -e 'tell application "Ghostty" to count of windows'`
launched Ghostty via Launch Services (the standard AppleScript
auto-launch behaviour). Probe teardown must quit Ghostty before
uninstalling. **Lesson for backends with AppleScript probing:**
use the `is running` guard pattern (per `terminal.sld:30-31`) to
prevent auto-launch during detection.

## Capability matrix row

| Backend       | Type             | Detection                                | 13-op surface              | Mechanism            | Chip render |
|---------------|------------------|------------------------------------------|----------------------------|----------------------|-------------|
| Ghostty 1.3.1 | host (no API)    | AX-walk of Ghostty.app subviews (TCC) OR process-tree + lsof | partial (~6/13 best, ~4/13 confirmed) | keystroke-proxy via default keybinds | not applicable (recommend detection-only classification) |
| Ghostty ≥ 1.4 | TBD              | TBD (user recall: workarounds exist)     | TBD                        | TBD                  | TBD |

## Recommendation deferred to 080

Treat Ghostty as **detection-only against 1.3.1**, with a stub for
"upgrade to splitting backend if v ≥ 1.4 and the workarounds the
user recalled materialise." Document the gate clearly so users
running 1.3.1 understand splitting requires a mux inside.

Re-investigate Ghostty in a future task when brew's cask passes
1.4.0.
