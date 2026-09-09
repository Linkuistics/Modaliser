# vscode-terminal-listing-k13

## Goal

An adversarial read of the VSCode window-parts design as it now stands —
`docs/specs/vscode-window-parts.md` and `docs/adr/0026-*.md` — before two
implementation leaves build to it. Findings, not fixes.

**Reviews:** `vscode-terminal-listing-k10`.

## Context

**Why this artifact earns a review.** The design it replaced went through a
review chain (`vscode-part-enumeration-k8` / `-k9`) that found **seven** defects
in the same area, two of which grew leaves of their own. This design then
**reversed that design's central decision** — the row source — mid-session, on a
suggestion the human made after the leaf had already started, and it was written
and settled inside that one session. Two leaves build directly onto it
(`vscode-companion-extension-k12`, then `vscode-part-panels-k7`), so a defect
here is paid for twice.

**What changed, in one paragraph, so you can read the diff with the right
expectation.** ADR-0026 previously said *what is open inside a VSCode window
comes from the accessibility tree*. It now says it comes from a **companion
VSCode extension** that Modaliser ships and talks to over a Unix-domain socket,
reusing ADR-0020's transport. The spec was renamed
`vscode-editor-listing.md` → `vscode-window-parts.md` and now covers both
listings. The producing session's running decision log
(`.grove/09-DONE-design--vscode-terminal-listing-k10.md`) records the reasoning
and the one defect it caught in itself.

**Specific doubts the producing session could not resolve on itself.** These are
where to spend your attention first; they are not the whole review, and a finding
outside them is worth as much.

- **The `focused` gate (spec decision 3).** Modaliser discards any reply whose
  `focused` is false, and the gate is claimed sound because the overlay panel is
  non-activating (`ui/overlay.scm:1053`), so VSCode keeps window focus through
  the modal. Is that actually true on every path? Modaliser's activation policy,
  a chip paint, a hint overlay, a `Relaunch`, or an op that raises another window
  are all live during a modal. If any of them takes focus from VSCode, **every**
  reply is discarded and both panels are permanently empty with nothing in the
  protocol to explain it — the worst kind of failure, because it looks like the
  extension is broken.
- **Whether `WindowState.focused` means what the design needs.** The design
  reads it as "this VSCode window is the one the human is looking at". Check that
  against the shipped `vscode.d.ts` and, if you can, live: does it track OS focus,
  workbench focus, or the *application* being frontmost? `WindowState` also
  carries `active`, which the design does not use and does not explain not using.
- **The pointer file's failure modes (spec decision 3).** One well-known file,
  written by whichever window last took focus. Enumerate what happens when: the
  focused window closes without another taking focus; two windows race; VSCode
  quits leaving the file behind; the file exists but the socket does not; a
  window opens with no folder. The design claims every one of these ends in an
  empty listing, and that claim is not individually evidenced.
- **`extensionKind: ["ui"]` versus the API the extension needs.** The design
  requires UI-side placement so the socket is on the local machine. Does a
  UI-side extension actually get `window.terminals` and `window.tabGroups` for a
  window connected to a remote host, or is that API remote-side only? If it is,
  the design has a hole for remote windows that it currently describes as merely
  degrading.
- **Token identity for tabs (spec decision 4).** The token map is keyed on
  **object identity** and pruned rather than replaced. That is correct for
  `Terminal`, which is a stable object. Is it correct for `Tab`? If VSCode
  recreates `Tab` objects when a tab changes — dirty, pinned, moved — then the
  same tab gets a new token on the next `parts` and the map grows with dead
  entries. The design asserts pruning handles this; check it.
- **The two-round-trips ruling (spec decision 5).** Deliberately un-memoised, on
  the argument that herdr's 0.1–0.6 ms wire time makes a cache premature. Nothing
  here is measured. Is the argument sound, or does it lean on herdr's numbers
  describing a different peer — a Rust process versus a Node extension host
  shared with every other extension in the window?
- **The security surface (spec decision 2).** Three methods, no
  `executeCommand`, socket directory at 0700, and an accepted exposure of the
  open editors' paths. Is the exposure characterised correctly and completely,
  and is "accepted on the same terms as herdr's" a fair comparison?

**And two questions about the record rather than the design.**

- **Is ADR-0026 still a minimum coherent record?** It now carries the reversed
  decision *and* the full evidence for four rejected sources. `ADR-FORMAT.md`
  wants the fewest records that coherently explain the current design — is one
  record right here, or has it become two decisions wearing one number?
- **Was every citation reconciled?** The spec was renamed and its merge decision
  renumbered 5 → 7. `CONTEXT.md`, `.grove/13-impl--vscode-part-panels-k7.md` and
  `.grove/14-impl--catch-all-error-teardown-k11.md` were edited for it. Sweep for
  what was missed, including the summary layers — `CONTEXT.md`'s glossary
  entries and `docs/reference/libraries.md`.

## Done when

- Every doubt above is either a stated finding or explicitly cleared, with what
  cleared it.
- Findings are recorded with enough evidence for an integrating session to act
  without re-deriving them, and with a severity that separates *this is wrong*
  from *this is a visible trade-off I disagree with*.
- No fixes are applied and no artifact is edited (`references/review.md`).

## Notes

- The producing session read the shipped `vscode.d.ts` and bundle rather than
  driving a live VSCode window, because the decision rested on the API surface
  rather than on observed AX behaviour. It also measured nothing. Both are
  deliberate and both are stated — but they mean **every live-behaviour claim in
  this design is inferred from the type declarations**, which is a fair thing to
  press on.
- `k6`'s worst three findings were all properties **asserted rather than made
  structural**. The producing session found one of exactly that shape in itself
  (the token map) and fixed it. That is a reason to look harder for a second, not
  a reason to relax.

## Findings

### F1 — blocker — a row is not bound to the peer that minted its token

The design makes tokens safe only **inside one window**: every extension host has
its own never-reset counter (`docs/specs/vscode-window-parts.md:200-229`). The
row target carries that integer, while `focus-terminal!` / `focus-editor-tab!`
perform a fresh round-trip through the query runner
(`docs/specs/vscode-window-parts.md:248-262`), which reads the global
last-focused pointer again. No socket path, peer identity, or globally unique
window/extension identity crosses the read-to-act gap.

That permits the exact wrong-target result the token invariant is supposed to
exclude. Window A can mint terminal token `3`; after the rows are drawn, the
pointer can move to window B, whose independent counter can also have a live
token `3`; pressing A's row then asks B to focus its token `3`. The `focused`
flag protects the **read** from an already-stale pointer
(`docs/specs/vscode-window-parts.md:150-178`), but it neither binds the later
action to that peer nor makes the check and use atomic. This violates the SHALL
that a label activates its own part or nothing, never a different part
(`docs/specs/vscode-window-parts.md:545-571`).

The integration needs to make peer identity structural: for example, carry the
enumerating socket/extension instance identity in every target and act through
that same peer, with the peer refusing an action once it is no longer the
focused window. Merely widening the per-window counter does not fix addressing;
merely rereading `focused` after dialing still leaves a check/use race unless
the peer owns the whole decision.

### F2 — high — the synchronous request shape has no safe stalled-peer budget

Both providers synchronously issue `parts`, so one come-to-rest performs two
serial request/reply exchanges (`docs/specs/vscode-window-parts.md:279-287`).
The copied native primitive blocks the Scheme evaluation thread for the whole
timeout (`Sources/Modaliser/UnixSocketLibrary.swift:44-72`); the existing herdr
transport sets that timeout to 1000 ms specifically as the ceiling for a wedged
server (`Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr-socket.sld:115-121`).
The spec also identifies the companion extension host as a shared event loop
that another extension can delay (`docs/specs/vscode-window-parts.md:472-478`).
It nevertheless specifies neither a total dispatch budget nor a shape that
prevents two consecutive timeouts. The healthy-path measurement requested at
`docs/specs/vscode-window-parts.md:480-486` cannot establish that worst-case
bound.

The action side has a separate, direct conflict with ADR-0014. `focus-*` returns
`{"ok": ...}` (`docs/specs/vscode-window-parts.md:130-135`), but the Terminal
action consumes no result: the FSM tears the modal down before invoking the
action (`Sources/Modaliser/Scheme/lib/modaliser/fsm.sld:895-900,1088-1156`).
ADR-0014 says a no-result call must use `unix-socket-send`, not wait for a reply
(`docs/adr/0014-interactive-commands-never-block.md:25-46`).

The integration should decide a **total** listing deadline and a request shape
that respects it (one shared snapshot is the natural candidate because `parts`
already contains both panels), then make fire-and-forget focus actions use the
no-reply transport unless some caller genuinely consumes acknowledgement.

### F3 — high — `focus-editor` is unspecified for tab kinds the listing marks actionable

The listing gives a token to any tab input that carries a URI and says only
URI-less inputs are inert (`docs/specs/vscode-window-parts.md:74-101`). It later
says `focus-editor` reveals the live `Tab` "by its URI in its own view column"
(`docs/specs/vscode-window-parts.md:130-135`). That is not one operation in the
shipped API. In VSCode 1.136.2, `Tab.input` includes text, custom-editor,
notebook, text-diff and notebook-diff inputs as distinct kinds (shipped
`vscode.d.ts:19294-19310`), while `TabGroups` offers only `close`, not reveal or
activate (`vscode.d.ts:19409-19448`). `window.showTextDocument` cannot activate
an arbitrary notebook or custom editor, and diff inputs do not even have one
unambiguous URI.

Thus the extension implementation leaf would have to invent a policy the design
has not settled, and reopening by resource can activate a different editor than
the exact tab whose token was pressed. The integration should either narrow the
actionable contract to tab kinds with a specified identity-preserving activation
operation and list the rest inert, or specify and justify the fixed per-kind
operations (including custom editors, notebooks and diffs). A bounded internal
operation for a named kind need not become the prohibited generic command
passthrough, but it does need to be part of the design.

### F4 — high — folderless windows contradict the unqualified listing requirements

The failure section says a folderless window does not listen and therefore
produces empty panels (`docs/specs/vscode-window-parts.md:433-448`). The
requirements contain no such exception: they require every editor tab and every
terminal in the frontmost VSCode window (`docs/specs/vscode-window-parts.md:496-529`).
A folderless window can contain both, and the last-focused pointer needs no
workspace-derived address, so the absence of a workspace does not prevent peer
selection. It only prevents workspace-relative rendering.

The integration should keep the peer alive with a nullable workspace and define
the path-rendering fallback, or explicitly narrow the requirements and explain
why visible folderless tabs and terminals are outside the feature. The current
text promises both full enumeration and deliberate emptiness for the same case.

### F5 — medium — the durable security record understates the data and omits the directory boundary

The `parts` example exposes the workspace path, terminal names and current
working directories, and editor labels/paths (`docs/specs/vscode-window-parts.md:113-121`).
The security analysis characterises the exposure only as open editor paths plus
the ability to switch tabs (`docs/specs/vscode-window-parts.md:137-143`;
`docs/adr/0026-vscode-parts-come-from-a-companion-extension.md:95-100`). It
omits terminal names/cwds, the workspace root, and the ability to focus a
terminal. Those are not necessarily unacceptable, but acceptance must enumerate
the actual surface.

The only instruction to create the socket directory with mode 0700 is in the
ephemeral implementation leaf
`.grove/12-impl--vscode-companion-extension-k12.md:137-140`. Neither the spec nor
ADR-0026 makes that filesystem boundary durable, and ADR-0020's transport choice
does not supply it by implication. The integration should record the complete
accepted disclosure/control surface and the mandatory directory permissions in
the lasting design.

### F6 — medium — public test hooks can turn off the collision invariant

The design says composition **raises** on provider/static-edge and
provider/permanent-state collisions, but exposes optional `'known-edges` and
`'known-state-ids` arguments on the same public
`jump-list-compose-providers` procedure; their caller-provided values replace
the FSM queries (`docs/specs/vscode-window-parts.md:323-360`). The test section
confirms that direct callers supply them (`docs/specs/vscode-window-parts.md:645-654`).
Because the user's configuration is Scheme code, a production caller can pass
empty readers and silently disable the checks. "The merge validates" is
therefore discipline, not structure—the same defect shape this review was asked
to look for.

The production interface should always obtain the owner's edges and registered
state ids itself. Tests can exercise a lower pure validator/helper or replace a
narrower internal dependency, but the exported composition operation must not
offer a switch that weakens its advertised invariant.

### F7 — medium — ADR-0026 and the spec are not a minimum coherent record

ADR-0026 now decides at least source selection, peer addressing, token identity,
protocol/security surface and transport (`docs/adr/0026-vscode-parts-come-from-a-companion-extension.md:80-129`).
The spec restates those decisions at much greater length. Grove's grain rule is
that an ADR records one decision/trade-off while a spec describes the area and
cites rather than restates ADR decisions (`SPEC-FORMAT.md:33-36`). The record
also retains a `Status: accepted` header
(`docs/adr/0026-vscode-parts-come-from-a-companion-extension.md:3-5`) although
the governing format explicitly says current-state records have no status line
(`ADR-FORMAT.md:20-24,50-63`). The repository overrides Grove only for numbered
ADR filenames and citations (`CLAUDE.md:189-197`), not for status or grain.

The integration should resharpen the set rather than mechanically split every
bullet: keep the source-choice trade-off together, decide whether the
peer/target-identity decision exposed by F1 earns a separate ADR, and leave
reversible protocol/interface detail in the spec. Whichever boundary is chosen,
remove duplicated normative accounts so there is one durable source for each
decision.

### F8 — low — one live implementation brief still cites the old decision number

`.grove/13-impl--vscode-part-panels-k7.md:102` says provider composition is
answered by spec decision 5. The same leaf correctly identifies composition as
decision 7 at `:58-64`, while decision 5 is now the un-memoised round-trip ruling
(`:75-77`). The stale citation sends the implementer to the wrong contract and
should be corrected to decision 7 when the design findings are integrated.

## Decisions (running log)

**The focus gate is cleared narrowly; it does not clear F1.** The shipped
VSCode 1.136.2 declaration defines `WindowState.focused` as whether the current
window is focused and defines `active` separately as recent interaction
(`vscode.d.ts:11038-11049`), so `focused` is the right field. Modaliser is an
accessory app (`Sources/Modaliser/Scheme/root.scm:125`); the overlay is created
with `activating #f` (`Sources/Modaliser/Scheme/ui/overlay.scm:1047-1064`);
nonactivating web panels neither call `NSApp.activate` nor become key
(`Sources/Modaliser/WebViewManager.swift:23-45,89-123`); and hint chips are
nonactivating and ignore mouse events
(`Sources/Modaliser/HintsLibrary.swift:197-249`). Terminal-state dispatch also
tears down presentation and capture before calling the action
(`Sources/Modaliser/Scheme/lib/modaliser/fsm.sld:895-900,1088-1156`). On those
paths Modaliser does not steal OS focus merely by displaying the modal. This
clears the feared permanently-empty normal path, but a peer switch between row
read and action remains the protocol defect in F1.

**The pointer failure modes split into safe misses and two findings.** A closed
focused window unlinks its socket on orderly deactivation or leaves a refusing
socket after failure; a quit leaves the same stale/refusing-pointer outcome; and
a pointer whose socket is absent maps to `#f` and empty rows
(`docs/specs/vscode-window-parts.md:190-198,433-444`). The two-window race is not
safe across the later action (F1). A folderless window is intentionally empty in
the design, but that is a requirements contradiction rather than a missing
failure analysis (F4).

**`extensionKind: ["ui"]` is cleared at the API-contract level.** VSCode's
official remote-extension documentation says UI extensions run locally and that
VSCode APIs are routed to the correct machine from either extension-host
placement; the shipped declarations expose `window.terminals`, `window.state`
and `window.tabGroups` as ordinary window APIs. There is no evidence these
particular APIs require the workspace host. The implementation should still
exercise a remote window if remote workspaces are claimed as a supported case,
but the design does not presently have the alleged host-placement hole.
Source: <https://code.visualstudio.com/api/advanced-topics/remote-extensions>.

**Tab object identity is cleared for the pinned VSCode version.** In the exact
shipped commit (`88e44fa0e00b08f7758b4f6d05632e4fd5e4df6f`), the extension-host
tab implementation memoises each API `Tab` object and `_reconcileTabs` reuses
the existing wrapper by stable tab id during incremental changes and full
resynchronisation. Dirty, pinned, active and moved updates therefore do not mint
a new API object in 1.136.2, and pruning by object identity does not grow dead
entries for those changes. This is source evidence, not a live drive:
<https://github.com/microsoft/vscode/blob/88e44fa0e00b08f7758b4f6d05632e4fd5e4df6f/src/vs/workbench/api/common/extHostEditorTabs.ts>.

**The two-round-trip and security doubts are findings, not preference notes.**
Healthy average latency might still make an un-memoised implementation fast,
but it does not establish the stalled-peer bound and does not justify waiting
for unused action acknowledgements (F2). The bounded method set is a good
constraint, but the accepted exposure and filesystem boundary are incomplete in
the durable record (F5).

**The record and citation questions produced F7 and F8.** The citation sweep
searched hidden Grove files and current documentation with both a deliberately
dirty old-path control (`vscode-editor-listing.md`) and positive current-path
controls (`vscode-window-parts.md`, ADR-0026). Old-path hits outside F8 were
historical DONE leaves or transition prose; `CONTEXT.md`,
`docs/reference/libraries.md`, and
`.grove/14-impl--catch-all-error-teardown-k11.md` contained no additional live
stale citation found by the bounded sweep.

**Coverage limitation.** The review inspected the producer commit
`vkuxqsvu`/`8fc214cc`, both design artifacts, governing ADRs, named summary
layers, live implementation briefs, relevant Swift/Scheme source, the exact
shipped VSCode declarations/source, and official remote-extension documentation.
The codebase-memory CLI was attempted repeatedly first, but refused to start
because a pre-coordination or unverified generation was active. Exact source
reads and targeted `rg` sweeps covered every reported range instead; no negative
claim here relies on an empty graph result. Per the `review-design` discipline,
no build, test, lint, formatter, or live UI drive was run, and no artifact or
implementation file was changed.
