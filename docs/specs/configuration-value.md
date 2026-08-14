# configuration-value

How Modaliser is configured once the value-composition refactor lands: the
Fragment model, the two-layer node model (dispatch structure + attached
display), the Terminal context map, lowering/validation, and the Handoff.
The root decision is ADR-0018 (`docs/adr/0018-configuration-as-one-explicit-value.md`);
the graph the value lowers to is ADR-0015 / `docs/specs/fsm-graph.md`;
nested-context activation is ADR-0013; the two-layer display factoring is
ADR-0011. Glossary: Configuration value, Fragment, Handoff, Registration
model, Terminal context map, Terminal-like, Display value, Embed, Display
root (Configuration domain); Splice (Overlay-presentation domain).

## Problem

The authoring surface is a registration model: `register!`/`set-*!` calls
mutating hidden globals — tree registry, entry table, the FSM's open graph,
the terminal-backends registry, and a single last-write-wins context-suffix
slot. Nothing at a call site says what accumulated where; load-bearing
integration wiring (backend registration, detection gates, entry rows,
up-edges) lives in the seeded-once config tier, so shipped improvements
collide with user configs on upgrade; and mux×host wiring is hand-authored
per host app-tree — a kitty user replicates ~80 intricate lines to get herdr
there.

The audience constraint has since changed: Modaliser is public behind a Homebrew
cask, so configs may **not** break freely. The sharper point is the failure mode
rather than the audience — a config naming a symbol the running binary no longer
binds used to degrade not to "that call stopped working" but to a wedged app. That
gate is now discharged (ADR-0022): the load is sequenced by the host, a failure
arms the bundled default in the broken config's place, and the status-bar menu is
built and fully enabled with the error on it. Widening (ADR-0021) and removing
authoring surface both ride on that.

## Solution

Libraries export **pure constructors** returning **Fragments** — printable
s-expression values. User config composes fragments with ordinary Scheme
(`define`/`let`/list-building), assembles them with `configuration` (a pure
merge + validation), and hands the result to the engine at exactly one
effectful point: `(modaliser:start! config)`. Everything upstream of that
call is inspectable, printable, testable data. Inner terminal tools attach
via one **Terminal context map** instead of per-host wiring. Every node in
the modal tree separates **dispatch structure** from an attached, pure
**Display value**.

## Decisions

### The Fragment: a tagged contribution bag

A fragment is a list of tagged contributions. The tags are the closed
vocabulary of what a configuration can contain:

- **tree** — a modal screen/tree (authored-altitude layout, see the
  two-layer model below), keyed by scope symbol.
- **backend** — a terminal-backend record (host or mux), including any
  host capabilities it exposes (see the context map below).
- **context** — a Terminal-context-map entry: exe name → tree (+ optional
  backend, for pane-op-capable exes).
- **setting** — one named setting (leaders, overlay delay, theme, …).

Any constructor may return any mix — one herdr constructor delivers its
backend, its context entry, and its digit-jump tree in a single value.
Composition never requires the author to know the taxonomy: fragments nest
and concatenate, and `configuration` flattens.

**Merge semantics** (`configuration`, pure). One uniform rule across all
four tags: contributions are keyed (tree → scope id, backend → backend
symbol, context → exe name, setting → setting name); two contributions with
the same key **merge silently iff they are the identical value** (`eq?` —
the diamond case, one fragment reached via two composition paths) and
**error otherwise**. There is no override, no last-wins. Unset settings
fall to engine defaults.

**Customization is composition, not patching** — and there is no stock tree to
patch. No library authors a screen: libraries export **facilities** (ops, blocks,
providers, backend records, context-map entries, machinery-named side trees) and
every screen is composed in user space from them (ADR-0021). So "a different tree
for that scope" is not a special path, it is the only path — you edit the screen
already in your `config.scm`. Constructors MAY take options where a library
anticipates variation, but an option that merely renames a key or a label is a
smell: that belongs to the call site. No fragment-editing combinator vocabulary
exists (fragments are plain data; ordinary Scheme suffices).

**The facility/decision line** (ADR-0021, enforced by
`scripts/check-decision-free.sh`). A **facility** is anything whose correctness is
fixed by the tool being wrapped or the machinery being implemented; a **decision**
is anything whose correctness is fixed only by the user's preference. The
operational test is that **no file under `lib/modaliser` authors a key or a
label** — so which ops are surfaced, on which keys, under which labels, in which
panels, with which forgiveness, are all config. Where a stock composition is
still wanted for a setup a fresh install does not run, it ships as a never-loaded
`Sources/Modaliser/Scheme/examples/*.scm`: mirror-carried, copied in by hand,
adding no frozen name because a user copies its contents rather than naming it.

**Walk hoisting and splice timing.** `walk` returns a splice node *carrying
its own tree*; `splice` (the renamed `fragment` form) likewise survives
construction as data. Splice expansion moves from constructor time to the
merge/lowering pipeline: the merge walks tree bodies, hoists any embedded
tree-bearing value into the tree set (identity-dedup as above), and
expansion happens during lowering. A walk is mentioned once, where it is
used.

### Settings are contributions

`(leaders …)` and `(overlay-delay …)` are pure constructors returning setting
contributions. `configuration` has one mechanism — merge — and no keyword
parameters. A named constructor earns its name by validating its argument or
by being read at the Handoff; anything else is spelled `(setting 'name value)`
through the raw constructor.

### The two-layer node model: dispatch structure + attached display

Every node holds two **disjoint** layers:

1. **Dispatch structure** — what the FSM runs: the flat `'children` list of
   key edges, action, gates, `'next`, providers, and **splices**
   (dispatch-level key copying, e.g. a walk's hjkl live at its parent).
   Unchanged semantics from ADR-0015. Live-list **blocks** are dispatch
   atoms: a block authored in the tree contributes its digit key-range and
   its show/hide hooks from there.
2. **Display value** — one `'display` entry: a pure display-DSL value
   saying how the node renders — **panels** referencing the node's own rows
   by key, block placement by reference (id defaulting to the block's
   type; a block-spec's explicit `'id` entry overrides it, disambiguating
   two same-type blocks — duplicate ids are a load-time error), spans,
   order, cols/layout, **embeds**, and the breadcrumb display-name. Extracted and replaced wholesale; dispatch reads never
   consult it, so substituting a display value structurally cannot change
   the live key set. A node with no display renders as plain loose rows in
   declaration order. `label` stays dispatch-side (a row's name is part of
   the row); `display-name` is display-side.

**Two authoring surfaces, one representation** (ADR-0011). The **bare
surface** is canonical: dispatch constructors (`tree-root`/`group`/`key`/
`walk`/`splice`) compose plain data, and `with-display` — pure, variadic
over display clauses, from `(modaliser display-dsl)` — attaches the display
value. The **authoring sugar** (`screen`/`panel`/`open`) keeps its authored
shape and lowers onto the bare surface as a veneer, pinned by a sugar≡bare
equivalence test (identical node output). Display references — panel key
lists, block ids, embed keys — point one level deep at the node's own
children and are validated at lowering, as load-time errors like every
authored reference. No panel-shaped node exists among dispatch children
(the former `category` node kind and its `flatten-categories` tunneling are
retired).

**Rendering resolves through a pure function.** `resolve-display`
((children, display value) → render plan) lives in the portable tree; the
overlay serializes its output. Tooling (and the future graph renderer)
reads or substitutes a node's display without touching dispatch.

**Embed.** A display may embed an edge's target: the target's UI renders as
a section of the parent's display. Firing the edge genuinely navigates — a
real Visit; dispatch is untouched — but presentation activates the section
*in place*: the fired key highlights, the rest dims, and backspace reverts
the styling. The target's keys do **not** merge into the parent's edge set.
The overlay invariant refines from "rows shown ≡ keys live" to **active rows
≡ live keys**: dimming is the display's statement of liveness.

The unit the overlay renders becomes the **Display root** — one persistent
layout spanning the states of a node and its embedded sections. The root's
*structure* persists as the Visit moves within it; a section's *content*
may re-render (a snapshot refresh, a provided-row change) inside that
persistent structure. Contracts:

- **Snapshots stay per-visit.** An embedded target that has not been
  visited renders its *static* rows, dimmed, without evaluating its gates
  or provider (detection cost stays once-per-landing; providers may
  side-effect). A provider-bearing section renders its static skeleton
  until visited; on come-to-rest its snapshot populates the section.
- **Show/hide and the delay bind to the root.** The show delay applies to
  the display root's first display in a Visit chain; once the root is on
  screen, moving the Visit into an embedded section fires that state's
  `show` immediately (no re-armed delay) and the departed state's `hide`,
  while the root stays up. The no-flash guarantee is the root's: fast
  muscle-memory presses that halt before the delay fires paint nothing.
- These contracts bind the embed renderer — the display-root/restyle
  implementation in the overlay (`docs/reference/renderer-protocol.md`
  "Embedded sections and the restyle protocol").

Mechanisms coexist: the **display** chooses per edge between **drill**
(sugar's `open` — swap to the target's own display root; the default
presentation of a group edge) and **embed** (in-place activation), and
groups a node's own rows with **panel** — a display clause, not a child
node; **splice** is a dispatch-structure mechanism, not a display choice.


### The Terminal context map

The configuration carries **one mapping exe → tree**, consulted by any
**terminal-like** context. A mapping entry is a fragment: a context entry
naming the tree it resolves to, plus a backend when the exe drives its own
panes (herdr, tmux, zellij) and none when it does not (nvim). Whether the
tree travels in the same fragment or is authored by the config is the
facility/decision line, not a property of the map — every bundled entry's
tree is the config's (ADR-0021), a user's own entry may bundle its own.
No host names an inner tool; no inner tool names a host.

**Terminal-likeness is capability, not just declaration.** A host is
terminal-like when its fragment supplies a host backend implementing the
chain probes (focused-pane identity, foreground-command detection) that
`focused-terminal-path` walks. Mux-backed inner contexts (herdr, tmux,
zellij) are themselves terminal-like — they host panes running foreground
commands, so the chain continues through them. An IDE's integrated
terminal joins by supplying such a backend for the IDE's bundle-id (future
work; the model requires nothing else of it).

**Host capabilities, consumed generically.** Host-specific glue an inner
tool's UI needs — today the canvas/pane frame probe behind herdr's chip
geometry — is a capability *of the host backend record*, resolved through
the terminal façade at use time ("which host am I in" is runtime state).
N hosts each expose one capability set; M inner tools each consume it
generically; no host×tool pairs. A host lacking a capability degrades that
feature gracefully (as chip painting already degrades without `ui.layout`).

**The inner tool's facilities live in its own library; its screen does not.**
No *host* authors an inner tool's integration — the jump provider, the chip
entry/exit hooks, the legend block, the prefix-keystroke ops, the default-prefix
constant — and no *library* authors where they are bound. So the tool's library
contributes its context-map entry, its backend record, and its machinery-named
side trees, while the user's config composes the screen that names them
(ADR-0021). Keystrokes to the frontmost app are host-generic, which is what lets
the copy-mode and scrollback ops belong to herdr rather than to any host.

**Activation** — one pure function, `resolve-activation` (the effectful
glue only fetches the chain and hands it in):

```text
resolve-activation(leader-kind, frontmost-bundle-id, chain, config):
  scope  := leader-kind = global → 'global, else frontmost-bundle-id
  screen := config.screens[scope], defaulting to config.screens['global]
  if screen is terminal-like and chain is non-empty:
    mapped := the chain's contexts with context-map entries, outermost first
    if mapped is non-empty:
      return (root  = innermost mapped tree,
              stack = [screen] + all-but-innermost mapped trees)
  return (root = screen, stack = [])
```

- **Outward step**: the existing backspace rule (up-edge, else pop stack,
  else halt/no-op) is unchanged — at a tree root, popping the seeded stack
  is the step outward; Escape clears the stack from any depth. Any nesting
  depth works.
- **Programmatic activation routes through the same resolution**: entering
  a context-map tree by scope symbol also seeds outward frames from the
  live chain when the chain contains that context; otherwise the stack is
  empty and backspace at the root is honestly a no-op (there is no outer
  context).
- **Chain-staleness doctrine**: the chain is probed at activation and at
  each come-to-rest snapshot (for the derived gate below); seeded frames
  are press-time values and outward steps never re-probe — backspace
  returns where you came from, even if the chain has since changed. The
  activation probe and the **landing** snapshot are one instant, and are
  therefore one walk: the leader handler pins the chain for the extent of
  the press (CONTEXT.md "Pinned chain"). Every later snapshot probes as
  before — the doctrine is unchanged in what it observes, only in what it
  pays.
- **Step-in**: every terminal-like screen derives a gated `.` call edge
  stepping **one mapped context inward** from that screen's own position
  in the chain — the target is computed at the visit's snapshot instant
  (like any gated/provided edge), the gate is "a mapped context exists
  inward of here", and firing pushes one return frame. Inward and outward
  steps are symmetric, one boundary at a time. Authored by nobody.
- **The entry table retires.** Activation is the screen-set lookup plus the
  chain walk; gated entry rows and all specificity ranking (up-edge
  containment, scope refinement, declaration-order ties) are deleted. The
  context-suffix hook retires with it: nvim/zellij variants are context-map
  entries. 

### Lowering and validation

Fragments hold **authored-altitude** data; printing the configuration value
shows what the user wrote. A **pure lower function** turns the merged value
into a graph **closed over its authored references**: every statically
declared target — key-edge targets, `'next` cross/call ids, authored
up-edges, embed/drill references — must resolve, as **load-time errors**.
The open-graph accumulate-as-config-loads contract retires. Two runtime
mechanisms are deliberately outside static closure, unchanged from
ADR-0015: **providers** (visit-scoped synthetic states and edges, resolved
per come-to-rest) and **dynamic `'next` resolvers** (0-arg procedures
resolved at fire time); the engine-derived `.` step-in edge is likewise
computed per visit, not validated statically.

### The Handoff

`(modaliser:start! config)` — the one effectful moment:

1. run the pure lower + closure validation;
2. install the result into the engine (graph, screen set, context map,
   backends, settings);
3. arm the leaders from the installed value.

One-shot: a second call is an error — reload is relaunch. A config that
fails before the handoff leaves the engine cleanly empty: the app's
config-error state is *defined* as "nothing was ever installed". That
definition is what makes the ADR-0022 fallback safe — the bundled default
loads into a clean engine rather than colliding with half of the user's
graph — and it is why the latch sets only on success, so the second
`modaliser:start!` in a degraded boot is allowed.

Residual mutable state lives only behind the handoff, as engine internals:
the FSM runtime configuration (current state, return stack, visit
bookkeeping and snapshots), the backend tool-health cache (ADR-0017), the
overlay/chooser/list-cursor UI state, and keyboard-capture state. The
installed configuration itself is written once and read-only thereafter.

### Behaviour slots

Unchanged from ADR-0015: gates, providers, and actions are procedures in
slots — lambda literals anywhere, the `named` wrapper for display. All
structure prints; only closure bodies are opaque.

## Test seams

One new seam — the **pure configuration pipeline** — plus the existing
suites:

1. `configuration` (merge + validation): fragments in → value or error.
2. the lower function: value → closed graph (or closure error).
3. `resolve-activation`: leader kind × bundle-id × detection chain ×
   value → landing state + seeded stack. The chain is an argument — no
   mocking machinery.
4. `resolve-display`: (children, display value) → render plan — pure,
   portable-side; the overlay only serializes. The sugar≡bare equivalence
   test (screen/panel/open output identical to bare constructors +
   `with-display`) rides this same seam.
5. **the shipped-config load** (`ConfigDslTests.defaultConfigSchemeLoadsWithoutErrors`):
   evaluate-and-install `default-config.scm`, then assert the screens lowered
   into the graph. Pre-existing, and the *only* seam ADR-0021's move needs —
   `examples/*.scm` ride it by iterating the directory, each into a fresh
   engine. Its converse is a deliberate **deletion**: library tree-shape
   assertions retire rather than relocate, because asserting a particular key
   binds a particular op asserts *preference* once the tree is user-authored,
   and load-time closure validation already catches a key bound to a
   nonexistent op. Op behaviour keeps its existing runner seams, which become
   the only library-side behavioural claim.

All exercised through the libraries' public API via the existing
LispKit-evaluation test pattern. The fsm unit suite (step semantics) and
the modal-façade / end-to-end suites are the regression gate, driving
build-value-then-handoff (install a lowered value, activate a resolved
landing). Embed's restyle protocol has renderer-side tests
(`PanelGridRendererTests` for the section payloads,
`EmbedRenderingTests` for in-place activation end-to-end).

## Out of scope

- **Seeding/upgrade rework** — what remains seeded once config shrinks to
  composition; the sibling planning leaf owns it.
- **The in-place-activation renderer** — this spec fixes the value model
  and the rendering contracts it must satisfy, not the implementation;
  the renderer itself is `docs/reference/renderer-protocol.md`'s
  ("Embedded sections and the restyle protocol").
- **IDE terminal backends** — the model admits them; building one is
  future work.
- **Hot reload** — the handoff is one-shot by doctrine; reload is relaunch.
- **Serializable behaviours** — rejected in ADR-0015; closures stay
  closures.
- **Compatibility machinery** — no version stamps, no shims, no migration
  scripts. A config either runs against current libraries or fails loudly with
  nothing installed; recovery is a *robustness* concern (the app must stay usable
  and offer a fallback), not a compatibility one.
