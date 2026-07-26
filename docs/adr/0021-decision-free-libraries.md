# Libraries hold facilities, configuration holds decisions: no library authors a key or a label

A `(modaliser …)` library may hold a **facility** — anything whose correctness is
fixed by the tool it wraps or the machinery it implements (`focus-pane-left` *is*
herdr's `pane.focus_direction`; a live-list block, a jump provider, a backend
record, a context-map entry). It may not hold a **decision** — anything whose
correctness is fixed only by the user's preference: which ops are surfaced, on
which keys, under which labels, grouped into which panels, with which
forgiveness. The operational test is mechanical and enforced: **no file under
`Sources/Modaliser/Scheme/lib/modaliser` authors a key or a label**, checked by
`scripts/check-decision-free.sh` at strict zero — one authored binding fails it,
exactly as one `(lispkit …)` import fails the portability check. Every
screen therefore lives in user space — the seeded `config.scm` for what a fresh
install runs, `Sources/Modaliser/Scheme/examples/*.scm` for compositions a fresh
install does not (mirror-carried, never loaded, copied in by hand). Libraries
export the ops, blocks, providers, and wiring those screens name.

## Why it binds

**Exporting a name freezes it**, so the exported surface must be the *stable*
layer — and it was the inverse. `build-herdr-tree`'s body churned across ten
commits; `focus-pane-left`'s definition changed twice, once at birth and once for
the socket cutover, behind an unchanged name and signature. Freezing whole-tree
constructors froze the volatile layer and kept the stable layer private, so three
consecutive herdr leaves (`herdr-copy-mode-key-k34`,
`herdr-tab-space-reorder-k36`, `herdr-detach-honours-prefix-k37`) each spent a
library change, tree-shape tests, and doc rework on what was — in its decision
half — a config edit. Moving the volatile layer out of the library ends that class
of work, and the count makes the drift legible: **136** authored key/label
decisions had accumulated across ten libraries under a doctrine that already said
wiring belonged in libraries.

It is safe because of what ADR-0019 established: the seeded tier can strand only
*preference*, never machinery. A capability added upstream that reaches no
existing keymap is a capability not yet adopted — the ordinary condition of every
tmux or vim config — and the mirrored `default-config.scm` is the diff reference.
The exposure this shifts instead is **loud**: a config naming a symbol the binary
no longer binds fails at load with nothing installed (ADR-0018). That is why
graceful config-failure degradation is a *precondition* of widening the surface,
not a follow-up.

Costly to reverse: the per-library op exports become public contract, and the
seed's authored shape, the `examples/` tree, the CI check, and the deletion of
every library tree-shape test all encode it.

## Considered options

1. **Group-grain constructors** — export ~10 `(key label → node)` builders per
   library (`(herdr:panes-group "P" "Panes")`), the library owning each drill's
   interior. Rejected: it freezes precisely the layer that churns, making every
   drill-shape change a breaking change; and it cannot express *dropping* a row
   the library authored, because two contributions on one key are
   `fsm-graph-edge!`'s duplicate-key error, not a merge. Reopened by: nothing.
2. **Screen grain — keep whole-tree constructors, split only the wiring out**,
   preserving ADR-0019's carve-out for "machinery with near-zero preference
   (iTerm, herdr)". Rejected: herdr and iTerm carry 47 and 37 authored key/label
   decisions; near-zero preference was not true of either. Reopened by: nothing.
3. **A stock composition retained in the library beside the ops** (sugar as a
   veneer over the real surface). Rejected *here*: the seed already **is** the
   readable stock composition, so a library copy is a second artifact to keep in
   sync and one more frozen name. The veneer survives — in user space, where it
   can be read and edited rather than only called. Reopened by: a library whose
   stock screen has neither a seed entry nor an example.
4. **An op-lookup table** — `(herdr:op 'focus-pane-left)`, one export instead of
   twenty-two. Rejected: it re-invents a module namespace as stringly-typed data
   inside a language that has modules, trading load-time resolution for a
   hand-rolled registry. Reopened by: nothing.
5. **A documented-only contract, no CI check.** Rejected: 136 decisions
   accumulated while the prose already pointed the other way, and the repo has
   the enforcement pattern to hand in `check-portable-surface.sh`. Reopened by:
   nothing.

## Consequences

- Whole-tree constructors are **deleted, not deprecated**: herdr's `context`
  (now `wiring`, integration only), `build-herdr-tree`, `focus-mode-tree`'s
  authored rows, `iterm:stock-screen` and its walks, and `settings-menu`'s
  `actions` along with four of its five options — `key`, `label` and
  `extra-bindings` dissolve into ordinary Scheme at the call site, leaving only
  `config-dir` and `editor`, which are facts about the machine rather than tree
  shape. Where a library's content was *entirely* screen, the **library itself**
  goes: `apps/safari` and `apps/chrome` were 41 lines of `(apply screen …)` each
  with no machinery underneath, so both files are deleted rather than hollowed
  out — an empty `define-library` is worse than no library.
- What survives is the **wiring half** — backend record, context-map entry,
  machinery-named side trees — which `kitty`, `wezterm`, `ghostty`, and
  `alacritty` already shipped in exactly this shape, and which is therefore a
  demonstrated target rather than a proposed one. A constructor whose
  contribution *becomes* wiring-only is **renamed to say so** (herdr's `context`
  → `wiring`): keeping the old name would leave the surface reading as though it
  still delivered a tree. Those four keep the name `fragment` precisely because
  nothing changed for them — they never delivered a tree, so there is no stale
  promise to correct, and renaming would freeze a second name for no gain. The
  two names denote the same kind of value; `wiring` is the narrower claim.
- Moving a decision out can require the authoring surface to be able to
  **express** it. A library bundling a decision could reach past the DSL
  into node internals; a configuration cannot. iTerm's provisioning row
  was `(cons (cons 'hidden gate) (key …))` inside the library, so `key`
  had never needed a `'hidden` keyword — it grew one when the row moved
  out. Expect one such gap per decision shape, and close it in the DSL
  rather than re-admitting the decision.
- Scope symbols crossing the boundary are **machinery, not preference**. The
  wiring's context entry references its screen by key (`'herdr`), and a
  cross-edge references its walk by key (`'herdr-panes-focus`), so the
  configuration must author both under those exact names — enforced by
  reference-closure validation at load, which turns a rename into a loud
  error rather than a silently dead binding.
- `Sources/Modaliser/Scheme/examples/` joins the mirrored tree, bundling and
  syncing for free (`.copy("Scheme")` plus whole-tree `SysSync`). It is **not**
  `app-trees/` returning: `app-trees/` was harmful because it was seeded *and
  loaded*, whereas an example is never loaded and adds no frozen name — a user
  copies its contents, never names the file.
- Library tree-shape tests are **deleted rather than relocated**: asserting
  `Q d` = Detach asserts preference, and load-time closure validation already
  catches a key bound to a nonexistent op. The shipped-config load test
  (`ConfigDslTests.defaultConfigSchemeLoadsWithoutErrors`) extends over
  `examples/*.scm` and is the one seam. Op-level behaviour keeps its existing
  runner seams, which become the only library-side behavioural claim.
- ADR-0013's "inner-tool wiring lives in the tool's own constructor" narrows to
  facilities only; ADR-0018's "a library's stock tree is taken or left whole" and
  ADR-0019's near-zero-preference carve-out are gone.
