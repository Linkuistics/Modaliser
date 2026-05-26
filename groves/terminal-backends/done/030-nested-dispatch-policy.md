---
kind: planning
---

# 030 — Nested-backend dispatch policy

## Goal

Decide and ship how `(modaliser terminal)` resolves directional ops
when a host backend with native splits (iTerm, WezTerm, Kitty) hosts
a multiplexer (tmux, zellij) inside one of its panes. Today the
walk-path in `terminal.sld` makes this implicit (innermost-wins,
always); the design has never been agreed explicitly, and there is
no knob.

## Source

Surfaced in conversation during 020-implement/050-wezterm-backend.
The user asked: "how do you suggest we handle zellij/tmux, which
will usually be running in a terminal that supports native splits —
what should these terminal/mux controls target and how should they
decide by default?"

## Where the design lands today

`active-backend` in `terminal.sld` returns the leaf of the walk
path: the deepest registered backend whose match-key matches at its
level. Mux backends match by foreground command ("tmux", "zellij"),
so when the focused host pane runs tmux, the mux *always* wins.
There is no knob.

This is the **innermost-wins** policy by default, undocumented.

## The interpretations of "h"

With iTerm split twice, tmux running in one of those panes with 3
mux panes inside, pressing leader+h ("focus left") could mean:

1. **Innermost-wins** (current). h targets the mux pane left of the
   focused mux pane. Iterm splits are ignored once you're inside
   tmux. Matches what a tmux-attached user usually expects when they
   pressed the leader inside tmux.

2. **Host-wins.** h always targets the iTerm pane left of the focused
   iTerm pane — ignore the mux. Useful when the user thinks of
   iTerm as the "outer" navigation surface and mux as the "content"
   that doesn't move.

3. **Escalate-on-edge.** Try the mux first; if at the left edge of
   the mux layout, jump to the iTerm pane to the left. This is what
   `vim-tmux-navigator` and friends emulate in tmux-land. Most
   ergonomic, but needs each backend to expose a `(pane-at-edge?
   direction)` predicate the façade can interrogate — a new ~15th
   op surface item.

## Suggested handling (from the discussion)

A global preference with a smart default, scoped narrowly:

- **Default:** current behaviour (`'innermost`).
- **A façade parameter** `(terminal:prefer-layer)` taking
  `'innermost` (default), `'host`, or `'escalate`. Set once in
  `config.scm`. Cheap, declarative, no per-binding plumbing.
- **For `'escalate`:** needs each backend to expose `(pane-at-edge?
  direction)`. Worth an ADR before adding because it's a real
  surface change.
- **Per-binding override** via a façade arg like `(terminal:focus-
  pane-h 'layer 'host)` for users who want one binding to always
  target the host (e.g. "alt+h is iTerm-native, leader+h is
  mux-aware"). Composes with the global default.

This isn't a per-backend provisioning question (which is what
configure-entry solves). It's a dispatch policy question on the
façade itself — belongs in `(modaliser terminal)`, not in any
backend module.

## Recommended decomposition

1. **Document current "innermost-wins" default** in the PRD
   (right now it's implicit in walk-path). Small. Standalone leaf.

2. **Add `(terminal:prefer-layer)` parameter** with the
   `'innermost | 'host` values. Skip `'escalate` for now. Cheap,
   covers the "I prefer native iTerm splits even when tmux is
   running" case. Touches `terminal.sld`'s walk-path; needs tests
   covering both values + a PRD update.

3. **Grill and ADR `'escalate`** as a separate planning node. Real
   design surface: edge detection per backend, behaviour when host
   backend doesn't support splits, behaviour when escalation crosses
   a backend boundary, what happens when both layers report edge.
   Worth its own grilling pass rather than smuggling in alongside
   the parameter work.

The planning task here should grill the above, possibly produce a
PRD increment for the `prefer-layer` step, then decompose into
those three (or more) leaves under `030-nested-dispatch-policy/`.

## Pointers

- **Walk-path implementation:** `Sources/Modaliser/Scheme/lib/
  modaliser/terminal.sld` lines ~196–234 (`walk-path`,
  `focused-terminal-path`, `active-backend`, `in-chain?`).
- **PRD:** `docs/prd/terminal-backends.md` — needs an explicit
  "dispatch policy" section that today's design pretends doesn't
  exist.
- **Existing ADRs touching dispatch:**
  - ADR-0003 (façade-only public surface)
  - ADR-0006 (multi-session mux resolution — different problem;
    that's "which mux session" not "which layer")
  - ADR-0008 (focused-terminal path shape)
- **Glossary:** `CONTEXT.md` § "Focused-terminal path".

## Notes

This task lands as a sibling of `020-implement/` (not a child)
because it's a façade design pivot, not part of the implement-the-
backends increment. Per grove constraint 4 (lazy and optional) we
plant it now while the context is fresh; the next pick after
020-implement retires will descend into it.

The decision isn't urgent — current behaviour ships and is usable.
But it's load-bearing for the user's daily experience once mux +
host-splits coexist, so it shouldn't sit indefinitely either.
