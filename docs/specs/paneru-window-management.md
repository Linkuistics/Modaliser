# paneru-window-management

## Problem

Modaliser's window surface is built from **Window-layout ops** — absolute
geometry on a bounded screen (thirds, halves, centre, maximise), drawn as a
layout diagram and dispatched by the `window-diagram` block. **Paneru** owns a
different world: an infinite horizontal strip where windows move *relative* to
each other and opening one never resizes its neighbours. The two vocabularies do
not map, which is why paneru cannot be a backend behind the existing surface.

When paneru is driving the desktop, every one of Modaliser's layout ops is
either inert or actively fights the window manager, and none of paneru's own
verbs is reachable — the user's `paneru.toml` `[bindings]` section is empty
because paneru ships no keyboard layer of its own.

Separately, paneru's strip can hold far more windows than the ten a digit
alphabet addresses (twelve on the live workspace this spec was written against),
so a jump surface over it cannot reuse the digit-range shape the existing window
list uses.

## Solution

When paneru is **installed**, the user composes their window screen from
**Paneru ops** instead of Window-layout ops, and that screen carries a **Strip
listing** — the active virtual workspace's windows, in strip order, each
reachable by a **jump label**.

The listing's rows come from paneru; its focusing comes from Modaliser, joined
on window id (ADR-0024). Labels are prefix-free one- or two-key sequences from
the user's own alphabets, and they reach the keyboard as **provided edges**: an
**Edge provider** on the window node mints exactly the labels this Visit's
strip earns, and the block renders the same snapshot the provider took. Nothing
about the composition is dynamic — which screen the user gets is fixed once, at
config load (ADR-0018).

## Decisions

### 1. The Strip listing is a new block, not a parameterised `window-list`

`blocks/paneru-strip` is a new block library — `.sld` + `.js` + `.css`, block
type `paneru-strip` — sitting beside the five list blocks already in
`blocks/`. `blocks/window-list` is **not** modified, and the non-paneru window
screen is untouched by this work.

This is the largest call in the workstream, and it goes the way it does for four
reasons, in descending weight:

- **`window-list`'s substance is chip placement, and the Strip listing paints no
  chips.** The great majority of that library is the two-stage placement
  pipeline — the slot lattice, the cascade, the desktop bounding box, the
  cross-chip non-overlap invariant. Reusing it means inheriting all of it behind
  a flag the Strip listing never sets.
- **The block must not query.** `window-list`'s `on-render-fn` *is* its data
  source. The Strip listing's rows come from the provider's Visit snapshot
  (decision 4), so its render hook reads a cell rather than gathering. That
  inverts the block's central contract; a block that can do both is two blocks
  wearing one name.
- **Three independent axes already differ**: the source (paneru query + join, vs
  Modaliser's own enumeration), the labels (escalating, from the user's
  alphabets, vs a private hardcoded digit list), and the row shape (`focused`
  and an app/title split, vs `visible`).
- **One block per renderer is the established convention.** Five list blocks
  exist, each with its own `.js` and `.css`, each renderer a near-copy of the
  same short row builder. Duplicating that builder is the pattern here, not a
  smell to be fixed on the way past.

The renderer is display-only, mirroring `blocks/herdr-jump-legend`: it dispatches
nothing, because the jump labels dispatch through provider edges. Its rows carry
`label` (blank when unlabelled), `app`, `title`, and `focused`; the focused row
gets the `.current` treatment the sibling list blocks already use.

The block library takes its rows through a caller-supplied thunk rather than
importing the paneru library, so it stays a generic UI component and the
dependency runs one way only (`wms/paneru` composes the block; the block knows
nothing of paneru).

### 2. Library surface

**`lib/modaliser/wms/paneru.sld` → `(modaliser wms paneru)`**, the whole of
paneru's integration in one file. `wms/` is a new category, peer to `muxes/`,
`apps/` and `tools/`: paneru is not a mux and does not live inside a pane — it
owns the desktop.

The file is shaped like `muxes/zellij.sld` and is deliberately missing that
file's two structural pieces. There is **no backend record** and **no `wiring`
fragment**, because paneru sits behind no façade: it is not a `(modaliser
terminal)` backend, it contributes no Terminal-context-map entry, and it has
nothing for the façade to dispatch to. Nothing replaces them. A reader coming
from `zellij.sld` should read that absence as the point, not as an omission —
the analogy between the two files stops at "ops plus detection in one library".

Exported surface:

| Export | Kind | Contract |
|---|---|---|
| `focus-west` `focus-east` | op | `paneru send-cmd window focus west\|east` |
| `swap-west` `swap-east` | op | `paneru send-cmd window swap west\|east` |
| `grow` `shrink` | op | `paneru send-cmd window grow\|shrink` — next/previous `preset_column_widths` entry |
| `center` | op | `paneru send-cmd window center` |
| `installed?` | predicate | `command -v paneru` through the derived tool path (ADR-0017); the **Paneru-installed composition** test |
| `strip-provider` | constructor | keyword opts (three alphabets, `'panel-label`, `'enumerate`) → the Edge provider for a `'provider` slot; invoked with its owning state's id |
| `strip-listing` | constructor | → the Strip-listing block spec, reading the same snapshot |
| `parse-strip-windows` | pure | payload text → strip rows |
| `join-strip-targets` | pure | strip rows × window enumeration → **Strip targets** |
| `strip-provider-result` | pure | assigned labels → provided edges + states |

Every op is a 0-arg thunk that lands straight in a `(key K L op)` slot, and
every one is a **facility**: its correctness is fixed by paneru's CLI. Which op
reaches which key under which label is the user's (ADR-0021), so this library
authors neither. The last three exports exist for tests (see **Test seams**).

**Seven ops, not twenty.** The rest of paneru's surface — `resize`, `fullwidth`,
`stack`/`unstack`, `equalize`, `balance`, `manage`, the `virtual*` workspace
verbs, the display verbs, and `focus first`/`last`/`<n>` — is deliberately
absent. Each further op is a config-visible follow-up costing one line, not
speculative library surface.

**`window focus <n>` is not used for targeting a listed row** (ADR-0024). It
remains a legitimate future op for the case where a *column* is genuinely what
the user means.

Every outward call — the `command -v` probe, each `send-cmd`, the state query —
goes through `(modaliser shell)` (ADR-0023), prefixed with `modaliser-tool-path`
so a GUI-launched Modaliser resolves `paneru` where the user's shell does. That
tool path is imported narrowly from `(modaliser terminal)`, as every CLI-native
backend already does. It is the one slightly awkward dependency in the file — a
non-terminal library reaching into the terminal façade for a string — and it is
accepted rather than fixed here; relocating `modaliser-tool-path` to a neutral
home is a separate concern that six other library files outside `terminal.sld`
already share (tmux, zellij, alacritty, wezterm, kitty, iterm-panes).

**`send-cmd` has no error channel.** Probed against the live daemon
(2026-08-04): an unrecognised command exits 0 and prints nothing — the daemon
silently discards it. A wrong wire form therefore fails invisibly, which is why
each op's exact command string is asserted in a test rather than trusted.

### 3. The parse and the join

Both are pure functions in `(modaliser wms paneru)`, tested by direct call.
`(modaliser json)` does the reading; neither function shells out.

**`parse-strip-windows`** takes the `paneru query state --json` payload text and
returns the active virtual workspace's windows in strip order, each row carrying
`window-id`, `bundle-id`, `app`, `title`, `focused` and `floating`. Malformed or
empty input yields the empty list rather than raising — a leader press must never
raise.

The active workspace is the `virtual_workspaces` entry whose `active` is true,
**not** the one matching `active.virtual_workspace_number`. The live daemon
reports two workspaces both numbered 1 (on different native workspaces), so the
number is not a key; `active` is.

**`join-strip-targets`** takes the strip rows and a Modaliser window enumeration
and returns one **Strip target** per strip row, in strip order, each carrying the
row's display fields plus the `owner-pid` recovered by matching `window-id`
against the enumeration's `windowId`. A row that finds no match keeps its place
with `owner-pid` `#f`.

Taking the enumeration as an *argument* rather than calling the primitive is what
keeps this a pure function: the caller passes it, and a test passes a canned list.

**Which enumeration the caller passes is itself injectable.** `strip-provider`
takes an `'enumerate` option — a 0-arg thunk defaulting to
`list-current-space-windows` — because the provider is where the live call
actually happens, and a provider test that let the real AX sweep run would assert
against the developer's live desktop (see **Test seams**). The option doubles as
the lever decision 4's cost paragraph names: `list-windows` is the wider, cached,
staler alternative, a one-line swap if the join's hit rate or the sweep's cost
ever proves a problem in practice.

**Unmatched rows still consume a label.** They render as ordinary rows and their
label dispatches to nothing, exactly as ADR-0024 anticipates. The reason is
stability: if unmatched rows were skipped during assignment, a single transient
join miss would renumber every label below it, and the labels are muscle memory.
A row that momentarily fails to join costs one dead key, not a reshuffled strip.

### 4. Dispatch is provider-minted, not a static key range

The paneru window node carries an **Edge provider** — `strip-provider`'s result
on its `'provider` slot. Each Visit it queries paneru, parses, joins, assigns labels
via `jump-labels-assign`, stores the result as the **Strip snapshot**, and
returns this Visit's edges and synthetic states:

- a **single-key label** becomes one direct edge to a provided Terminal state
  whose entry focuses that window;
- a **two-key label** contributes to a provided **prefix state** for its leader,
  whose own edges are the second keys and whose up-edge un-narrows;
- an **unlabelled** target (both pools exhausted) and an **unmatched** target
  (no `owner-pid`) are dropped from the edge set. Both still render as rows.

This shape is `(modaliser muxes herdr)`'s jump provider, minus the parts paneru
does not have: one target kind instead of four, one label pool instead of
per-axis pools, no chips, no dim-state narrowing.

**The prefix state, in full.** A two-key label needs a provided *resting* state,
and a resting provided state is the one kind whose shape is constrained: it
survives as a Visit owner across keystrokes, so the presentation façade reads it
the way it reads a permanent state. Three things about it are therefore not
free-form, and `paneru-strip-list-k7` should not have to rediscover them —
`muxes/herdr.sld` records the same three at length, having found each the hard
way:

- **Its id is `<owner-id>/<leader>`**, the convention permanent child states use
  (`fsm-child-id`). `strip-id-prefix` derives a breadcrumb segment by
  `substring`-ing the parent's id off the child's, so any other shape yields a
  garbled segment or raises outright.
- **Its `'up` edge targets `<owner-id>`**, or backspace does not un-narrow and
  `ancestors-within-tree` stops the climb early.
- **Its `'payload` carries the two-layer node shape** that `screen` lowers a
  registered root's payload into: a `'children` list holding the block, plus a
  `'display` clause with one panel referencing it. `fsm-resolved-payload` hands
  this alist to the façade as `modal-current-node`, and the panel-grid renderer
  resolves `'children` + `'display` off whatever that is (ADR-0011) — so the
  *unchanged* renderer draws the narrowed listing. A prefix state with no payload
  resolves to `#f`, and the user narrows into a leader to find nothing on screen
  and no indication of which second keys are live.

The payload closes `blocks/paneru-strip` over the **survivor rows** — this
leader's targets only. That is what decision 1's caller-supplied thunk earns its
keep for. The panel's label rides in from the user, as `'panel-label` on
`strip-provider`: a label authored in a library file sits inside ADR-0021's
spirit even where `check-decision-free.sh`'s grep cannot see it, and the user is
already naming the un-narrowed panel one line away.

**The prefix state carries its own small `'provider`** too, re-minting exactly
the Terminal states its own second-key edges target — closed over the
`(second-key . target)` pairs the owner's provider already computed, so there is
no second paneru query and no re-narrowing. This is not an optimisation but a
requirement: provided states are Visit-scoped, and stepping into the prefix state
*begins a new Visit* whose provided table holds only what that state's own
provider returns. Without it, the second key resolves to a state nobody minted.

`<owner-id>` throughout is the id of the state the provider is lowered onto,
supplied to the provider as its argument (decision 5).

Three reasons this is a provider rather than a `key-range`:

- **A two-key label is not a key.** `key-range` binds single keys; a two-key
  label structurally needs a prefix state.
- **A static maximal structure cannot express escalation.** Whether a letter is a
  single-key label or a leader depends on how many windows are on the strip,
  which is runtime data. A static tree carrying both a range over the single
  alphabet and a group per leader would have the group silently shadow the label
  whenever the two alphabets overlap — the engine takes static edges first, so
  the failure is silent rather than an error. `jump-labels-assign` resolves that
  overlap correctly, but only at assignment time.
- **It removes the fast-keypress race by construction.** A provider runs at
  come-to-rest, before any render; a block's render hook runs only once the
  overlay's show delay elapses. A label pressed faster than the overlay appears
  still dispatches, and — because the block reads the provider's snapshot rather
  than re-querying — the listing and the dispatch can never disagree. The
  alternative shape needs a refresh-on-miss patch to reach the same place.

**What the provider's timing costs.** The third reason above has a matching
bill, and both sides belong in the spec. `'next 'self` on the repeatable ops
(decision 5) makes each op a transient that auto-edges back to the paneru node,
and *every* come-to-rest — a cyclic re-arm included — re-runs
`classify-and-snapshot`, hence the provider. So each press of Focus West pays,
synchronously and before the next key can be handled: one
`paneru query state --json` subprocess spawn, plus one window enumeration. The
existing `window-list` block pays a comparable enumeration cost, but only at
*render*, behind `modal-overlay-delay`. Moving it onto the dispatch path is a
change in kind, not a smaller version of the same thing, and the comparison
against `key-range` above does not capture it.

This is accepted rather than eliminated. Two levers are already in the design:

- The enumeration is an injectable option (decision 3), so a composition can pass
  the cached, wider `list-windows` instead of the uncached AX sweep
  `list-current-space-windows` performs over every regular running application.
- `'next 'self` is the user's call (decision 5), so a composition that finds the
  cost unacceptable drops it and re-enters the screen per op.

**Measured (2026-08-04, `paneru-strip-list-k7`, an 11-window strip — the live
one this spec was written against):**

| Stage | Median | Notes |
|---|---|---|
| `paneru query state --json` | **13 ms** | `/bin/zsh -c` spawn (≈3 ms) + the daemon's socket round trip |
| Window enumeration | **11 ms** | `list-current-space-windows`, an uncached AX sweep |
| `parse-strip-windows` | **36 ms** | the JSON read, over a 1689-byte payload |
| `join-strip-targets` | **6 ms** | |
| Assign + lower | **<1 ms** | |
| **Come-to-rest total** | **≈66 ms** | synchronous, before the next key is handled |

**Ruling: the reference composition ships without `'next 'self`.** 66 ms per
press is not comfortably inside a keypress budget — a held or quickly repeated
Focus West would spend most of its interval in the provider, on the main thread,
ahead of the next key. A composition that wants cyclic re-arm can add `'next
'self` itself and pay for it knowingly; the shipped example does not make that
choice on the user's behalf.

**The cost is not where this decision predicted.** The paragraph above assumed
the subprocess spawn and the AX sweep, and named the two levers accordingly.
Neither is the dominant term: **the interpreted JSON read is 55% of the total**,
and it scales linearly with strip length (a 20-window strip roughly doubles it),
so the two levers between them can remove at most a third of a cost that grows
with exactly the thing the listing is for. `paneru query state` emits the same
JSON with or without `--json` and paneru's narrower subcommands
(`virtual-workspaces`, `active`) do not carry less window data, so the payload
cannot simply be made smaller. Making the read cheap is its own concern, tracked
as `strip-parse-cost-k10`; if it lands, this ruling is worth revisiting, because
`'next 'self` is the ergonomically better default and only the cost rules it out.

Measurement method, for anyone re-running it: the query was timed as `/bin/zsh
-c` from outside the process (matching `ShellLibrary`'s own spawn), and the
Scheme stages through `SchemeEngine.evaluate` in a throwaway test — the harness
baseline is 0.03 ms, so it contributes nothing. The join's *hit rate* cannot be
measured that way: `swift test` is not an accessibility-trusted process, so
`_AXUIElementGetWindow` yields `windowId` 0 for every window and every row
misses. That is a harness artefact, not a property of the join — which is also
precisely why the enumeration had to become an injectable seam.

**This does not reopen ADR-0018.** The decision that composition happens at
config load fixes *which screen the user gets*; per-Visit edge provision inside
a screen is precisely what the FSM's provider slot is for, and predates this
work.

**The shared lowering is not extracted.** herdr's equivalent is entangled with
its narrowed legend, its chip painting and its per-axis pools; paneru's is the
simple case. Extracting a common "assignment → edges + states" helper is worth
doing when a third consumer appears, or when the two implementations converge on
the same shape — not on the strength of the second one.

### 5. The composition the user writes

The branch is one `if` at config load over `installed?`, choosing between two
`open` bodies:

```scheme
(import (prefix (modaliser wms paneru)     paneru:)
        (prefix (modaliser window-actions) window:))

(define paneru-labels '("h" "j" "k" "l" "n" "m" "u" "i" "o" "p"))

(define windows-screen
  (if (paneru:installed?)

      (open "w" "Windows"
        'provider (paneru:strip-provider
                    'single-alphabet paneru-labels
                    'leader-alphabet '("a" "s" "d" "f")
                    'second-alphabet paneru-labels
                    'panel-label     "Strip")
        (panel "Move"
          (key "H" "Focus West"  paneru:focus-west  'next 'self)
          (key "L" "Focus East"  paneru:focus-east  'next 'self)
          (key "S" "Swap West"   paneru:swap-west   'next 'self)
          (key "D" "Swap East"   paneru:swap-east   'next 'self))
        (panel "Size"
          (key "G" "Grow"        paneru:grow        'next 'self)
          (key "R" "Shrink"      paneru:shrink      'next 'self)
          (key "C" "Center"      paneru:center))
        (panel "Strip"
          (paneru:strip-listing)))

      (open "w" "Windows"
        (panel #f (window:layout-block …))
        (panel "Windows" (window:list-block 'chips? #t)))))
```

Three things about this surface are load-bearing:

- **The alphabets come from the user.** ADR-0021 means the library cannot author
  a key, and jump labels are keys. `strip-provider` takes all three alphabets;
  the library ships none, not even a default.
- **A plane rule is the user's contract to honour.** Provider edges and static
  edges share one key space, and static edges match first — so any letter the
  user binds to an op is silently unreachable as a jump label. The sketch above
  resolves that the way herdr's jump space does: labels on lowercase, ops on
  capitals. The library cannot enforce this (it authors neither side), so the
  spec states it and the reference docs must repeat it. Any disjoint split works;
  overlap is the trap.
- **`'next 'self` on the relative-motion ops is the user's call**, and the
  natural one: focus and swap are repeated, so re-arming in place beats
  re-entering the screen. `center` is terminal, and the per-press cost recorded
  in decision 4 is the reason that call is worth making deliberately.

`'panel-label` names the panel of the *narrowed* legend the prefix state renders
(decision 4). It is a second label rather than a reuse of the `(panel "Strip" …)`
above because the two are different renders, and ADR-0021 puts both in the user's
hands.

**Two engine changes are required, and together they are the whole of it.**

`open` does not currently accept `'provider`. `screen` and `group` both do, and
`open`'s own docstring records the slot as unwired only because no caller needed
it; threading the keyword through `open`'s argument parse into its existing
`dispatch-head` call is indeed mechanical. It is *not* sufficient on its own, and
an earlier reading of this spec that said so is corrected here.

A provider must know **the id of the state it is lowered onto**, because that id
is the prefix state's parent and its up-edge target (decision 4). Nothing hands
it over today: providers are invoked with zero arguments in
`classify-and-snapshot`, and the engine's own `%fsm-visit-owner` is set *after*
the provider runs — so at provider time it holds the previous owner on first
entry and this node's own id on a re-arm. Inconsistent, therefore unusable.

**So the provider calling convention gains one argument: the id of the state
whose provider is running.** The engine already has the value —
`resolve-state-def` puts `'id` on every def, permanent and provided alike, and
`def-id` reads it — so the engine side is a single call site. Exactly three
providers exist in the tree, all of them library code: `muxes/herdr`'s root jump
provider, its per-prefix-state provider, and `activation.sld`'s
`compose-step-in-provider` wrapper. All three accept the argument; only paneru's
uses it. `provider-state-id-k9` owns this, ahead of `paneru-strip-list-k7`.

Three alternatives were weighed and none is free:

- **A registered tree under a library-declared machinery scope** — herdr's shape,
  and the only option that solves the id problem by *fixing* the id rather than
  discovering it. Rejected because it moves the whole paneru window surface out
  of the user's `open` and into a library-constructed tree reached by a
  `step-in`: a registered tree root ends `ancestors-within-tree`, so the
  breadcrumb stops showing the path in and backspace stops walking back out. A
  visible regression in the surface the requirements grilling settled, paid to
  avoid a one-line engine change.
- **`strip-provider` takes the enclosing state's id as an argument** — cheapest
  of all, and rejected because the user would then be authoring a raw FSM id
  string (`"global/w"`) with nothing validating it, which breaks silently the
  moment the screen is nested one level deeper.
- **Single-key labels only, escalation out of the first slice** — rejected as
  outside the workstream's stated bounds: escalating labels are in the root
  brief's Done-when, and the strip is unbounded by construction. Ten digits
  against twelve live windows is the motivating case, not an edge one.

The change carries a documentation surface that lands in the same commit, since
three sites currently state the opposite and point at `group` instead:
`dsl.sld`'s `open` docstring, `docs/reference/dsl.md`, and
`docs/reference/state-machine.md` — the last also gaining the provider's new
argument in its contract description. `provider-state-id-k9` owns all of it; no
other leaf in this workstream touches `fsm.sld` or `dsl.sld`.

### 6. Degradation

Every path degrades quietly and locally; none reaches a leader press as an
error.

| Condition | Result |
|---|---|
| paneru not installed | predicate is false; the non-paneru screen composes. Nothing else in this spec runs. |
| paneru installed, daemon down | the query returns empty; the parse yields no rows; zero edges, empty listing. The established empty-output path (ADR-0017, ADR-0023). |
| No shell runner installed (a bare engine) | `run-shell` returns `""`, so the probe fails and **row 1** applies — not row 2. Under `swift test` the paneru screen therefore never composes at all. |
| A strip row that does not join | listed, labelled, no edge — its label does nothing (ADR-0024). |
| More windows than the label pools cover | the tail renders with a blank key and no dispatch — the existing list-block convention. |
| A wrong `send-cmd` wire form | nothing happens, silently. Covered only by the op tests (decision 2). |

Testing *installation* rather than daemon liveness is what makes the first two
rows different in kind: a down daemon degrades the listing, but it can never
change what a key means. Liveness would make that depend on whether Modaliser or
paneru won the startup race.

## Test seams

**Two seams.** The requirements grilling aimed at one, and one is what the
*shell* path costs. The second is not a shell path at all: the provider's gather
also reads Modaliser's own window enumeration, and that call is neither pure nor
deterministic.

1. **`current-shell-runner`** (`(modaliser shell)`, ADR-0023) — the `command -v`
   probe, the state query, and all seven ops. One canned runner closes the whole
   outward *shell* surface.
2. **The enumeration**, injected as `strip-provider`'s `'enumerate` option
   (decision 3), defaulting to `list-current-space-windows`.

The second seam was added because the alternative was worse, not because it was
wanted. `WindowCache.listCurrentSpaceWindows` performs an uncached AX sweep of
every regular running application, so a provider test that let it run would
assert an edge/state set determined by whatever happened to be open on the
developer's desktop at that moment — vacuous when the desktop is quiet, flaky
when it is not. The suite already calls the primitive once as a deliberate shape
smoke test (`WindowLibraryTests.swift`), so this is a **determinism** fix, not an
isolation one: ADR-0023's reaches-nothing-outside-the-process property is
untouched either way.

Tested through the seams:

1. **`installed?`** — a canned runner returning a path, and returning `""`.
2. **The seven ops** — assert each op's exact command string. This is the only
   thing standing between a mistyped wire form and silence (decision 2).
3. **The provider's gather** — a canned runner returning a captured payload and a
   canned enumeration, asserting the Strip snapshot and the resulting edge/state
   set. Where a leader is assigned, that includes the prefix state's id, its
   up-edge target, and that its payload carries the two-layer shape decision 4
   requires — the three things a wrong answer to breaks silently.

Tested by direct call, no seam needed:

4. **`parse-strip-windows`** — canned payload text in, rows out. Cases: the
   two-workspaces-numbered-1 selection, a floating window, an absent/empty
   `windows` array, malformed text.
5. **`join-strip-targets`** — two canned lists in, Strip targets out. Cases: full
   match, a paneru row absent from the enumeration, an enumerated window absent
   from paneru, strip order preserved.
6. **`strip-provider-result`** — a canned assignment in, edges and provided
   states out. Cases: all single-key, escalation into a leader, an unlabelled
   tail, an unmatched target.
7. **The block's rows** — Strip targets in, row payload out.

`list-current-space-windows` is never *reached* from a test: the join takes the
enumeration as an argument and the provider takes it as an injectable option, so
the live AX sweep stays on the live path. That is what makes test 3's assertion
mean something — and, incidentally, what keeps the suite's cost flat as the
listing grows.

## Out of scope

- **Cross-workspace listing and jumping.** Focusing a window on an inactive
  virtual workspace needs a workspace switch before the focus, and that
  behaviour is unverified. Deliberately left rather than guessed at.
- **The remaining paneru ops** (decision 2). Each is a one-line follow-up.
- **A floating marker in the listing.** The payload carries `floating` and the
  parse keeps it; whether a row should *show* it is a preference nobody has
  expressed yet.
- **Chips.** The Strip listing is overlay rows only. Paneru scrolls the strip and
  windows move continuously under animation, so a chip's rect is stale the moment
  it is painted.
- **A selection cursor on the listing.** ⏎ on a cursor row replays the row's
  label through normal dispatch, which works for a one-key label and strands the
  user mid-narrowing on a two-key one. Coherent cursor support needs the cursor
  to know about multi-key labels; out of scope for the first slice.
- **Extracting the shared assignment→edges lowering** from `muxes/herdr`
  (decision 4), with the criterion recorded there.
- **Relocating `modaliser-tool-path`** out of `(modaliser terminal)`
  (decision 2).
- **Simplifying `muxes/herdr` onto the provider's new id argument** (decision 5).
  herdr's hardcoded `herdr-jump-scope` becomes redundant once a provider is
  handed its owner's id, but it is correct today and its provider is the
  regression surface for that engine change — so herdr accepts the argument and
  ignores it. Doing both at once would mean the same commit widens the engine and
  rewrites its only existing consumer.
- **Any change to `blocks/window-list` or the non-paneru window screen**
  (decision 1).

## See also

- **ADR-0024** — windows are targeted by id, not column. The load-bearing
  decision behind the join.
- **ADR-0023** — the inert-by-default `(modaliser shell)` seam.
- **ADR-0021** — decision-free libraries: why the alphabets and every key arrive
  from the user's config.
- **ADR-0018** — configuration is one explicit value built once at load.
- **ADR-0017** — tool-path resolution and contextual absence.
- **`CONTEXT.md` → Paneru-window-management domain** — the vocabulary.
- **`docs/specs/herdr-jump-navigation.md`** — the jump-label and provider
  machinery this design reuses, in its first consumer's setting.
