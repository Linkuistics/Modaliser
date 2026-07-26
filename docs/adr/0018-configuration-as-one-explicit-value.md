# Configuration is one explicit value: pure constructors, one merge, one handoff

Libraries export **pure constructors** returning **Fragments** — printable
tagged contribution bags (tree / backend / context / setting) — and user
config composes them with ordinary Scheme. `configuration` merges fragments
into a single **Configuration value**; `(modaliser:start! config)` is the
**only effectful moment**: it lowers the value to a closed graph, installs
it, and arms the leaders, exactly once (a second call is an error; reload is
relaunch). No `register!`/`set-*!` call exists on the authoring surface;
mutable accumulation survives only as engine internals behind the handoff.
The full model — contribution vocabulary, merge semantics, lowering,
residual engine state — is `docs/specs/configuration-value.md`.

## Why it binds

The registration model scattered configuration across hidden globals (tree
registry, entry table, FSM open graph, terminal-backends registry, a
last-write-wins suffix slot): call sites did not say what accumulated where,
integration wiring gravitated into the seeded-once config tier (upgrade
collisions), and nothing was inspectable or testable as data. Making the
configuration one value makes it printable, diffable, and unit-testable
upstream of any effect — and the merge can *reject* conflicts instead of
silently absorbing them. Costly to reverse: every library constructor, every
config, the lowering pipeline, and the engine's install path all target the
value shape.

## Considered options

1. **Typed top-level sections** (`configuration 'backends … 'screens …`).
   Rejected: a feature's contributions scatter back across sections in user
   config — the wiring knowledge the refactor removes. Reopened by: nothing.
2. **Closed record monoid** as the fragment type. Rejected: same semantics
   as the tagged bag, less printable and less extensible. Reopened by: a
   need for static shape checking that outweighs printability.
3. **Constructor-time lowering** (fragments carry lowered graph pieces).
   Rejected: cross-fragment references resolve only at merge anyway, and the
   printed value stops matching what the user wrote. Reopened by: nothing.
4. **Idempotent-replace handoff** (hot reload). Rejected: partial teardown
   of live visit/chips/capture is the orphan-state trap the
   reload-by-relaunch doctrine exists to avoid. Reopened by: a hot-reload
   design that owns full runtime teardown.
5. **Override/last-wins merge.** Rejected: silent conflict absorption is the
   suffix-slot failure generalised; the merge errors on same-key,
   non-identical contributions, and customization is composition — you edit
   the screen you authored, there being no stock value to patch (ADR-0021).
   Reopened by: nothing.

## Consequences

- Seeded config holds exactly the decisions — screens, keys, labels, panels —
  composed from stable library exports, and nothing Modaliser ships-and-improves.
  ADR-0019 (the seeding boundary) and ADR-0021 (where the facility/decision line
  falls) both build on this.
- The engine's config-error state acquires a clean definition: nothing from
  the failing config was ever installed, so there is no half-applied
  configuration to unwind. That is what lets ADR-0022 recover by evaluating
  the bundled default in its place.
- The fsm graph's open accumulate-as-config-loads contract retires
  (ADR-0015); validation of authored references moves to load time.
