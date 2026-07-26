# fsm-graph

How Modaliser's modal dispatch works once the explicit-graph refactor lands:
the graph model, its construction DSL, the runtime semantics, and the compat
façade. The *decision* and its trade-offs are recorded in ADR-0015
(`docs/adr/0015-explicit-fsm-graph.md`); nested-context activation is
ADR-0013; the configuration value the graph is lowered from is ADR-0018 /
`docs/specs/configuration-value.md`. Glossary: FSM graph, State class,
Visit, Up-edge, Call edge / Return stack, Action slots, Edge gate, Edge
provider (CONTEXT.md, Jump-navigation domain).

## Problem

The dispatch core is an implicit machine: transitions live in per-node-kind
`cond` branches, backspace in a stack-and-path special case, activation in a
scope-lookup-plus-suffix-hook side channel. The features this grove needs —
activation at inner entry points, a gated `.` step-in edge, per-invocation
jump labels with narrowing — would each grow another bolt-on. Meanwhile a
planned rendering grove wants to draw the machine itself (multiple states
and edges in one window), which an implicit machine cannot offer.

## Solution

A portable core library, `(modaliser fsm)`, owning three things: the
**graph model** — states and labelled edges as printable, queryable
s-expression data — the **step engine** that runs it, and the **modal
façade** over it (the pure lower function, the node accessors the overlay
renders through, the modal-* presentation layer derived from the engine's
configuration, and the overlay/chooser hook cells). The authoring sugar
(screens/panels/keys) remains the user surface; the pure lower function
turns the assembled configuration value (ADR-0018) into the closed graph
the engine consumes. The `(modaliser state-machine)` re-export shim was
removed once its importers migrated (docs-sweep-k15); `(modaliser fsm)`
is the one library.

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
- The graph is **closed over its authored references**: it is produced in
  one pass by the pure lower function from the configuration value
  (ADR-0018), and every statically declared target — key edges, `'next`
  cross/call ids, up-edges, embed/drill references — must resolve, as
  load-time errors. Construction also validates: a state may not carry both
  key edges and an auto edge; ids are unique. Providers' visit-scoped
  synthetic states and dynamic `'next` resolvers are the two deliberate
  runtime mechanisms outside static closure.
- There is **no entry table**: activation resolves outside the graph
  (screen-set lookup plus the Terminal context map's chain walk — below),
  and "where can a leader land?" is answered by the configuration value's
  screen set and context map.

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
- **Activation**: `resolve-activation` (pure — chain in, landing out) maps
  the leader kind to a screen ('global or the frontmost bundle-id), then,
  on a terminal-like screen, walks the detection chain for context-map
  entries: the innermost mapped tree is the landing state, and the return
  stack is seeded with one frame per outer context (ADR-0013). Any state id
  is also directly activatable programmatically, through the same
  resolution (outward frames seed when the chain contains that context).
  Full algorithm and chain-staleness doctrine:
  `docs/specs/configuration-value.md`.
- Entry actions of provided shared targets may receive the arriving key —
  how range-commands and digit lists lower. Dispatch precedence (literal
  keys shadow ranges; first range wins) is resolved at lowering into the
  explicit per-key edge set, not re-decided at step time.
- Overlay show timing stays derived: immediate for walk-like states,
  delayed otherwise; reasons (`'navigate`/`'confirm`/`'cancel`/`'exit`)
  flow to `exit` as today's on-leave reasons do.

### Lowering and the façade

- `screen`/`open`/`panel`/`key`/`walk` lower to states and edges: groups
  become resting states with implicit `up` edges; command leaves become
  transient/terminal states with their body as `entry`; `'next` becomes
  the auto edge (`'self` = cyclic, registered id = call edge, procedure =
  dynamic resolver); panels stay dispatch-transparent; inherited
  `'exit-on-unknown` is stamped per state at lowering. Lowering runs once,
  as the pure function from the configuration value to the closed graph
  (ADR-0018); each state carries its display value's lowered form as the
  presentation payload (ADR-0011).
- A resting state's authored hooks split by timing contract, keyword
  naming the slot pair it lowers onto: `'entry`/`'exit` (on `group`/
  `open`/`screen`/`tree-root`, author-only — block hooks never
  compose into them) lower onto the unconditional entry/exit slots,
  firing at come-to-rest and visit end regardless of whether the overlay
  ever shows — the escape hatch for a hook that must not wait out the
  show delay; `'on-enter`/`'on-leave` lower onto the presentation-gated
  show/hide pair and keep the delayed no-flash behaviour. Every visible
  side effect in the shipped tree — jump-chip paint/clear included
  (defer-chips-to-overlay-k33) — rides the gated pair, so the escape
  hatch currently has no user.
- Screens land in the configuration value's screen set keyed by scope;
  inner-tool trees land in the Terminal context map. Activation, the
  chain-seeded stack, and the derived `.` step-in are
  `resolve-activation`'s business (`docs/specs/configuration-value.md`) —
  no per-screen entry wiring exists.
- The modal façade's names are derived, never hand-tracked:
  `modal-current-path` reads the up-edge chain (stopping at the graph's
  recorded tree roots), `modal-root-node` / `modal-current-node` return
  carried presentation nodes, and `modal-activate!` is the one activation
  entry (a resolved landing: root state id + seeded return stack).
  Breadcrumb bookkeeping (`modal-root-segments` append-on-cross,
  deliberate non-reset at exit for the chooser) is preserved by the
  derivation.
- `(modaliser event-dispatch)` owns only the catch-all key handler:
  `modal-key-handler`'s keycode-level duties (leader toggle,
  Escape/Delete, Return/arrows with the list cursor, modifier prefixing,
  Cmd passthrough) feed the engine. Leader activation lives with the
  handoff: armed handlers call `resolve-activation` on the live chain
  ((modaliser handoff) / (modaliser activation)); the entry table and the
  suffix-hook API are deleted — nvim/zellij variants are context-map
  entries.

## Test seams

1. **`(modaliser fsm)` unit suite** — graph construction, validation,
   printing/queries, step semantics, visits, stack, gates, providers,
   exercised through the library's public API on toy graphs via the
   existing LispKit-evaluation test pattern.
2. **Existing modal-façade / end-to-end suites** — the regression gate,
   unchanged, running through the façade's unchanged names.

Configuration assembly, lowering, and activation resolution are the pure
configuration pipeline's seam — `docs/specs/configuration-value.md`.

## Out of scope

- **Rendering from the graph** — the current overlay keeps its
  `(node, path)` contract; the graph-aware renderer is a parked future
  grove (multiple states/edges in one window).
- **Statechart hierarchy** (parents active inside children) — rejected in
  ADR-0015; flat edges express the needed cases.
- **Serializable behaviours** (registry-resolved action names) — structure
  prints; closures stay closures.
- **User-facing authoring changes** — the authoring sugar is untouched;
  the graph DSL is config-visible but not required authoring.
- **Configuration assembly and activation policy** — the fragment model,
  merge semantics, the Terminal context map, and the handoff are
  `docs/specs/configuration-value.md`'s; this spec owns only the graph the
  value lowers to and the engine that steps it.
