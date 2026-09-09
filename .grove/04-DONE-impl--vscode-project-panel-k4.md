# vscode-project-panel-k4

## Goal

Put the open VSCode projects on the F17 VSCode screen as a **top-level labelled
panel** — one row per project, each reachable by a jump label from an
escalating alphabet (`a s d f g …`, with leader keys past exhaustion) — rather
than only behind the `w` chooser row that `vscode-screen-k2` shipped.

The human asked for this after using the chooser: *"I would rather that project
list at the top level with the standard 'asdfg' extensible shortcut assignment
to select them."* "Standard" is the right word — this is the **Strip listing**
pattern from `wms/paneru.sld`, applied to a different row source.

Whether the `w` chooser row survives beside the panel is the human's call; ask,
and default to keeping it (fuzzy matching over a long worktree name is a
different affordance from a jump label).

## Context

**Everything downstream of the row source already exists**, and
`vscode-screen-k2` shipped the row source itself.

- `(modaliser apps vscode)` exports `windows-of` (pure: enumeration → items,
  each carrying `'text` = project name, `'title` = raw title, `'windowId`,
  `'ownerPid`) and `focus-choice` (pure: item → the alist `focus-window`
  reads). No new VSCode knowledge is needed.
- `(modaliser jump-labels)` `jump-labels-assign` is the label machinery —
  targets × three alphabets → prefix-free one- or two-key labels.
- `(modaliser blocks paneru-strip)` is **already generic**. Its own header
  states it: it takes an `'assigned-fn` thunk returning `((label . target) …)`
  with the target carrying `'app` / `'title` / `'focused`, and "knows nothing
  of paneru". It is a candidate for reuse as-is.

**The one real decision, and it is why this is its own leaf.** Paneru's
`strip-provider` / `strip-provider-result` / `strip-prefix-state` trio is ~120
lines of FSM state-and-edge minting (single-key edges, leader prefix states
that re-mint their own provided states, `'up` edges, the panel-label passed in
from the user under ADR-0021). A VSCode panel needs the same shape over a
different row source. Three ways to go, and the leaf should decide deliberately
rather than reach for the first:

1. **Duplicate the trio into `apps/vscode.sld`.** Cheapest to land, and it
   keeps paneru's tested behaviour untouched — but it is a second copy of the
   subtlest machinery in the tree, and the two will drift.
2. **Extract a shared `(modaliser jump-list)`** carrying the provider trio over
   an injected row source, and re-express paneru's strip-provider on top of it.
   The right shape if a third caller is plausible; it edits a tested,
   load-bearing path, so it wants its own tests green before and after.
3. **Reuse `blocks/paneru-strip` but not the provider** — some middle where the
   block is shared and the provider is not. Note the block's `'type` is
   `'paneru-strip` and its CSS classes carry that name, so a VSCode panel
   rendering through it inherits paneru's name in the DOM; whether that is
   acceptable or wants a renamed generic block is part of the same decision.

**Where the keys and labels go.** The three alphabets and the panel label are
the user's under ADR-0021 — `strip-provider` takes all four as arguments and
defaults none, and the human's `config.scm` already passes
`paneru-label-keys` three times for the paneru strip. Follow that exactly; a
library that defaults an alphabet has authored a key.

**Pointers**

- `~/.config/modaliser/config.scm`, the `paneru-windows-screen` definition —
  the working reference for composing a provider with a listing block, live on
  the human's machine.
- `wms/paneru.sld` from "The Edge provider" to the end of file.
- `docs/specs/paneru-window-management.md` decision 1 and 4, and ADR-0024 — the
  Strip listing's design and the reason a listed row is targeted by a joined
  identity rather than by position.
- `.grove/02-impl--vscode-screen-k2.md`'s decision log for why the item shape
  is what it is (in particular why `'title` is preserved).

**Cost warning from k2's own measurements section:** paneru's provider runs on
the dispatch path at every come-to-rest, measured ~34ms with a subprocess spawn
in it. A VSCode panel has **no subprocess** — it is enumeration + filter +
assign — so it should be materially cheaper, but the enumeration is the same
8-29ms warm / 200ms+ cold AX sweep, and `KeyboardCapture` filters no
auto-repeat. Ship without `'next 'self`, exactly as the paneru reference
composition does, and for the same reason.

## Done when

- The F17 VSCode screen carries a top-level panel listing the open projects,
  each with a jump label that focuses that window, on the human's machine.
- The alphabets and the panel label come from the human's `config.scm`, not
  from any file under `lib/modaliser`.
- Whichever of the three routes above is taken is recorded as a decision with
  its reasoning — and if route 2, paneru's own suite is green before and after.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh`
  and `./scripts/check-decision-free.sh` both pass.
- The new surface is documented where `docs/reference/libraries.md` documents
  `(modaliser apps vscode)`'s existing exports.

## Notes

- **Verify against a real VSCode, not against a successful import.** `CLAUDE.md`
  records a shipped library whose primitives all resolved and permanently
  returned null. `vscode-screen-k2` installed the app (`./scripts/install.sh`,
  ~23 min for the release build) and confirmed `config: loaded` in
  `/usr/bin/log show --predicate 'subsystem == "dev.antony.Modaliser"'` before
  asking the human to press the keys. Do the same.
- A shell alias shadows `log` in this environment — use `/usr/bin/log`.
- The human runs four VSCode windows, one per grove worktree, so the folder
  names are long (`grove.add-user-guide-and-code-walkthoughs-for-all-crates`).
  A panel row has to render that legibly, which the chooser did not have to.

---

## Decision log

### The one real decision: route 2, extract `(modaliser jump-list)`

**Taken.** The provider trio moved to a new portable library
`lib/modaliser/jump-list.sld`; `wms/paneru.sld` re-expresses
`strip-provider-result` on top of it with an unchanged signature, and
`apps/vscode.sld` composes the same library for its panel.

The human confirmed this route mid-session ("We should extract a shared
`(modaliser jump-list)`"), independently of the same conclusion reached here.

**Why, in one line:** this machinery fails *silently* when it is wrong, and a
second copy would drift with nothing going red.

That is the whole argument, and it is worth stating precisely because it also
decides the *block* question below the opposite way. Each of the trio's
load-bearing properties fails without raising: a prefix state minted with the
wrong id garbles a breadcrumb (`modal-current-path` `substring`s the parent's
id off the child's); one minted without its own provider makes the second key
resolve to a state nobody minted (provided states are Visit-scoped and stepping
in begins a new Visit); one minted without a payload narrows into a blank
screen. Duplicating that is not a maintenance cost, it is a correctness risk
with no detector.

Route 1 (duplicate) was rejected on exactly that. Route 3 (share the block, not
the provider) inverts the risk: it shares the half that is cheap to duplicate
and duplicates the half that is not.

**The extraction is smaller than the leaf's ~120-line estimate**, because the
trio was already nearly generic. Diffing paneru's needs against VSCode's, only
four things were paneru-specific — the state-id namespace, the focusability
predicate, the focus action, and the block. Two of them collapse: *"is this
target actionable?"* and *"what does pressing it do?"* are the same question,
so `'action` returns a thunk or `#f` and there is no separate predicate to
disagree with it. That took the injected surface from five callbacks to three
(`'state-id`, `'action`, `'block`), which is what makes the result a deep
module rather than a configuration blob. The block's `'type` is read back out
of the spec the caller constructs, so a caller never restates it.

**Verification, as the leaf required for this route.** Paneru's own suite was
run before and after: 32 tests in 2 suites, green both times, including
`prefixStateRemintsItsOwnTerminalStatesWithoutQueryingAgain` and
`prefixStateIdFollowsWhateverOwnerIdTheEngineSupplies` — the two that pin the
subtlest parts. A new `ModaliserJumpListLibraryTests` (10 tests) states those
properties once against the machinery itself, through a *synthetic* caller
whose targets are deliberately not windows, so a window-shaped assumption
cannot leak back in unnoticed.

### The block: NOT extracted, and that is the same argument running the other way

`blocks/paneru-strip` was left untouched and `blocks/project-list` added beside
it (~90 lines of JS + CSS, close to it in shape).

The asymmetry is the point: **duplicated machinery drifts silently, duplicated
presentation drifts visibly — you are looking at it.** So the machinery is
shared and the renderers are not. The alternative considered was renaming
`paneru-strip` into a generic block, which would have churned a shipped spec,
its tests and its DOM class names for a caller that renders different content
anyway.

The content genuinely differs. A Strip row is app name plus window title in
four columns; a Project row is one long name — the human's worktree folders run
past forty characters — which wants the full remaining width and an ellipsis,
not a `1fr` column with a title competing for the rest. This also settles the
leaf's sub-question about `'type 'paneru-strip` leaking paneru's name into the
DOM: it does not, because the VSCode panel renders through `project-list`.

### The `w` chooser row: dropped

The leaf said to ask and default to keeping it. Asked; the human answered "We
don't need to preserve the w chooser". Removed from both the human's config and
the shipped example. `window-source` / `focus-window!` stay exported and the
example says so, so a chooser row is one paste away.

### The alphabet: `a s d z x`, not `a s d f g`

The human asked for "the standard 'asdfg'". On this screen `f` (Find in File)
and `g` (Grove Leaf) are already bound, so `asdfg` would have collided on two
of five. `a s d z x` is the nearest non-colliding set; the config comment says
what to rebind to get the home row back. **This is the human's call to revisit**
— it is a key, so it lives in their config, not in a library.

### No ADR

The extraction changes no contract and reopens no decision: ADR-0021's
decision-free rule is honoured (all three alphabets and the panel label arrive
from the user, none defaulted), ADR-0023's inert seams are untouched (nothing
new reaches outside the process — the panel is enumeration, filter, sort and
assign), and ADR-0011's payload shape is preserved verbatim, just relocated.
The reasoning that *is* durable — why the machinery is shared and the renderers
are not — is recorded where a reader meets it: in `jump-list.sld`'s header, in
`blocks/project-list.sld`'s header, and in `docs/reference/libraries.md`.
`docs/specs/paneru-window-management.md` records that the lowering moved and
that its behaviour did not.

## Verification

- `swift build` — clean.
- `swift test` — **1242 tests in 103 suites, all passed**, including the
  example-config load test (`exampleConfigsLoadWithoutErrors`).
- `./scripts/check-portable-surface.sh` — OK. `jump-list.sld` imports only
  `(scheme base)`, `(modaliser util)` and two FSM primitives.
- `./scripts/check-decision-free.sh` — OK.
- `./scripts/install.sh` — built, bundled Scheme tree verified against
  `Sources/`, installed, relaunched; `config: loaded` confirmed in
  `/usr/bin/log`.
- **On the human's machine, still to confirm by hand:** F17 with VSCode
  frontmost should list four projects — `APIAnyware.add-ocaml-target` (a),
  `grove.add-user-guide-and-code-walkthoughs-for-all-crates` (s), `InTheLoop`
  (d), `Modaliser.local-tree-for-vscode` (z).

## Note for a later leaf

The panel is declared last in the screen, so it renders below the flat key
rows — following the paneru screen's convention. "Top level" in this leaf's
goal was about the *key hierarchy* (not behind the `w` chooser), which is
satisfied. If the human wants it visually first, move the `(panel "Projects" …)`
form above the flat keys in their config; it is a one-line move and no library
changes.

### Late amendment: the alphabet is `a s d f g` after all

The human revisited the alphabet in-session, which is exactly what the note
above invited. Two keys were cleared to make the home row available, both on
their instruction:

- **Top-level Find in File dropped.** cmd-f is already muscle memory, and a
  leader press to reach it is slower than just pressing it.
- **Grove Leaf moved from `g` to `L`** — for *Leaf*, and chosen with the
  next leaves in view: the coming editor alphabet is `h j k l ;`, all
  lowercase, so the capital plane stays clear of every label pool.

Applied to the human's config, `Scheme/examples/vscode.scm` and the worked
snippet in `docs/reference/libraries.md`. No library changed — which is the
contract working: an alphabet and the keys it has to dodge are both preference,
so revisiting them touches config and nothing else (ADR-0021).
