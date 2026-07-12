# Navigation is a static graph: declared `'next` edges, derived stickiness, terminal nodes release capture

## Status

accepted

## Context

`modal-handle-key` ran a command's action *before* its cleanup decision so an
action could call `(enter-mode! …)` imperatively — which meant a node's
outgoing transitions were hidden inside opaque action bodies. Nothing could
know, before running an action, whether it needed modal capture to stay live
(it transitions) or released (it hands the keyboard elsewhere — a dialog, an
external prompt). ADR-0014 originally patched the dialog case by having the
dialogs library call `(modal-exit)` imperatively as its own first step.

Paths explored and rejected while deciding this:

- **Release before every (non-sticky) action** — breaks every action that
  calls `enter-mode!` (the seven `focus-pane-by-digit` backends): released
  first, the push lands against no context and Escape semantics silently
  regress.
- **Statically predict which opaque actions exit** — dead on arrival; two
  structurally identical commands can need opposite treatments.
- **A per-kind dialog node (modelled on `selector?`)** — expressible, but
  degenerate: every real dialog site fires conditionally on runtime guards
  and one computes its message at fire time, so the "static" node is a bag
  of thunks whose only static fact is its tag; chained dialogs still need
  the procedural surface, yielding two surfaces for one concept.

The insight that resolves it: terminality — *has this node any outgoing
edge?* — is static the moment all edges are declared. The hidden edges were
the only problem, and there were exactly seven, all one identical line.

## Decision

The navigation tree is a **static graph**; a node's outgoing edges are
declared, never buried in an action body.

- **`'next` edge.** A command leaf's post-action transition is the `'next`
  property: a registered collection's id, or `'self` (the leaf's own
  containing group — the cycle case). A façade-dispatched op may carry a
  fire-time-resolved target (which backend's collection is decided at press
  time); the *existence* of the edge is still static. `'sticky-target` is
  renamed to `'next`.
- **Terminal = no outgoing edge** (no children, no `'next`, nothing to cycle
  to). Dispatch releases modal capture (`modal-exit`) **before** running a
  terminal node's action. Selector dispatch becomes an instance of this rule.
- **Non-terminal nodes keep capture**; after the action the edge is taken. A
  cyclic edge re-arms the collection in place — it does not push
  `modal-stack`; a cross edge enters the target mode (pushing the caller
  context as today).
- **Stickiness is derived, not declared.** The group `'sticky` flag and the
  per-press sticky-ancestor walks are retired; what was a "sticky mode" is a
  collection whose members cycle — authored with the `walk` form (formerly
  `sticky-set`), which stamps `'next <collection-id>` on its members.
  `'exit-on-unknown` is unaffected (an unknown-key policy, not an edge).
- **`enter-mode!` becomes framework-internal.** Action bodies must not
  transition imperatively; the seven backend `focus-pane-by-digit` slots
  carry their digit-mode id instead of a thunk.
- **Fail-safe direction.** A dynamic edge target that resolves to `#f` keeps
  capture and does normal cleanup — the design never releases wrongly; it
  can only decline to release.

## Consequences

- Dialog commands need no release machinery at all: they are ordinary
  terminal leaves, and dispatch has already released capture when the action
  fires its external UI. ADR-0014 slims to its surviving invariant (never
  block the Scheme thread).
- A keyboard-needing leaf *inside* a walk is expressible, not a config
  error: omit `'next` and the leaf is terminal — it breaks the cycle and
  gets the release.
- Overlay markers and tooling can read transitions statically (the cell
  marker previously keyed off `'sticky-target` now keys off `'next`).
- Migration: the seven `focus-pane-by-digit` slots, four in-tree `'sticky`
  groups (herdr/iTerm Move Pane, Messages, Dia), three `sticky-set` walks
  (Dia, iTerm ×2), user configs, and `docs/reference/`
  state-machine/dsl docs.
- Suspected bonus fix (verify at implementation): the old `'sticky-target`
  cycle fired `enter-mode!` per press, apparently pushing one `modal-stack`
  context per step of a latched walk; a cyclic edge re-arms without pushing.
