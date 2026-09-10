# configuration-design-k7

**Integrates:** configuration-design-k6

## Goal

Triage the findings from `configuration-design-k6` and integrate the valid ones
into the exploratory configuration design and its corrected research inputs.

## Context

The reviewed artifact is `docs/specs/configuration-exploration.md`. Treat
`configuration-design-k6` as the sole finding record; re-check each cited source
before changing the design.

## Done when

Every finding in `configuration-design-k6` is explicitly adjudicated. Valid
findings are integrated into the design and any affected research provenance;
rejected findings have their evidence-based disposition recorded in this task.

## Notes

Documentation only. Do not create implementation work or reopen the settled
stable-groups choice.

## Adjudication

Every finding in `configuration-design-k6` was re-checked against the named
sources before anything was changed. All seven were accepted as real; none was
noise, and none required a redesign that would exceed this session's charter.
Two coordinator consistency items arrived mid-session and are recorded below the
findings. The reviewed artifact and one corrected research input changed;
nothing else did.

Note on provenance: where `configuration-design-k6`'s body attributes the six
commissioned doubts to "the user", that is the **coordinator** commissioning a
technical review. None of them is a new user decision, and none of the edits
below treats one as such.

### Accepted and applied

**High — snapshot identity is not a late-reply guard.** Confirmed at both cited
sources. `vscode-extension/src/registry.ts:18-23,46-65` documents the opposite
of the spec's claim in its own comments — "PRUNE, NEVER REPLACE", and a token
"stable across any number of `parts` calls for as long as the object is live",
kept that way precisely so a second panel's read cannot invalidate the first
panel's rows. The engine's actual stale-callback guard is a separately captured
Visit generation compared on the way back in
(`Sources/Modaliser/Scheme/lib/modaliser/fsm.sld:602-606,814-843,979-1001`).
Two identities had been collapsed into one. Applied: the facility contract's
*Entity identity* row now states what the shipped registry actually promises and
a new **Request identity** row states the missing obligation (Visit, runtime
instance, subscription, plus teardown); the *Late replies* bullet is rewritten to
name the generation guard rather than the token, and to split the obligation
Approach 1 inherits from the one Approach 2 owes; the "two additions" passage is
now three, with request identity named as the one with no shipped precedent at
that boundary; a late-reply row is added to the validation obligations; and the
recommendation's "Approach 2 stays reachable without a redesign" is explicitly
scoped to the layout and boundary work, since the callback seam has no
contract-level answer in the document.

**High — an independently restartable helper conflicts with the one-shot
Handoff.** Confirmed against `docs/adr/0018-configuration-as-one-explicit-value.md:38-41`,
which rejects idempotent-replace handoff on exactly the partial-teardown ground
a crashed resident config peer would re-create. The finding correctly concedes
the part that holds — process exit does own teardown, so the embedded-shutdown
limitation really is dissolved out of process — and attacks only the step from
*containable* to *independently restartable*. Applied: the SBCL paragraph now
concludes "not ruled out … pending that lifecycle choice", names the two honest
semantics (crash-containment with ADR-0022 degradation and relaunch recovery, or
independent restart with supervision, readiness, rebinding and diagnostic state),
prices neither, and points the second at ADR-0018's own reopening terms; the
lifecycle table's "Restartable helper process" row is renamed and carries the
same caveat, so the table no longer asserts restartability as a property of the
process boundary.

**Medium — responsive arrangements have counts but no selection boundary.**
Confirmed by reading the document against itself: the renderer is told to choose
by a continuous display budget while never deriving a track count, and the
surface offers only `'tracks 3`, `'narrow-to '(2 1)` and the non-numeric
`'width 'declared`. A count is not comparable with a pixel budget, so the
narrow-display requirement was unsatisfiable without smuggling a sizing
calculation back into the renderer. The finding's own dismissals of `'span 'full`
and of a later-added panel are sound and were left alone. Applied: a new passage
states that normalisation is closed and *selection* is not, names the missing
input as a missing authored fact, and gives the two forms that would supply it (a
declared track width, or a per-step boundary) as **open choice 9**; the
illustrative sketch marks `'width 'declared` a placeholder and says plainly that
no real surface can be drawn until choice 9 settles.

**Medium — the proposed surface cannot express its constrained-lane option.**
Confirmed. "Lane *assigned by the author*" and "author-pinned lanes" cannot
coexist with "nothing here names a track coordinate" while a deterministic order
is offered as the substitute; order plus span places into a grid or a flow, but
lanes stack independently, so deriving a lane from an order restores the running-
height measurement the section rejects. Applied without reopening the settled
stable-groups choice: the constrained-lanes bullet now states that pinned lanes
are the one discipline needing a positional coordinate and names its costs (a
per-panel lane value plus validation for out-of-range, empty and degenerate
lanes); the sketch's "no track coordinate" bullet is scoped to grid and flow and
says the silence is a limit of the sketch; and open choice 1 records lanes as a
larger arrangement vocabulary that also interacts with choice 9's re-mapping,
rather than presenting three cost-equal peers.

**Medium — the capability requirement states both sides of an unmade policy
decision.** Confirmed, and the finding's analysis of *why* the two mechanisms are
different contracts rather than two readings of one is correct: tombstones
diagnose a legitimate newer reference against an older facility, and a tolerance
marker suppresses a misspelling on the marked row. Applied: the requirement's
SHALL is now the part both policies make true (no other key, label or group is
invalidated), the never-declared scenario is explicitly marked
policy-dependent and carries a GIVEN naming the policy it needs, the *Unresolved*
note is reframed as a recorded choice, the *Compatibility* discussion no longer
asserts "everything else is a diagnostic", and the decision is added to the
enumerated open choices as **choice 10** so it can no longer read as settled.

**Low — the Lua comparison makes a cost superlative the banner forbids.**
Confirmed: "the smallest, most robust embedding" is a comparative runtime and
packaging claim in a document whose banner promises every cost claim is surface
area, and nothing was embedded, packaged or measured. The finding's verdict that
the rest of the cost sweep passes, and that the bundled/helper recommendation is
consistent across all four places it appears, was spot-checked and agreed.
Applied: the row's condition is restated as the surface-area fact its evidence
supports — a small C-API embedding with protected evaluation at the boundary —
with the superlatives withdrawn and handed to E6.

**Low — one corrected survey silently retains its pre-correction provenance.**
Confirmed: `git show 2f4e76d` rewrote `docs/research/configuration-runtimes-a.md`
in two material places while its header still named only its inspected revision,
even though the same commit message claims the correction pass was recorded in
each header, and the other two surveys do carry notes. Applied: a correction note
is added to that survey's header, attributing the corrections to
`configuration-design-k5` and the note itself to this leaf, and naming both
changes (§3's declarative front end rewritten from a single shape into a
spectrum, with the matching row added to §6.2's table; §8's tracing-collector
count corrected from three to two, ARC being reference counting). Findings and
recommendation are unchanged, and the note says so.

### Coordinator consistency items, applied

- **Approach 2's migration event is a policy, not an inevitability.** The
  comparison table asserted "100 % of `config.scm` at once" for Approach 2, while
  the approach's own description admits a second language *beside* LispKit.
  Applied: the table cell now distinguishes a chosen per-user rewrite (Scheme
  keeps loading) from dropping Scheme support, and recommendation reason 3 makes
  the same distinction, naming two resident runtimes as the price of coexistence.
- **Source-inferred layout effects are expected mechanisms, not reproduced
  behaviour.** Applied at the Problem section's load-bearing claim — the chain
  from a longer editor title to re-columnised command rows is now marked as the
  mechanism the source implies, with E2/E3 named as what would confirm it.

### Rejected

None. Every finding reproduced from the sources it cited.

### Not done here, and why

No finding demanded that the artifact be rethought rather than repaired, so no
new producer review chain was cut. The two genuine gaps the findings exposed —
the responsive selection input and the unknown-name policy — are *decisions for
the coordinator*, so they are recorded as open choices 9 and 10 rather than
resolved by this session; picking either would put an unreviewed design choice
into an agreement artifact under a leaf chartered to apply findings. No ADR was
written or amended: the spec remains exploratory and explicitly amends none. No
implementation, prototype or experiment was run, and the settled stable-groups
choice was not reopened.

### Second coordinator round: provisional defaults, applied

The coordinator asked that the two policy gaps this session had recorded as open
choices be made *reviewable* — a provisional default written concretely, marked
unaccepted — rather than left as caveated holes, and that contradictory SHALLs be
removed instead of excused. Four changes, all in the spec:

- **The capability requirement now states one coherent policy.** Provisional
  default: **strict required operations plus an explicit optional marker**. The
  two contradictory SHALLs are gone, replaced by three that hold together — an
  undeclared capability behind an optional marker yields an absent row and the
  config loads; without the marker it yields a load diagnostic degrading per
  ADR-0022; preserving the other keys and groups applies to a successfully loaded
  screen with an absent optional reference, not to the bundled fallback after a
  required-reference failure. The coordinator's
  correction is stated explicitly at the point of use: **this does not make every
  withdrawn operation silent** — silence is a property of the *marker*, so an
  unmarked withdrawal diagnoses and a typo inside a marked reference stays
  silent. Three scenarios replace the two policy-dependent ones (withdrawal
  behind a marker, withdrawal without one, a misspelling), and the *untestable*
  caveat is deleted rather than relied on. The requirement is retitled to what it
  now promises — *does not invalidate a **marked** Decision*. Open choice 10
  keeps the alternative (retired-name declarations) with its own cost.
- **The responsive rule is grounded numerically.** Provisional default: a
  declared **track width and gap**, with `width(n) = n × track + (n − 1) × gap`
  computed per step at resolve. The numbers are the stylesheet's own
  source-declared defaults — `--panel-min-width` 184px and `--panel-gap` 10px
  (`Sources/Modaliser/Scheme/base.css:382-383`) — so the sketch's three steps are
  572, 378 and 184 pixels; the passage says plainly that this is arithmetic over
  source values, not a measured layout, and points at E5. The narrow-display
  scenario is rewritten to select the widest fitting step, with a GIVEN naming
  which of choice 9's two forms supplied the width. The `'width 'declared`
  placeholder is gone from the sketch, replaced by `'track` and `'gap`.
- **Lane assignments take the explicit deferral.** Rather than invent a
  coordinate, the proposed vocabulary now offers `'placement 'grid` and `'flow`
  only, and says so wherever lanes appear: the placement table, the
  constrained-lanes bullet, the sketch's read-out, Approach 1's summary, and open
  choice 1 — which now names the three things un-deferring lanes would require (a
  per-panel lane value, its validation, and a re-mapping rule for a reduced track
  count) and poses the choice as whether independent stacking is worth them.
- **The residual per-Visit minting sentence is fixed.** *Dynamic snapshots* said
  "a Visit takes one snapshot; identities are minted in it", which contradicts the
  now-correct lifetime-stable entity token. It now states that a target token is
  minted once per live object and outlives any number of snapshots; what a Visit
  scopes is the set of rows read, and what dies with it is the *request*.

The document's banner names both provisional defaults, states that a marked
provisional default is not an accepted decision, and says each carries the
alternative it was chosen over. Two validation-obligation rows were added (the
per-step width arithmetic; the marked/unmarked capability outcomes), and the
facility row split so peer unavailability is distinct from capability absence. No
survey was re-run and no implementation work was created.

### Coordinator final consistency check

The final read scoped the unchanged-screen guarantee to optional absence: a
required-capability error rejects the user configuration and may install a
different bundled screen under ADR-0022. It also distinguished reusable provider
functions from their Visit-scoped continuations, and narrowed stable geometry to
membership/order/track assignment and contained title width; wrapped content may
move later content vertically. These are consistency corrections to the accepted
review findings and the recorded user choice, not new accepted design decisions.
