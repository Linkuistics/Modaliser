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
  renumbered 5 → 7. `CONTEXT.md`, `.grove/12-impl--vscode-part-panels-k7.md` and
  `.grove/13-impl--catch-all-error-teardown-k11.md` were edited for it. Sweep for
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
