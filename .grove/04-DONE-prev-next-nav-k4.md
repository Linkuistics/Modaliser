# prev-next-nav-k4

**Kind:** planning

## Goal

Grill previous/next cycling for the Workspaces, Tabs, Agents and Panes
groups in the herdr tree, then grow the implementing work leaf/leaves.

## Context

- Human direction (2026-07-13, verbatim, raised mid plan-k1): "We should
  also add previous/next to workspace, tab, agent and pane groups."
- Open questions to grill (not exhaustive):
  - **Keys.** Inside each drill, which keys are prev/next? The user
    navigates with hjkl exclusively (no arrow keys), but in the Panes
    drill hjkl is *directional* focus — a linear prev/next needs a
    different pair there. `n` is taken (New) in Tabs/Workspaces.
    Candidates: `[`/`]`, `,`/`.`, or h/l where free. Consistency across
    the four drills vs. best-fit per drill is itself a decision.
  - **Walk or terminal?** Cycling wants repetition — `'next 'self` walk
    members (like Move) so prev/prev/prev chains without re-drilling?
  - **Wrap.** Cycle past the ends or clamp?
  - **Ordering source.** "Next" in what order — the herdr list order
    (`tab list` carries a read-only display-order `number`; agents are
    status-reordered blocked-first in the block) or raw id order?
  - **Scope interaction.** Presumably next-pane cycles within the
    displayed tab and next-tab within the focused workspace (matching the
    scoped lists — pane-list-tab-local-k3); confirm.
  - **Mechanism.** herdr CLI probably has no focus-next verb — probe the
    CLI first (feedback_sdef_first spirit: audit before concluding).
    Fallback is pure computation over `<x> list` + focused id, exactly
    the shape of `next-blocked-pane-id` (`muxes/herdr.sld` — the `b`
    Jump-to-Blocked round-robin: stateless, keyed on current focus,
    wrapping, fixture-testable). That helper is the in-repo precedent to
    generalize.

## Decisions (running log)

- **Mechanism (audit, 2026-07-13):** herdr 0.7.3 has no prev/next verb on
  any CLI noun and no cycle action on the socket API (`api schema`
  checked; `previous_*` hits are focus-event payload fields). Cycling is
  pure computation over list + focused id → `<x> focus` /
  `agent focus`, the `next-blocked-pane-id` shape.
- **Cycle domain (human):** "The herdr cli (or at least the key bindings)
  already define this" — mirror herdr's own semantics, which coincide
  with cycling the drill's *displayed rows*: tabs in `number` order
  within the focused workspace (herdr `prefix+n/p`), workspaces in
  `number` order (herdr navigate-mode up/down), panes tab-local (herdr
  `prefix+Tab` cycle). Agents have no herdr binding — default to the
  displayed (status-banded, blocked-first) order, flagged for veto.
- **Keys (human):** `[` prev / `]` next, uniform across all four drills.
  herdr's own mnemonics all collide (n/p vs n=New; Tab unbindable
  without new Swift key-mapping — keyCode 48 absent from
  `keyCodeToCharacter`; j/k owned by the selection cursor). `[`/`]` is
  free everywhere, zero Swift work.
- **Branch fact:** tabs workspace-scoping (5b2ffa1) is on main only;
  this branch has pane tab-scoping (a5a51bf) — same regions of
  herdr-list.sld/herdr.sld, so the implementing leaf must merge main
  first (conflict expected and understood).
- **Walk (human):** `[`/`]` are walk members — 'next 'self back into the
  drill, so presses chain and the list re-renders showing the new
  focused row each step. Matches the Move precedent.
- **Wrap (human):** ring semantics — wrap at both ends, matching
  `next-blocked-pane-id`'s round-robin.
- **Agents order (human):** displayed order (status-banded,
  blocked-first, stable within band) — one mental model across all four
  drills; mid-walk reshuffle on a status flip accepted (each press
  re-renders first).
- **Non-goals:** Worktrees drill gets no [/] (the direction named four
  groups); no ADR — every decision here is cheap to reverse, failing
  the when-to-write bar; decisions live in this log + the leaf specs.

## Done when

Shared understanding on keys/semantics for all four groups; decisions
recorded (glossary/ADR only if they clear the bar); implementing work
leaf/leaves grown with the agreed spec.

## Notes

Depends on the shapes landed by pane-drill-k2 (the Panes drill) and
pane-list-tab-local-k3 (scoped lists) — sequenced after both.
