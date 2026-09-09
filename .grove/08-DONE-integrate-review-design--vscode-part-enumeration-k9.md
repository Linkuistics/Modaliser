# vscode-part-enumeration-k9

**Integrates:** `vscode-part-enumeration-k8`

## Goal

Triage the paired design review and apply every finding that survives scrutiny
to the VSCode part-enumeration design, leaving k7 an implementable and coherent
contract.

## Context

- The reviewed artifacts are `docs/specs/vscode-editor-listing.md` and
  `docs/adr/0026-vscode-parts-come-from-the-accessibility-tree.md`.
- The producer is `vscode-part-enumeration-k6`; the review handle above is the
  source of findings and evidence.
- `vscode-part-panels-k7` is the consumer. Reconcile its charter with the
  resulting current-state design rather than leaving it to rediscover a design
  choice during implementation.

## Done when

- Every review finding is classified and every accepted one is integrated into
  the design artifacts; rejected findings retain the evidence for rejection.
- The spec's requirements, seams, accessibility anchors, collision policy, and
  handle invariants agree with one another and with ADR-0026.
- ADR-0026 remains a minimum coherent current-state record, reworked in place if
  its terminal or editor-source decision changes.
- k7 can implement the result without reopening a source-selection or sequencing
  question.

## Notes

Findings live in the review leaf and are deliberately not copied here.

## Decisions (running log)

**All seven findings survived triage; none was noise.** Each was graded against
the source rather than against the review's summary of it, and the four
source-checkable ones were confirmed by reading the cited lines:
`AccessibilityLibrary.swift:71`/`:98` (the counter reset — F4),
`fsm.sld:751`/`:640` (append with no check, provided-state shadowing — F3),
`KeyboardLibrary.swift:300` (deregister and nothing else — F6), and the
producer commit's own file list (no instrument committed — F7).

**F1 and F2 were re-verified live rather than taken on the reviewer's word**,
since they drive the two largest changes. A `swiftc -O` walk of the frontmost
VSCode 1.136.2 window confirmed the shape both findings rest on: exactly one
empty-description `AXTabGroup`, holding an `AXTabButton`-subroled child whose
`AXDescription` is the filename and whose actions include `AXPress`; and, in the
same window, a visible terminal panel exposing `Terminal (⌃`)` tab buttons and
`Terminal 1, zsh` — with no `Terminal tabs` list, because that window runs a
single terminal and `hideCondition` defaults to `singleTerminal`, which is
itself one of the facts the terminal design has to price. F1's split-editor and
`showTabs` cases were accepted on the review's live evidence plus the structural
argument that settles them either way: VSCode builds one tab strip per editor
group from the same component, so "the only empty-description tab group" cannot
be a property of a window that has two groups.

**Three findings share one shape, and that is the lesson worth keeping.** F3,
F4 and F5 are each a **property asserted where nothing made it structural** —
two dictionaries called two disjoint handle spaces, a merge said to catch
collisions over a namespace it never sees, a fixture instruction the row type
made unsatisfiable. Each repair moves the property from claimed to enforced:
one never-reset counter, a validation surface that includes the owner's static
edges and the registered state ids, and a native row that keeps `description`
and `title` apart until Scheme joins them. That is why the repairs are small
despite the findings being severe — the designs were nearly right and the
guarantees were free.

**F2 is accepted, but the redesign it implies is not this session's work.**
Correcting ADR-0026's terminal ruling is a record-keeping repair and is done
here: the three "independent" blockers were one premise restated, and the tree
half of it is false with the panel shown. Designing the show-then-enumerate
interaction is not — it needs an FSM-ordering decision that touches every
screen's dispatch path, a `hideCondition` decision that changes what the human
sees in VSCode, and a UX call between a two-step op and no panel at all. That is
`vscode-terminal-listing-k10`, cut ahead of the panel implementation
(`references/integrate-review.md`: a finding that demands rethinking rather than
repair becomes a producer leaf beside the one being integrated).

**F6's residue is accepted visibly rather than solved, and then externalised.**
The spec now states what each dispatch path actually does — the leader path is
clean because `modal-activate!` raises before it registers or shows anything;
the catch-all path releases the keyboard and leaves the overlay standing — and
accepts that residue, because raising still beats a silent wrong dispatch. But
the defect is precisely stateable, so by the fog-or-ticket test it earns a leaf
rather than a horizon note: `catch-all-error-teardown-k11`. It is a host change
across every modal screen, which is exactly why it is not a rider on a VSCode
design.

**F7 cost the spec a conclusion, not a section.** The measurement is real and
the pruning result stands; what was withdrawn is the comparison — an instrument
figure set against two in-app figures — and with it "two panels stay inside one
panel's old budget". The `'next 'self` ruling never depended on either and is
untouched. k7 now carries an explicit instruction to measure the shipping path,
and k10 an instruction to commit whatever instrument it measures with, which is
the repair for the underlying cause rather than for this instance.

**k7 was reconciled rather than left to rediscover.** Its charter pointed at
k6's commit, which is wrong in seven places; it now points at the current spec
and ADR, names the five repairs that change what it builds, and makes the
Terminal panel conditional on k10's outcome — including what happens to the `t`
row if that panel is not built, which is the human's call and not a derivation.
