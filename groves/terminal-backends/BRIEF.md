# Terminal backends grove

Phase 2 of the terminal-pane work. Phase 1 (docs only, merged at
`17c3621`) wrote per-backend recipes. Phase 2 lifted those recipes
into `(modaliser terminal)` (façade + 7 backend modules) as library
calls behind a uniform abstraction. The implementation increment
(`020-implement/`) and the recovery investigations
(`010-recover-design/`) are both done; the live grove now holds
`025-hand-verify.md` (the per-backend live-driver checklist) and
`030-nested-dispatch-policy.md` (a follow-on design pivot).

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

## What shipped

The 020-implement increment landed:

- **`(modaliser terminal)` façade** — the single public surface
  exporting the 14 ops (`focus/split/move-pane-{left,right,up,down}`,
  `focus-pane-by-digit`, `toggle-pane-zoom`), the 5 capability
  predicates (`supports-splits?`, `supports-move-pane?`,
  `supports-digit-jump?`, `supports-zoom?`, `supports?`), and the
  structured detection primitive (`focused-terminal-path`, with
  `focused-terminal-foreground-command` and `in-chain?` convenience
  accessors). Per ADR-0003, this is the only place to call the ops
  from `config.scm`.
- **7 backend modules** registering against the façade:
  - Hosts: `(modaliser apps iterm)`, `(modaliser apps wezterm)`,
    `(modaliser apps kitty)`, `(modaliser apps ghostty)`.
  - Detection-only host: `(modaliser apps alacritty)` (all 14 op
    slots `#f`; contributes only the host frame of the
    focused-terminal path so a mux can take over the splitting
    surface).
  - Muxes: `(modaliser muxes tmux)`, `(modaliser muxes zellij)`.
- **configure-entry overlay actions** for iTerm, WezTerm, Kitty,
  and (optionally) Alacritty's brew-cask quarantine workaround.
- **User config migrated** — `~/.config/modaliser/config.scm`
  calls `(terminal:focus-pane-*)` rather than `(iterm:focus-pane-*)`;
  the 12 splits-tree exports were dropped from `(modaliser apps
  iterm)`.
- **Phase-1 docs updated** — `docs/reference/terminal-detection.md`
  and `docs/how-to/terminal-pane-aware-tree.md` document the façade
  as the official interface (capability-predicate pattern included).

## Machine state (2026-05-24)

- Installed: iTerm.app, zellij 0.44.3, tmux 3.6b, Modaliser.app
  (rebuilt + reinstalled at 020-implement/090 cutover).
- Not installed: WezTerm, kitty, ghostty, alacritty — each was
  brewed/probed/uninstalled per task contract during recovery and
  implementation. See `done/010-recover-design/notes/<backend>.md`
  and `done/020-implement/BRIEF.md` for the live-probed findings.
  Each will be reinstalled-then-uninstalled during the
  `025-hand-verify.md` pass.
- User's `~/.config/kitty/kitty.conf` was not touched during probing
  (the `--override allow_remote_control=yes` runtime flag was used).

**Verifier note:** `brew list --cask` reads metadata only — it
returns success for casks whose .app was manually trashed. Verify
the actual artifact with `[ -d /Applications/<App>.app ]` or
`mdfind -name <App>`.

## Non-goals

- Swift-side changes — Scheme + shell only. See
  [[feedback_scheme_first]], [[feedback_scheme_driven_design]].
- `close-pane`, resize, zoom, swap, rotate (not in locked surface).
- Cross-host (SSH).

## References

- **Phase-2 PRD:** `docs/prd/terminal-backends.md` — the agreement
  produced by `done/010-recover-design/090`, what `done/020-implement`
  shipped.
- **ADRs:**
  - `docs/adr/0001-terminal-backends-named-modules-with-facade.md` (**superseded by 0003**)
  - `docs/adr/0002-terminal-backends-keep-direction-word-procedure-names.md`
  - `docs/adr/0003-terminal-backends-facade-only-public-surface.md`
  - `docs/adr/0004-terminal-backends-capability-predicates.md`
  - `docs/adr/0005-terminal-backends-configure-entry-day-one.md`
  - `docs/adr/0006-terminal-backends-multi-session-and-ssh.md`
  - `docs/adr/0007-terminal-backends-pane-zoom-in-op-surface.md`
  - `docs/adr/0008-terminal-backends-focused-terminal-path.md`
- Phase-1 spec: `docs/superpowers/specs/2026-05-22-terminal-pane-and-remote-docs-design.md`
- Phase-1 reference: `docs/reference/terminal-detection.md` (now
  documents the façade as the official interface)
- Phase-1 how-to: `docs/how-to/terminal-pane-aware-tree.md` (now
  shows the capability-predicate pattern)
- Façade: `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
- Backend modules:
  `Sources/Modaliser/Scheme/lib/modaliser/apps/{iterm,wezterm,kitty,ghostty,alacritty}.sld`,
  `Sources/Modaliser/Scheme/lib/modaliser/muxes/{tmux,zellij}.sld`
- Glossary: `CONTEXT.md`
