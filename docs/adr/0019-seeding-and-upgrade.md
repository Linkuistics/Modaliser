# Seed preference once; mirror shipped code always-fresh; upgrade by diff

First run seeds exactly one user-owned file, `~/.config/modaliser/config.scm`,
copied from the bundled default and never touched again. Everything Modaliser
ships-and-improves — libraries, UI plumbing, assets, and the current default
config itself — reaches the user through the **sys/ mirror**: the whole
bundled `Scheme/` tree, wiped and re-copied to `~/.config/modaliser/sys/scheme/`
whenever the bundle fingerprint changes, read-only in contract and presented
as such (a generated `sys/README.md`). Every hop along that chain **replaces
rather than merges**: `build-app.sh` wipes the `.app` before assembling it and
fails the build unless the bundled `Scheme/` tree matches
`Sources/Modaliser/Scheme/` exactly, `install.sh` wipes
`/Applications/Modaliser.app`, `release-build.sh` wipes `dist/`, and `SysSync`
wipes the mirror. One merging hop reintroduces the whole bug class silently, a
step further upstream than anyone looks: a `cp -R` into a surviving bundle
shipped five libraries retired months earlier, and a user config importing one
of them **resolved**. The seeded default authors **every**
screen **inline from library utilities**: preference — keys, labels, panels —
lives in the user's file; machinery (helpers, blocks, protocols, ops) lives in
libraries and stays current. No screen is exempt — ADR-0021 draws that line and
enforces it. A composition a fresh install does not run ships as a
never-loaded `Scheme/examples/*.scm`, carried always-fresh by the same mirror
and copied in by hand. There is no other upgrade
mechanism: library improvements arrive on the next launch after an install;
preference improvements never auto-apply — the user diffs their `config.scm`
against the mirrored `sys/scheme/default-config.scm` when curious; a breaking
library change fails loudly at load with nothing installed (ADR-0018).

## Why it binds

The two tiers have opposite update behaviours, so whatever sits in the wrong
tier produces a recurring bug class: shipped machinery seeded once goes stale
in every existing config (the "feature works in source, not live" hunt), and
user preference in the fresh tier would be overwritten on every install. The
configuration-value model (ADR-0018) made the split expressible — wiring
moved into constructors — and this decision finishes it: the seeded tier can
no longer strand anything Modaliser improves, because it contains only
composition and preference. Costly to reverse: the seeding code path, the
default config's authored shape, the library surface (utilities exported per
app), and the docs' upgrade contract all encode it.

## Considered options

1. **Keep shipped per-app screens seeded** (`app-trees/`, the status quo).
   Rejected: they are shipped content with real machinery (Dia's AppleScript
   tab enumeration), frozen at each user's first run — the stale-seed class
   this decision closes. Reopened by: nothing.
2. **Stock factories in the seed** (`(dia:fragment)` one-liners). Rejected:
   the user's actual preference — which keys, which labels — hides inside
   library code, and customising means learning the rebuild-from-blocks
   story before touching a binding. The seed is user space; preference
   belongs in it, visibly. This holds for **every** screen: the carve-out
   this decision once made for "machinery with near-zero preference (iTerm,
   herdr)" was measurably false — those two carried 47 and 37 authored
   key/label decisions — and ADR-0021 removes it. Reopened by: nothing.
3. **Lib-only mirror** (mirror `lib/modaliser` only, as the docs once
   described). Rejected: production reads `root.scm`, `ui/`, and assets via
   `*scheme-directory*` from the mirror; splitting resolution between mirror
   and bundle adds a dev-vs-prod divergence for no reader benefit — the
   whole tree is legitimately browsable and forkable. Reopened by: nothing.
4. **Auto-resync or merge the seeded config on upgrade.** Rejected: any
   write to the user's file violates its ownership; merge machinery is the
   collision problem reinvented. Reopened by: nothing.
5. **Version stamp + startup nudge, or a migration-notes doc.** Rejected on
   cost: both add ongoing discipline to every release, and the manual diff
   against the mirrored default already answers "what changed". The original
   rejection also leaned on "no external users yet" — that is no longer true
   (public at v3.3.0 behind a Homebrew cask), so only the cost argument
   still carries it. Reopened by: external users hitting silent staleness —
   a preference improvement that never reaches an existing config because
   nothing told anyone to look.

## Consequences

- First-run seeding is one file copy; the `app-trees/` seed step and its
  directory retire.
- The `.app` is a pure function of the source tree, checked at build time, so a
  resource deleted from `Sources/` cannot survive into a release. Nothing
  downstream — install, mirror, cask — carries pruning logic of its own.
- Per-app machinery becomes library surface (first: `(modaliser apps dia)`),
  covered by the portability contract and the LispKit-evaluation tests.
- The mirrored `default-config.scm` doubles as the reference for "what would
  a fresh install look like" — the manual-diff upgrade path.
- A user's config can only fail loudly or run against current libraries;
  there is no silently-stale integration state. Loudly no longer means
  fatally: ADR-0022 degrades a failed load to the bundled default with the
  status-bar menu intact, which is the precondition that let ADR-0021 widen
  the named library surface.
