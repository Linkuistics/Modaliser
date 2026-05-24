---
kind: work
---

# 010 — Build the `(modaliser terminal)` façade

## Goal

Extend `(modaliser terminal)` with the abstraction's coordinating
machinery: backend record, registry, active-backend resolution,
focused-terminal-path walk, the 14 op shims, the 5 capability
predicates. No real backend yet — smoke-tested with a stub backend
registered in test code.

## Context

- PRD § "Abstraction shape" → "Backend record (internal)" and
  "`(active-backend)` resolution" for the shape.
- ADR-0003 (façade is the only public surface), ADR-0004 (predicate
  set), ADR-0008 (path structure).
- Existing `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`
  currently exports `focused-iterm-tty`, `focused-terminal-foreground-
  command`, `tty-foreground-command`. The new exports add to this
  module — don't create a `(modaliser pane)` sibling.

## Done when

- New exports from `(modaliser terminal)`:
  - `<terminal-backend>` record type (internal helpers only — not
    re-exported; consumers use the façade).
  - `register-backend!` (called by per-backend modules).
  - `(active-backend)` — returns the backend record currently in
    scope (the most-specific mux if present, else the host).
  - `(focused-terminal-path)` — alist per ADR-0008.
  - `(focused-terminal-foreground-command)` — leaf frame's `fg`.
    (Existing string-returning behaviour preserved.)
  - `(in-chain? sym)` — predicate.
  - 14 op shims (`focus-pane-{left,right,up,down}`,
    `split-pane-{l,r,u,d}`, `move-pane-{l,r,u,d}`,
    `focus-pane-by-digit`, `toggle-pane-zoom`).
  - 5 predicates: `supports-splits?`, `supports-move-pane?`,
    `supports-digit-jump?`, `supports-zoom?`, `(supports? sym)`.
- Multi-session-local tty-correlation helper exported for mux
  backends to use (`correlate-mux-client-to-host-tty`, name TBD).
- Tests pass with a stub backend registered in test code that
  returns canned values for all 14 op fields + `focused-pane-id` +
  `detect-foreground-command`. Verify: predicates report correctly;
  path walk produces the expected alist; op shims dispatch.
- `swift build` succeeds; no regressions in existing
  `focused-iterm-tty` / `tty-foreground-command` behaviour.

## Notes

- The active-backend resolution depends on a host backend being
  registered. With no host registered, ops error cleanly with a
  message naming the registry as the source of truth ("no backend
  registered for bundle-id <id>"). This is the failure mode the user
  sees if they import `(modaliser terminal)` but forget
  `(iterm:register!)`.
- The path-walk algorithm and active-backend resolution share work
  — implement once, cache per leader press (the existing rebuild-
  per-press pattern from `iterm.sld:526` style). The cache key is
  the (frontmost-bundle, focused-host-tty) pair.
- Stub backend lives in test code, not in the library. Don't ship a
  `(modaliser terminal stub-backend)` — that's test scaffolding.
