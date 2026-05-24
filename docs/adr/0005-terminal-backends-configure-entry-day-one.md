# Terminal-backends: configure-entry ships day-one per backend

Every backend whose op surface or detection requires user-side
configuration ships a `configure-entry` overlay action from day one,
not as future work. The configure-entry pattern is what closes
gaps between "what the backend exposes natively" and "what Modaliser
needs from it" — without it, the abstraction would either ship
permanent capability holes or push provisioning onto users as a
read-the-docs step.

Day-one configure-entry coverage:

- **iTerm2 (existing).** Writes split / move keybinds into
  `~/Library/Preferences/com.googlecode.iterm2.plist`.
- **WezTerm.** ~~Appends move-pane keybinds to the user's
  `wezterm.lua` (which Modaliser then invokes via keystroke-proxy).
  Without this, WezTerm is 13/14 (raw); with it, 14/14.~~
  **Reversed at implementation time** (020-implement/050): re-probe
  found WezTerm has no directional pane-swap primitive — not in CLI
  (`activate-pane-direction` is focus, `adjust-pane-size` is resize,
  `split-pane --move-pane-id` moves into a new split), not in default
  keybinds (`RotatePanes` is global Clockwise/CCW), not in the Lua
  pane API. A keybind would have nothing to call. WezTerm ships at
  13/14 with no configure-entry; move-pane is honestly absent like
  Ghostty. Re-add a configure-entry if a future WezTerm release adds
  the primitive.
- **Kitty.** Sets `allow_remote_control yes`, `listen_on
  unix:/tmp/kitty-modaliser`, and ensures `enabled_layouts` includes
  `splits` in `~/.config/kitty/kitty.conf`. The `listen_on` directive
  was added at implementation time (020-implement/060) after the
  recovery notes' live-probe pattern (`kitty @ --to=unix:…` with
  `--listen-on=` at launch) made it clear Kitty's per-instance
  abstract socket isn't reachable from outside its own terminal —
  Modaliser, running as a separate process, needs a known socket
  path to call `kitty @` against. Without `listen_on`, the IPC is
  refused even with `allow_remote_control yes`. Without `splits` in
  `enabled_layouts`, `launch --location=vsplit` falls back to the
  wrong layout — i.e. 0/14. The user's existing kitty.conf (a 98-line
  A/B-rendering mirror of `wezterm.lua`) is backed up to
  `kitty.conf.modaliser-backup` once on first run; the backup is kept
  forever so the pre-Modaliser file remains restorable. (Kitty stays
  13/14 even with configure-entry — no native zoom.)
- **Alacritty.** Optional: `xattr -d com.apple.quarantine
  /Applications/Alacritty.app` if installed via the (Gatekeeper-
  deprecated) brew cask. Required only when the brew install path
  was used; no-op when Alacritty was installed from the direct
  GitHub-releases DMG.

Backends with **no** day-one configure-entry:

- **Ghostty 1.3.0+.** The `move_split` keybind action does not exist
  in Ghostty's vocabulary; no amount of user config closes the gap.
  Ghostty stays 12/13 until upstream adds the action. A
  `configure-entry` may land at that future point.
- **tmux, zellij.** Native CLI works out of the box; no provisioning
  needed for the 14-op surface or detection. (Future tweaks like a
  display-panes keybind for the user's own ergonomics are not in
  scope.)

Capability predicates ([ADR-0004](0004-terminal-backends-capability-predicates.md))
reflect *current* configured state — `(supports-move-pane?)` is `#f`
before WezTerm's configure-entry runs and `#t` after. This makes
provisioning user-visible in trees that rebuild per-press: the
move-pane bindings appear once the user accepts the overlay.

The trade-off is implementation work upfront for each provisioning
backend vs shipping capability holes the user works around manually.
Given the user has already prioritised "functions that work across
all terminals/muxes" (ADR-0003), shipping holes contradicts that
goal; configure-entry from day one is the consistent choice.
