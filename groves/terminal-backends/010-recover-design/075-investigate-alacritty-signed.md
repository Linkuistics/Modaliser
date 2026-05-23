---
kind: work
---

# 075 — Investigate Alacritty (signed release from GitHub)

The 070 task used brew's adhoc-signed cask and could not run the
binary (macOS refuses to launch it). User intervention: **we can
install a properly-signed Alacritty** from the GitHub releases
page.

This task re-runs the 070 audit against a working binary.

## Install

Download the signed DMG from the latest release at
`https://github.com/alacritty/alacritty/releases`. Verify the
signature is proper (`codesign -dv /Applications/Alacritty.app`
should not say `adhoc`). Verify the binary actually runs:
`/Applications/Alacritty.app/Contents/MacOS/alacritty --version`
should output something.

## Probe

- **Verify `alacritty msg`** — the IPC for window management
  (create-window, config, get-config) per the manpages. Confirm
  the messages behave as documented.
- **Single-instance vs multi-instance** — does `alacritty msg
  create-window` reuse the parent process (single PID) or spawn
  a new one? Affects multi-window detection strategy.
- **AX hierarchy of Alacritty.app** — does each window expose an
  attribute identifying its pty/pid? Probe via System Events
  (TCC-required; do via osascript). If yes, multi-window
  detection is clean (no activity-proxy hack needed).
- **Window-title trick** — verify whether shell-set title text
  propagates to the NSWindow title (the typical macOS pattern).
  Useful for the title-correlation detection fallback.

Goal: confirm Alacritty's classification as **detection-only**
(which 070 already concluded) AND verify the detection mechanisms
actually work on a real binary.

## Capture

Write `notes/alacritty-signed.md` with:
- Exact version probed.
- Live confirmation of each manpage-derived finding from 070.
- AX hierarchy findings.
- Multi-window detection mechanism — which fallback actually works.
- Updated capability matrix row.

## Teardown

Same as 065: leave installed unless asked to remove. Update root
`BRIEF.md`.
