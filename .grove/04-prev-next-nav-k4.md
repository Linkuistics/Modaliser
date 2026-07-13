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

## Done when

Shared understanding on keys/semantics for all four groups; decisions
recorded (glossary/ADR only if they clear the bar); implementing work
leaf/leaves grown with the agreed spec.

## Notes

Depends on the shapes landed by pane-drill-k2 (the Panes drill) and
pane-list-tab-local-k3 (scoped lists) — sequenced after both.
