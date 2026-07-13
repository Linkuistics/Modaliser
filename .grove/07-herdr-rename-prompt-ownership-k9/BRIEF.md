# herdr-rename-prompt-ownership-k9 — brief

## Goal

A Scheme-driven parameter-collection-then-continuation UI primitive,
generalizing the existing chooser panel — started from the narrow case that
surfaced the need: herdr's `tab rename` / `workspace rename` ops require a
label herdr 0.7.3 has no prompt-on-missing-arg feature to collect, so
Modaliser's bare async fire (`herdr tab rename <id>`, no label) just hits
herdr's own usage-error exit — no UI ever opens. Reopens the k4-era "herdr
prompts are herdr's own UI" decision, but narrowly: `herdr worktree
create`/`worktree remove` were checked against `herdr worktree --help` and
have no required arg Modaliser omits, so they keep the old story unchanged
(no gap to fix). Only the two rename ops move to a Modaliser-owned prompt.

## Done when

The first child (`chooser-prompt-herdr-rename-k10`) lands: a `chooser-prompt`
primitive reusing the chooser's activating-WebView-panel machinery in a new
mode (no result list; Enter submits the typed value via a closure
continuation, mirroring `dialog-confirm`'s CPS shape), wired into
`rename-focused-tab!` / `rename-focused-workspace!` with the input pre-filled
from the focused id's current `label` (`herdr tab list` / `workspace list`).
ADR-0014 and the root `BRIEF.md` are already reworked in place as part of
this planning session (see Pointers) — the child leaf implements what they
now state. Further children, if any, sharpen the general primitive beyond
this first slice; none are required for this node to retire.

## Decomposition

- 01 `chooser-prompt-herdr-rename-k10` — the narrow, independently-demoable
  slice: the `chooser-prompt` primitive plus the two herdr call sites.

## Pointers

- ADR-0014 (`docs/adr/0014-interactive-commands-never-block.md`) — reworked
  in place this session to split "herdr's own UI" (worktree create/remove,
  unchanged) from "Modaliser-owned prompt" (rename ops, new).
- Root `BRIEF.md` Goal, bullet 2 — same rework, same session.
- `Sources/Modaliser/Scheme/ui/chooser.scm` / `chooser.js` — the panel
  machinery `chooser-prompt` extends: activating WKWebView panel
  (`'activating #t`, real Cocoa keyboard focus, no CGEvent capture
  involved), message-handler round-trip, `webview-create`/`webview-close`/
  `webview-set-html!`/`webview-on-message`. `chooser.js`'s `sendSelect`
  currently returns early when `chooserItems.length === 0` — there is no
  existing path for submitting raw typed text, only picking a list item.
- `(modaliser state-machine)` — the deferred-hook indirection pattern
  `open-chooser`/`set-open-chooser!`/`chooser-open?` uses to let a portable
  `(modaliser ...)` library call into a host-specific `ui/*.scm` file
  without importing it directly. `chooser-prompt` needs the same shape of
  hook so `herdr.sld` (portable tree) can call it.
- `Tests/ModaliserTests/ChooserRenderTests.swift` — stubs
  `webview-create`/`webview-close`/`webview-set-html!`/`webview-on-message`
  at the Scheme level to test `ui/chooser.scm` without a real WKWebView;
  the pattern to mirror for `chooser-prompt`'s tests.
- `Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld` (~lines 377–390)
  — `rename-focused-tab!` / `rename-focused-workspace!`, and the existing
  `current-herdr-async-runner` / `current-herdr-query-runner` test seams the
  rewired ops still fire through.
- `(modaliser dialogs)` — the architectural sibling: `chooser-prompt` is a
  self-contained async action a terminal leaf calls directly (continuation
  via closure), same shape as `dialog-confirm`, not a `'selector` tree-node
  kind — no `(modaliser state-machine)` *dispatch* integration needed
  (ADR-0015 already releases capture before a terminal leaf's action runs).

## On the horizon

- The general "parameter-collection UI, up to complete applications"
  ambition is real but too dim to leaf yet. Sharpen it once a second
  concrete use case beyond herdr rename makes the general shape legible.

## Notes

- Surfaced live-testing `herdr-dialogs-async-k2`'s async firing, after
  `provision-scripts-async-k8` retired — not part of either leaf's scope.
