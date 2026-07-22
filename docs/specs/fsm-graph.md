# fsm-graph

How Modaliser's modal dispatch works once the explicit-graph refactor lands:
the graph model, its construction DSL, the runtime semantics, and the compat
façade. The *decision* and its trade-offs are recorded in ADR-0015
(`docs/adr/0015-explicit-fsm-graph.md`); nested-context activation is
ADR-0013. Glossary: FSM graph, State class, Visit, Up-edge, Call edge /
Return stack, Action slots, Edge gate, Edge provider, Entry table
(CONTEXT.md, Jump-navigation domain).

## Problem

The dispatch core is an implicit machine: transitions live in per-node-kind
`cond` branches, backspace in a stack-and-path special case, activation in a
scope-lookup-plus-suffix-hook side channel. The features this grove needs —
activation at inner entry points, a gated `.` step-in edge, per-invocation
jump labels with narrowing — would each grow another bolt-on. Meanwhile a
planned rendering grove wants to draw the machine itself (multiple states
and edges in one window), which an implicit machine cannot offer.

## Solution

A portable core library, `(modaliser fsm)`, owning two things: the **graph
model** — states and labelled edges as printable, queryable s-expression
data, built by a construction DSL with a strong homoiconic flavour — and the
**step engine** that runs it. The layout spec (screens/panels/keys) remains
the only user authoring surface and lowers to graph registrations.
`(modaliser state-machine)` survives as a façade deriving its existing
exports from the FSM runtime, so the overlay's `(node, path)` contract and
user-visible behaviour are unchanged until the rendering grove consumes the
graph directly.

## Decisions

### The graph model

- A **state** has an id (readable, region-derived), optional label,
  presentation payload (the lowered node the current overlay renders), four
  action slots (`entry`, `exit`, `show`, `hide`), an optional edge
  **provider**, and its outgoing **edges**.
- An **edge** is labelled by its trigger — a key string, `up` (backspace),
  or `auto` (post-action) — and carries a target state id, an optional
  **gate** predicate, and an optional `call` marking (pushes a return
  frame). Edges are declarable standalone or inline within a state form;
  both surfaces build the same graph.
- **Behaviour slots take procedures**: lambda literals anywhere; an optional
  naming wrapper attaches a display name. Printing the graph shows all
  structure and every given name; only closure bodies are opaque.
- The graph is **open**: registrations (from lowering or direct DSL use)
  accumulate states, edges, and entry-table rows. Construction validates:
  a state may not carry both key edges and an auto edge; ids are unique;
  entry rows reference known states (dangling edge targets are deferred to
  step time — the graph is built incrementally).
- The **entry table** maps activation names to states, each optionally
  gated, each carrying derived specificity (below). It is part of the graph
  and enumerable by tooling ("where can a leader land?").

### Runtime semantics

The engine's configuration is `(current state, return stack)`. One step
rule (sketch from the grilling, decision-rich):

```text
step(input):
  edge := current.edges[input]        ; from the visit's snapshot
  if none: unknown-key policy (per-state, stamped at lowering)
  if edge.call: push return frame
  move to edge.target
  classify target by its edges:
    terminal  (none):     end the visit (exit/hide), HALT,
                            then run entry()
    transient (auto):     run entry(input?), resolve auto edge ->
                            follow it; #f -> HALT (after action)
    resting   (keys):     same state as the visit's owner ->
                            continue visit: refresh snapshot,
                            update overlay; nothing re-fires.
                          different state -> end the previous
                            visit (exit/hide), begin a new one:
                            entry(), snapshot gates + provider,
                            show() when the overlay displays it
```

- **The visit is the unit of presentation.** A visit spans from coming to
  rest in a resting state until the machine rests elsewhere or halts.
  `entry` fires when a visit begins; `exit` (with reason) when it ends;
  `show`/`hide` pair with the overlay actually displaying the state during
  the visit (the delayed-show cancellation and no-flash guarantees carry
  over from the current hook gating). A transient excursion returning on a
  cyclic auto edge **continues** the visit — nothing re-fires, matching
  today's re-arm-in-place — but the **snapshot refreshes**, so provided
  edges track live content (a walk's list re-renders with fresh targets).
- **Backspace** is one rule: follow the state's `up` edge if present
  (implicit parent from lowering, or an explicit outward edge such as
  herdr → iTerm), else pop the return stack, else — walk root halts, any
  other root no-ops. **Escape** halts from any depth and clears the stack.
- **Gates and providers snapshot when the machine comes to rest** — at
  visit start and on each cyclic re-arm. The snapshot is the edge set the
  overlay renders and dispatch consults — rows shown and keys live cannot
  disagree. Provided synthetic states (jump-label prefix states) are
  ordinary states scoped to the visit; narrowing's backspace is their `up`
  edge, and a jump firing is an ordinary terminal state.
- **Activation**: the leader resolves the entry table — the most specific
  passing entry wins. Specificity is derived, never hand-ranked: up-edge
  containment (a nested context outranks its container) or **scope
  refinement** stamped at lowering (a `bundle-id/suffix` variant outranks
  its base — non-nested siblings today's suffix hook disambiguates); ties
  fall to declaration order. Any state id is also directly activatable
  programmatically.
- Entry actions of provided shared targets may receive the arriving key —
  how range-commands and digit lists lower. Dispatch precedence (literal
  keys shadow ranges; first range wins) is resolved at lowering into the
  explicit per-key edge set, not re-decided at step time.
- Overlay show timing stays derived: immediate for walk-like states,
  delayed otherwise; reasons (`'navigate`/`'confirm`/`'cancel`/`'exit`)
  flow to `exit` as today's on-leave reasons do.

### Lowering and the façade

- `screen`/`open`/`panel`/`key`/`walk` lower to states, edges, and entry
  rows: groups become resting states with implicit `up` edges; command
  leaves become transient/terminal states with their body as `entry`;
  `'next` becomes the auto edge (`'self` = cyclic, registered id = call
  edge, procedure = dynamic resolver); panels stay dispatch-transparent;
  inherited `'exit-on-unknown` is stamped per state at lowering.
- A resting state's authored hooks split by timing contract, keyword
  naming the slot pair it lowers onto: `'entry`/`'exit` (on `group`/
  `open`/`screen`/`register-tree!`, author-only — block hooks never
  compose into them) lower onto the unconditional entry/exit slots,
  firing at come-to-rest and visit end regardless of whether the overlay
  ever shows — how jump-chip paint/clear escapes the show delay
  (jump-chip-paint-bypasses-overlay-delay-k46); `'on-enter`/`'on-leave`
  lower onto the presentation-gated show/hide pair and keep the delayed
  no-flash behaviour.
- A `(screen 'bundle-id …)` registration auto-adds its gated entry-table
  row; a suffix-variant registration (`bundle-id/suffix`) adds an entry
  gated on the suffix hook's answer, outranking its base by scope
  refinement — preserving `resolve-app-tree`'s try-variant-then-fall-back
  semantics until the nested-context cutover (ADR-0013) retires the suffix
  path in favour of detection-gated entry points. The herdr entry node's
  detection gate and outward up-edge come from its own registration.
- `(modaliser state-machine)` keeps its exported names, derived:
  `modal-current-path` reads the up-edge chain, `modal-root-node` /
  `modal-current-node` return carried presentation nodes, `register-tree!`
  lowers to graph registration, `enter-mode!` wraps activation. Callers
  passing raw inline trees to `modal-enter` (tests do) are lowered on the
  fly — audit all entry paths at cutover.
- `(modaliser event-dispatch)` cuts over with it: `make-leader-handler`
  resolves through the entry table instead of `lookup-tree` /
  `resolve-app-tree`; `modal-key-handler`'s keycode-level duties (leader
  toggle, Escape/Delete, Return/arrows with the list cursor, modifier
  prefixing, Cmd passthrough) are unchanged and feed the engine. The
  config-facing `set-local-context-suffix!` API keeps working (its answers
  become gate results) until ADR-0013's cutover retires it; breadcrumb
  bookkeeping (`modal-root-segments` append-on-cross, deliberate
  non-reset at exit for the chooser) is preserved verbatim by the façade.

## Test seams

1. **`(modaliser fsm)` unit suite** — the one new seam: graph construction,
   validation, printing/queries, step semantics, visits, stack, gates,
   providers, entry resolution, exercised through the library's public API
   on toy graphs via the existing LispKit-evaluation test pattern.
2. **Existing state-machine / end-to-end suites** — the regression gate,
   unchanged, running through the façade's unchanged names.

## Out of scope

- **Rendering from the graph** — the current overlay keeps its
  `(node, path)` contract; the graph-aware renderer is a parked future
  grove (multiple states/edges in one window).
- **Statechart hierarchy** (parents active inside children) — rejected in
  ADR-0015; flat edges express the needed cases.
- **Serializable behaviours** (registry-resolved action names) — structure
  prints; closures stay closures.
- **User-facing authoring changes** — the layout spec surface is untouched;
  the graph DSL is config-visible but not required authoring.
- **Retiring the suffix-hook API** — deferred to the nested-context
  cutover (ADR-0013); this refactor only re-plumbs it as gates.
