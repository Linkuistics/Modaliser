# Terminal backends grove

Phase 2 of the terminal-pane work. Phase 1 (docs only, merged at
`17c3621`) wrote per-backend recipes. Phase 2 lifts those recipes into
`(modaliser terminal)` (or sibling modules) as library calls behind a
uniform abstraction.

## Two surfaces

**Detection (point 1).** Per terminal / multiplexer, presuming it's
front-most: get the focused pane/split + what's running in it. **Every
backend implements this.**

**Operations (point 2).** Abstract pane/split operations across all
*splitting* backends. The locked surface is **14 procedures** (see
[the PRD](../../docs/prd/terminal-backends.md) for the authoritative
list):

- `focus-pane-{h,j,k,l}` — directional focus
- `split-pane-{h,j,k,l}` — directional split
- `move-pane-{h,j,k,l}` — directional move
- `focus-pane-by-digit` — paints a chip on each pane, focuses pane N
- `toggle-pane-zoom` — stateless zoom toggle (added per ADR-0007;
  capability-gated, Kitty omits in v1)

Chip rendering is internal to `focus-pane-by-digit`, not a separate
op. Quality may be "indirect and inexact" for backends that don't
expose pane geometry — the user's recall confirms this is acceptable.

## Backends and applicability

| Backend       | Type             | Surface           | Notes |
|---------------|------------------|-------------------|-------|
| iTerm2        | host w/ splits   | full (13 + det)   | baseline; implemented in `apps/iterm.sld` |
| WezTerm       | host w/ splits   | full              | `wezterm cli`; cask installed today |
| Kitty         | host w/ splits   | full              | `kitty @ ls`; needs `allow_remote_control` |
| Ghostty 1.3.0+ | host w/ splits  | **12/13** (no move-pane — same gap as WezTerm) | **AppleScript API** (added in 1.3.0): `split direction <dir>`, `focus <terminal>`, `perform action "<keybind>" on <terminal>`. Brew's 1.3.1 has it. 060 missed this; 065 corrected. |
| tmux          | mux              | full              | `display-message`; `display-panes` may serve chips |
| zellij        | mux              | full              | installed today; ops via `zellij action` |
| Alacritty 0.17.0 | host no splits | detection only    | by-design no panes; users add a mux. `alacritty msg` IPC for window mgmt only. **No AppleScript SDEF**. Brew cask is Gatekeeper-deprecated AND quarantine-blocked; direct GitHub-releases DMG download bypasses both (075 live-verified). |

## What's lost

A prior conversation produced first-hand investigation results for
every backend (install → probe → uninstall). Nothing survived. This
grove rebuilds those findings via per-backend tasks under
`010-recover-design/`.

User recall to date:
- Solutions for every terminal/mux were found (some hacks).
- Chip rendering worked for every backend (indirect/inexact in some).
- Ghostty workarounds existed — *corrected*: AppleScript API
  added in **1.3.0** (not 1.4 as initially recalled). brew's 1.3.1
  has it.
- Software was installed then uninstalled — same pattern repeats here.
- Non-splitting terminals only need *detection* — users add a mux.

## Machine state (2026-05-23)

- Installed: iTerm.app, zellij 0.44.3.
- Not installed: WezTerm (probed in 030 against cask
  `20240203-110809-5046fc22`, uninstalled per task contract),
  kitty (probed in 050 against cask 0.47.0, uninstalled per task
  contract), tmux (probed in 040, uninstalled per task contract),
  ghostty (probed in 060 + 065 against cask 1.3.1, uninstalled per
  task contract), alacritty (probed in 070 against cask 0.17.0 via
  manpages only — macOS refuses to launch the cask's adhoc-signed
  binary; uninstalled per task contract).
- User's `~/.config/kitty/kitty.conf` (98 lines, A/B-rendering
  mirror of `wezterm.lua`) was NOT touched during the kitty probe
  — the `--override allow_remote_control=yes` runtime flag was used
  instead of a config edit.

Each per-backend task brews/installs, probes, and uninstalls. The
"Machine state" section above is updated at the end of each task so
this brief always reflects on-disk truth.

**Verifier note:** `brew list --cask` reads metadata only — it returns
success for casks whose .app was manually trashed. Verify the actual
artifact with `[ -d /Applications/<App>.app ]` or `mdfind -name <App>`.

## Non-goals

- Swift-side changes — Scheme + shell only. See
  [[feedback_scheme_first]], [[feedback_scheme_driven_design]].
- `close-pane`, resize, zoom, swap, rotate (not in locked surface).
- Cross-host (SSH).

## References

- **Phase-2 PRD:** `docs/prd/terminal-backends.md` — the agreement
  produced by 010-recover-design/090, what 020-implement (TBD) ships.
- **ADRs:**
  - `docs/adr/0001-terminal-backends-named-modules-with-facade.md`
  - `docs/adr/0002-terminal-backends-keep-direction-word-procedure-names.md`
- Phase-1 spec: `docs/superpowers/specs/2026-05-22-terminal-pane-and-remote-docs-design.md`
- Phase-1 reference: `docs/reference/terminal-detection.md`
- Phase-1 how-to: `docs/how-to/terminal-pane-aware-tree.md`
- Existing library: `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
- iTerm app module: `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`
- Glossary: `CONTEXT.md`
