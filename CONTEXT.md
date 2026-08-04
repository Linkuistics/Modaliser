# CONTEXT — Modaliser glossary

The Ubiquitous Language for this repo. Append terms inline as they
harden. Glossary only — no implementation detail.

## Terminal-pane domain

**Pane / split** — interchangeable. The unit of focus inside a terminal
or multiplexer. Each backend has its own native term (iTerm "session",
tmux/zellij/WezTerm "pane", Kitty "window"); externally we say "pane."

**Focused pane** — the pane currently receiving keystrokes. Determined
in principle by the foreground process group of its controlling tty.

**Host terminal** — the OS-level terminal emulator (iTerm2, WezTerm,
Kitty, Ghostty, Alacritty). What macOS reports as the frontmost app.

**Multiplexer (mux)** — a process running *inside* a host terminal that
provides its own panes (tmux, zellij).

**Backend** — an implementation of the terminal-backends abstraction
for one host terminal or one multiplexer.

**Splitting backend** — a backend that exposes the directional
focus/split/move ops + digit-jump (and optionally `toggle-pane-zoom`).
Implies the terminal/mux supports native splits. See the
capability-predicates section of
`docs/how-to/terminal-pane-aware-tree.md` for the op surface.

**Detection-only backend** — a backend that exposes the detection
primitive (process running in the focused/only pane) but not the
splitting op surface. Used for host terminals without native splits;
users add a mux inside for splits.

**herdr socket transport** — how Modaliser talks to herdr: newline-delimited
JSON-RPC over herdr's Unix socket, one `{"id","method","params"}` request per
connection, rather than shelling out to the `herdr` CLI. herdr is
socket-native (its CLI is a thin wrapper over the same socket), so this is the
integration boundary, not a workaround; the other muxes are CLI-native and stay
on the CLI (ADR-0020). _Avoid_: calling it an "API client" — there is no
session, no connection to hold, and no state between calls.

**Backend reachability** — whether Modaliser can currently reach a backend's
control surface. For herdr this is read straight off a query: the transport
answers `#f` only when herdr did not answer at all (unreachable socket,
timeout, unparseable reply, or a transport still **inert** — see below).
A reachable herdr always answers truthily —
with an empty result when there is nothing to list, or an `error` envelope
when it has an objection to raise. Distinct from **Tool path**
health, which is a CLI-only concern and answers a different question (is the
binary resolvable?). _Avoid_: "herdr not found" for an unreachable herdr —
nothing is being looked for on a path.

**Inert transport** — an outward channel that has been imported but not yet
wired, so it refuses to carry anything and every call degrades to the value an
unreachable peer already returns. Reaching a running tool is a property of the
app being *live*, not of a library being *imported*, so the portable library
ships the unwired default and the **host** installs the real one at bootstrap.
Three instances, one shape: herdr's socket transport ships
`current-herdr-socket-path` as `#f` and degrades to `#f` (ADR-0020); the
**Shell seam** ships no runner and degrades to `""`; the **HTTP seam** ships no
runner and degrades to a callback receiving `#f` (both ADR-0023). Distinct from
**Backend reachability**, which is about the peer; inertness is about this side
never having been wired. _Avoid_: "disabled" or "unconfigured backend" — the
backend is fully present and composed; only its channel has nowhere to go.

**Shell seam** — `(modaliser shell)`, the one place the library tree shells out
through. A portable library with no native import, so `run-shell` /
`run-shell-async` dispatch through parameters that hold no runner until
`root.scm` installs the native ones; the tree is therefore *incapable* of
spawning a process rather than merely declining to (ADR-0023). What makes the
distinction load-bearing: `swift test` builds a bare engine that never runs
`root.scm`, so no test can drive the developer's own tmux, zellij, wezterm,
kitty, ghostty, alacritty, nvim, or a Mac app over AppleScript. _Avoid_:
"stubbing the shell" — nothing is substituted, and there is no per-test setup to
forget; the safe state is the default. An **Inert transport**, in the shell's
form.

**HTTP seam** — `(modaliser http)`, the shell seam's sibling and the one place
the library tree fetches a URL through: a portable library with no native import,
whose `http-get` dispatches through `current-http-runner`, unwired until
`root.scm` installs the native fetch (ADR-0023). Same construction, different
peer — the shell seam's reach ends at the user's own machine, this one leaves it,
so what the inertness buys is a suite that does not depend on a third party being
up. Its degradation value is `#f`, which the one consumer already reads as
"network error". _Avoid_: "the HTTP client" — there is no session, no connection
held, and one procedure. An **Inert transport**, in the fetch's form.

**Sent, not called** — issuing a socket request and closing without reading the
reply, for an op whose answer cannot arrive promptly (herdr answers
`worktree.create`/`.remove` only after a git subprocess) or at all
(`server.stop` kills the responder). The op still completes in full: herdr
performs every effect before composing a reply and discards the reply if nobody
is listening. Distinct from **fire-and-forget**, which described the CLI era's
`run-shell-async` and implied a spawned process and a callback; a sent op has
neither. _Avoid_: "async" for these — nothing is deferred, and no continuation
runs.

**Tool path** — the search path backend shell-outs resolve their tools
(tmux, zellij, …) through: the user's login-shell PATH union'd with a
hardcoded floor, derived once at startup. Exists because GUI-launched
Modaliser inherits a minimal PATH lacking the user's tool locations. A
configured backend whose tool is absent from it surfaces contextually
(overlay message + log), never silently (ADR-0017). Derived by spawning the
login shell through the **Shell seam**, so in an unbootstrapped engine it
degrades to the floor alone. Moot for herdr, which
is reached over its socket at a path derived from `$HOME` and carries no
`tool-name` at all — see **Backend reachability**. _Avoid_: treating a
CLI backend's empty query result as proof no session is running — tool
absence is a distinct state, and only detectable there by re-probing.

**Focused-terminal path** — alist keyed by backend symbol with
`#(pane <id> fg <cmd>)` vector values, representing the chain from
the host terminal down through any mux to the innermost foreground
command. Each backend symbol appears at most once. See
`docs/reference/terminal-detection.md`.

**Chip** — the digit-label overlay painted on each pane by
`focus-pane-by-digit`. **Always a native macOS overlay window**
drawn by `(modaliser hints)` `hints-show`, never injected text or
escape sequences into the terminal stream. The per-backend job is
producing the `(label, screen-rect)` pairs `hints-show` consumes;
chips themselves are uniform. "Indirect and inexact" refers to
whether a backend can produce screen-accurate rects (e.g. when
cell-pixel dimensions must be derived rather than read).

**Suffix hook** — RETIRED: the per-app context handler
installed via `set-local-context-suffix!`, returning a string like `/nvim`
to select a variant tree. Replaced by **Terminal context map** entries
(nvim, zellij are exe→tree mappings; no global slot, no composition
discipline). _Avoid_: reintroducing a global context-selection slot.

**herdr** — an "agent multiplexer that lives in the terminal" (herdr.dev):
a client/server TUI run *inside* a host terminal (the user runs it in iTerm).
A **mux** backend, like tmux/zellij, but with a richer surface (workspaces,
tabs, panes, worktrees, agent status) and a JSON socket-API CLI as its control
surface (`herdr pane|tab|workspace|worktree|agent …`) rather than keystrokes.

**Workspace (herdr)** — herdr's top-level grouping, one level *above* tabs; a
set of tabs (each holding panes) for a body of work. Modaliser's own overlay
_screen_ and OS _window_ are unrelated senses — qualify as "herdr workspace"
when ambiguous. Displayed as **Spaces** in herdr's UI and in Modaliser's
herdr-tree labels; "workspace" remains the API/code term (`workspace_id`).

**Worktree (herdr)** — a git worktree that herdr can create/switch/manage; herdr
ties a workspace to a worktree for agent work. Distinct from Modaliser's grove
`.grove-worktrees/` (unrelated). A worktree is **open** when a herdr workspace is
currently live on it (`herdr worktree list` reports its `open_workspace_id`),
else **dormant**; "switch to a worktree" means focus its open workspace, or open
one if dormant.

**Agent status** — herdr's per-pane state for an AI coding agent running in that
pane: `idle` / `working` / `blocked` / `unknown`. Surfaced by `herdr pane list`.
The thing "jump to a blocked agent" acts on.

**herdr client prefix** — the modifier+key that opens herdr's own client
keybindings (default `ctrl+b`), written `prefix+X` throughout. herdr exposes no
way to query the resolved one, so Modaliser takes it as a single stated
assumption rather than a reading — one value shared by every herdr op that
emits keystrokes (**Detach**, **Copy mode**, **Scrollback**), never one per op.

**Detach (herdr)** — end the herdr *client*, leaving the server and every
pane/agent running for a later re-attach (`herdr`). A client-side keybinding
(default `prefix+q`), not a socket/CLI verb. Contrast **Stop (herdr server)**.

**Stop (herdr server)** — end the herdr *server* (`herdr server stop`):
every pane and agent terminates; the host terminal returns to the shell.
"Quit" unqualified is ambiguous between detach and stop — name which one.

**Copy mode (herdr)** — herdr's per-pane selection/yank mode, entered in the
*live* focused pane (`copy_mode`, default `prefix+[`). Layout-aware: it acts on
herdr's focused pane, not the whole herdr canvas. A **host** terminal's own copy
mode is a different thing and the wrong tool here — the host sees herdr as one
session and selects across the entire canvas, ignoring herdr's pane layout.
The stock composition binds it at the herdr screen's top level on
`c` (the library ships the op, the config chooses the key — ADR-0021).
Distinct from **Scrollback (herdr)** — _avoid_ using either name for the
other, or "copy/scrollback" as though it were one op.

**Scrollback (herdr)** — the focused herdr pane's scrollback *buffer*, opened in
an editor (`edit_scrollback`, default `prefix+e`). The stock composition binds
it at the herdr screen's top level on `C`. Distinct from **Copy mode (herdr)**:
copy mode selects in the live
pane, scrollback leaves it for the buffer's history. Both are client-side
keybindings with no socket/CLI verb, so both are emitted as prefix-then-key
keystrokes (like **Detach (herdr)**).

**Panes drill (herdr)** — the `P` drill row in the stock herdr screen holding the
*entire* pane surface: focus (hjkl, crossing into the focus walk), split, move,
`[`/`]` prev/next cycling, zoom, close, and the panes live-list (chips +
digit-jump). Parallel to the Tabs / Workspaces / Worktrees / Agents drills; no
pane op lives at the herdr screen's top level. Provisional grouping "until a better
hierarchy of interaction" is worked out (herdr-pane-group grove).

**Reorder (herdr)** — moving a tab within its workspace's tab bar, or a space
within the sidebar, to a different *position* (`tab.move` / `workspace.move`,
via an **Insert index**). Distinct from a **pane move**, which is a
`pane.swap` with a neighbour and carries no index; and from **Prev/Next
cycling (herdr)**, which moves *focus* along a list and leaves the order
alone. The stock composition binds it as `m` Move inside the `T` / `S` drills,
on the axis the target is drawn along (tabs `h`/`l`, spaces `k`/`j`). Either
end of the list is a
no-op, not a wrap — cycling wraps, reorder does not.

**Insert index** — herdr's reorder parameter: a **gap** index into the list
*before* the target is removed (valid `0…len`), not the target's final
position. The result lands on `source < insert ? insert - 1 : insert`, so
moving one place later is `pos + 2` and one place earlier is `pos - 1`.
_Avoid_: reading it as a destination position, and _avoid_ taking a tab's
`number` for its position — `number` is a **stable identity** that survives a
reorder; display order is the `<kind>.list` array order.

**Prev/Next cycling (herdr)** — a ring step through a drill's *displayed rows*,
one at a time, bound in the stock composition to `[` prev / `]` next uniformly
across the Panes / Tabs / Workspaces / Agents drills (Worktrees excluded): tab-scoped for Panes,
workspace-scoped for Tabs, global for Workspaces, status-banded order for
Agents — mirroring herdr's own cycle semantics (`prefix+n/p` tabs,
navigate-mode workspaces, `prefix+Tab` panes). Loose keys, not a sub-mode:
each carries `'next 'self` directly in the drill body, so pressing one
re-arms in place and the drill's live list re-renders with the new focus
(prev-next-nav-k4).

## Jump-navigation domain (herdr screen)

**FSM graph** — the explicit dispatch model: a graph of **states** with
labelled **edges**, held as first-class printable s-expr data built by its
own construction DSL and introspectable by tooling and renderers — replacing
the implicit tree-walk + `'next`-edge machinery. Flat Moore: actions attach
to states via **Action slots**, never to node kinds; authored nesting is
edges only (no statechart hierarchy). "Firing a command" = transition into
its state, run its entry action, follow its **auto edge** (halt if terminal).
The layout spec remains the authoring surface and lowers to this graph.
Runtime configuration is (current state, **Return stack**) — an RTN, not a
pure FSM. See `docs/specs/fsm-graph.md`.

**State class (resting / transient / terminal)** — derived from a state's
outgoing edges, never declared: key edges = **resting** (awaits input); an
auto edge = **transient** (a command: entry action runs, then the edge is
followed); none = **terminal** (the machine halts, releasing capture
*before* the entry action runs). _Avoid_: declaring terminality — it is
always structural.

**Visit** — the span from the machine coming to rest in a resting state
until it rests elsewhere or halts; the unit presentation and snapshots
belong to. A transient excursion returning on a cyclic auto edge
*continues* the visit — entry/show do not re-fire (re-arm in place), though
the snapshot refreshes.

**Up-edge** — a state's backspace edge, implicit to its lowering parent
(intra-tree containment only). Backspace is one rule: follow the up-edge,
else pop the Return stack, else (walk root → halt; otherwise no-op).
_Avoid_: declared cross-context up-edges — retired; stepping outward
across contexts rides Return-stack frames seeded at activation (Terminal
context map).

**Call edge / Return stack** — a cross edge into a Walk is a **call**: it
pushes a return frame; backspace at the target region's root pops it
(return-to-caller, callers vary per entry site). Activation also SEEDS the
stack — one frame per outer context from the detection chain (Terminal
context map) — so outward steps pop the same way. Escape clears the whole
stack. The stack is runtime configuration, not graph structure.

**Action slots** — a state's two action pairs with distinct timing
contracts: **entry/exit** run unconditionally at a Visit's boundaries
(command bodies live in entry); **show/hide** are presentation-paired —
show fires when the overlay actually displays the state (possibly never,
under the show delay), hide only if show fired. Every visible side
effect lives in show/hide, chip paint/clear included, so chips appear
*with* the overlay and never ahead of it; the no-flash and pairing
guarantees are the contract. Authoring: `'entry`/`'exit` name the
unconditional pair; `'on-enter`/`'on-leave` lower onto show/hide —
they are NOT the entry/exit slots, despite the name. A leaving hook may
take an **Exit reason**; an entering one, the arriving key.

**Exit reason** — the symbol saying *why* a Visit ended, handed to a
leaving hook that declares an argument: `'navigate` (the modal moved
elsewhere and stayed up), `'confirm` (Return), `'cancel` (Escape, the
leader again, an unmappable key, or an unknown key under
`'exit-on-unknown`), `'exit` (any other end — a Terminal fire, a Walk
root backspaced out of, a bare `modal-exit`). One vocabulary, two
recipients on the two timing contracts of **Action slots**: the
unconditional `'exit` slot sees every Visit end, the
presentation-gated `'on-leave` only the displayed ones. Declaring the
argument is per-hook and optional — a nullary hook stays correct.
_Avoid_: calling a leaving hook a "thunk" unqualified — that reads as
"nullary, full stop", which is how the reason went undocumented.

**Edge gate** — a predicate on an edge (detection — e.g. the `.` step-in
edge). Gates snapshot when the machine comes to rest (Visit start, and
refreshed on cyclic re-arm); the snapshot is the Visit's edge set, shared
by overlay and dispatch, so rows shown ≡ keys live. A gated-out edge is
simply absent (the key falls to the unknown-key policy).

**Edge provider** — a resting state's per-visit edge source: a procedure
run at the gate-snapshot instant returning extra edges and synthetic states
(jump labels, narrowing prefix states), valid for that Visit only.
Narrowing needs no bespoke machinery: a prefix state is an ordinary
provided resting state whose up-edge un-narrows. It is called with **the id
of the state it is lowered onto** — not decoration: a provided *resting*
state's id must read `<owner-id>/<key>` and its up-edge must target
`<owner-id>`, or the breadcrumb derivation garbles or raises, so a provider
that mints one cannot be written without knowing its owner. _Avoid_: reading
the owner from the visit owner — that is set *after* the provider runs.

**Entry table** — RETIRED: the graph-carried activation
registry with gated rows and derived specificity ranking. Activation is
now the screen-set lookup plus the **Terminal context map**'s chain walk
(Configuration domain); nothing ranks entries because the chain itself is
the containment order. _Avoid_: reintroducing gated activation rows or
specificity machinery.

**Entry point** — the state activation lands on: a screen root (by leader
kind and frontmost bundle-id), or, on a **Terminal-like** screen, the
innermost mapped context's tree root chosen by the detection chain
(ADR-0013), with the Return stack seeded for outward steps. _Avoid_:
"subtree" for an inner context — its region is graph nodes reachable from
its root, not a contained copy; and per-entry gates — detection lives in
the chain walk, not on entries.

**Jump space** — the herdr top level's unified navigation surface: one flat
key space covering every *visibly drawn* target across four axes — the
current tab's panes, the focused workspace's tab bar, the sidebar Spaces
entries, the sidebar Agents entries (Worktrees excluded; they have no screen
presence). One jump label = one destination; two visible targets with the
same destination (an agent whose pane is in the current tab) share one label.
Scrolled-away entries get no label — the capital drills cover them.

**Jump label** — the one- or two-key lowercase sequence assigned to a jump
target: a prefix-free code, assigned deterministically **per axis from a
reserved letter pool** (panes and spaces each own a fixed pool; agents then
tabs share the remainder), visual order within an axis. Stability contract:
an axis's labels depend only on that axis's own visible list — a changed
axis reassigns only itself (and, for the shared pool, the axis after it).
No cross-invocation persistence — same list, same labels. Produced by
per-axis calls to the general parameterised assignment utility
(restrictable single-key alphabet, valid-leader set, valid-second-key set);
disjoint first-char pools keep the combined space prefix-free. _Avoid_:
"axis-priority order (panes → spaces → agents → tabs)" — the retired
global-assignment spelling.

**Jump legend** — the overlay panel listing the jump space's full
label → target-name mapping, kind-tagged, in stable-axis order
(spaces → agents → tabs → panes), read from the Visit's snapshotted
assignment so it always agrees with the chips; its narrowed variant on a
prefix state lists only survivors with their remaining key.

**Plane rule** — the disjoint split a screen keeps between the keys its
**Edge provider** may hand out as labels and the keys it binds statically.
Not decoration: the two share one key space and a static edge is matched
first, so an overlapping label is silently unreachable rather than an error.
Every jump surface needs one; which split is free.

Both shipped surfaces put labels on lowercase and the named surface on
capitals. **herdr's** is the top level's discipline: lowercase letters belong
to the jump space (plus `b` Jump-to-Blocked — itself a jump); every named
operation or drill moves to a capital (`P` Panes, `T` Tabs, `S` Spaces,
`W` Worktrees, `A` Agents, `Q` Quit). Digits stay list-row selectors inside
drills, out of the jump space. One deliberate exception: the `c` **Copy mode
(herdr)** / `C` **Scrollback (herdr)** pair — a lowercase key that is not a jump
label and a capital that is not a drill — kept as a case pair because the two
ops are each other's nearest neighbour and are reached for together. `c` is
consequently excluded from the jump label pools; a capital needs no such
exclusion (the pools are lowercase-only). **Paneru's** is wholly the user's,
since the library authors neither plane (ADR-0021): the **Strip listing**'s
labels come from the config's alphabets and the **Paneru ops** from its keys,
and nothing checks that they are disjoint.

**Mini-chip** — the compact chip variant painted over a herdr sidebar entry
(at the end of the entry's row) or a tab title (just above it); sibling of
the pane **Chip** and **Window chip**, same `hints-show` native-overlay
machinery. Carries a letter jump label, never digits. Pane targets keep
full-size chips.

**Narrowing (vimium-style)** — the two-key jump state after the first key:
ALL chips remain visible; chips whose label doesn't start with the typed key
dim; surviving chips dim their consumed first char, leaving the remaining
key prominent. Backspace returns second-key state to first-key state
(un-narrows); Escape exits and clears chips. A jump firing is Terminal —
focus moves, the modal exits.

**ui.layout** — the herdr socket-API surface (Modaliser-side name for the
fork-added method) reporting the *drawn* cell-rects of sidebar entries and
tab titles, keyed by `workspace_id` / `pane_id` / `tab_id`; the geometry
source for mini-chips. Pane rects stay with `pane.layout`. Against a herdr
without it, mini-chips don't paint (jump keys and drills still work).
See `docs/specs/herdr-ui-layout.md` for the wire contract.

**Grid frame** — the calibrated pixel rect the herdr canvas maps onto for
chip placement: origin = the measured top-left character cell, extent =
canvas × true cell size (via the AX text interface's bounds-for-range).
Distinct from the **AXScrollArea frame** (the raw host frame), which also
spans the terminal's margins and sub-cell slack — scaling against the raw
frame stretches positions proportionally to the coordinate. _Avoid_:
using "host frame" for both; the raw frame is only the calibration
fallback.

## Configuration domain

**Configuration value** — the single explicit value describing the
entire configuration: settings (leaders, overlay delay), terminal
backends, context hooks, and the modal node/edge graph. Composed from
**Fragments** by ordinary Scheme; the complete description of what the
engine runs. _Avoid_: "config" for this value where it could mean the
user's file — the file *builds* the value.

**Fragment** — a piece of configuration returned by a pure library
constructor (a subgraph, a backend record, a settings group), composed
with standard Scheme (define/let/append). Carries its own wiring
(detection gates, edges, providers) internally, so composing fragments
never requires authoring wiring.

**Wiring fragment** — the **Fragment** a decision-free tool library
exports, conventionally named `wiring`: everything the tool's
integration needs and nothing a user would choose — a backend record, a
context-map entry, machinery-named side trees. No key, no label, so
composing the tool is one call and the screen is authored separately
(ADR-0021). A constructor renamed *to* `wiring` is announcing that it no
longer delivers a tree. _Avoid_: "wiring fragment" for the host-side
installs `root.scm` performs (the herdr socket path, the theme CSS) —
those are host plumbing outside the configuration value, not fragments
in it.

**Handoff** — the single effectful call that installs the assembled
configuration value into the engine; the only effectful moment in
config authoring. Everything upstream is inspectable, printable,
testable data.

**Registration model** — the retired authoring pattern this grove
replaces: `register!`/`set-*!` calls accumulating into hidden globals
(tree registry, entry table, FSM open-graph tables, terminal-backends
registry). _Avoid_: introducing new `register!`-style authoring
surfaces; mutable accumulation survives only as engine internals behind
the **Handoff**.

**Terminal context map** — the configuration value's single exe→tree
mapping, consulted by any **Terminal-like** context: the focused pane's
innermost mapped foreground exe (via the detection chain) selects the
tree leader activation lands in; backspace steps outward through the
chain. One entry per inner tool (herdr, nvim, zellij …), independent of
which host contains the pane. Replaces compound host/mux scopes,
per-host step-in wiring, and the context-suffix hook. _Avoid_:
"attachment" for mux×host wiring — there is no per-pair attachment;
composition is host ⊥ mapping.

**Terminal-like** — the property of a context that hosts panes running
foreground commands and therefore consults the **Terminal context
map**: every host terminal, and terminal panes embedded in other apps
(IDE integrated terminals). Declared by the host's fragment, not
derived per inner tool.

**Host capability** — a named procedure a host's backend record exposes
for host-specific glue an inner tool's UI needs (e.g. `canvas-frame`,
the calibrated-grid-frame probe behind herdr's chip geometry), consumed
generically through the terminal façade at use time ("which host am I
in" is runtime state). N hosts publish, M inner tools consume — never
host×tool pairs; a host lacking a capability degrades that feature.
_Avoid_: "capability predicate" for this — the `supports-*?` op
predicates are a different, op-surface mechanism.

**Display value** — a pure display-DSL value attached to a node as its
single, disjoint display entry, saying how to render it: panels
referencing the node's own rows by key, block placement by reference,
spans, order, embeds. The configuration's second layer: dispatch reads
never consult it, so substituting a display cannot change the live key
set. Authored with the display DSL and attached by `with-display`; the
sugar builds both layers at once as a veneer. _Avoid_: "presentation
annotations" — display is a first-class value, not metadata smeared
through the operational tree.

**Bare authoring surface** — the canonical, de-complected config-authoring
path: dispatch structure composed from the plain tree constructors, then a
Display value attached as a separate explicit step. The sugar
(screen/panel/open) is a veneer over it, never the only way in; a node
with no display renders as loose declaration-ordered rows. _Avoid_:
confusing with the loose region's "rendered bare" (header-less) sense —
that is an Overlay-presentation term.

**Embed** — the display mechanism that renders an edge-target's UI as
a section of the parent's display. Firing the edge genuinely navigates
(a real Visit); presentation activates the section in place — the
fired key highlights, the rest dims, backspace reverts. The target's
keys do NOT merge into the parent's edge set (contrast the dispatch
transparency of a **Panel**). _Avoid_: "swallow" — the working name
during design; and any reading where embed changes dispatch.

**Display root** — the unit the overlay renders under the two-layer
model: one persistent rendered layout spanning several FSM states
(a node's display plus its embedded sections), carrying an
active-section marker that restyles — never rebuilds — as the Visit
moves within the root. The invariant becomes **active rows ≡ live
keys**: dimming is the display's statement of which keys are live.

**Facility** — anything a library may hold: whatever's correctness is
fixed by the tool being wrapped or the machinery being implemented — an
op (`focus-pane-left` *is* herdr's `pane.focus_direction`), a live-list
block, a provider, a backend record, a context-map entry, a
machinery-named side tree, a documented constant like herdr's default
prefix. Contrast **Decision**. _Avoid_: "utility" as a synonym — a
utility is a facility, but so is a backend record, which is not
utility-shaped.

**Decision** — anything only the user's preference can make correct:
which ops a screen surfaces, on which keys, under which labels, in
which panels, with which forgiveness. Decisions live in user space
only — the **Seeded config** or an **Example composition** — never in a
library. Contrast **Facility**. _Avoid_: reading "decision" as an ADR;
that is a *design* decision, this is a *configuration* one.

**Decision-free library contract** — the invariant that no file under
`lib/modaliser` authors a key or a label, so no library holds a
**Decision** (ADR-0021). Mechanically enforced at **strict zero** by
`scripts/check-decision-free.sh`, the sibling of the portability
check: one authored binding fails it. _Avoid_: treating it as a style
rule — it is a gate. Also avoid reintroducing the ceiling it was
introduced with (136, falling to 0 as the contract was paid off): the
ratchet was migration scaffolding, not part of the contract.

**Example composition** — a never-loaded `Scheme/examples/*.scm`
holding a stock screen for a setup a fresh install does not run (tmux,
Chrome). Complete and self-contained — it evaluates as a working
`config.scm` in its own right, which is what lets the shipped-config
load seam prove it still composes. Carried always-fresh by the **sys/
mirror** and copied in by hand; adds no frozen name, because a user
copies its contents and never names the file. _Avoid_: confusing with
the retired `app-trees/`, which was harmful precisely because it was
seeded *and loaded*.

**Seeded config** — the one user-owned file first run copies from the
bundled default (`config.scm`) and never touches again: composition
plus every **Decision** — keys, labels, panels, and the screens
themselves — authored inline from library **Facilities**. Nothing
Modaliser ships-and-improves may live in it (ADR-0019); no screen is
exempt from living in it (ADR-0021). _Avoid_: "seeded tier" implying
multiple seeded files — the app-trees/ seed is retired.

**Degraded boot** — the state Modaliser runs in when the user's
config failed to load: the bundled default is armed in its place, the
status-bar menu is built and every item enabled, and the error is
logged, shown once, and left on the menu (ADR-0022). Distinct from a
*failed* boot, where the bundled default failed too and nothing is
armed — the menu is still built either way. _Avoid_: "safe mode" —
nothing is switched off; it is the shipped default configuration
running. And do not read it as recovery from a *reload*: reload is
relaunch, so every boot is a cold one.

**sys/ mirror** — the always-fresh copy of the entire bundled Scheme
tree under the user's config dir, wiped and re-copied per bundle
fingerprint. Read-only in contract: it exists so users can read shipped
code and IDEs can navigate into it from user config; fork by copying a
file out into the config root, which shadows it. Its
`default-config.scm` is the diff reference for the manual upgrade path.
_Avoid_: editing in place (silently overwritten); "seeding" for the
mirror — seeding is the one-shot config copy, the mirror is a sync.

## Modal-dispatch domain

**`'next` edge** — the DSL-authored keyword on `(key …)` declaring a
command leaf's post-action transition: a tree-set collection's id (a
**cross** edge), `'self` (a **cyclic** edge — the leaf's own containing
group), or a 0-arg procedure (a **dynamic** edge). The config-authoring
surface for what lowers to the FSM graph's **auto edge**
(Jump-navigation domain); a leaf without one is **Terminal**. _Avoid_:
"sticky-target" — the retired flag-era spelling.

**Terminal** — a leaf with no outgoing edge: no `'next`, no children.
Firing one releases the modal key capture *before* its action runs, so
the action may freely hand the keyboard elsewhere (an external prompt, a
chooser). Terminality is static — knowable from the declaration alone,
never from what an action's body does. The FSM graph's **terminal**
state class (Jump-navigation domain) is exactly this, derived from a
state's edges rather than declared.

**Walk** — a collection in the configuration's tree set whose member leaves
cycle back to it via
`'next 'self` (latched UX: fire a row, stay in the collection). Authored
with the `walk` DSL form. What the flag era called a "sticky mode";
stickiness is now *derived* from the members' edges, never declared on
the group. _Avoid_: "sticky", "sticky-set" — retired; a group carries no
latch flag.

**Dialog command** — a command leaf whose action needs the user's keyboard
outside modal key-capture: it fires a command whose UI prompts the user
(herdr's own new-worktree prompt, the worktree-remove confirm) or raises UI
Modaliser itself owns (a **Chooser prompt** for herdr tab/workspace rename;
native info/confirm dialogs for backend errors). Necessarily **Terminal** —
the released capture is what lets the external UI receive typing — and its
action must not block Scheme evaluation while that UI is up (ADR-0014).
_Avoid_: "trigger" — ambiguous with the key that fires an action; assuming
every dialog command's UI is literally outside the app — some, like the
Chooser prompt, are Modaliser's own panels.

## Window-switching domain

**Focused window** — the frontmost OS window: the top-level window macOS routes
keystrokes to. Resolved via `NSWorkspace.frontmostApplication` → that app's AX
`kAXFocusedWindow` (falling back to `kAXMainWindow`), the cold-AX-safe path
already used by the window-layout ops (`focusedWindowAndFrame`). The
`(modaliser window)` `focused-window` primitive surfaces its identity
(`ownerPid`, `windowId`, frame) to Scheme. _Avoid_ conflating with **Focused
pane** — a split *inside* a terminal window, a different granularity.

**Window chip** — the digit-label overlay painted over an on-screen
*window* (not a terminal pane) so the user can focus that window by
typing its digit. Same overlay machinery as the pane **Chip** above
(`hints-show` native windows); the distinction is the labelled target:
a top-level OS window vs. a pane inside a terminal. Triggered by
`(window:list-block 'chips? #t)`. Source: `window-list.sld`.
_Avoid_ bare "chip" when the window-vs-pane distinction matters.

**Display** — a physical monitor (`NSScreen` / `CGDirectDisplayID`). _Never_
called a "screen": `screen` is the overlay-DSL word for a navigable overlay
level. Source: `list-displays` (`WindowLibrary.swift`).

**Display chip** — the round, letter-labelled overlay chip painted at a
display's top-right corner; the sibling of the square, digit-labelled **Window
chip**. Plain letter = move the focused window here (preserving its fraction of
the display); Shift+letter = focus this display. Painted in the `'displays`
hint group so it coexists with window chips (the `default` group) without
clobbering — the per-paint `hints-show`/`hints-show-in` only rebuild their own
group. Source: `blocks/display-list.sld`, `display-actions.sld`.

**Same-app overlap** — the failure this grove addresses: two or more
windows of the *same* application whose on-screen frames overlap, so
their window chips land on top of each other and become unreadable /
un-aimable. Observed with iTerm and Dia; treated as generic, not
app-specific.

**Chip placement** — the two-stage pipeline that turns a window into a
`(label, screen-rect)` pair for `hints-show`: (1) a Swift geometric
stage that subtracts occluder rects from the window to find a clear
fragment (`ChipPlacement.swift`), then (2) a Scheme reactive stage that
"dodges" chips which still collide (`window-list.sld`).

**Chip cascade** — the fallback tier of chip placement: when a window
has no usable visible area for an on-window chip, its chip is placed
into a **slot lattice** anchored near the occluded window's natural
corner, filling the nearest free lattice slot. Co-located same-app
windows therefore produce a local stack of chips by their cluster. The
cascade is what keeps a fully-occluded window selectable.
_Avoid_: "cascade" for the on-window dodge — that is the first tier.

**Slot lattice** — a screen-covering tiling of chip-sized cells
(step = chip side + padding) used to assign non-overlapping fallback
positions. Finite cells + the ≤10-chip cap (`default-window-labels`)
make the no-overlap invariant a counting argument, not a fixpoint.

**Strong invariant** — the correctness contract this grove enforces:
(1) no two window chips ever overlap, and (2) every listed window keeps
exactly one chip (a fully-occluded window is relocated, never dropped).
Label readability and selectability win over keeping a chip at its
window's natural corner.

## Chooser domain

**Chooser** — an activating modal panel built on a `WKWebView`, containing
a single text input above a filtered result list. The user types to filter,
selects with arrows/hjkl, activates with Enter. Sources: `chooser.scm`,
`chooser.js`, `ChooserSearchEngine.swift`. The only Modaliser surface that
hosts a focused text input.

**Chooser input** — the single `<input id="chooser-input">` element
each chooser hosts. The lone keyboard-text-entry site in Modaliser; if
clipboard paste fails anywhere in Modaliser, it fails here.
_Avoid_: "search box", "filter field" — use "chooser input."

**Chooser prompt** — a mode of the Chooser panel with no result list: one
pre-filled text input, submitted via a closure continuation (CPS, mirroring
`dialog-confirm`'s shape) rather than an on-select callback. Reuses the same
activating-WebView machinery and chooser input as the list Chooser;
`chooser.js` tells the two apart by the *absence* of a `.chooser-results`
element, not a separate mode flag. A self-contained async action a **Dialog
command** calls directly (not a `'selector` tree node — no modal-dispatch
integration). Used where a command needs one piece of typed text before it
can fire (herdr's tab/workspace rename).

**Standard text-editing shortcuts** — the full Cocoa class of keyboard
behaviours a focused `NSTextField` / `<input>` gives a macOS user without
opt-in: Cmd-V/C/X/A, option-arrows for word movement, Cmd-arrows for
line/document jumps, Cmd-Z/Shift-Cmd-Z undo, etc. Treated as one class
because they share an event path; failing one usually means failing all.
A chooser input should support the whole class.

## Overlay-presentation domain

**Layout spec** — the authoring sugar's shape: a tree of **screens**. The
sugar builds BOTH layers of the two-layer node model at once — dispatch
structure and attached **Display values** — as a veneer lowering onto the
**Bare authoring surface** (ADR-0011, Configuration domain). _Avoid_:
calling it the "command tree" — that's the derived IR below, not what the
user writes; and "the single authored artifact" — the layers are
separable, the sugar is one convenient way to author both.

**Operational node-tree (IR)** — the internal `(kind . group)` / `(kind .
command)` node-alist tree lowered from the **layout spec** or authored
directly on the **Bare authoring surface**. Since ADR-0011 each node's
children are flat and dispatch-only, with the whole **Display value**
riding as one disjoint display entry (category nodes retired). The handoff's pure lower lowers it a second time into the **FSM
graph** (Jump-navigation domain) — the graph, not this tree, is what
dispatch runs on; the tree survives as each state's carried presentation
payload (`modal-current-node` / `modal-root-node`).

**Screen** — one navigable level of the overlay: a **loose region** above a
**grid of panels**. A top-level screen is *carried in the tree set* under a scope **symbol**
(the tree-root name a leader activation resolves to); a deeper level is
declared **inline** by an `open`, which carries its own body rather than
referencing another screen by name. On lowering, a screen's root becomes a
tree-root group and an `open` becomes a navigable `group`, each carrying its
structured **Display value** (which is what selects the panel-grid render
path — no marker). The overlay is a tree of screens, one shown at a time.
_Avoid_: implying `open` resolves a named screen — drill-down sub-screens are
anonymous and inline.

**Loose region** — everything in a screen/open body *not* wrapped in a
`(panel …)`: loose command rows, folded top-level `open`s (each a drill row),
and loose **live lists** / diagrams. Rendered **bare** (header-less, no card)
**above** the panel grid, in declaration order — visual parity with a plain
`(group …)` or the Settings overlay. _Avoid_: "General panel" — there is no
auto-collecting card; the loose rows are the screen's own inline rows.

**Panel** — a strongly-separated, banded card in a screen's grid; one declared
visual grouping. Holds command rows and/or an embedded **live list**. Lives
only in the **Display value** — a display clause referencing its rows by
key — so it is invisible to dispatch (keys keep their paths; no
panel-shaped node exists among a node's children). Carries a width
**span**. _Avoid_: "category" — the retired display-in-children node kind.

**Span** — a panel's width hint: `narrow` (1 column, default) | `wide` (2) |
`full` (all). A panel holding a live list auto-promotes to `wide` unless an
explicit span is given. Spans are relative to the **balanced** column count
(below): `wide` = 2 of the chosen columns, `full` = all of them.

**Column balancing** — the renderer chooses the overlay body's column count by
**aspect-ratio balance**, not by maximizing what fits: a JS pass measures the
rendered content and picks the count whose grid shape is closest to a target
width:height ratio (≈ 1.4). An authored `'cols N` hard-pins instead (the only
override). The **loose region** and the **grid of panels** share one overlay
**width** but pack into *different* counts — a bare key-row is narrower than a
panel card, so loose rows columnize into more columns than the panels to fill the
same width; loose **blocks** (diagram, live list) stay full-width. _Avoid_:
"auto-fit columns" as the live behaviour — CSS auto-fit is only the no-JS
fallback now; the default is the JS balance.

**Row order** — a panel's row-ordering mode: `keys` (key-sorted, default) |
`declared` (declaration order). Authored via the `'order` keyword on `panel`,
or on `screen` / `open` as a grid-wide default; resolved **panel-explicit >
screen/open default > `keys`**. Presentation only — dispatch is key-addressed
and order-independent. The **loose region** is always `declared`. A
A **walk** (the latched collection) also takes an `'order`
keyword, opting its rows out of the default key-sort so the walk reads in the
same grouped order as its declaration-ordered entry point.

**Live list** — a dynamic-list block (`window-list`, `iterm-panes`,
`iterm-tabs`): a **dispatch atom** authored in the tree (it contributes its
hidden digit key-range and hooks there), which the **Display value** places —
inside a panel or **loose** (then it renders bare in the **loose region**) —
by reference, its id defaulting to the block type. Supports a **selection cursor** (`↑↓` /
`k j` move, `⏎` activate) alongside the immediate `1–9` digit-jump selectors.
The first live list a screen renders owns the cursor — a loose list, serialized
first, wins over a panel list (multi-list `Tab` cycling is a non-goal). Distinct
from the **Chip** overlays it can paint.

**Selection cursor** — the movable highlight over a live list's rows: `↑↓` / `k j`
move it (clamped, no wrap), `⏎` activates the highlighted row. Its activation
label *is* the row's digit, so `⏎` dispatches through the same digit-jump path the
immediate `1–9` selectors use — the cursor adds only a pointer, no separate
action. State lives in `(modaliser list-cursor)`, owned by the first live list a
screen renders; the focused row is marked `.is-focused` (accent bar + tint).
On the pass that first claims the cursor (overlay open) it **seeds** to the
currently-focused row (see **Cursor seed**), else row 0.
Distinct from a **Selector** (the chooser-opening node) and from the digit
**selectors** (immediate direct-jump keys).

**Cursor seed** — the once-per-open derivation of the **Selection cursor**'s
opening row: a list block MAY carry a `cursor-initial-index-fn` thunk returning
the **Focused** item's row index (tabs/panes/windows), consulted *only* on the
claiming pass so the focus probe runs once per overlay open, never per re-render.
A non-negative integer seeds that row; anything else (`#f`, out-of-range, no
thunk) falls back to row 0. Mechanism: `list-cursor-offer!` + `seed-index` in
`(modaliser list-cursor)`.

**Open** — the authored drill-down affordance: `(open KEY LABEL body…)`. A row
that navigates *into* a sub-screen (its own body). A **top-level** open folds
into the parent's **loose region** as a single "→ LABEL" drill row; an open
declared *inside* a panel is an accent group-row in that panel. Lowers to a
navigable `group` carrying its own **Display value**. The only navigable layout
form (a `panel`, by contrast, is transparent — it never changes key paths).

**Splice** — a reusable, named chunk of layout (panels or command rows) spliced
into multiple screens/panels for DRY (e.g. a shared `window-actions` set). Built
on `expand-splices` — the same splice mechanism `walk` already uses for
keys — so nothing downstream sees the splice; the result is identical to
writing its contents inline. _Avoid_: "fragment" — the retired name for this
form; **Fragment** now means a configuration contribution bag (Configuration
domain).

## Window-layout domain

**Window-layout op** — a `w`-menu action that repositions or resizes the
*focused* OS window (thirds, halves, two-thirds, maximise, center,
fullscreen, restore) via the Accessibility API. Changes geometry, not
focus — distinct from the window-switching chips, which only change which
window is focused. Sources: `WindowManipulator.swift`, `window-actions.sld`.
_Avoid_: bare "window movement" when precision matters — it is the colloquial
name (and this grove's name) but conflates geometry with focus-switching.

**EUI flip** (AXEnhancedUserInterface flip) — the disable→write→restore dance
Modaliser performs around AX position/size writes for apps that set
`AXEnhancedUserInterface` (Electron and some others). While that flag is on,
AX geometry writes silently no-op; Modaliser flips it off, issues the writes,
then restores it. Source: `withResizableApp`.

**EUI-settle race** — _[REFUTED as this grove's failure cause — see 010
diagnosis and **Cold-AX resolution gap**.]_ The original hypothesis: on some
machines the Electron app has not finished applying the EUI-off transition
before Modaliser issues/restores the geometry writes, so they are dropped.
Investigation showed the layout-op failure occurs **upstream of any geometry
write** (resolution returns nil), is independent of the settle delay, and
afflicts apps (Dia) that never enter the EUI flip. The EUI flip itself remains
real — Chromium apps that honor `AXEnhancedUserInterface=true` do ignore
setFrame while it is on — but it is orthogonal to the window-not-moving bug.
_Avoid_: blaming the `usleep(50_000)` settle delay for layout ops not working.

**Cold-AX resolution gap** — the confirmed root cause of this grove's failure.
Chromium/Electron apps keep their accessibility engine **dormant** until an
assistive client activates it (via `AXEnhancedUserInterface`/
`AXManualAccessibility` = true, or sustained AX tree queries), and let it lapse
when idle. While dormant, `AXUIElementCreateSystemWide()` +
`kAXFocusedApplicationAttribute` returns `kAXErrorNoValue (-25212)`, so
`focusedWindowAndFrame()` resolves to `nil` and the layout op silently no-ops.
Native apps always expose an AX interface, so they never hit this — explaining
the Electron-only, intermittent, per-app symptom. Resolving the frontmost app
via `NSWorkspace.frontmostApplication` (a window-server API, a11y-independent)
+ the app element's `kAXFocusedWindow` works regardless of a11y state.
Source: `WindowManipulator.focusedWindowAndFrame`.

## Paneru-window-management domain

**Paneru** — the external sliding/tiling window manager Modaliser drives
(`karinushka/paneru`): windows live on an infinite horizontal **strip**, and
opening a window never resizes its neighbours. A daemon owns the strip; the
`paneru` binary talks to it over a Unix socket. Modaliser is a *client* of it,
never a reimplementation. _Avoid_: calling it a "tiling layout" — it does not
tile a bounded screen, which is exactly why its ops do not map onto the
**Window-layout op** vocabulary.

**Column** — one horizontal slot on the strip, holding one window or a
**stack** of them. Columns are numbered 1-based from the left and are the only
thing `window focus <n>` can target. No paneru query payload reports a
window's column, so a column number is never derivable from a window — the
gap that rules out position-arithmetic targeting.

**Paneru op** — a 0-arg thunk wrapping one `paneru send-cmd …` invocation
(`window focus east`, `window swap west`, `window grow`, `window center`, …).
A **facility**, not a decision (ADR-0021): its correctness is fixed by
paneru's own CLI. Which ops reach which keys is the user's `config.scm`.
Fire-and-forget: the daemon acknowledges nothing and silently discards an
unrecognised command, so a wrong wire form fails invisibly. _Avoid_: the
underscored spelling (`window_focus_east`) — that is the *TOML binding name*
in `paneru.toml`, not the send-cmd wire form, which is space-separated.

**Paneru-installed composition** — the load-time branch that decides whether
the user's window screen is composed from **Paneru ops** or from
**Window-layout ops**. It tests *installation* (`command -v paneru`,
ADR-0017), never daemon liveness, so it cannot race Modaliser's launch against
paneru's. A daemon that is down degrades to the established empty-output path
(ADR-0023) rather than flipping what a key does. _Avoid_: "is paneru running?"
— liveness is precisely what this must not ask.

**Strip listing** — the window rows the paneru screen shows, sourced from
`paneru query state --json` (strip order, titles, app names, `window_id`) and
joined on `windowId` against Modaliser's own window enumeration to recover the
`ownerPid` that `focus-window` requires. Paneru contributes the *ordering and
membership*; Modaliser contributes the *focusing*. Deliberately renders as
overlay rows with jump labels and paints no **Chip**. It renders the **Strip
snapshot** rather than querying — the rows and the live jump labels are the
same data, so they cannot disagree.

**Strip target** — one row of the **Strip listing**, in strip order: the
paneru window's id, app name, title, focused and floating flags, plus the
`ownerPid` the id join recovered — or `#f` when the join found no match.
An unmatched target still occupies its place and still consumes a jump label
(so a transient join miss costs one dead key rather than renumbering every
label below it), but it gets no dispatch edge.

The **Plane rule** (Jump-navigation domain) applies to this screen and is
entirely the user's to keep here: the library authors neither the labels nor
the op keys, so nothing can check that the two planes stay disjoint.

**Strip snapshot** — the per-**Visit** gather → join → label-assign result:
the **Strip targets** paired with their assigned labels. Taken by the strip
**Edge provider** at come-to-rest and read by the **Strip listing** at render.
The provider always runs first, so a label pressed faster than the overlay
appears still dispatches. _Avoid_: re-querying paneru inside the block —
that reintroduces the two-sources-can-disagree bug the snapshot exists to
prevent.
