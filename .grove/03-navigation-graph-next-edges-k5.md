# navigation-graph-next-edges-k5

**Kind:** work

## Goal

Implement ADR-0015: the navigation tree becomes a static graph. Declared
`'next` edges replace `'sticky-target`; terminality (no outgoing edge) is
static; dispatch releases modal capture *before* running a terminal node's
action; stickiness is derived, never declared.

## Context

1. **`state-machine.sld`.** In the command / range-command branches: a leaf
   with no `'next` and no compiled cycle → `(modal-exit)` **before** the
   action; a cyclic edge re-arms the collection in place **without pushing
   `modal-stack`** (verify the suspected per-press push wart noted in
   ADR-0015 while here); a cross edge enters the target mode (push, as
   `enter-mode!` does today). Retire `node-sticky?`, `in-sticky-context?`,
   `deepest-sticky-on-path`, `modal-reset-to-sticky-ancestor` (or reduce to
   internals of edge-following). `enter-mode!` stops being part of the
   config-facing story (framework-internal; un-document, keep or unexport per
   what root.scm/ui need). Selector dispatch becomes an instance of the
   terminal rule. `'exit-on-unknown` untouched.
2. **`dsl.sld`.** `key-cmd`: `'sticky-target` → `'next` (values: registered
   collection id | `'self`). `sticky-set` → `walk` (same lowering, stamps
   `'next <id>` on members; drop the group `'sticky` flag it set —
   `'exit-on-unknown #t` stays). `group`/`screen`/`open` drop the `'sticky`
   keyword. A compile/registration pass resolves `'self` to the containing
   group. Update the `key` doc comment (dsl.sld:527 canonical example
   changes — no more `enter-mode!` in an action).
3. **The seven `focus-pane-by-digit` slots** (`ghostty` 313, `iterm` 661,
   `kitty` 686, `wezterm` 355, `tmux` 376, `zellij` 418, `herdr` 281 — at
   k4 time): the backend-record slot carries the digit-mode id, not a thunk;
   the `terminal.sld:286` façade exposes a declared edge whose target
   resolves at fire time (frontmost backend). Fail-safe: unresolvable target
   → keep capture, normal cleanup.
4. **Migrate every sticky usage** (inventory at k4 time, excluding `sys/`):
   in-tree `'sticky #t` groups — herdr.sld:621 (Move Pane), iterm.sld:563 +
   585, `app-trees/com.apple.MobileSMS.scm:16`,
   `app-trees/company.thebrowser.dia.scm:124` → per-leaf `'next 'self`;
   registered sticky modes — herdr.sld:582 (`herdr-panes-focus`),
   iterm.sld:198 — flag dropped, members get edges; `sticky-set` call sites
   — dia.scm:104, `com.googlecode.iterm2.scm:79` + 92 → `walk`; the hjkl
   `'sticky-target` keys (herdr.sld:611-614, iterm.sld:543-546) → `'next`.
   Check the live user config (`~/.config/modaliser/`) for the same
   patterns and migrate it too (feedback_config_sync: sync config ↔
   default-config/app-trees both ways).
5. **Docs.** `docs/reference/state-machine.md` + `dsl.md` (and any other
   reference doc naming sticky) rewritten to the graph vocabulary
   (`'next`, terminal, walk). CONTEXT.md already carries the terms.
6. **Tests.** Through the existing e2e modal harness
   (`EndToEndSchemeModalTests`): release-before-terminal ordering (a test
   action observes `modal-active?` already #f), cyclic re-arm with no
   `modal-stack` growth, `'next 'self` resolution, `walk` lowering,
   cross-edge push, dynamic-target `#f` fallback. Migrated-backend tests
   stay green; `scripts/check-portable-surface.sh` passes.

## Done when

- All of Context lands (decompose per the grove skill if it proves bigger
  than one session); `swift test` green (usual skips:
  ModaliserAppsItermLibraryTests, HttpLibraryTests); portable-surface check
  passes; a live smoke of one walk (herdr Move Pane) and one terminal
  release (any digit-jump entry then Escape semantics) behaves per ADR-0015.

## Notes

- Grep guard: no `'sticky` / `sticky-set` / `sticky-target` left outside
  retired-terminology _Avoid_ notes and git history.
- The k2/k3 leaves build on this: k2's herdr verbs and k3's error alerts are
  plain terminal leaves once this lands.
