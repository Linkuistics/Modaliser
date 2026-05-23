# Recover & design the terminal-backends abstraction

The original `010-recover-design.md` leaf was sized to grill + design
in one session. Grilling revealed the scope: per-backend empirical
investigation must precede abstraction design, because the prior
session's findings (workarounds for every backend, install→probe→
uninstall pattern) survive nowhere. This node decomposes the work.

## Children

| Order | Task                          | Surface needed |
|-------|-------------------------------|----------------|
| 010   | iterm-baseline                | audit existing `iterm.sld` against the locked 13-op + detection surface |
| 020   | investigate-zellij            | full (installed today; no install needed) |
| 030   | investigate-wezterm           | full (cask installed today; CLI at app path) |
| 040   | investigate-tmux              | full (install fresh) |
| 050   | investigate-kitty             | full (install fresh) |
| 060   | investigate-ghostty           | brew cask (1.3.1); concluded detection-only |
| 065   | investigate-ghostty-current   | proper install from ghostty.org (1.4+); re-probe for splitting-backend status |
| 070   | investigate-alacritty         | brew cask (manpages-only; binary Gatekeeper-blocked) |
| 075   | investigate-alacritty-signed  | signed install from GitHub releases; live verification |
| 080   | design-abstraction            | synthesise: mechanism, names, surface split, mux-inside-host composition |
| 090   | prd                           | `docs/prd/terminal-backends.md` if convergent |

## Per-investigation deliverables

Each per-backend task lands:
1. A hand-verified Scheme recipe (shell-out or keystroke-proxy) for
   every op in the backend's applicable surface.
2. Notes on the *mechanism* (CLI flag / IPC socket / keystroke
   proxy) and limitations (e.g. "chip position is row-counted, not
   pixel-exact").
3. A short capability matrix row.

Findings accumulate in `notes/<backend>.md` under this node, so the
synthesis task (080) has structured input.

## Per-investigation contract

- **Install.** `brew install <pkg>` if not present; record exact
  version.
- **Probe live.** Open the tool, create panes, run the ops; verify
  by eye.
- **Capture.** Write `notes/<backend>.md`.
- **Teardown.** `brew uninstall <pkg>` for tools not already
  installed (matches the prior session's pattern; keeps the machine
  reproducible). Update the root `BRIEF.md`'s "Machine state" line.
- **Commit.** One commit per backend.

## Synthesis (080) decides

- **Abstraction mechanism.** Record-of-closures, symbol-dispatch
  table, or per-backend named modules with caller-side `cond` on
  bundle-id (the existing iTerm pattern).
- **Procedure naming.** `focus-pane-h` (user typed hjkl) vs
  `focus-pane-left` (existing `iterm.sld` convention). One-way door
  once configs use it.
- **Surface split.** Detection-only backends present the same
  record (ops return `#f` / signal unsupported) or a smaller
  `<detection-backend>` record refined by `<splitting-backend>`?
- **Mux-inside-host composition.** When tmux is running inside an
  iTerm pane, does `focus-pane-h` route via iTerm or tmux? Library-
  automatic detection vs caller-explicit context switch.

## PRD (090) — optional

Only if synthesis converges into a real agreement worth sharing
externally. If it doesn't (e.g. abstraction reduces to "iTerm +
tmux only, others stay as recipes"), 090 records the reason and
this node retires the grove.

## 080 outputs (status after the synthesis task)

Synthesis **converged.** Decisions locked:

- **Mechanism** — per-backend named modules **+** an additive façade
  `(modaliser pane)` (option D in 080's task file). See
  `docs/adr/0001-terminal-backends-named-modules-with-facade.md`.
- **Naming** — keep direction-word procedure names
  (`focus-pane-left`/`-right`/`-up`/`-down`, ×focus/split/move).
  Hjkl aliases are a future façade-level concern only. See
  `docs/adr/0002-terminal-backends-keep-direction-word-procedure-names.md`.
- **Surface split** — one `<terminal-backend>` record with nullable op
  fields; detection-only backends have a populated `detect-foreground-
  command` and `#f` for the 13 ops. Captured in `notes/abstraction.md`
  rather than its own ADR (no real alternative once nullable-ops is in).
- **Mux-inside-host composition** — both styles supported. **Explicit**
  via the existing `set-local-context-suffix!` flow (different *trees*
  per context, call backends directly); **implicit** via the façade
  (one tree, `(active-backend)` routes per keystroke). Captured in
  `notes/abstraction.md` — usage pattern, not a one-way door.

Full sketch lives at `notes/abstraction.md` — the source material 090
turns into `docs/prd/terminal-backends.md`.

## 090 status

Unblocked. 090 writes the PRD from `notes/abstraction.md` + the two
ADRs above. Implementation lands in a **separate node grown after 090
locks**, not in this `010-recover-design/` subtree.
