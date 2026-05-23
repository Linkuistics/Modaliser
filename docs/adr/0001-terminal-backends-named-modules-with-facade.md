---
status: superseded by ADR-0003
---

# Terminal-backends: per-backend named modules with an additive façade

The terminal-pane abstraction exposes the same 13-op surface (focus / split
/ move in hjkl directions + digit-jump) across iTerm, WezTerm, Kitty,
Ghostty, tmux, and zellij. Phase 1 already shipped one per-backend named
module (`(modaliser apps iterm)` exporting prefixed procedures); rather
than collapse that into a single dispatched call (record-of-closures or
symbol-dispatch) and break existing call sites, Phase 2 keeps the named
modules and adds a thin façade `(modaliser pane)` whose 13 procedures
resolve `(active-backend)` at call time and route to the right module.

Both binding styles are first-class and forever-supported: calling
`(iterm:focus-pane-left)` (explicit, lets the user wire different
*trees* per context via the existing `set-local-context-suffix!` flow)
and calling `(pane:focus-pane-left)` (implicit, one tree across all
backends). The façade is additive — no existing call site changes.

See `groves/terminal-backends/010-recover-design/notes/abstraction.md`
for the considered alternatives (record-of-closures, symbol-dispatch,
named-modules-only, hybrid) and why hybrid is the convergent choice.
