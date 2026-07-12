# navigation-graph-next-edges-k5 — brief

## Goal

Implement ADR-0015: the navigation tree becomes a static graph. Declared
`'next` edges replace `'sticky-target`; terminality (no outgoing edge) is
static; dispatch releases modal capture *before* running a terminal node's
action; stickiness is derived, never declared.

## Why this decomposed

Investigating the migration inventory (grep across `Sources/Modaliser/Scheme`)
turned up a bigger blast radius than the leaf brief assumed: the overlay
renderer (`ui/overlay.scm` + `overlay.js` + `base.css`) reads `node-sticky-target`
/ `deepest-sticky-on-path` directly to paint the ↻ marker and the `.sticky`
container class, `modal-step-back`'s root-backspace branch depends on
`in-sticky-context?`, and a fourth in-tree sticky group (`com.tdesktop.Telegram.scm:15`,
not in the original inventory) plus its user-config mirror also need migrating.
Five test files (`SchemeCoreSmokeTests`, `ConfigDslTests`, `LayoutDslTests`,
`OverlayRenderTests`, plus the iterm/herdr library tests) assert on the old
vocabulary. That's a single, tightly-coupled flag-day rename (no dual-surface
shim, per house style) too large for one session.

The **seven `focus-pane-by-digit` slots** (Context item 3 in the original
brief) turn out to be separable: they call `enter-mode!` imperatively today,
independent of the `'sticky`/`'sticky-target`/`sticky-set` flag mechanism
entirely. They only *depend on* the new `'next`/terminal dispatch existing —
they don't participate in the sticky-flag migration. So they split cleanly
into their own leaf, sequenced after the core lands, with `enter-mode!`'s
un-export (truly framework-internal) deferred to that second leaf — until
then it stays exported so the seven backends' current direct calls keep
working undisturbed while the core lands.

## Decomposition

- 01 `next-edge-core-and-migration-k6` — `state-machine.sld` + `dsl.sld`
  (the `'next`/terminal/dispatch model; `walk` replaces `sticky-set`); the
  overlay renderer's sticky→walk/next rename; every `'sticky #t` /
  `'sticky-target` / `sticky-set` call site (herdr.sld, iterm.sld, the four
  app-trees files × their `~/.config/modaliser/` mirrors); docs
  (`state-machine.md`, `dsl.md`); the five affected test files. Keeps
  `enter-mode!` exported (the seven backends still call it directly — untouched
  here). This is the atomic core: `swift test` must stay green throughout,
  which is why it isn't split further.
- 02 (not yet added) — the seven `focus-pane-by-digit` slots → backend-record
  digit-mode-id + `terminal.sld` fire-time-resolved `'next` edge; un-export
  `enter-mode!`; update the how-to doc's generic-capability-tree example.

## Pointers (carried from the original leaf brief)

- ADR-0015 (`docs/adr/0015-navigation-graph-next-edges-terminal-release.md`).
- `CONTEXT.md` Modal-dispatch domain — **'next edge**, **Terminal**, **Walk**.
- Test seams: the existing e2e modal harness (`EndToEndSchemeModalTests`).

## Done when

Both children retired; `swift test` green (usual skips:
ModaliserAppsItermLibraryTests, HttpLibraryTests); portable-surface check
passes; a live smoke of one walk (herdr Move Pane) and one terminal release
(any digit-jump entry then Escape semantics) behaves per ADR-0015.

## Notes

- Grep guard: no `'sticky` / `sticky-set` / `sticky-target` left outside
  retired-terminology _Avoid_ notes and git history.
- The k2/k3 leaves depend only on child 01 (the core dispatch semantics);
  they don't touch the digit-jump façade in child 02.
