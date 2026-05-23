---
kind: work
---

# 080 — Build the Alacritty backend

## Goal

New module `(modaliser apps alacritty)` exporting `alacritty:register!`
and `alacritty:backend`. Detection-only backend — all 14 ops are
`#f`. Optional `alacritty:configure-entry` to remove
`com.apple.quarantine` if the user installed via the brew cask.

## Context

- Recovery notes: `groves/terminal-backends/done/010-recover-design/
  notes/alacritty.md` and `notes/alacritty-signed.md` — Alacritty
  has no AppleScript SDEF; `alacritty msg` is window-management
  only; detection via process-tree walk (`pgrep -P <parent>` for
  multi-window in same instance).
- ADR-0005 — optional configure-entry: `xattr -d com.apple.quarantine
  /Applications/Alacritty.app`. Only useful if installed via the
  Gatekeeper-deprecated brew cask.
- Install pattern from notes/alacritty-signed.md: **direct GitHub-
  releases DMG**, not brew cask. The cask installs an adhoc-signed
  binary that macOS refuses to launch. Direct DMG bypass: `curl`
  download + `hdiutil` + `cp` to `/Applications/`.

## Done when

- Alacritty installed (preferred: direct GitHub-releases DMG;
  fallback: brew cask + `xattr -d com.apple.quarantine`). Record
  exact version + install path.
- New module `(modaliser apps alacritty)` exports
  `alacritty:register!`, `alacritty:configure-entry`,
  `alacritty:backend`.
- Internal record fields populated:
  - All 14 op fields = `#f`. `(supports-splits?)`,
    `(supports-move-pane?)`, `(supports-digit-jump?)`,
    `(supports-zoom?)` all `#f` for Alacritty alone.
  - `focused-pane-id` returns `#f` (no pane concept).
  - `detect-foreground-command` via `pgrep -x alacritty` →
    `pgrep -P <parent>` → `lsof -p <child> -d 0` → tty →
    `ps -t <tty>` for fg cmd. Single-window case only is
    well-supported per notes; multi-window-multi-instance falls
    back to AX (TCC-required, runs in production).
  - `configured?` checks for `com.apple.quarantine` on the .app;
    returns `#t` if absent.
- `alacritty:configure-entry` overlay action: shows the user the
  `xattr -d com.apple.quarantine` command and runs it on
  confirmation. Only useful for brew-cask installs.
- Hand-verify: with Alacritty + tmux (or zellij) running inside,
  pressing leader → `(terminal:focus-pane-left)` routes to the
  *inside-mux* backend correctly (the host backend is detection-
  only; the mux takes over the 14 ops). `(focused-terminal-path)`
  returns `'((alacritty . #(pane #f fg "tmux")) (tmux . #(pane "%0"
  fg "nvim")))`.
- Uninstall after probe — `rm -rf /Applications/Alacritty.app`.

## Notes

- The direct-DMG install path is the recommended one for users per
  notes/alacritty-signed.md, but Modaliser docs may still cover the
  brew-cask path with the quarantine-removal workaround. The
  `alacritty:configure-entry` exists for users who chose the
  brew route.
- Detection-only means most of the file is documenting what's NOT
  implemented. Keep it short — the record-population code is mostly
  literal `#f` fields.
- The Modaliser+Alacritty value proposition is small (just the
  detection primitive driving the suffix hook), but it completes
  the matrix and proves the abstraction handles the edge case
  cleanly. Worth doing.
