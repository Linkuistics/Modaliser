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
**Edge provider** on the screen's root mints exactly the labels this Visit's
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
| `strip-provider` | constructor | keyword opts → the 0-arg Edge provider for a `'provider` slot |
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
home is a separate concern with eight other callers.

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
keeps this a pure function: the live path passes `list-current-space-windows`,
and a test passes a canned list. It also makes the choice of enumeration a
one-line decision to revisit — `list-windows` is the wider, staler alternative if
the join's hit rate ever proves a problem in practice.

**Unmatched rows still consume a label.** They render as ordinary rows and their
label dispatches to nothing, exactly as ADR-0024 anticipates. The reason is
stability: if unmatched rows were skipped during assignment, a single transient
join miss would renumber every label below it, and the labels are muscle memory.
A row that momentarily fails to join costs one dead key, not a reshuffled strip.

### 4. Dispatch is provider-minted, not a static key range

The screen's root carries an **Edge provider** — `strip-provider`'s result on a
`'provider` slot. Each Visit it queries paneru, parses, joins, assigns labels
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
                    'second-alphabet paneru-labels)
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
  re-entering the screen. `center` is terminal.

**One DSL change is required.** `open` does not currently accept `'provider`,
though `screen` and `group` do and `open`'s own docstring records the slot as
unwired only because no caller needed it. Threading the keyword through `open`'s
argument parse into the existing `dispatch-head` call is mechanical, and it is
the whole change. (The alternative, authoring the paneru window surface as a
separate registered `screen` reached by a `'next` edge, works today but changes
the breadcrumb and backspace shape for no gain.)

### 6. Degradation

Every path degrades quietly and locally; none reaches a leader press as an
error.

| Condition | Result |
|---|---|
| paneru not installed | predicate is false; the non-paneru screen composes. Nothing else in this spec runs. |
| paneru installed, daemon down | the query returns empty; the parse yields no rows; zero edges, empty listing. The established empty-output path (ADR-0017, ADR-0023). |
| No shell runner installed (a bare engine) | identical to "daemon down", by the same path. |
| A strip row that does not join | listed, labelled, no edge — its label does nothing (ADR-0024). |
| More windows than the label pools cover | the tail renders with a blank key and no dispatch — the existing list-block convention. |
| A wrong `send-cmd` wire form | nothing happens, silently. Covered only by the op tests (decision 2). |

Testing *installation* rather than daemon liveness is what makes the first two
rows different in kind: a down daemon degrades the listing, but it can never
change what a key means. Liveness would make that depend on whether Modaliser or
paneru won the startup race.

## Test seams

**One seam: `current-shell-runner`** (`(modaliser shell)`, ADR-0023). Every
outward call in this spec — the `command -v` probe, the state query, all seven
ops — goes through it, so one canned runner closes the whole surface. Driving the
seam count to one was an explicit goal of the requirements grilling, not an
accident of what happened to be easy.

Tested through it:

1. **`installed?`** — a canned runner returning a path, and returning `""`.
2. **The seven ops** — assert each op's exact command string. This is the only
   thing standing between a mistyped wire form and silence (decision 2).
3. **The provider's gather** — a canned runner returning a captured payload,
   asserting the snapshot and the resulting edge/state set.

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

`list-current-space-windows` is never called from a test, because the join takes
the enumeration as an argument (decision 3). The live AX enumeration stays on the
live path only, which is what keeps this work inside the suite's
reaches-nothing-outside-the-process property without adding a second seam.

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
