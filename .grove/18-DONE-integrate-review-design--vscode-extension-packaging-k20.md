# vscode-extension-packaging-k20

**Integrates:** vscode-extension-packaging-k19

## Goal

Triage the adversarial review of the companion-extension packaging design,
applying every finding that stands before implementation builds against the
decision.

## Context

Read `vscode-extension-packaging-k19` from its committed review task, then
reconcile ADR-0028, any affected current-state documentation, and the live
implementation handoffs it cites. This is design integration: settle the
distribution, consent, cleanup, and host-boundary contracts rather than
implementing the companion-extension installer.

## Done when

- Every finding in `vscode-extension-packaging-k19` is explicitly accepted,
  rejected, or reframed with evidence.
- Every accepted finding is integrated into the durable design and affected
  live implementation briefs; every rejection or reframing records why.
- The resulting ADR set and documentation are internally coherent, and no live
  implementation leaf points at a superseded or under-specified contract.

## Notes

Preserve this repository's numbered-ADR convention. Production and test
implementation remain the responsibility of the downstream implementation
leaves.

## Triage (running log)

**All six findings stand, and none of them changes the decision.** That is the
shape of the result worth noting: ADR-0028 still decides what it decided —
bundle the payload, install only on a confirmed request — and every finding lands
on *how the decision is specified or argued*. Three were under-specification (F1,
F2, F3) and three were over-claiming (F4, F5, F6). No finding demanded the
artifact be rethought, so nothing was externalised as a new producer chain.

**F1 — accepted; the seam had a library side and no adapter.** Confirmed at the
source rather than from the finding: `SchemeEngine` defines exactly one path for
Scheme, `*scheme-directory*` (`SchemeEngine.swift:183`), and in production
`SysSync` deliberately redirects it to `~/.config/modaliser/sys/scheme` while the
payload is to live under `Contents/Resources`. `root.scm`'s existing pointers
(herdr's socket, the VSCode socket) all default from `$HOME`, which is why they
need no Swift adapter; a bundle resource root has no such source
(`root.scm:80-102`). So ADR-0028's "the host installs the path" named a
requirement with nothing able to meet it. Resolved by deciding the host input
rather than leaving it to k18: a second definition beside `*scheme-directory*`,
set only on the `isProductionBundlePath` branch, with its three values
tabulated. The ADR's "no new native surface appears" is narrowed to "no new
native *library*", which is what was true.

**F2 — accepted; the predicate, not the count.** k19 was right that one
transcription is the right count and that the defect is the predicate.
`antony.modaliser-companion-*` marks no name/version boundary and the extension's
own name contains a hyphen (`vscode-extension/package.json:2`), so a sibling like
`antony.modaliser-companion-beta-1.0.0` matches. Resolved by splitting the claim
along the two paths' capabilities: the install-time sweep treats the glob as a
candidate filter and confirms each candidate's `package.json` identity before
`rm -rf`, and the cask's `zap trash:` — a path list, not a program — is stated to
reserve the whole prefix. Two different properties, each claimed only where it
holds, which is the honest version of "this extension and only this extension".

**F3 — accepted, and it was the cheapest finding to miss.** `vscode-extension/README.md`
is required by ADR-0028 to be copied into the payload and still names the
repository-only installer and the reversed rationale (`vscode-extension/README.md:14-29`).
It was absent from k18's five-file list. Added as the sixth, in k18, `CLAUDE.md`
and the spec's *Out of scope*, all three of which carried the five-file
enumeration.

Its second half is accepted with a distinction the finding did not draw. k16 was
right that a doc describing an *unbuilt mechanism* is honest to leave standing —
but a doc asserting a *reversed rationale* is not, because that is a claim about
the present. So the installer commands stay in `README.md`,
`docs/reference/libraries.md` and `apps/vscode.sld` (they are what runs), and only
the "upgrades on its own cadence" rationale is qualified to name ADR-0028 and mark
itself as transitional. k18 is told to remove those qualifiers, not merely the
commands.

**F4 — accepted; the analogy was doing work it cannot do.** Read at the source,
the three `configure!` ops share only mechanics: kitty edits a text config with a
backup (`apps/kitty.sld:395-431`), iTerm2 edits preferences and relaunches itself,
Alacritty removes a quarantine xattr and says the app is otherwise unchanged
(`apps/alacritty.sld:211-241`). None installs code that activates by itself.
Resolved by splitting ADR-0028's Context paragraph into shape (settled, three
instances) and act (not settled, answered on its own terms), and by requiring the
dialog to disclose the two durable effects the enumeration omitted: activating
extension code, and survival of a plain `brew uninstall`.

**F5 — accepted as a reframing; the decision holds, the word does not.**
Install-then-notify is a live fourth shape, and the reason is the one k19
identified: this design's own path test *is* the reliable trigger the ADR claimed
was missing, which also made the recorded reopen condition self-contradictory.
"Strictly dominates" is therefore false. Recast as a consent judgement — one extra
keypress against never making an uninvited write into another application — with
a reopen condition that can actually fire (a persisted user preference to keep the
companion current, which would *be* the consent).

**F6 — accepted; one half verified externally before acting on it.** I did not
take the `vsce` claim on trust, because the fix was to delete an argument: the
current `main` of `microsoft/vscode-vsce` sets `const flags = ['Public']`
unconditionally and never reads `manifest.private`, and upstream issue #597
reports exactly that. So `private: true` is npm's do-not-publish flag and is no
evidence of Marketplace readiness; it is now explicitly marked as not being
cited. Registered publisher identity, expiring credentials, a publish step with
no CI, and inverted skew causality carry the rejection on their own. The
reversibility asymmetry is withdrawn — neither channel removes already-installed
copies — and both reopen conditions are replaced with events that arrive in the
maintainer's inbox, since "gains users who are not the maintainer" needs telemetry
this project does not have.

**Verification.** `swift build` and `swift test` green (1307 tests, 106 suites),
`./scripts/check-portable-surface.sh` and `./scripts/check-decision-free.sh` both
OK — the last two because the `apps/vscode.sld` comment change touches a file
under `lib/modaliser`. No production behaviour was changed and none was expected
to be: this session edited one ADR, three current-state documents, one library
comment, and the downstream implementation handoff.
