---
kind: planning
---

# 080 — Design the abstraction

Synthesise the per-backend findings (under `notes/`) into a single
abstraction shape that Modaliser configs use uniformly.

## Inputs

- `notes/iterm.md`, `notes/zellij.md`, `notes/wezterm.md`,
  `notes/tmux.md`, `notes/kitty.md`, `notes/ghostty.md`,
  `notes/alacritty.md`.
- The 13-op surface + detection primitive defined in the root
  `BRIEF.md`.
- `CONTEXT.md` (glossary).

## Decisions to lock

### 1. Abstraction mechanism

How does the same Scheme call route to the right backend at
runtime?

- **(A)** Record-of-closures: `(current-backend)` returns a record
  whose fields are the 13 ops + detection. Configs call
  `((backend-focus-pane-h (current-backend)))`. The backend is
  looked up by frontmost-app bundle-id; mux-inside-host is handled
  by a chain.
- **(B)** Symbol-dispatch: `(pane-op 'focus-h)` does the lookup
  internally each call.
- **(C)** Named per-backend modules: `(iterm:focus-pane-h)`,
  `(tmux:focus-pane-h)`, etc., with caller-side `cond` on
  bundle-id. This matches the existing `(modaliser apps iterm)`
  pattern.
- **(D)** Hybrid: per-backend modules export named procedures
  (option C), AND a thin façade `(modaliser pane)` provides the
  dispatched generic ops (option A).

Each backend's *notes* may push for one or the other.

### 2. Procedure naming

- `focus-pane-h` (hjkl, as user typed) vs `focus-pane-left`
  (existing `iterm.sld` convention). One-way door once configs
  call the new names.
- Detection: `focused-pane-command` vs `focused-terminal-foreground-command`
  (existing). Phase 2 may rename for symmetry.

### 3. Surface split

- Detection-only backends present the same record with op fields
  signalling unsupported, OR
- Two record types: `<detection-backend>` and `<splitting-backend>`
  where the second `extends` the first.

### 4. Mux-inside-host composition

When tmux is running inside the focused iTerm split:
- **Implicit.** Library detects tmux's presence (via
  `focused-terminal-foreground-command` returning `"tmux"`) and
  routes `focus-pane-h` through the tmux backend. Caller writes one
  binding, it works in either context.
- **Explicit.** Caller binds different leader trees for "iTerm
  context" vs "tmux context" (the existing suffix-hook pattern).
- **Layered both.** Implicit by default; explicit via a flag.

## Output

Either:
- One or more ADRs under `docs/adr/` for the hard-to-reverse
  decisions (mechanism, naming).
- A sketch in `notes/abstraction.md` ready for 090's PRD.

Or:
- A "phase 2 doesn't converge on a single abstraction" finding,
  capturing why and what to ship instead (e.g. per-backend
  named modules + a how-to that demonstrates the cond-pattern).
  Retires the grove.
