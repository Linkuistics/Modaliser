# configuration-design-k6

**Reviews:** configuration-design-k5

## Goal

Adversarially read `docs/specs/configuration-exploration.md` — the exploratory
synthesis produced by `configuration-design-k5` — and produce findings, not
fixes. The six doubts below were named by the user when the review was
commissioned; they are where the artifact is most likely to be wrong, not the
whole of what to read.

## Context

Read the spec first, then the three corrected surveys it synthesises:
`docs/research/layout-controls-a.md`, `docs/research/app-facilities-a.md`,
`docs/research/configuration-runtimes-a.md`, and the shared baseline
`docs/research/configuration-exploration-context.md`. All four carry
correction notes in their headers recording what `configuration-design-k5`
changed and why; check the corrections as well as the synthesis built on them.

The grove brief is `.grove/BRIEF.md`. Standing decisions the spec builds on:
ADR-0011, ADR-0012, ADR-0018, ADR-0021, ADR-0022, ADR-0023, ADR-0026/0027/0028.

**This is documentation-only, like the rest of this grove.** Do not implement,
prototype, run the app, install anything, or create implementation leaves. Cut
an `integrate-review-design` leaf at the end **only if there are findings worth
acting on**; a review that finds nothing creates nothing and retires.

## Done when

Each of the six commissioned doubts has been read against the spec and the
surveys, and either dismissed with a reason or written up as a finding.

1. **Resolve-time span clamping versus the runtime display budget.** The spec
   normalises spans in `resolve-display` against the authored track count, and
   separately proposes that the renderer may reduce the track count from the
   display budget. Its answer is that resolve emits one pre-normalised
   arrangement per declared responsive step and the renderer only chooses among
   them. Is that actually closed? Check the enumerated-steps proposal against a
   continuous budget, against `'span 'full`, against a panel added after the
   steps were authored, and against the lane-layout path where the placement
   algorithm the correction cites may not govern.

2. **An optional unavailable capability versus a misspelled or removed
   operation.** The spec's Requirement promises a withdrawn capability degrades
   silently and an undeclared name produces a diagnostic, then admits nothing
   today distinguishes them and offers two unchosen mechanisms. Is the
   requirement testable as written? Does the silent path let a typo become a
   missing row? Does either proposed mechanism actually separate the cases, or
   does it move the ambiguity?

3. **Callback lifetime and late replies across two runtimes.** The spec rules
   that the resident language owns every closure and the facility contract
   carries none, then names scope, rooting and late replies as obligations —
   marking the two-runtime late-reply case unpriced. Test that: is
   snapshot-scoped identity sufficient to drop a late reply, what happens to a
   continuation whose Visit the *other* runtime tore down, and does the rule
   survive the day subscriptions are added, which the spec proposes a place for.

4. **The concrete layout authoring example.** The sketch in *Three approaches*
   is marked illustrative and uses constructors that do not exist. Does it
   nonetheless describe something the proposed model can express? Check it
   against the real `panel` sugar (children are key nodes, not references; no
   nesting; at most one block), against `resolve-display`'s shape, and against
   the claim that regrouping costs no key path. An illustrative example that
   quietly needs a facility the design does not propose is a finding.

5. **SBCL kept as a viable requested candidate.** The user asked for Common Lisp
   on SBCL specifically. The spec now lists SBCL with its documented costs and
   argues it is viable as a restartable helper process rather than embedded,
   with ECL offered as an alternative implementation rather than a redirection.
   Is that fair to the request, and is the helper-process argument sound — does
   it actually dissolve the no-clean-shutdown limitation, and does it import
   costs the spec does not name? Also check the reverse: whether the spec is now
   too kind to SBCL relative to its evidence.

6. **Consistency of the bundled-versus-helper recommendation, and unmeasured
   cost claims.** The spec states two defaults — bundled Scheme libraries for
   in-process facilities, an out-of-process peer for anything reaching outside —
   and a Swift facility module between them. Check that this is stated
   consistently everywhere it appears: the facility-contract section, the three
   approaches, the comparison table, and the recommendation. Separately, sweep
   the whole document for cost language (*small*, *bounded*, *cheap*, *for
   free*) and confirm each is either an explicit surface-area claim or flagged
   unmeasured, against the banner that promises exactly that.

## Notes

**Do not reopen the settled stable-groups choice.** Whether "groups stay in
place" means cells or pixels is *not* an open question: the user confirmed *keep
groups stable; wrap or truncate titles*, and the brief records stable placement
under content-width changes as a requirement rather than a preference. The spec
records that explicitly. A finding that re-raises it is out of charter; a finding
that the spec's *reasoning* for treating both as entailed is wrong is in charter.

Also settled, and not to be reopened: comparing both a front-end-only change and
a runtime replacement (both are compared); that list contents may not rearrange
groups; and that wrapping/truncation are user controls.

The spec is an **agreement artifact, not an accepted specification**. Findings
should test whether it is a sound basis for a decision — whether its evidence
supports its conclusions, whether it hides a choice inside a recommendation, and
whether a reader could act on it — not whether it is implementable today.

## Review findings

The repository knowledge-graph client could not list projects because another,
unverified graph generation was active. No generation or index-coverage result
was therefore available. The source claims below were checked by reading the
named files directly; no negative or exhaustive graph claim is made.

### High — snapshot identity is not a late-reply guard

The facility table calls `(peer, token)` snapshot-scoped
(`docs/specs/configuration-exploration.md:243`), and the lifetime discussion then
says that this identity already tells the host whether to drop a reply from a
finished Visit (`:333-338`). That is not the contract being generalised. The
actual VS Code registry deliberately keeps a token stable across any number of
`parts` snapshots for the lifetime of the object
(`vscode-extension/src/registry.ts:18-23,46-65`); it identifies a target, not the
Visit that owns an outstanding continuation. The existing stale-callback guard is
instead a separately captured Visit generation
(`Sources/Modaliser/Scheme/lib/modaliser/fsm.sld:602-606,814-843,979-1001`).

Consequently, a live target token can accompany a reply whose continuation has
already died, and invoking that continuation after its owning runtime was torn
down is unsafe before target lookup is even relevant. The same omission becomes
long-lived ownership and cancellation once the proposed subscription channel
exists (`configuration-exploration.md:260-271`). Scope and rooting are listed,
but the protocol still lacks an identity and teardown contract for requests,
Visits, runtime instances, and subscriptions. This undercuts the claim that
Approach 2 remains reachable without redesign (`:540`): the proposed common
facility contract has not yet named the seam that makes its callbacks safe.

### High — an independently restartable configuration helper conflicts with the one-shot Handoff

The SBCL discussion correctly keeps the requested implementation in the
comparison, and running it out of process really does remove the embedded-C
shutdown limitation: process exit, including `sb-ext:exit` inside Lisp, owns the
runtime rather than asking C to undo Lisp initialisation. The problem is the
stronger claim that this makes SBCL a *restartable* peer whose only new cost is
the ordinary per-Visit protocol (`configuration-exploration.md:385-394,428-434`).

Approach 2 is a resident configuration runtime that owns the user's closures.
If that helper crashes after the one-shot Handoff, all installed callback handles
die with it. Recreating them requires re-evaluating configuration and reconnecting
the live host graph while a Visit, chips, and capture may still exist — precisely
the partial-replacement/orphan-state problem for which ADR-0018 rejects hot reload
(`docs/adr/0018-configuration-as-one-explicit-value.md:38-41`). If recovery is
instead whole-app relaunch, the process boundary supplies crash containment but
not independently usable restart. The design has neither selected one of those
semantics nor priced the supervision, readiness, rebinding, and diagnostic state
the former needs, so “SBCL is viable ... as a helper process” is stronger than
the lifecycle evidence supports. The fair conclusion established here is only
that SBCL is not ruled out as a helper pending that lifecycle decision.

### Medium — responsive arrangements have counts but no selection boundary

Pre-normalising one arrangement per authored track count closes the span-clamping
half of doubt 1, but not the renderer-selection half. The design says the renderer
chooses among those arrangements by a continuous display budget while never
deriving a track count (`configuration-exploration.md:219-231`), yet the concrete
surface supplies only counts — `'tracks 3` and `'narrow-to '(2 1)` — plus the
non-numeric placeholder `'width 'declared` (`:468-473`). Neither a breakpoint nor
an authored track width nor a rule for deriving the boundary is part of the
proposed value. Thus the narrow-display requirement (`:608-612`) cannot determine
which pre-normalised arrangement to choose without moving an unstated sizing
calculation back into the renderer. The design needs that input/rule before its
claim that responsive choice is a pure authored fact is closed.

`'span 'full` does not add another defect: it can retain its semantic full-width
placement in each selected arrangement. Nor does a panel added later: resolving
all variants from the current Display value would include it in each one. Those
two commissioned cases are dismissed on the model the document itself proposes.

### Medium — the proposed surface cannot express its constrained-lane option

The stability argument defines constrained lanes as a lane “assigned by the
author” (`configuration-exploration.md:126-140`), and the open choice later calls
them “author-pinned lanes” (`:670-674`). The illustrative authoring surface,
however, explicitly says no track coordinate exists and placement remains only
membership, order, and span (`:495-503`). A deterministic order is not an authored
lane assignment, while height-based automatic lanes are the unstable behaviour
the design set out to reject. The document therefore offers constrained lanes as
a valid selectable discipline without a representation for their defining
constraint. That option is not a sound peer to aligned grid or constrained flow
until the contradiction is resolved.

### Medium — the capability requirement states both sides of an unmade policy decision

The normative requirement says every undeclared capability is absent
(`configuration-exploration.md:614-617`) and, nine lines later, that a name no
version ever declared must diagnose (`:626-630`). It then acknowledges that these
scenarios are indistinguishable and the requirement is not testable (`:632-635`),
but the missing policy is absent from the document's enumerated open choices
(`:660-691`).

The two candidate mechanisms do not discover intent; they encode different
policies. Complete retired-name tombstones distinguish withdrawn names from
never-known names, but diagnose a legitimate newer operation against an older
facility. A per-row “tolerate absence” marker permits that compatibility case but
also intentionally suppresses a misspelling on the marked row. Either can be a
coherent contract once its trade-off is selected; neither makes both current
SHALL statements true as written. Because capability declaration is one of the
two load-bearing additions to the recommended boundary (`:260-271`), this cannot
remain a hidden, untestable choice in the agreement artifact.

### Low — the Lua comparison makes the cost superlative that the evidence banner forbids

Most of the commissioned cost-language sweep passes: “small” normally names
surface area, “bounded” names an interface boundary, and runtime performance and
size are explicitly left to E6 (`configuration-exploration.md:709-711`). The Lua
row is the exception: “the smallest, most robust embedding” (`:424`) is a
comparative runtime/packaging claim even though no candidate was embedded,
packaged, measured, or tested for robustness. The row's real evidence establishes
a protected C API and enumerates costs; it does not establish either superlative.

The bundled/helper recommendation itself is otherwise consistent. Bundled Scheme
libraries remain the default for in-process facilities, foreign outward reach
remains process-separated, and a Swift facility module remains the explicit
in-between option throughout the facility section, approaches, table, and
recommendation.

### Low — one corrected survey silently retains its pre-correction provenance

The producer commit materially rewrote the declarative-front-end spectrum and
corrected the tracing-collector count in
`docs/research/configuration-runtimes-a.md:228-251,684-693`, but that survey's
header still names only its original inspected revision and contains no correction
note (`:1-10`). The layout and facilities surveys do carry such notes. Therefore
this task's assertion that all corrected inputs record what
`configuration-design-k5` changed is false, and a durable research input now
contains post-survey judgment without provenance at its stated evidence boundary.

## Commissioned doubt dismissed

The concrete VS Code layout sketch is expressible by the proposed model. Each
peer panel has at most one block, none nests a panel, key children lower into
display references, and `resolve-display` already separates the display grouping
from dispatch ownership
(`Sources/Modaliser/Scheme/lib/modaliser/dsl.sld:676-723,788-828`;
`Sources/Modaliser/Scheme/lib/modaliser/display-dsl.sld:190-210`). Regrouping
those peers therefore does not add or alter a key path. The lane-coordinate
contradiction above concerns one selectable packing discipline; it does not
invalidate the peer-panel example itself.
