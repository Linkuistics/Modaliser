# vscode-terminal-listing-k14

**Integrates:** vscode-terminal-listing-k13

## Goal

Triage the findings from the adversarial review of the VSCode window-parts
design, applying the findings that stand and recording why any are rejected,
before either implementation leaf builds against the design.

## Context

Read `vscode-terminal-listing-k13` from its committed review task, then reconcile
the current `docs/specs/vscode-window-parts.md`, ADR set, and live Grove briefs it
cites. This is design integration: resolve the record and downstream contracts,
not the companion-extension or Scheme implementation itself.

## Done when

- Every finding in `vscode-terminal-listing-k13` is explicitly accepted,
  rejected, or reframed with evidence.
- Every accepted finding is integrated into the durable design and any affected
  live implementation brief; every rejected or reframed finding has its
  rationale recorded in this task.
- The resulting spec/ADR set is internally coherent, and no queued implementation
  leaf is left pointing at a superseded path, decision number, or contract.

## Notes

Preserve the repository's deliberate numbered-ADR convention. No production or
test implementation belongs in this leaf.

## Decisions (running log)

**Every finding from `vscode-terminal-listing-k13` was verified against the
artifacts and the shipped sources before it was acted on, and all eight stand.**
Nothing was rejected as noise. One (F2) is accepted on its defect and *reframed*
on its remedy; the rest are applied as reported. What follows is the verification
and the shape of each fix, so the impl leaves do not have to re-derive either.

**F1 (blocker) — accepted, and it is the session's real work.** Confirmed by
reading the design rather than trusting the report: the seam every reader and
every action went through resolved the pointer file itself, so an action's address
was recomputed at press time from global state while its token came from a
per-window counter. Two windows both hand out `3`; a pointer move between the read
and the press therefore delivered window A's token to window B, where it resolves
to a different tab, with both sides behaving exactly as specified.

The fix makes identity an *address* rather than a longer name. The `parts` reply
carries `peer` — the socket path the answering instance is listening on — every
target carries it beside its token, and `focus-*` is delivered to that path. The
read and the act name the same peer because the act's address came out of the
read. Note what was **not** chosen: widening the counter to a UUID would have made
the collision improbable rather than impossible and repairs the symptom, since the
defect in a bare token is that it is not an address, not that it is short (recorded
as a rejected option in ADR-0027).

The residual read→act *time* gap — the human moved to another VSCode window — is
closed on the **peer's** side, which refuses a notification while
`window.state.focused` is false. That is where the check is atomic against the
state it checks; nothing on Modaliser's side can make check-and-use atomic, only
narrow the interval in which it is wrong. The review's own decision log had already
cleared `WindowState.focused` as the right field for exactly this question.

**F2 (high) — the defect is accepted; the remedy is reframed.** Both halves are
real. The action side is a direct ADR-0014 violation: `{"ok": …}` was specified and
nothing consumes it, because the FSM tears the modal down before invoking a
Terminal state's action — so the focus methods become **notifications**, sent with
`unix-socket-send`, which is the shape ADR-0014 names for a call whose result is
discarded. That also removes the action side from the latency budget entirely.

On the read side the finding proposed one shared snapshot. **Not adopted**, and the
reason is the one decision 5 already recorded: a per-visit memo needs either a
visit generation the engine does not expose or a cell whose invalidation nothing
drives, so it is machinery bought ahead of need. What the finding is right about is
that *nothing bounded the total* — and a healthy-path measurement never could. So
the design now states the bound instead: a **200 ms** per-request timeout, and the
number that has to hold is `panels × timeout` (400 ms here), because a blocked eval
thread is a blocked keyboard tap. herdr's 1000 ms is the right ceiling for a peer
Modaliser launched and the wrong one for a peer whose event loop every other
extension in that window shares — two of them in a row is two seconds. A third
panel reopens the total, and *then* the answer is the shared read, which the reply
shape already permits without a protocol change.

**F3 (high) — accepted, and the reported cause understates it.** Verified against
the shipped 1.136.2 declarations: `TabGroups` exposes `close` and nothing else
(`vscode.d.ts:19409-19448`) — there is no reveal-this-`Tab` call at all, and
`TabInputTextDiff` / `TabInputNotebookDiff` carry `original` and `modified` and no
`uri` property whatsoever. So "carries a URI" was never the same question as "can
be activated"; it was a proxy that happened to agree on the common case. Decision 1
now decides per input kind, in a table, keyed on *the activation operation*:
`TabInputText` via `showTextDocument` and `TabInputNotebook` via
`openNotebookDocument` + `showNotebookDocument` (both verified present, at
`:11257` and `:11267`/`:14339`), each carrying the pressed row's own
`viewColumn` — which is what makes them identity-preserving when one resource is
open in two groups. Every other kind is listed inert. Reopening a kind costs a
bounded internal call to one named command, which is recorded as the reopen
condition rather than left as an implementer's judgement call.

**F4 (high) — accepted.** The contradiction is real and the resolution runs the
way the finding suggests: nothing in the addressing needs a workspace, so a
folderless window is an ordinary peer with `workspace: null`, and only path
*rendering* degrades. The empty-listing bullet is deleted from decision 8 and
replaced with a sentence saying explicitly that this case is not a miss — an empty
listing there would have narrowed an unqualified requirement rather than degraded
gracefully. Decision 6 gains the fallback, and it covers the neighbouring case the
finding did not name: a path that does not lie under the workspace at all.

**F5 (medium) — accepted.** The exposure is now a table in ADR-0026 with reads and
acts separated: workspace root, every terminal's name and cwd, every editor's
label, path, dirty and active flags and group, the focused flag, plus focusing a
terminal and activating a tab. The 0700 socket directory moves out of the
ephemeral impl brief into the same record. What is new against herdr — a list of
the human's open file paths and their workspace root — is called out as the reason
the enumeration is not a summary.

**F6 (medium) — accepted, and it is the same shape as F1.** A public procedure
whose advertised invariant can be switched off by two arguments is discipline
wearing a check's clothes, and this repo's users configure in Scheme, so the
"test-only" override is a production-reachable one. The surface splits at the
purity line instead: `jump-list-validate-composition` is pure, raising, takes every
fact as data, and is where all four collision cases are tested;
`jump-list-compose-providers` is a thin impure wrapper that queries
`fsm-state-edges` / `fsm-state-ids` itself and offers nothing to replace them.
Confirmed both queries already exist and are already reachable from the portable
tree (`fsm.sld:331`, `:440`), so the wrapper needs no new export.

**F7 (medium) — accepted, and resharpened rather than split per bullet.** Three
changes. The `Status: accepted` header is gone: `ADR-FORMAT.md` says current-state
records carry none, `CLAUDE.md` overrides grove only on numbered filenames and bare
citations, and the repo is already split roughly evenly between records that carry
a status line and records that do not — so dropping it follows an existing shape
here rather than imposing a foreign one. The other records were left alone: they
are not this leaf's subject. The record splits along the
seam F1 exposed — ADR-0026 keeps *what the source is*, its four rejected sources,
and the exposure it accepts; **ADR-0027** takes *which peer is asked and how a row
stays bound to it*, which now carries four rejected alternatives of its own
(derived socket path, directory scan, re-reading the pointer at act time, a
globally unique token). And the spec's duplicated normative accounts are cut to
citations: the rejected-addressing-scheme paragraph and the security rationale now
live in the ADRs once each, with the spec keeping only what is normative for a
builder.

**F8 (low) — accepted and fixed**, with the sweep re-run rather than inherited:
`.grove/14-impl--vscode-part-panels-k7.md` now says decision 7 at both places. The
old-path pattern `vscode-editor-listing` was used as the dirty control and came
back with five hits, all historical DONE leaves plus `k11`'s transition prose,
which is correct as it stands; the `decision N` enumeration over `.md`, `.sld`,
`.scm` and `.swift` with `--hidden` found no other live citation of a superseded
number. `jump-list-compose-providers` and `validate-composition` appear nowhere in
`Sources/` or `Tests/`, so F6's signature change has no implementation to
reconcile.

**Both live impl briefs were reconciled, because an integration that fixes the
durable design and leaves the work orders pointing at the old one has moved the
defect rather than fixed it.** `k12` gains the six protocol properties it now has
to carry, each stated as a property that must be structural rather than asserted,
plus four new `Done when` rows (the `peer` field, the unfocused-refusal test, the
one-way actions and 200 ms read, the folderless window). `k7` gains the composition's
new shape with an explicit "do not put the override arguments back for
testability", the peer-bound target, the fire-and-forget action, the folderless
listing, and the bounded-not-memoised framing of the two round-trips. `CONTEXT.md`
gains two clauses: the extension entry now says reads are addressed by pointer and
actions by the peer that answered, and the Editor listing entry says a listed tab
is not necessarily an actionable one.

**One defect found while integrating F1, which no finding named: socket-path
reuse.** Since a target now *is* a socket path plus a token, a path returning to
service under a new extension instance would be an address that outlived what it
addressed — a row drawn before a window reload would reach the reloaded window,
whose counter starts where the old one's did, and the token would resolve to a
different part. That is F1's failure arriving through the back door, so the design
now states that names are unique per *instance* and never reused. The tidy-up
consequence is stated with it: no unlink-before-bind on a stable name, but a sweep
of **connect-refused** sockets at activation — refused rather than unanswered,
because a wedged host is still listening and its rows are still valid, so a
liveness probe that waited for a reply would delete a busy peer's socket.

**The session's one narrow reviewer was spent on the F1 fix, and it earned its
keep** (`references/execute.md`'s allowance). The claim put to a fresh adversarial
context was the peer-binding one — *a label activates its own part or nothing,
whatever has changed* — with the artifact and the contract handed over and the
conclusion stripped. It could not break peer-bound addressing itself: no
interleaving of pointer writes, window closes or focus changes delivers one
window's token to another, given unique-per-instance paths and per-window maps. It
broke five other things, three of them in the repair I had just written, and every
finding is classified below.

**Valid and actionable, applied here.**

- **`viewColumn` is a position, not an identity** — the worst of them, and mine.
  My activation table recorded the pressed row's column in the snapshot;
  `ViewColumn` is an ordinal, so reordering or closing a group renumbers it. Same
  file in two groups ⇒ the pressed row activates the *other* row's tab, and a
  vanished column makes `showTextDocument` create a group and a new editor — a part
  that did not exist when the rows were drawn. Both are exactly the failure F1 was
  fixed to exclude, arriving through the activation instead of the address. The fix
  is one word — read `viewColumn` off the **live** `Tab` the token resolved to, whose
  `group` is a live reference — and the lesson is that decision 2's presence check
  was validating the `Tab` and then acting on a coordinate taken from elsewhere.
- **`focus-terminal` had no membership check** where `focus-editor` had one. The map
  is pruned only when `parts` is called, so between a read and a press a closed
  part's token is still mapped; the terminal path therefore rested on
  `Terminal.show()` on a disposed terminal being harmless, which the shipped API
  nowhere says. Both methods now check membership, and the spec says why the check
  is not redundant with the map.
- **The pointer file was never written for a window already focused at
  activation.** `onDidChangeWindowState` fires on *change* and activation is
  `onStartupFinished`, so the single-window case — and every host restart, and
  every fresh install — wrote no pointer at all and both panels would have been
  empty until the human clicked away and back. Verified against the declaration.
  The extension now writes at activation when focused, with the handler guarded on
  a focus gain because the same event carries the `active` inactivity flag.
- **The cross-kind refusal contradicted itself.** "One counter, one lookup" means a
  terminal token handed to `focus-editor` *is* found; implemented literally it
  would hand a `Terminal` to `showTextDocument`. Entries carry their kind and each
  method checks it — the refusal is the tag, not a hopeful lookup failure.
- **`preview: false` would pin a preview tab**, contradicting the requirement that
  pressing an already-active row changes nothing. Now `LIVE.isPreview`.
- **Two field sources were missing and two mistyped** (`dirty`, a terminal's
  `active`, the doubly-optional `shellIntegration?.cwd?`, and the diff kinds having
  no `uri` at all) in a table whose own sentence claims completeness.
- **The `#f` from `unix-socket-send` was being thrown away** — the one action
  failure observable from Modaliser's side, and precisely the dangling-peer case.
  Logged now; still no behaviour.
- **No seam observes an activation**, which is what let the `viewColumn` defect
  through: a fake records the arguments and passes. Stated in the spec as a limit
  of the test plan rather than left implicit, with the two cases only a real window
  can settle written into both build leaves' `Done when`.

**Contract stated unclearly — reworded, mechanism unchanged.**

- **"Atomic against its own state" was an overclaim of mine.** The peer's focus
  check narrows the race and does not close it: the host reads a `window.state`
  replica, the socket read is a callback on the shared event loop decision 9
  already calls unboundedly delayable, and the activation is asynchronous. What it
  eliminates is the *systematic* case — a modal held open across a deliberate
  window switch. The residue is a focus steal on a sub-tenth-of-a-second race the
  human causes with their own keypress, and it is now accepted visibly instead of
  being described as impossible. The check still belongs to the peer, because the
  residue there is strictly smaller than anything Modaliser can achieve alone.
- **`Tab` object identity is an assumption, not a guarantee.** The review chain
  verified it in the pinned version's extension-host source; the API promises only
  that `close()` invalidates a tab. Now stated as an assumption with its failure
  symptom (the second panel's labels quietly stop working) and its fallback (key on
  URI plus group), pinned where it is visible — the extension's own fixtures.
- **"On-screen order" promised more than `tabGroups.all` declares.** Within a group
  the order is the strip the human sees; across groups the API documents no order,
  and a 2×2 grid has no honest linearisation. The claim is now exact about which
  half is which, with a reopen condition, in a decision that opens by refusing to
  take anything from documentation.
- **Socket-name uniqueness needed sharpening** to *cannot recur* rather than
  *unlikely to recur*, since a restart is an ordinary event that keeps window focus
  and would otherwise pass every guard. The unlink-then-bind idiom is named as what
  this rules out, along with why it is a hijack rather than a tidy-up.

**Noise raised for want of context — recorded, not acted on as a defect.**

- **"The `focused` gate means these panels only work while VSCode is frontmost."**
  True, and not a defect: the F17 screen dispatches on the frontmost app, so it is
  only *reachable* while VSCode is frontmost, and the grove's brief already carries
  the two-step cost of crossing in from another app as the human's call. The
  reviewer could not have known that from the spec, which is the useful half of the
  finding — the spec now says it, so the next reader does not re-derive it.
- **The held-leader auto-repeat aside.** Real, pre-existing, and not this design's:
  the `'next 'self` ban does not reach the leader key, and the Projects panel's cold
  accessibility sweep is already the same order as the new budget. Recorded in
  decision 9 as a mechanism to recognise rather than a bug to fix here.

**No second review chain, and the reasoning is on the record rather than
implied.** `references/execute.md` treats a second review need as the signal that
review has become tree-sized work. This is not that: every finding above is a
localised repair to an artifact that has now had a full review chain *and* an
adversarial pass, and what remains unverifiable offline is concentrated in two
VSCode behaviours that only the human's machine can settle — which is why they were
written into `k12`'s and `k7`'s `Done when` instead of into a third review leaf.
Either build leaf may still cut its own `review-impl` chain; that judgement is
theirs, not this leaf's to pre-empt.
