# Terminal-backends: façade-only public surface (supersedes ADR-0001)

The 14 pane operations and 1 structured detection primitive
(`focused-terminal-path`) are exported **only** from `(modaliser
terminal)` as generic procedures (`focus-pane-left`, `split-pane-right`,
`toggle-pane-zoom`, …). At call time the façade resolves
`(active-backend)` by frontmost-app bundle-id + the path walk, and
routes to the right per-backend implementation.

Per-backend modules (`(modaliser apps iterm)`, `(modaliser muxes tmux)`,
…) become an implementation layer. They no longer export the 14 ops on
their public surface — the façade is the single user-facing API. Per-
backend modules still export inherently-backend-specific procedures
(e.g. `iterm:configure-entry` to provision iTerm keybinds; the
`pane-list-block` for iTerm's AX-discovered chips). Only the 12 splits-
tree procedures (the existing `iterm:focus-pane-*`, `iterm:split-pane-*`,
`iterm:move-pane-*`) are removed from `(modaliser apps iterm)`; the
new ops (`focus-pane-by-digit`, `toggle-pane-zoom`) live only on the
façade.

The existing `(iterm:focus-pane-left)` etc. exports are dropped, not
aliased. Users migrate their configs to call `(focus-pane-left)`. The
trade-off is one bounded migration (the user's `config.scm:157-176`,
12 procedures × ~20 sites) in exchange for a single non-redundant
public surface; aliases would have left two ways to do the same thing
forever.

Supersedes ADR-0001 (which kept both styles first-class). See
ADR-0004 for the capability-predicate surface that enables one
generic tree to gate ops by backend support.
