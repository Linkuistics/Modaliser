# vscode-companion-install-k21

## Goal

A fresh-context adversarial read of what `vscode-companion-install-k18` built:
the companion payload's build, its install op, and the one script that deletes
directories inside another application. Findings only, no fixes.

**Why this chain exists.** k18 spent its own in-session review allowance on the
sweep script and the consent path, and that reviewer found **six real defects,
all reproduced** — a merge-copy that silently shipped stale code as current, a
self-install that destroyed the payload, a confirmed write that could fail in
total silence, a half-finished copy that read as installed and hid the only row
that could repair it, a symlinked copy the sweep skipped, and a precondition
checked after the bundle wipe. k18 applied all six. Five of those fixes were
substantive rather than mechanical, which is the signal `references/execute.md`
names: review here is tree-sized work, so it is scheduled rather than run a
second time in-session. **Read the committed artifact, not k18's account of it.**

## Context

**What this code can do that most of the tree cannot.** It removes directories
under `~/.vscode/extensions` — another application's state, outside
`~/.config/modaliser`, which ADR-0028 records as the first time Modaliser writes
there. Everything else in the repo either stays inside its own config directory
or drives a tool that owns its own state. So the standard of evidence here is
higher than "the tests pass", and the question to keep asking is *what does this
delete that it should not, and what does it fail to delete that it must.*

**The artifacts.**

    scripts/install-companion-payload.sh     the sweep and copy — the sharp one
    scripts/install-vscode-extension.sh      the developer entry point, delegating
    scripts/build-app.sh                     the payload block
    Sources/Modaliser/SchemeEngine.swift     *bundle-resources-directory*
    Sources/Modaliser/Scheme/root.scm        the parameter install
    …/lib/modaliser/apps/vscode.sld          install-companion!, companion-installed?
    …/Scheme/examples/vscode.scm             the row
    Tests/…/ModaliserAppsVscodeCompanionInstallTests.swift
    scripts/templates/modaliser.rb.tmpl      the zap entry
    scripts/release-doctor.sh                the npm row

**The contract they must satisfy** — ADR-0028 is the authority; this is the
short form, and where it and the ADR differ the ADR wins.

- The sweep removes **this extension and nothing else**. The glob
  `<publisher>.<name>-*` is a candidate filter only, because extension names may
  contain hyphens and `antony.modaliser-companion-beta-1.0.0` is a different
  extension that must survive; each candidate is confirmed against its own
  `package.json`. The cask's `zap trash:` deliberately claims *less* — it
  reserves the whole prefix, because a path list cannot run a check.
- **Nothing reaches `~/.vscode` without a confirmed dialog**, and the dialog
  carries two disclosures kitty's has no need to: this installs code that
  activates in every VSCode window, and a plain `brew uninstall` leaves it.
- **Unconfigured is not-installed.** No payload (a `swift run`; a bare
  `SchemeEngine()` under `swift test`) ⇒ the predicate answers not-installed and
  the op is a no-op that logs why. Never an error, never a guessed path, never a
  spawn. This is what keeps the suite off both the bundle and `~/.vscode`
  (ADR-0023).
- **"Installed" means the copy completed**, not that a directory exists — the
  row gates on it, so a false positive hides the repair.
- `build-app.sh` produces the payload and the `Scheme/` exact-mirror check
  (ADR-0019) keeps passing untouched. The payload is deliberately *not* under
  that invariant.

**Where to be most adversarial.** In k18's own reading, the confirmed decision —
the manifest check — was correct, and every defect lived in what happened
*around* it: ordering, error propagation, what a partial failure leaves behind.
Look there first, and look at the seams *between* the pieces rather than at each
piece alone: the script and the Scheme predicate must agree on what "installed"
means; `build-app.sh` and the op must agree on where the three siblings are;
the cask and the sweep must not claim the same strength.

Two properties are asserted rather than made structural, and asserted properties
are what k6's review found worst in this grove — check both against the source:
(1) that the payload is the only thing under `Contents/Resources` matching what
the op reaches for, and (2) that `swift test` cannot reach `~/.vscode`.

## Done when

- Every artifact above has been read, and each contract clause is either
  confirmed against the source or has a finding against it.
- Findings are specific: file:line, the defect in one sentence, and a **concrete
  failure scenario** — inputs or state → wrong outcome. A concern without a
  scenario is noise and belongs in the noise list, not the findings.
- Anything reproducible has been reproduced against a scratch extensions
  directory. Nothing in this review writes to the real `~/.vscode`, installs to
  `/Applications`, or restarts anything of the human's.
- No fixes. If nothing survives, say so plainly — a clean read is a result.

## Notes

- k18's task file carries its running decision log and its classification of the
  first review's findings. Read it **after** forming your own view, not before;
  it is an account of the work by the party that did it.
- `docs/adr/0028-…` is the contract. ADR-0026 (why a companion at all, and why a
  miss is an empty panel), ADR-0019 (wipe-before-assemble, and where the
  exact-mirror invariant stops), ADR-0021 (no library authors a key or a label),
  ADR-0023 (the inert-by-default seams), ADR-0025 (portable Scheme never indexes
  a string), ADR-0027 (no directory listing in the portable tree).
- The human's own machine already carries an installed copy of this extension.
  It is not yours to touch.
