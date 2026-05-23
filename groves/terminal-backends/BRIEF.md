# Terminal backends grove

Add first-class focused-pane detection backends to `(modaliser terminal)`
beyond iTerm2 — at minimum WezTerm, Kitty, Ghostty, tmux, zellij — so users of
those terminals/multiplexers can write the same Scheme as iTerm users instead
of pasting `run-shell` recipes.

## Why this exists

- Phase 1 (the docs effort) landed via `worktree-terminal-docs` — commit
  `17c3621`. It produced the spec, a how-to, and a reference, all of which
  explicitly document non-iTerm flows as **DIY recipes** so they can later be
  swapped for library calls with light revision. Phase 2 is that swap.
- The library today exports exactly one terminal-specific entry point —
  `focused-iterm-tty` — and `focused-terminal-foreground-command` cond's on
  it (`Sources/Modaliser/Scheme/lib/modaliser/terminal.sld:55-58`).
- Keeps Scheme as THE state machine ([[feedback_scheme_first]]); Swift host
  unchanged. Each backend is shell + parsing in Scheme, the way `terminal.sld`
  already works for iTerm.

## Open questions (for the first planning task to grill)

- **Backend priority.** What ships first? (WezTerm, Kitty, Ghostty, tmux,
  zellij — and SSH/remote desktop is a separate axis.)
- **Detection contract.** Do we extend `focused-terminal-foreground-command`
  into a multi-backend cascade, or expose `focused-<backend>-tty` siblings
  to `focused-iterm-tty` and let callers compose? The docs lean toward the
  latter.
- **Multiplexer composition.** tmux/zellij wrap a host terminal. Does the
  library cascade host→mux→pane automatically, or is composition the
  caller's job?
- **"Focused" semantics for non-AppleScriptable terminals.** WezTerm CLI?
  Kitty's remote-control socket? Env vars + focus-reporting state file?
  Each terminal answers this differently.
- **Naming.** `focused-iterm-tty` set a precedent; do new backends follow it
  (`focused-wezterm-tty`, …) or do we generalize first?

## References

- Spec:      `docs/superpowers/specs/2026-05-22-terminal-pane-and-remote-docs-design.md`
- Reference: `docs/reference/terminal-detection.md`
- How-to:    `docs/how-to/terminal-pane-aware-tree.md`
- Library:   `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
- Memory:    `project_terminal_detection_phase2.md` (the only durable trace of
  prior discussion)

## Non-goals

- Swift-side changes. This is Scheme + shell.
- Replacing focus-reporting escape protocol with something custom — we reuse
  what each terminal already provides.
- Cross-host (SSH) focus, except where it falls out for free.
