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
*splitting* backends. The locked surface is **13 procedures**:

- `focus-pane-{h,j,k,l}` — directional focus
- `split-pane-{h,j,k,l}` — directional split
- `move-pane-{h,j,k,l}` — directional move
- `focus-pane-by-digit` — paints a chip on each pane, focuses pane N

Chip rendering is internal to `focus-pane-by-digit`, not a separate
op. Quality may be "indirect and inexact" for backends that don't
expose pane geometry — the user's recall confirms this is acceptable.

## Backends and applicability

| Backend       | Type             | Surface           | Notes |
|---------------|------------------|-------------------|-------|
| iTerm2        | host w/ splits   | full (13 + det)   | baseline; implemented in `apps/iterm.sld` |
| WezTerm       | host w/ splits   | full              | `wezterm cli`; cask installed today |
| Kitty         | host w/ splits   | full              | `kitty @ ls`; needs `allow_remote_control` |
| Ghostty ≥ 1.4 | host w/ splits   | full *(verify)*   | recall: 1.4+ gates the workaround |
| Ghostty < 1.4 | host (no API)    | detection only    | needs mux inside |
| tmux          | mux              | full              | `display-message`; `display-panes` may serve chips |
| zellij        | mux              | full              | installed today; ops via `zellij action` |
| Alacritty     | host no splits   | detection only    | no IPC; users add a mux for splits |

## What's lost

A prior conversation produced first-hand investigation results for
every backend (install → probe → uninstall). Nothing survived. This
grove rebuilds those findings via per-backend tasks under
`010-recover-design/`.

User recall to date:
- Solutions for every terminal/mux were found (some hacks).
- Chip rendering worked for every backend (indirect/inexact in some).
- Ghostty was gated on v1.4+.
- Software was installed then uninstalled — same pattern repeats here.
- Non-splitting terminals only need *detection* — users add a mux.

## Machine state (2026-05-23)

- Installed: iTerm.app, zellij 0.44.3, WezTerm.app (cask reinstalled
  during 030-investigate-wezterm; CLI at `/opt/homebrew/bin/wezterm`,
  version `20240203-110809-5046fc22`).
- Not installed: kitty, tmux, ghostty, alacritty.

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

- Phase-1 spec: `docs/superpowers/specs/2026-05-22-terminal-pane-and-remote-docs-design.md`
- Phase-1 reference: `docs/reference/terminal-detection.md`
- Phase-1 how-to: `docs/how-to/terminal-pane-aware-tree.md`
- Existing library: `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
- iTerm app module: `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`
- Glossary: `CONTEXT.md`
