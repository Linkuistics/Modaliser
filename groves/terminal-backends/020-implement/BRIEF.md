# Implement the terminal-backends abstraction

## Goal

Land the abstraction designed by `010-recover-design/` and locked in
`docs/prd/terminal-backends.md` — `(modaliser terminal)` façade + 7
backend modules + multi-session tty correlation + per-backend
configure-entry. Phase-1 docs and the user's `config.scm` migrate at
cutover.

## Done when

- `(modaliser terminal)` exports the 14 ops, 5 capability predicates,
  and the `focused-terminal-path` (with `focused-terminal-foreground-
  command` and `in-chain?` convenience accessors).
- All 7 backends register: iTerm, WezTerm, Kitty, Ghostty, Alacritty
  (host backends), tmux, zellij (mux backends).
- configure-entry overlay actions ship for iTerm, WezTerm, Kitty;
  optional one for Alacritty.
- User's `config.scm` migrated from `(iterm:focus-pane-*)` to
  `(terminal:focus-pane-*)`. 12 splits-tree exports removed from
  `(modaliser apps iterm)`.
- Phase-1 reference + how-to docs updated to match the new model.

## Decomposition

Ordering encodes risk + dependencies:

| Order | Task | Why this position |
|-------|------|-------------------|
| 010 | facade | Everything depends on it. Stub-tested in isolation. |
| 020 | iterm-wiring | First real backend behind the façade. Non-breaking — keeps existing `iterm:focus-pane-*` exports alive as aliases until 090's cutover. Adds `toggle-pane-zoom`. |
| 030 | tmux-backend | First mux. Drives the tty-correlation work for multi-session. |
| 040 | zellij-backend | Second mux. Parallel implementation to tmux. |
| 050 | wezterm-backend | First non-iTerm host. configure-entry writes wezterm.lua. |
| 060 | kitty-backend | Most complex chip-geometry (topology BFS). configure-entry writes kitty.conf. |
| 070 | ghostty-backend | AppleScript-driven; 13/14 (no move-pane). |
| 080 | alacritty-backend | Detection-only; smallest backend. Optional configure-entry. |
| 090 | cutover-and-docs | Drop 12 splits-tree exports from `(modaliser apps iterm)`. Migrate `config.scm:157-176`. Update phase-1 reference + how-to. **Breaking step; runs last.** |

The breaking change is deliberately delayed until every backend has
been validated and the user has confirmed the new surface meets
their needs in practice. Backends 050-080 can be reordered freely
— they're independent.

## Pointers

- **PRD (source of truth):** `docs/prd/terminal-backends.md`.
- **ADRs (all must-read before any implementation leaf):**
  - 0002 — direction-word naming
  - 0003 — façade-only public surface (supersedes 0001)
  - 0004 — capability predicates
  - 0005 — configure-entry day-one
  - 0006 — multi-session local muxes via tty correlation
  - 0007 — toggle-pane-zoom in op surface
  - 0008 — focused-terminal-path
- **Glossary terms:** Pane, Host terminal, Multiplexer, Backend,
  Splitting backend, Detection-only backend, Chip, Suffix hook,
  Focused-terminal path (`CONTEXT.md`).
- **Recovery notes (frozen historical record per backend):**
  `groves/terminal-backends/done/010-recover-design/notes/<backend>.md`.
  Each implementation leaf reads its backend's note for the verified
  CLI / AppleScript / IPC recipes — these don't need re-investigation.
- **Existing implementations to preserve / refactor:**
  - `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld` (extended)
  - `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` (modified)
  - `Sources/Modaliser/Scheme/lib/modaliser/blocks/iterm-panes.sld`
    (likely unchanged; the iTerm backend wraps this for its
    focus-pane-by-digit op)
- **User config to migrate at 090:** `config.scm:157-176` per
  [[feedback_install_flow]] (changes need `./scripts/install.sh`).

## Notes

### Per-backend probe pattern

Each implementation leaf for a non-installed backend mirrors the
recovery investigation's pattern:

1. `brew install <pkg>` (or direct DMG for Alacritty per ADR-0006
   companion notes/alacritty-signed.md).
2. Build the module + register! + ops + configure-entry.
3. Live-verify all ops by hand in a real session.
4. `brew uninstall <pkg>` if not user-retained.
5. Update root grove BRIEF "Machine state" (deferred — root BRIEF
   currently still describes recovery-phase machine state; can be
   updated as a final cleanup or left to the next reset).

### Façade smoke test strategy

The 010 façade leaf can't validate end-to-end against a real
backend (iTerm wiring is 020). Smoke test with a stub backend
registered in the test code that returns canned values — proves
the registry, resolution, path walk, and predicates behave
correctly without depending on AppleScript / shell-out.

### Tests vs. by-hand verification

These are interactive Mac UI features. Type-checking + Scheme
syntax verification catches some bugs; the real validation is
visual ("did the chip render where I expected"). Each leaf's
"Done when" includes hand-verification, not just `swift test`.
Per CLAUDE.md the project ships visual changes only after seeing
them work — that applies here.

### Daily-driver continuity

Throughout 010-080 the user's existing iTerm flow keeps working
unchanged (the `iterm:focus-pane-*` exports remain). 090's cutover
is the only step that touches `config.scm`; it should run on a
day when the user can validate immediately and roll back if needed.

### Hand-verification debt

Each implementation leaf includes an interactive "verify with real
session" step that the leaf's own commit cannot complete (background
sessions can't drive iTerm focus). The pattern: leaf code lands +
`swift test` green + machine state reflects the install; the user
runs through the hjkl/split/move/zoom/digit-jump matrix at a moment
of their choosing and confirms or files a follow-up.

Outstanding as of 020-implement/050:
- **tmux:** chip-rendering for multi-iTerm-split + tmux is a known
  soft spot (v1 takes the first AXScrollArea). Single-split is the
  expected daily case; multi-split is a refinement when the
  cross-cutting host cell-dim helper called out in the PRD lands
  (likely 020-implement/060-kitty-backend, the next per-host leaf
  that needs the helper for its own chips).
- **zellij:** same multi-iTerm-split chip-rendering soft spot
  (inherits the iTerm-as-host assumption from tmux). Additionally,
  multi-zellij-session selection depends on parsing
  `ps -p PID -o args=` for `--session NAME` / `attach NAME` tokens;
  unusual launch shapes (wrapper scripts, `zellij --layout …` with
  no explicit session, attached via socket without --session) will
  miss the session name and fall back to the default session. Single-
  session is the expected daily case and works without any of this.
- **wezterm:** chip rendering assumes WezTerm exposes its panes as
  `AXScrollArea` (parallel to iTerm). Not verified live; if WezTerm
  uses a different role (likely `AXGroup` or similar in newer
  versions) chips simply don't render and digits still dispatch via
  the hidden key-range fallback. Pick this up if/when WezTerm becomes
  a daily-driver candidate or someone reports the gap. The window-
  origin derivation (focused pane AX frame minus its cell offset
  times cell-pixel ratio) is mathematically clean once an AX frame
  is in hand. Also: `move-pane-{h,j,k,l}` are honestly unsupported
  in v1 — see [[../done/010-recover-design/notes/wezterm.md]] and
  ADR-0005 reversal note; no work scheduled until WezTerm grows a
  directional pane-swap primitive upstream.
- **kitty:** module live-probed against cask 0.47.0 (the same
  version recovery investigated in 050). Findings rolled back into
  the module + docs as the leaf landed:
  - **`listen_on` directive** added to configure-entry — Modaliser
    running outside kitty.app needs a known socket path, which the
    leaf spec didn't capture; recorded in ADR-0005.
  - **JSON parser** filters to the active OS-window's active tab —
    `kitty @ ls` returns the full UI tree including background tabs;
    flattening across tabs collides panes when laying out the grid.
  - **Position derivation** rewritten from a tree BFS into constraint
    propagation: a pane sits at `(max-over-L of L.col + L.cols,
    max-over-T of T.row + T.lines)`. The probe's nested layout (one
    vsplit with an hsplit inside) revealed that kitty's `neighbors`
    is a relation, not a tree — pane 1 with R=[2,3] (both panes
    touching its right edge) can't be queue-walked without checking
    top-neighbor constraints simultaneously.
  - **AX-subview probe** — unable to verify from this session: AX
    queries require process accessibility-trust, which a sidecar
    `swift` CLI doesn't have. The module's runtime three-layer
    fallback (AX-per-pane → AX-host-frame + position-prop → no-chips
    key-range) lets *both* paths ship; the intended path becomes
    clear only when Modaliser itself (which has TCC trust) runs the
    code against a live kitty window. Hand-verify item: confirm
    which path activates.
  - Outstanding for the user's live hand-verify session:
    - Run `(kitty:configure-entry)` + relaunch kitty.
    - Open 2-3 panes, run through hjkl focus + split-h/j/k/l +
      move-pane-h/j/k/l + digit-jump.
    - Visually confirm chips land within ~1 cell-width of correct
      positions (the [[feedback_chips_are_overlays]] bar).
    - Verify `(supports-zoom?)` reports `#f` and zoom binding omits.
