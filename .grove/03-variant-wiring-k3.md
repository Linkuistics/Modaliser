# variant-wiring-k3

**Kind:** work

## Goal

Make the iTerm tree switch shape by the herdr situation: a **replace/augment
classifier**, the composed **context-suffix hook**, and the two **variant screens**
(skeleton) — so a leader press picks `/herdr` vs `/herdr+split` vs the plain tree.

## Context

Read the root `BRIEF.md`. Depends on leaf `herdr-backend-k2` (backend registered).
This is the leaf where the review's corrections land:

- **Classifier = current-tab session count via AppleScript** (R1), NOT
  `ax-find-elements-named` AXScrollArea count (that spans all tabs and would misfire on
  a herdr window with a second tab). Use the tab-scoped `iterm-list-session-ids` shape
  (`sessions of current tab of current window`). == 1 → `/herdr` (replace); the focused
  pane runs herdr AND > 1 → `/herdr+split` (augment); else fall through to the existing
  nvim/zellij branches / #f.
- **Export iTerm-direct pane ops** (or a `build-iterm-splits-drill` helper) from
  `apps/iterm.sld` (R2) — they're internal defines today, and the augment `i`-drill
  needs iterm-direct ops (the façade points at herdr when herdr is focused).
- **Compose the context-suffix hook** (R4): the user config must change from
  `(iterm:register! 'install-tree? #f)` to `… 'install-context-suffix? #f`, plus a
  custom `set-local-context-suffix!` that delegates the iTerm branch to
  `iterm:context-suffix-handler` and adds the herdr cases. The single global suffix
  slot is last-write-wins, so composition (not a second install) is mandatory.
- Register the two variant screens `com.googlecode.iterm2/herdr` and
  `com.googlecode.iterm2/herdr+split` (skeleton here; content is leaf 4).
- **Own ADR `docs/adr/0013-herdr-replace-vs-augment-tree.md`** (post-validation): the
  surprising, load-bearing decision — replace/augment keyed on current-tab split count,
  herdr-primary hjkl, direct-ops-not-façade. Follow the numbered-slug convention of the
  live ADRs 0009–0012; consult `linkuistics:decision-records`.

Heads-up: the variant-tree path has **never been exercised in production** (no `/nvim`
or `/zellij` screen ships) — herdr is its first real user, so test that
`resolve-app-tree` actually *resolves* the variant, not silently falls back.

## Done when

- Leader press: herdr sole split → `/herdr`; herdr + other current-tab splits →
  `/herdr+split`; no herdr → plain tree (unchanged). Verified live.
- Tests: the classifier (incl. the multi-tab trap), and variant-tree resolution.
- ADR-0013 written; config wired in `app-trees/com.googlecode.iterm2.scm` + bundled
  `default-config`/`app-trees` sync ([[feedback_config_sync]]).
- `swift test` + `check-portable-surface.sh` green.

## Notes

### Deliverables

- `apps/iterm.sld` — export `iterm-list-session-ids` (tab-scoped classifier
  count source) + new `build-iterm-splits-drill` (the augment `i` drill bound
  to iTerm-DIRECT ops, R2).
- `muxes/herdr.sld` — `classify-herdr-variant` (the R1 count→suffix
  replace/augment decision, host-agnostic pure) + `build-herdr-tree` (skeleton
  herdr variant tree: herdr owns top-level hjkl, herdr-direct). Kept
  host-agnostic; the iTerm glue lives in the config composition.
- `app-trees/com.googlecode.iterm2.scm` (bundled + user `~/.config`) —
  `(iterm:register! 'install-tree? #f 'install-context-suffix? #f)`,
  `(herdr:register!)`, the two variant screens, and the composed
  `set-local-context-suffix!` (herdr branch gated on `(terminal:in-chain?
  'herdr)` + tab-scoped count; else delegates to `iterm:context-suffix-handler
  … 'rebuild? #f`). `default-config.scm` + user `config.scm` gain the
  `(modaliser muxes herdr)` + `(modaliser event-dispatch)` imports.
- `docs/adr/0013-herdr-replace-vs-augment-tree.md`.
- Tests: `ModaliserMuxesHerdrLibraryTests` gains `classifierMapsCurrentTabSplitCount`,
  `treeBuildersAndItermExportsAreShapeCorrect`, and
  `variantTreeResolvesReplaceAugmentAndFallback` (R4 — asserts the variant
  RESOLVES, not falls back). `swift test` = 728 pass / 75 suites (with the
  pre-existing `ModaliserAppsItermLibraryTests` + `HttpLibraryTests` skips,
  [[project_iterm_tests_crash]]); `check-portable-surface.sh` green.

### Live verification (observed against the user's real iTerm + herdr client)

Ran the exact probes the classifier consumes against the running environment
(iTerm2 up, herdr client on `ttys010`, `herdr pane current` = `w9:p1`):

- **Replace path — OBSERVED.** The herdr iTerm tab (`ttys010`, fg `herdr`) holds
  exactly **1** session → classifier inputs `(herdr-focused #t, current-tab-count
  1)` → `/herdr`. The pure `classify-herdr-variant` maps `1 → "/herdr"` (unit
  tested).
- **Multi-tab trap — OBSERVED avoided.** iTerm had 10 tabs / 28 total sessions;
  the tab-scoped `id of every session of current tab` returned **1** for the
  herdr tab. An all-tabs AX count would have overcounted → wrong "augment". R1
  fix confirmed against the real layout.
- **Fall-through — OBSERVED.** iTerm's *current* window ran `grove do …` (3
  splits, no herdr) → classifier falls through to the plain tree. Correct.
- **Augment path** (`count > 1 → /herdr+split`): not present in the current
  layout (herdr is alone in its tab), so unit-tested only, not observed live.
- **Not done here:** the full F17→overlay→variant-tree *visual* confirmation in
  the installed app (needs `./scripts/install.sh` + the user's herdr iTerm
  window frontmost + a manual F17 press). Deferred to leaf 4, where the herdr
  tree gains real content and the same install+confirm applies — installing a
  hjkl-only skeleton mid-session onto the actively-working daily driver earns
  nothing. The switching *logic* is verified above; only the pixels aren't.
