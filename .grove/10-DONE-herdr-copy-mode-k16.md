# herdr-copy-mode-k16

**Kind:** work

## Goal

Make a **copy / scrollback-selection mode reachable from the herdr trees** — the
gap the user hit during live-verify (k11): in the **replace** tree (`/herdr`,
herdr is the sole iTerm split) there are *zero* iTerm controls by design, so
there is no way to reach iTerm's Copy Mode. The user needs copy mode available
there. Confirmed with the user live: "I do need the copy mode from iTerm
available even when there is just one pane showing herdr — unless herdr has a
copy mode."

## Context

Read the root `BRIEF.md` (herdr design charter). This is a small additive control,
but with a real **design fork** — resolve it first (a short grill is fine), then wire.

**What already exists (plain iTerm tree).** Copy Mode is a top-level key that
sends the iTerm keystroke `Cmd+Shift+C`:
- `Sources/Modaliser/Scheme/app-trees/com.googlecode.iterm2.scm:116` —
  `(key "c" "Copy Mode" (λ () (send-keystroke '(cmd shift) "c")))`
- portable DSL form in `lib/modaliser/apps/iterm.sld:533` —
  `(key "c" "Copy Mode" (keystroke '(cmd shift) "c"))`

**What herdr offers (grounded from the CLI, v0.7.1).**
- herdr's **CLI has no interactive copy mode.** Closest is `herdr pane read
  <pane_id> [--source visible|recent|recent-unwrapped] [--lines N] [--format
  text|ansi]` — a *programmatic* scrollback dump to stdout, not interactive
  selection. Not what the user wants.
- herdr's **TUI** binds `edit_scrollback = "prefix+e"` (from `herdr --default-config`)
  — its native scrollback view, editor-style, per-pane. Triggering it from
  Modaliser would mean sending herdr's `prefix e` keystrokes (fragile: depends on
  the user's herdr prefix binding; no CLI verb for it).

**The fork.**
1. **iTerm Copy Mode (host keystroke)** — bind `c "Copy Mode"` → `Cmd+Shift+C`.
   In replace mode herdr owns the sole iTerm session, so the keystroke lands on
   it; in augment mode it lands on the focused (herdr) split. Matches the user's
   explicit ask. **Likely the answer** — trivial, reuses the existing binding.
2. **herdr-native scrollback** (`prefix+e`) — send herdr's own keybinding. More
   "correct" layering (herdr-direct) but fragile and editor-style, not on-screen
   selection.

**Where it slots in (layering matters).** The herdr base tree is
`muxes/herdr.sld` `build-herdr-tree` (~line 649); the **config** splices the
variant screens — `(screen 'com.googlecode.iterm2/herdr …)` (replace) and
`…/herdr+split …` (augment, = base tree + `iterm:build-iterm-splits-drill`). An
iTerm keystroke is **host-specific**, so it arguably belongs at the **config
composition layer** (the iTerm app-tree that already wraps both variant screens),
NOT in the portable, host-agnostic `muxes/herdr.sld`. Decide placement so both
replace and augment get `c` with identical muscle memory. Portability contract:
if it *does* go in `lib/modaliser`, no `(lispkit …)` — run
`scripts/check-portable-surface.sh`.

## Done when

- `c "Copy Mode"` (or the chosen affordance) is reachable at the herdr tree top
  level in **both** replace and augment modes, and confirmed to trigger copy mode
  against the live herdr-in-iTerm window.
- Fork decided and recorded (a line in the relevant `.sld`/config header; an ADR
  only if the layering choice earns one — probably not).
- Config synced both ways: user `~/.config/modaliser/` ↔ bundled
  `Sources/Modaliser/Scheme/` ([[feedback_config_sync]]).
- `swift test` + `check-portable-surface.sh` green; any behavioural `.sld` change
  gets a matching test.

## Notes

- This is a keystroke, not a socket op — no JSON parsing.
- Chips/overlay are irrelevant here; copy mode is a single leaf key.
- Live re-check folds naturally into the next herdr-in-iTerm session (same setup
  as k11: `./scripts/install.sh` → Relaunch → herdr frontmost → F17 → `c`).
