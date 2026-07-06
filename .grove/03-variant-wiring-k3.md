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
