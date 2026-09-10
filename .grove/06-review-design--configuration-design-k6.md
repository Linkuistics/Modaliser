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
