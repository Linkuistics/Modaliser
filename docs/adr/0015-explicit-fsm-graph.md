# Modal dispatch is an explicit FSM graph: states and labelled edges as first-class data

Modal dispatch runs on an **explicit graph**: states and labelled edges are
first-class, printable s-expression data, built by a dedicated construction
DSL in a portable core library (`(modaliser fsm)`) and introspectable by
tooling and renderers. The layout spec remains the authoring surface and
lowers to this graph (ADR-0011's lowering, retargeted). Nothing about a
node's transitions is ever buried in an action body — every edge (key,
backspace, post-action, gated, provided) is data an inspector can read.

The machine is a **flat Moore RTN**:

- **States, not node kinds.** Behaviour attaches to states as two action-slot
  pairs with distinct timing contracts: `entry`/`exit` run unconditionally at
  transition time (command bodies are entry actions); `show`/`hide` are
  presentation-paired — `show` fires when the overlay actually displays the
  state (under the show delay, possibly never), `hide` only if `show` fired.
  This preserves the no-flash guarantee (fast muscle-memory presses paint no
  chips) as a slot contract instead of per-kind dispatch logic.
- **State classes are derived, never declared:** key edges = *resting*, an
  auto edge = *transient*, none = *terminal*. Entering a statically terminal
  state halts the machine — capture is released **before** the entry action
  runs, so the action may hand the keyboard elsewhere (dialogs, choosers). A
  dynamic auto edge that resolves to `#f` halts *after* the action — the
  fail-safe direction: the design never releases wrongly, it can only
  decline to release early.
- **Presentation and snapshots are per-visit.** A **visit** spans from the
  machine coming to rest in a resting state until it rests elsewhere or
  halts. A transient excursion that returns on a cyclic auto edge
  *continues* the visit — `entry`/`show` do not re-fire (today's
  re-arm-in-place hook pairing, preserved), though the snapshot refreshes so
  provided edges track live content.
- **Runtime configuration is (current state, return stack)** — an RTN, not a
  pure FSM. Containment is static: lowering gives every state an implicit
  `up` (backspace) edge to its parent, and an entry node declares its
  outward up-edge explicitly (herdr → iTerm, ADR-0013). Cross edges into
  Walks are **call** edges pushing a return frame. Backspace is one rule:
  up-edge, else pop, else (walk root → halt; otherwise no-op). Escape clears
  the stack — full teardown from any depth.
- **Walks stay derived:** a Walk is a region whose members carry cyclic auto
  edges; no group-level flag exists.
- **Activation is graph data.** An entry table maps names to states, each
  optionally gated by a detection predicate; leader activation picks the
  most specific passing entry. Specificity is derived, never hand-ranked:
  up-edge containment (a nested context outranks its container) or scope
  refinement stamped at lowering (a `bundle/suffix` variant outranks its
  base); ties fall to declaration order. This retires bundle-id scope
  lookup and, ultimately, the context-suffix hook.
- **Gates and providers snapshot when the machine comes to rest** — at visit
  start and again on each cyclic re-arm. The snapshot is the visit's edge
  set, shared by overlay and dispatch, so rendered rows and live keys
  cannot disagree, and detection cost stays once-per-landing.
- **Per-visit edges come from providers:** a resting state may carry a
  procedure run at the snapshot instant returning extra edges and synthetic
  states (jump labels, narrowing prefix states). Provided states are
  ordinary states — narrowing's backspace is just an up-edge; a jump firing
  is just a terminal state.
- **Behaviour slots take procedures** — lambda literals anywhere, an
  optional naming wrapper for display. All structure is printable; only
  closure bodies are opaque.

During the cutover, `(modaliser state-machine)` keeps its exported names as
a façade deriving them from the FSM runtime, so the overlay's `(node, path)`
contract and existing configs/tests continue working until the planned
rendering-model grove consumes the graph directly. The keyboard entry path
(`(modaliser event-dispatch)`) cuts over with it — the leader resolves
through the entry table — while the config-facing suffix-hook API keeps its
semantics as derived gates until the nested-context cutover retires it
(ADR-0013).

## Why it binds

The previous machine was implicit: dispatch semantics lived in per-node-kind
cond branches, backspace in a four-way special case over a mutable path and
stack, activation in a lookup-plus-suffix-hook side channel. Each new need —
entry points at inner contexts (ADR-0013), gated step-in edges,
per-invocation jump labels with narrowing — would have grown another bolt-on.
Making the graph first-class data collapses these into one step rule and
makes the coming graph renderer (multiple states/edges in one window) a
plain graph consumer. The choice is costly to reverse because the layout
lowering, the dispatch engine, and future tooling all target the graph
representation.

## Considered options

1. **Keep the tree-walk engine, add bolt-ons per feature** (status quo
   trajectory). Rejected: each of entry points, gating, and generated
   prefix states needs its own special case, compounding the existing
   per-kind branching. Reopened by: nothing — the features are committed.
2. **Mealy machine (actions on edges).** Rejected: chip paint/clear and
   command bodies are state-scoped; actions on edges duplicate per incoming
   edge and leave no state to hang show/hide on.
3. **Hierarchical statechart semantics** (parents stay active inside
   children). Rejected for now: it changes the existing leave-parent/
   enter-child hook pairing that chip code and tests rely on, and the flat
   model expresses the needed cases with explicit edges. Reopened by: a real
   need for region-scoped invariants that flat edges express poorly.
4. **Pure FSM, no return stack.** Rejected: Walks are entered from multiple
   call sites and backspace must return to the caller — a static up-edge
   cannot express that without duplicating the Walk per caller, the same
   multiplication ADR-0013 killed for trees.
5. **Fully symbolic behaviours (registry-resolved names only).** Rejected:
   configs create closures inline; forcing minted names and registry
   indirection buys serializability the renderer does not need — structure
   is already fully printable with procedures in slots.

## Consequences

- ADR-0014 is unaffected: dialog commands remain ordinary terminal states;
  the never-block invariant stands.
- ADR-0013's prerequisite (activation at a named inner entry point with the
  outward edge in place) is supplied by the entry table plus explicit
  up-edges.
- The overlay/tooling read transitions statically off the graph (the `↻`
  marker keys off the auto edge, as it keyed off `'next`).
- Unknown-key policy (`'exit-on-unknown`) is stamped per state at lowering —
  no runtime ancestor walk.
- Migration is expand→contract: graph model, then engine, then lowering
  shadows the tree, then dispatch cuts over and tree-walk internals retire;
  the existing state-machine suite is the regression gate throughout, and
  callers that pass raw inline trees to `modal-enter` are lowered on the
  fly.
