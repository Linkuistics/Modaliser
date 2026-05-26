---
kind: work
---

# 025 — Hand-verify every backend end-to-end

## Goal

Run the live, interactive checks that the per-backend implementation
leaves under `done/020-implement/` couldn't complete from a background
session. AppleScript focus, AX-trust paths, and chip-rendering
geometry are only honest once Modaliser itself (which has TCC trust)
drives the code against a real window.

This leaf is **the user**; it can't be machine-executed. Each item
either confirms the implementation works, or files a follow-up.

## Backends to verify

Reproduced from `done/020-implement/BRIEF.md` § "Hand-verification
debt". One section per backend, each a self-contained run-through.

### tmux

- Open iTerm with a single split, run tmux inside; verify
  `(terminal:focus-pane-h)` etc. routes to tmux ops.
- Press leader → `g` → digit; chips should land within ~1 cell of
  the right tmux panes.
- **Known soft spot:** multi-iTerm-split + tmux chip rendering
  takes the first AXScrollArea in v1; multi-split is a refinement
  for the cross-cutting host cell-dim helper (likely lands with the
  kitty work or a follow-on).

### zellij

- Same as tmux, but with zellij. Single-session is the daily case
  and is fully supported.
- Multi-zellij-session: launch zellij with `--session NAME` or
  attach to a specific session; verify the right session takes the
  ops (the backend parses `--session` / `attach NAME` from
  `ps -p PID -o args=`).
- Unusual launch shapes (wrapper scripts, `zellij --layout …` with
  no explicit session, attached via socket without `--session`) will
  miss the session name and fall back to the default session.
  Document as a v1 limit, file follow-up only if encountered.

### WezTerm

- `brew install --cask wezterm` (uninstall after, unless retained).
- Open WezTerm with 2-3 splits; run hjkl focus + split-h/j/k/l +
  digit-jump.
- Verify `(terminal:supports-move-pane?)` reports `#f` and the
  move-pane group is omitted from any capability-gated tree.
- **Known soft spot:** chip rendering assumes WezTerm exposes panes
  as `AXScrollArea`. Not verified live; if WezTerm uses a different
  role (likely `AXGroup` in newer versions) chips simply don't
  render and digits still dispatch via the hidden key-range fallback.

### Kitty

- `brew install --cask kitty` (cask 0.47.0 is the version probed
  during implementation).
- Run `(kitty:configure-entry)` + relaunch Kitty.
- Open 2-3 panes, run hjkl focus + split-h/j/k/l + move-pane-h/j/k/l
  + digit-jump.
- Visually confirm chips land within ~1 cell-width of correct
  positions (the [[feedback_chips_are_overlays]] bar).
- Verify `(terminal:supports-zoom?)` reports `#f` and the zoom
  binding is omitted.
- **AX-subview probe** — confirm which of the three-layer fallback
  paths activates (AX-per-pane → AX-host-frame + position-prop →
  no-chips key-range). Implementation note's intended path was
  unclear from a sidecar `swift` CLI which lacks TCC trust.

### Ghostty

- `brew install --cask ghostty` (cask 1.3.1).
- Open 2-3 splits via the overlay, run hjkl focus + split-h/j/k/l
  + digit-jump (no move-pane — gap is honest, gated by
  `(supports-move-pane?)`).
- Verify `(terminal:supports-zoom?)` reports `#t` and
  `(terminal:supports-move-pane?)` reports `#f`.
- Visually confirm chips land within ~1 cell-width of correct
  positions.
- Confirm whether AX returns one rect per pane or one for the whole
  window — only the former lets chip count match split count cleanly;
  the latter would need a follow-up to derive per-pane geometry as
  Kitty's BFS does.
- **Known soft spot:** phantom-terminal leak in AppleScript
  enumeration grows with each split. Implementation mitigates by
  truncating chip list to AX-rect count; directional ops are
  unaffected (Ghostty's own `goto_split:<dir>` routes only between
  real panes).

### Alacritty

- Install via the recommended path (direct GitHub-releases DMG;
  brew cask is Gatekeeper-deprecated AND quarantine-blocked).
- Confirm `org.alacritty` is the bundle-id via
  `mdls -name kMDItemCFBundleIdentifier /Applications/Alacritty.app`.
  If different, edit the `make-terminal-backend` literal in
  `Sources/Modaliser/Scheme/lib/modaliser/apps/alacritty.sld`.
- Confirm `(alacritty:configure-entry)` stays hidden after the
  direct-DMG install (no quarantine xattr).
- Optionally: re-install via `brew install --cask alacritty`,
  confirm the entry appears, run it, confirm the entry vanishes
  and Alacritty launches.
- Run tmux (or zellij) inside Alacritty as `shell.program`; press
  leader → focus-pane-left; verify the mux backend takes over (the
  Alacritty backend supplies only the host frame of
  `focused-terminal-path`).
- Verify `(focused-terminal-path)` looks like
  `'((alacritty . #(pane #f fg "tmux"))
     (tmux . #(pane "%0" fg "nvim")))` when nvim is running inside
  tmux inside Alacritty.
- Uninstall Alacritty after probing
  (`rm -rf /Applications/Alacritty.app`) unless retained.

## Done when

All six backends have been driven by hand and either:

- Confirmed working (note in the relevant ADR or the root BRIEF's
  "Machine state"), or
- A follow-up leaf has been planted for any gap that needs code
  changes.

The leaf retires after the user signs off on each section.

## Pointers

- The implementation each section verifies lives under
  `Sources/Modaliser/Scheme/lib/modaliser/{apps,muxes}/<backend>.sld`.
- The hand-verify checklist originally came from
  `done/020-implement/BRIEF.md` § "Hand-verification debt" — promoted
  here at 020-implement retirement so it survives the move.
- Per [[feedback_install_flow]] — Modaliser must be re-installed
  via `./scripts/install.sh` after any source change; "Relaunch" alone
  restarts the stale `/Applications` bundle.
