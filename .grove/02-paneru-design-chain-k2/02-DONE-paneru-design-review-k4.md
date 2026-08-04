# paneru-design-review-k4

**Kind:** review-design
**Reviews:** paneru-design-k3
**Producer launch:** {"producer":"paneru-design-k3","session":"paneru-design-k3","generation":"k3","harness":"claude","model":"opus"}

## Goal

Adversarially review `paneru-design-k3` and record concrete findings for its integration step.

## Verdict

The spec is sound on the parts it grounded empirically. Verified true against
the live daemon and the code: the payload shape (`window_id`, `bundle_id`,
`app_name`, `title`, `focused`, `floating`), the two-workspaces-both-numbered-1
selection rule (`active` is the key — reproduced: `number=1/native=3/active=true`
beside `number=1/native=7/active=false`), the static-edges-match-first plane rule
(`fsm.sld:737` appends provider edges after static; `fsm.sld:2014` takes the
first match), `open`'s missing `'provider` (`dsl.sld:975` passes `#f`), the
narrow `modaliser-tool-path` import precedent (`muxes/zellij.sld:86`), and the
five sibling list blocks. Decisions 1, 3 and 6 need no rework.

The defects are concentrated in **decision 4 (the provider) and its interaction
with decision 5 (composition under `open`)** — the two the spec argued from
herdr's shape rather than from herdr's code. Two are load-bearing: the spec
understates the DSL change to the point where `paneru-strip-list-k7` would build
something that cannot work, and the test-seam section states three things that
cannot all be true.

## Findings

### F1 — major. The provider cannot mint its prefix states under `open`; the DSL change is not "the whole change"

Decision 5 says: "Threading the keyword through `open`'s argument parse into the
existing `dispatch-head` call is mechanical, and it is the whole change." It is
not. A **two-key label** needs a provided *resting* prefix state, and a provided
resting state's id is constrained:

- Its id must read `<parent-id>/<leader>` — `fsm.sld:1802`'s `strip-id-prefix`
  computes `(substring child (+ 1 (string-length parent)) …)`, so a
  free-form id yields a garbled breadcrumb segment or a `substring` raise.
  `muxes/herdr.sld:827-840` records exactly this, at length.
- Its `'up` edge must target that same parent id (`muxes/herdr.sld:1020`), or
  backspace does not un-narrow and `ancestors-within-tree` (`fsm.sld:1785`)
  stops the climb early.

herdr can satisfy both because its provider sits on a **registered screen whose
scope it hardcodes** — `herdr-jump-scope` = `"herdr"`, declared machinery, with a
load-time closure error if the user's screen carries another scope
(`muxes/herdr.sld:842-849`). Under `open`, the enclosing state's id is
`<tree-scope>/<the user's open key>` (`fsm.sld:1020`, `fsm-child-id`) — a value
the library cannot know, because ADR-0021 puts both halves in the user's config.

Nor can it be recovered at runtime: providers are invoked with **zero arguments**
(`fsm.sld:734`), and `classify-and-snapshot` runs the provider *before*
`begin-new-visit!` sets `%fsm-visit-owner` (`fsm.sld:858` vs `805-811`) — so at
provider time that variable holds the *previous* owner on first entry and the
paneru node's own id on a re-arm. Inconsistent, so unusable.

This bites immediately rather than at the margin: the spec's own motivating case
is 12 windows against a 10-key single alphabet, i.e. escalation on the first
press.

The alternative the spec dismissed is the one that solves it. Decision 5 weighs
only "a separate registered `screen` reached by a `'next` edge … for no gain" —
but a registered screen has a **known, hardcodable id**, which is precisely
herdr's reason for that shape. The spec also never mentions the escape hatch the
code itself documents in three places: drop to `group`, which accepts
`'provider` today (`dsl.sld:317-322`, `docs/reference/dsl.md:386`,
`docs/reference/state-machine.md:431-433`) — though note `group` alone does not
solve the id problem either.

**For integration:** re-decide decision 5 across the four options, and state the
chosen id and up-edge target explicitly so `paneru-strip-list-k7` does not have
to invent them: (a) registered screen with a machinery scope (herdr's precedent,
solves it outright); (b) `strip-provider` takes the enclosing state id as a
required argument — cheap, but the user is now authoring an FSM id with no
validation; (c) widen the DSL so a provider learns the id of the state it is
lowered onto — an `fsm.sld` lowering change, not the keyword-threading the spec
described; (d) single-key labels only, capped at the single alphabet, escalation
out of scope for the first slice.

### F2 — major. The Test seams section states three things that cannot all hold

The section asserts, in order: **one seam** (`current-shell-runner`) was "an
explicit goal, not an accident"; test 3 exercises **the provider's gather**,
"asserting the snapshot and the resulting edge/state set"; and
"`list-current-space-windows` is **never called from a test**, because the join
takes the enumeration as an argument".

Decision 3 puts `list-current-space-windows` on the live path *inside the
provider* ("the live path passes `list-current-space-windows`"), and the provider
is what test 3 runs. So test 3 calls it, and the third claim is false as written.

The consequence is not an isolation breach — `WindowLibraryTests.swift:179`
already calls the primitive deliberately as a shape smoke test, so read-only AX
enumeration is within what the suite tolerates. The consequence is
**nondeterminism in the one assertion that matters**:
`WindowCache.listCurrentSpaceWindows` performs an uncached AX sweep of every
regular running application (`WindowCache.swift:74` → `162-192`), so which strip
rows recover an `owner-pid` — and therefore the edge/state set test 3 asserts —
depends on the developer's live desktop at the moment the test runs. The test as
specified is either vacuous or flaky.

**For integration:** pick one and say so. Either `strip-provider` accepts the
enumeration as an injectable option (a **second** injection point — then retire
the "one seam" claim honestly and reconcile ADR-0024's "Neither is a new test
seam" sentence, which the change makes stale), or test 3 is narrowed to the parse
path with the join's output left to test 5 (keeps one seam; costs coverage of the
gather's wiring). The first is the better trade; the spec's aversion to a second
seam is what produced the inconsistency.

### F3 — medium. What the narrowed prefix state *renders* is unspecified

Decision 4 defines the prefix state by its edges alone: "whose own edges are the
second keys and whose up-edge un-narrows". It says nothing about the state's
`'payload`. A provided resting state with no payload resolves to `#f` through
`fsm-resolved-payload` (`fsm.sld:662`), so the user narrows into a leader and the
overlay has nothing to draw — no indication of which second keys are live.

herdr found this non-trivial and recorded why at `muxes/herdr.sld:982-1000`: the
prefix state's payload must carry the exact two-layer shape `screen` lowers a
root's payload into (`'children` + a `'display` panel clause), so the *unchanged*
renderer draws the survivor legend. It closes the same block constructor over the
survivor pairs (`muxes/herdr.sld:1009-1014`).

The spec's "minus the parts paneru does not have: … no chips, no dim-state
narrowing" covers the chips but not the legend, which is a display concern that
survives the chip removal.

**For integration:** state it. The natural answer is that the prefix state's
payload closes `blocks/paneru-strip` over the survivor rows — one line to write,
and it makes decision 1's "caller-supplied thunk" earn its keep. If the answer is
instead "narrowing renders nothing, accepted for the first slice", say that
explicitly. Note that a panel label on that payload is a **label authored in a
library file** — invisible to `check-decision-free.sh`'s grep (which matches only
`(key|keys|group|open) "…" "…"`, `scripts/check-decision-free.sh:48`) but inside
ADR-0021's spirit; herdr already carries one (`'label "Jump"`), so a precedent
exists either way.

### F4 — medium. The provider re-runs on every op press, and the spec prices only its upside

Decision 4 sells the provider's timing as pure gain ("runs at come-to-rest,
before any render … removes the fast-keypress race by construction"). The other
side is unstated. `'next 'self` on the six repeatable ops (decision 5) makes each
op a transient that auto-edges back to the paneru node, and every come-to-rest —
including a cyclic re-arm — re-runs `classify-and-snapshot`, hence the provider
(`fsm.sld:858`, `878-880`).

So each press of Focus West costs, synchronously and before the next key can be
handled: one `paneru query state --json` subprocess spawn, plus a full uncached
AX sweep of every running application with several attribute round-trips per
window (`WindowCache.swift:162-192`). The existing `window-list` block pays the
same AX cost but only at *render*, behind `modal-overlay-delay`; moving it onto
the dispatch path is a change in kind that the spec's comparison against
`key-range` never mentions.

**For integration:** record the cost as an accepted trade-off with a measurement,
or cheapen it. The obvious cheapening is that the ops do not need a fresh
snapshot at all — only the listing does — so gathering could be skipped on re-arm
(a generation/dirty check), or `'next 'self` dropped in the reference
composition. Either way the spec should not read as though the provider's timing
is free.

### F5 — minor. The DSL change has a doc surface the spec calls mechanical

If F1 resolves toward widening `open`, three sites currently state the opposite
and must be reconciled in the same commit: the docstring at `dsl.sld:945-946`, 
`docs/reference/dsl.md:386`, and `docs/reference/state-machine.md:431-433` — all
three say `open` does not expose `'provider` and point to `group` instead. The
lowering test at `FsmLoweringTests.swift:392` covers `group`/`tree-root` only.

Separately: **no leaf in the tree owns this change.** The root brief's
decomposition is ops / strip-list / docs, and a `dsl.sld` + reference-docs +
lowering-test change belongs to none of them cleanly. Integration should either
name the owner explicitly in the spec or `leaf-add` it.

### F6 — minor. A degradation-table row contradicts the predicate above it

"No shell runner installed (a bare engine) → identical to 'daemon down'" is not
reachable as written: with no runner, `run-shell` returns `""`, so `installed?`
is false and row 1 applies — the non-paneru screen composes and nothing else in
the spec runs. The row only describes a test that forces the paneru composition
while answering the probe but not the query. Reword or drop.

## Not findings — checked and sound

Recording these so integration does not re-open them:

- The parse contract against the live payload, including the `active`-not-number
  workspace rule. Reproduced this session.
- The plane rule (static edges win over provider edges). `fsm.sld:737`, `2014`;
  `muxes/herdr.sld:851-864` states the same conclusion independently.
- `installed?` at config load is well-ordered: `root.scm:31` installs the shell
  runner ahead of every other import, so the probe answers truthfully in
  production and false in a bare engine.
- Decision 1's reuse call, on all four of its stated grounds.
- "Unmatched rows still consume a label" — the stability argument is right, and
  the label-pool waste it costs is the correct trade.
- The `modaliser-tool-path` import and the "accepted, not fixed here" framing:
  6 library files outside `terminal.sld` already import it exactly this way
  (tmux, zellij, alacritty, wezterm, kitty, iterm-panes). The spec's "eight
  other callers" matches no reading of the tree — 6 files, 12 call sites — but
  the framing it supports is right, so this is a number to fix in passing, not
  a decision to revisit.
- ADR citations are citations, not restatements; the ADR set needs no rework
  *unless* F2 resolves toward injecting the enumeration (see F2).

## Notes

Review-target diversity: this review ran on the same harness and model as
`paneru-design-k3` (claude/opus). Non-blocking, but findings F1–F4 are all
places where the spec reasoned from herdr's *shape* without reading herdr's
*code* — a blind spot a differently-routed reviewer might have hit from a
different angle.
