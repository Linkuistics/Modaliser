# vscode-extension-packaging-k19

**Reviews:** vscode-extension-packaging-k16

## Goal

An adversarial read of ADR-0028 — *The companion extension ships inside the app
and installs only when asked* — and of the four files k16 reconciled with it.
Findings, not fixes.

## Context

k16 was told, in its own Context, that it was *"reversing, or softening, a
decision that was made deliberately and whose reasons are written down"* and to
**answer the counter-argument rather than around it**. Whether it did is the
review's central question, and it is not a question k16 can settle about itself.

**What k16 produced**

- `docs/adr/0028-companion-extension-ships-in-the-app-and-installs-on-request.md`
  — the new record. Decision: `build-app.sh` builds the extension into the app
  bundle; Modaliser copies it into `~/.vscode/extensions` **only on a confirmed
  user request**, through the `configure!` op shape `apps/kitty.sld`,
  `apps/iterm.sld` and `apps/alacritty.sld` already share.
- `docs/adr/0026-…` — its distribution *consequence* reworked to hand the
  question to ADR-0028 rather than keep asserting the old rule (`ADR-FORMAT.md`:
  split a record covering two independent calls; never append a superseding one).
- `docs/specs/vscode-window-parts.md` *Out of scope*, `CLAUDE.md`,
  `scripts/install-vscode-extension.sh`'s header — reconciled.
- Five further files were found asserting the old rule and **deliberately left
  standing**, named as the build leaf's work. Check that enumeration is complete
  and that leaving them is honest rather than convenient.

**The specific doubts, strongest first.** These are k16's own, written down
because a producer cannot test them on itself — not a work list, and not a
ranking you owe any deference to.

1. **The load-bearing fact.** The whole reversal rests on one observation:
   `release-build.sh:assemble_bundle` stages `Modaliser.app`, `README.md` and
   `LICENSE`, so a cask user has no `scripts/` and no `vscode-extension/`, while
   the shipped `README.md:52` tells them to run
   `./scripts/install-vscode-extension.sh`. **Verify it against the scripts, not
   against the ADR's summary of them.** If there is an intended path k16 missed —
   anything that puts the repo or the extension on a cask user's machine — the
   argument collapses and the status quo is a baseline again rather than a defect.

2. **"Auto-install is *dominated*" is the ADR's weakest word, and k16 knows it.**
   The claim is that silence buys nothing because the user must restart VSCode
   anyway. But *install-then-notify* is a fourth shape, and it is arguably
   **fewer** user actions than offer-then-confirm-then-restart. k16 rejected it on
   three grounds (an ambiguous trigger, an uninvited write, an orphan a plain
   uninstall leaves). Ask whether those support **rejected on consent** —
   defensible — or the stronger **dominated**, which they may not. If the word is
   too strong, the finding is that the ADR is arguing past a live option.

3. **Is the `configure!` precedent as close as k16 claims?** kitty, iTerm2 and
   alacritty write *configuration* into an app the user has already chosen to
   drive from Modaliser. This writes **executable code** into another app's
   extension directory, where it then runs on every window start, outlives
   Modaliser's uninstall, and is subject to that app's trust and profile rules.
   Same five-part shape; is it the same *kind* of act? If not, what does the
   dialog have to say that kitty's does not?

4. **The host-installed payload path.** ADR-0028 requires `(modaliser apps
   vscode)` to reach `Contents/Resources/` without knowing it, via a parameter
   `root.scm` installs at boot, defaulting to not-configured (ADR-0023's shape).
   Check it actually holds: that the portability contract is satisfied, that the
   default really makes `swift test` reach no bundle and no `~/.vscode`, and that
   the dev-vs-production divergence `SchemeEngine.resolveSchemeDirectory` branches
   on does not leave the parameter pointing at a tree that has no built payload in
   it (a `swift run` has never run `build-app.sh`).

5. **Two claims stated as structural that may only be asserted** — the BRIEF
   records this as k6's worst failure mode, so test both.
   *Freshness by construction*: ADR-0028 says a bundled payload cannot drift
   because the copy source is produced by the step before, provided `out/` is
   wiped first because `tsc` overwrites but does not prune. Does that give the
   ADR-0019 property or only resemble it?
   *Sweep in one place*: one shipped script performs sweep-and-copy and
   `install-vscode-extension.sh` delegates to it. Is there any path by which the
   `rm -rf` over `<publisher>.<name>-*` gets transcribed twice, or runs with a
   glob that could match more than this extension?

6. **Unchecked mechanical claims.** Two the ADR leans on without evidence in the
   tree: that a Homebrew cask `zap trash:` accepts a glob (needed for
   `~/.vscode/extensions/<publisher>.<name>-*`), and that a shell script shipped
   inside a signed `.app` and invoked through `(modaliser shell)` runs without
   signature or quarantine trouble. Either failing changes the mechanism.

7. **The Marketplace call is the one a reviewer should push hardest**, because it
   is the option that keeps the extension's independent cadence — the reason the
   original separation existed, and the one thing ADR-0028 knowingly spends. k16
   rejected it on ongoing obligation and on reversibility, and explicitly recorded
   that whether that obligation is worth paying is **the human's to price**. Test
   whether the reversibility argument is sound, and whether the reopen conditions
   are conditions someone would actually notice.

## Done when

- ADR-0028 has been read against `release-build.sh`, `build-app.sh`,
  `install-vscode-extension.sh`, `scripts/templates/modaliser.rb.tmpl`,
  `apps/kitty.sld`'s `configure!`, and ADR-0019 / ADR-0021 / ADR-0023 / ADR-0026 —
  the sources, not the ADR's account of them.
- Each doubt above is answered, confirmed or dismissed, and any finding k16 did
  not anticipate is recorded beside them. The list is k16's; it is not the scope.
- `ADR-FORMAT.md`'s test is applied to the pair: is `docs/adr/` still a **minimum
  coherent set**, with no two live records asserting different answers to the same
  question, and every citation of the reworked ADR-0026 paragraph still true?
- The five files left standing are checked for completeness and for honesty —
  a doc describing a mechanism that does not exist yet is a defect even when it is
  scheduled.
- Findings only. If there is nothing worth acting on, this leaf creates nothing
  and retires; otherwise it cuts `integrate-review-design` with the same stem.

## Notes

- `CLAUDE.md` overrules grove's slug-only ADR naming in this repo: numbered
  filenames, bare `ADR-00NN` citations. Do not report that as a defect.
- k16's `## Decisions (running log)` carries the reasoning behind every choice in
  the ADR, including the ones the ADR states without their derivation. Read it
  before concluding a claim is unsupported.

## Findings

### F1 — high — the payload-path seam has no host-side source

ADR-0028 says `(modaliser apps vscode)` receives a payload-directory parameter
from `root.scm`, because only the host knows the difference between a dev tree and
an installed app (`docs/adr/0028-companion-extension-ships-in-the-app-and-installs-on-request.md:106-116`).
That specifies the library side of the seam but not the adapter that supplies it.
Today Swift exposes only `*scheme-directory*` to Scheme
(`Sources/Modaliser/SchemeEngine.swift:160-189`). In production that value is
deliberately replaced with the `~/.config/modaliser/sys/scheme` mirror, while the
new payload is to live directly under `Contents/Resources`; in development it is
`Sources/Modaliser/Scheme` and `swift run` has never assembled a payload
(`Sources/Modaliser/SchemeEngine.swift:301-335`). `root.scm` can install the
existing socket pointer because its default is derived from `$HOME`; it has no
equivalent source for `Bundle.main.resourceURL`
(`Sources/Modaliser/Scheme/root.scm:45-62,92-102`).

The implementation leaf would therefore have to invent an unrecorded
Swift-to-Scheme interface, derive a brittle path from the Scheme mirror, or
hard-code an installed-app location. That also conflicts with ADR-0028's claim
that “no new native surface appears” (`:134-139`). The design should name the
host input explicitly — for example a resource-root binding installed by
`SchemeEngine` before `root.scm` — and state its installed-app, `swift run`, and
bare-test values before k18 implements the seam.

### F2 — high — the cleanup glob can delete a different extension

The promised safety property is “this extension, and only this extension,” but
the existing rule is
`find ... -name "${PUBLISHER}.${NAME}-*" -exec rm -rf ...`
(`scripts/install-vscode-extension.sh:33-55`), and ADR-0028 carries the same
`<publisher>.<name>-*` pattern into both install-time sweep and cask zap
(`docs/adr/0028-companion-extension-ships-in-the-app-and-installs-on-request.md:118-123,211-215`).
VSCode extension names may contain hyphens — this one's name is itself
`modaliser-companion` (`vscode-extension/package.json:2`) — so the pattern also
matches a distinct sibling such as
`antony.modaliser-companion-beta-1.0.0`. It distinguishes neither the extension
name boundary nor a version suffix.

This directly fails k18's requirement that the destructive glob be incapable of
matching anything else (`.grove/19-impl--vscode-companion-install-k18.md:52-58`),
and the planned `zap trash:` repeats the same overmatch. The design needs an
extension-exact selection rule — for example validating each candidate's
manifest identity before deletion — or it must narrow the claimed invariant and
explicitly reserve the whole publisher/name prefix. Sharing one transcription
does not make an over-broad transcription safe.

### F3 — high — the stale-document enumeration omits the README that will ship in the payload

ADR-0028 requires `vscode-extension/README.md` to be copied into the bundled
payload (`docs/adr/0028-companion-extension-ships-in-the-app-and-installs-on-request.md:66-70`).
That README still instructs the reader to run the repository-only installer and
says the extension remains deliberately separate with its own upgrade cadence
(`vscode-extension/README.md:14-29`). It is not one of the five files handed to
k18 (`.grove/19-impl--vscode-companion-install-k18.md:79-95,128-129`). If k18
satisfies its stated Done-when exactly, the new app will bundle a README that
asserts the decision ADR-0028 just reversed and names a script unavailable to a
cask user — the same defect the ADR exists to remove.

Add this sixth file to the implementation handoff and reconcile it as part of
the payload. The broader transition prose should also distinguish “the source
checkout's installer is what runs until k18 lands” from “separate cadence is the
current decision”: `README.md`, `docs/reference/libraries.md` and
`apps/vscode.sld` still assert the latter
(`README.md:44-56`; `docs/reference/libraries.md:861-877`;
`Sources/Modaliser/Scheme/lib/modaliser/apps/vscode.sld:200-212`). Scheduling
their replacement does not make those present-tense rationale claims coherent
with the new current-state ADR.

### F4 — medium — the `configure!` precedent does not establish equivalent consent

ADR-0028 says kitty, iTerm and Alacritty all have the same five-part operation,
including a closing relaunch instruction, and uses the three instances to treat
the act as an established house pattern
(`docs/adr/0028-companion-extension-ships-in-the-app-and-installs-on-request.md:50-57`).
The source is narrower. Kitty edits a text config and asks the user to relaunch
(`Sources/Modaliser/Scheme/lib/modaliser/apps/kitty.sld:395-431`); iTerm edits
preferences and performs its own quit/relaunch asynchronously
(`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld:490-531`); Alacritty only
removes a quarantine xattr and explicitly says the app is otherwise unchanged
(`Sources/Modaliser/Scheme/lib/modaliser/apps/alacritty.sld:211-241`). Only the
confirm/idempotence/hidden-gate mechanics are genuinely shared.

None of those operations installs executable code that activates in every
VSCode window and survives a plain Modaliser uninstall. The proposed dialog
enumeration names source, destination, removed versions and restart, but not
those two durable effects (`docs/adr/0028-companion-extension-ships-in-the-app-and-installs-on-request.md:125-132`).
The operation shape is a useful UI/test seam; it is not a consent precedent for
the kind of write being performed. The ADR should narrow the analogy and require
the dialog to disclose that it installs automatically activating extension code
and that only `brew uninstall --zap`, not a plain uninstall, removes it.

### F5 — medium — offer-and-confirm does not strictly dominate install-then-notify

The rejected automatic option assumes the only trigger is an ambiguous `parts`
miss and concludes that a forced user-visible moment makes offer-and-confirm
strictly dominant
(`docs/adr/0028-companion-extension-ships-in-the-app-and-installs-on-request.md:152-161`).
But the chosen design itself creates a reliable trigger: the exact bundled
version's installed-directory test (`:97-104`). On that signal Modaliser could
install automatically and then notify the user to restart VSCode. That shape is
not silent, repairs future presses after the restart, and costs one fewer user
action than offer → confirm → restart.

The selected answer can still win on informed consent and on avoiding an orphan
after a plain uninstall, but it is not structurally dominant. Recast this as a
consent trade-off and price install-then-notify honestly; the recorded reopen
condition is also wrong because the design already supplies the “is this bundled
version installed?” half it says is missing.

### F6 — medium — the Marketplace rejection overstates both unreadiness and reversibility

ADR-0028 treats `"private": true` as evidence that the manifest is not
Marketplace-ready and uses reversibility as the tie-break: bundling supposedly
stops by dropping the payload and changing the row, while a published extension
cannot be quietly withdrawn
(`docs/adr/0028-companion-extension-ships-in-the-app-and-installs-on-request.md:172-190`;
`vscode-extension/package.json:6-8`). The current official `vsce` implementation
does not consult npm's `private` field for that purpose: its manifest processor
sets Marketplace packages to `Public`, and the long-standing upstream report
states that `vsce package`/`publish` ignore `private`.
See <https://github.com/microsoft/vscode-vsce/blob/main/src/package.ts> and
<https://github.com/microsoft/vscode-vsce/issues/597>.

The reversibility asymmetry is also incomplete. Stopping bundling does not
remove copies already installed under `~/.vscode/extensions`; ADR-0028 itself
says plain uninstall leaves them (`:125-132`). Conversely, the Marketplace
supports unpublishing or removing an extension, albeit with consequences, and
VSCode documents those operations explicitly:
<https://code.visualstudio.com/api/working-with-extensions/publishing-extension>.
Both channels leave migration work once users have installed a copy. Ongoing
publishing/authentication cost and skew direction are real reasons to defer the
Marketplace, but `private` and one-sided reversibility are not. The first reopen
condition — “gains VSCode users who are not the maintainer” — is also not
observable without telemetry; make it an event the maintainer can actually see,
such as an external user's Marketplace request, or retain only the already
observable extension-only-release condition.

## Decisions (running log)

**The load-bearing release fact is confirmed.** `assemble_bundle` stages only
`Modaliser.app`, `README.md` and optional `LICENSE`, and `package_bundle` tars
exactly those entries (`scripts/release-build.sh:67-90`). The cask installs only
the app (`scripts/templates/modaliser.rb.tmpl:1-23`). No release path puts
`scripts/` or `vscode-extension/` on the cask user's machine, so the status quo
really is unreachable rather than merely inconvenient.

**Freshness by construction is sound if k18 follows the stated order.** The
current extension build compiles both `src` and `test` into `out`
(`vscode-extension/package.json:31-41`; `vscode-extension/tsconfig.json:7-19`),
and the design wipes `out` before building and copies only `out/src`. Together
with `build-app.sh`'s existing whole-app wipe (`scripts/build-app.sh:15-25`),
that makes deleted source unable to survive in either compilation output or the
bundle. This is not ADR-0019's exact-mirror check, and ADR-0028 correctly avoids
claiming it is.

**One sweep source is the right count; F2 is about its predicate.** A source
script copied into the app and called by the source-checkout installer gives two
entry points one maintained deletion rule. No second current transcription was
found outside the cask's separate zap policy. The defect is that the selected
prefix is not extension-exact.

**The two external mechanics are cleared against primary sources.** Homebrew's
official Cask Cookbook says `trash:` follows `delete:` path rules and those rules
perform glob expansion, so `zap trash:` can accept a glob:
<https://docs.brew.sh/Cask-Cookbook>. Apple's Code Signing Guide explicitly says
shell scripts and other non-Mach-O executables belong in `Contents/Resources`,
where the outer signature seals them in `CodeResources`:
<https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html>.
`release-build.sh` re-signs after bundle assembly
(`scripts/release-build.sh:50-64`), and the cask strips quarantine recursively
from the installed app (`scripts/templates/modaliser.rb.tmpl:15-21`). The
location/invocation shape is therefore supported; k18 should still perform the
requested end-to-end installed-app drive.

**ADR-0026 and ADR-0028 are the right two-record grain.** ADR-0026 answers where
window parts come from; ADR-0028 answers distribution and consent. The former's
reworked consequence explicitly hands distribution over, and its remaining
citations refer to source choice, protocol skew, exposure or peer addressing,
all of which remain true. No live record was found asserting the old
distribution answer alongside ADR-0028; F3 is a documentation/handoff defect,
not a second live ADR.

**Every producer doubt is resolved by a finding or a clearance above.** F1
answers the host-path question; F2 the destructive sweep; F3 the stale-file
enumeration; F4 the precedent/consent question; F5 automatic installation; F6
the Marketplace. The cask-user premise, build freshness, script placement,
Homebrew glob support, ADR grain and ADR-0026 citation reconciliation are
cleared.

**Coverage limitation.** The review inspected producer commit
`tyzpurkv`/`8006e562`, its complete changed-file summary and artifact diff, the
producer decision log, ADR-0019/0021/0023/0026/0027/0028, the changed spec
section, every named script/library source, both task handoffs, repository
summary layers, and primary Homebrew/Apple/VSCode sources. Candidate stale
assertions were enumerated with hidden Grove files included and every relevant
hit classified. The codebase-memory CLI was attempted three times first, but
refused to start because a pre-coordination or unverified generation was active;
typed graph tools were unavailable. Exact source reads and targeted `rg` sweeps
supplied the evidence instead, and no negative claim relies on an empty graph
result. Per `review-design`, no build, test, lint, formatter, or live UI drive
was run, and no production, test, ADR, or spec file was edited.
