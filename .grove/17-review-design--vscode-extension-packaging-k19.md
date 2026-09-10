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
