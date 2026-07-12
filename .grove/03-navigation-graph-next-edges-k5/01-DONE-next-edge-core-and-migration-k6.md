# next-edge-core-and-migration-k6

**Kind:** work

## Goal

Land the `'next`-edge navigation model (ADR-0015) end to end: the dispatch
core in `state-machine.sld` + the DSL surface in `dsl.sld`, the overlay
renderer's rendering of it, and every existing `'sticky #t` / `'sticky-target`
/ `sticky-set` call site migrated to match — as one atomic, green-tests
commit. (The seven `focus-pane-by-digit` slots are a separate, later leaf —
see the parent `BRIEF.md`'s "Why this decomposed.")

## Design (resolved by investigation this session — implement per this, don't re-derive)

**`node-next` (state-machine.sld).** Replaces `node-sticky-target`. Reads the
`'next` alist entry, value is one of:
- a symbol naming a registered tree (a `register-tree!` scope/mode-id)
- the literal symbol `'self`
- a 0-arg procedure — a fire-time resolver, called with no args, returning a
  symbol or `#f` (the façade's dynamic case; not used by this leaf's own
  migrations, but the dispatch logic must support it since ADR-0015 requires
  it and the next leaf depends on it existing)

**Terminality is presence, not value.** `(node-terminal? node)` = `(not
(node-next node))` for command/range-command leaves. A node whose `'next` is
a procedure is NEVER terminal, even if the procedure resolves to `#f` at fire
time — "the *existence* of the edge is static" (ADR-0015). This is why
release-before-action only needs to check *presence* of `'next`, never call a
resolver first.

**Dispatch rewrite (`modal-handle-key`, command + range-command branches):**
1. `terminal? = (not (node-next child))`. If terminal, `(modal-exit)`
   **before** running the action (no reason arg — matches today's default
   'exit path, not 'confirm/'cancel).
2. Run the action (unchanged: `(action)` / `(action char)`).
3. Guard: if the action itself already changed modal state (root-node
   identity check, exactly as today — some legacy safety net), do nothing
   further.
4. If terminal, nothing further (already exited in step 1).
5. Else resolve `next`: if it's a procedure, call it (0 args) to get a
   symbol-or-`#f`; otherwise use it as-is (a symbol or `'self`).
   - `target` is `'self` → **cyclic**: no navigation change (firing a leaf
     never moves `modal-current-node`/`path` — they're already correct), no
     stack push; just `(update-overlay …)` if the overlay is open.
   - `target` is a symbol and `(eq? (lookup-tree target) modal-root-node)` →
     **also cyclic** (same tree, reached via a symbol rather than `'self` —
     this is how a *registered* mode's own members could in principle refer
     to themselves by id; not used by any current call site, which all use
     `'self`, but keep the check for correctness/symmetry).
   - `target` is a symbol whose `lookup-tree` is a *different* tree (or the
     current one isn't it) → **cross**: `(enter-mode! target)` — push +
     switch, the exact mechanics `enter-mode!` already implements today.
   - `target` is `#f` (dynamic resolver declined) → **fail-safe**:
     `(modal-exit)` — capture was kept through the action (never released
     before it, since the node wasn't terminal), and this is the "normal
     cleanup" ADR-0015 calls for when a dynamic edge can't resolve.

**Retire:** `node-sticky?`, `deepest-sticky-on-path`, `in-sticky-context?`,
`modal-reset-to-sticky-ancestor`. Keep `any-on-path?` (still used by
`exit-on-unknown-context?`, which is unaffected — `'exit-on-unknown` is an
unknown-key policy, orthogonal to edges). Remove `'sticky` keyword parsing
from `register-tree!` (the `sticky` accumulator + case branch), from `group`,
`screen`, `open` (dsl.sld).

**`modal-step-back` simplification.** The old root-of-path branch was a
3-way split: transient root (no-op) / sticky root with a caller (pop stack) /
sticky root with no caller (exit). Since there's no more per-tree sticky
flag to distinguish "sticky root" from "transient root," and in every real
usage a walk-registered tree is *only* ever entered via a cross-edge push
(never bound directly to a leader), the 3-way collapses to 2-way: **pop the
stack if non-empty, else no-op.** The "sticky root, empty stack → exit"
branch is now unreachable dead code, not a behaviour this migration needs to
preserve. Mirror the same simplification in `ui/overlay.scm`'s
`back-available-for-path?` (drop the `in-sticky-context?` check; `(or (not
(null? path)) (not (modal-stack-empty?)))`).

**`enter-mode!`.** Keep its implementation exactly as-is (it already does
"push if active, else become the root" — precisely what a cross-edge needs).
**Do not un-export it this leaf** — the seven backends still call it directly
today (`(enter-mode! 'xxx-pane-digit)`); un-exporting now would break their
Scheme import and is out of scope until the next leaf migrates them. Do
update its doc comment to note it's the internal cross-edge primitive, not
a config-facing form (drop the `(key … (lambda () (enter-mode! …)))` example
that dsl.sld's `key` doc comment currently shows at dsl.sld:36-43 — the
canonical example there changes to a `'next` decoration instead).

**`dsl.sld` changes:**
- `key-cmd`: the `'sticky-target` keyword → `'next` (same shape: `(loop (cddr
  rest) (cons (cons 'next (cadr rest)) acc))`).
- `sticky-set` → renamed `walk` (keep the OLD name nowhere — flag day, no
  alias). Same two-part lowering (register the mode tree + return a splice),
  but now:
  - the **splice** copy (for entry points elsewhere) decorates each key with
    `'next mode-id` (was `'sticky-target mode-id`) — a cross edge.
  - the **registered tree** copy (passed to `register-tree!`) must ALSO be
    decorated, with `'next 'self` on each key — this is new. Under the old
    model the group-level `'sticky #t` flag made the registered tree's own
    members auto-cycle without per-key decoration; under the new model there
    is no group flag, so `walk` must decorate BOTH copies (entry splice:
    `'next mode-id`; registered members: `'next 'self`), from the same
    `keys` list, non-destructively (two separate `map`s over `keys`, same
    pattern the current splice-building map already uses).
  - drop `'sticky #t` / `'exit-on-unknown #t` from the `register-tree!`
    call's sticky flag (keep `'exit-on-unknown #t` — that part is unaffected).
- `group` / `screen` / `open`: drop the `'sticky` keyword branch entirely
  (falls through to nothing — these forms no longer accept it at all; a
  config still passing `'sticky #t` here should error as an unknown keyword,
  not silently no-op — check `group`'s keyword-parsing shape: unknown
  keywords fall to `(else …)` which accumulates as an opaque extra rather
  than erroring, same as today for genuinely-unknown keywords — that's
  existing behaviour, not a regression, so no extra guard needed).
- Update the `key` doc comment (dsl.sld:36-43, the canonical example at
  dsl.sld:527-ish if it also demonstrates `enter-mode!` — grep at
  implementation time, line numbers will have shifted after edits).

**Overlay renderer (`ui/overlay.scm` + `overlay.js` + `base.css`).** Three
call sites in overlay.scm read `node-sticky-target` (per-cell ↻ marker,
`render-entry` + `entry->row-json` + `push-overlay-update-default`) → become
`(node-next child)` (truthy check, unchanged shape — a `'next`-bearing leaf
still gets the marker, whether the edge is a cross, self, or dynamic
resolver). Three call sites read `(deepest-sticky-on-path node path)` (the
container-level "we're in a walk" class, `render-overlay-body` +
`push-overlay-update` + `push-overlay-update-default`) → replace with a new
predicate: add `(node-walk? node)` to state-machine.sld (exported) — true
iff any direct command/range-command child of `node` carries `(eq? (node-next
child) 'self)` — and call `(any-on-path? node path node-walk?)` in its place
(reuses the existing ancestor-walk helper, new leaf predicate). Rename
consistently away from "sticky" terminology per CONTEXT.md's _Avoid_ note
(the bare word, not just the compound identifiers):
- CSS class `.overlay.sticky` → `.overlay.walk` (base.css:181, doc comment
  above it at 176-180).
- JSON/JS field `"sticky"` / `data.sticky` → `"walk"` / `data.walk`
  (overlay.scm's three emission sites; overlay.js lines ~36-55, ~448-456).
- CSS class + JS class `.entry-sticky-marker` → `.entry-next-marker`
  (base.css:319-331, overlay.js:106-110 + 403-409).
- JSON field `"isSticky"` → `"isNext"` (overlay.scm:626, 889; overlay.js:108,
  405).
- Update the doc comments referencing "sticky tree/subgroup" /
  "sticky-target" in these three files to the new vocabulary (`'next`,
  Walk, Terminal — CONTEXT.md already has the terms).

**Every `'sticky`/`sticky-set`/`'sticky-target` call site to migrate**
(verified this session, supersedes the parent brief's inventory — it missed
Telegram):
- `Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld`: `focus-mode-register!`
  (register-tree! 'herdr-panes-focus 'sticky #t …) → drop 'sticky, decorate
  its four hjkl keys with `'next 'self`. `build-herdr-tree`'s Focus panel
  hjkl (`'sticky-target 'herdr-panes-focus`) → `'next 'herdr-panes-focus`.
  `build-herdr-tree`'s "Move Pane" group (`'sticky #t 'exit-on-unknown #t`) →
  drop `'sticky`, decorate its four hjkl keys with `'next 'self`.
- `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`: `focus-mode-register!`
  (register-tree! id 'sticky #t … `(focus-mode-tree)`) → drop `'sticky`;
  `focus-mode-tree`'s four hjkl keys → decorate with `'next 'self` (today
  they carry no sticky-target at all — relied entirely on the group flag).
  `rebuild-tree!`'s Focus panel hjkl (`'sticky-target sticky-id`) → `'next
  sticky-id`. `rebuild-tree!`'s "Move Pane" group (~line 562) and
  `build-iterm-splits-drill`'s "Move Pane" group (~line 197) — both `'sticky
  #t 'exit-on-unknown #t` → drop `'sticky`, decorate their four hjkl keys
  with `'next 'self`.
- `Sources/Modaliser/Scheme/app-trees/com.apple.MobileSMS.scm` (+ its mirror
  at `~/.config/modaliser/app-trees/com.apple.MobileSMS.scm`): the
  "Conversations" group (`'sticky #t 'exit-on-unknown #t`, 2 keys) → drop
  `'sticky`, decorate both keys `'next 'self`.
- `Sources/Modaliser/Scheme/app-trees/company.thebrowser.dia.scm` (+ mirror):
  `(sticky-set 'dia-tab-walk "Tabs" …)` → `(walk 'dia-tab-walk "Tabs" …)`.
  The "Recent Tabs" group (`'sticky #t 'exit-on-unknown #t`, with reason-aware
  `on-leave` — preserve that hook untouched) → drop `'sticky`, decorate its
  keys `'next 'self`.
- `Sources/Modaliser/Scheme/app-trees/com.tdesktop.Telegram.scm` (+ mirror —
  **not in the original leaf's inventory**, found by grep this session): a
  `'sticky #t` group at line 15 — read it at implementation time and migrate
  the same way.
- `Sources/Modaliser/Scheme/app-trees/com.googlecode.iterm2.scm` (+ mirror):
  two `(sticky-set …)` call sites (`iterm-tab-walk`, `iterm-split-walk`) →
  `(walk …)`, same args.
- Confirm the `~/.config/modaliser/app-trees/*.scm` mirrors are byte-identical
  to the in-tree versions before diffing (feedback_config_sync) — if they've
  drifted, migrate both independently and reconcile.

**Docs:** `docs/reference/state-machine.md` and `docs/reference/dsl.md` (and
grep any other `docs/reference/*.md` naming "sticky") rewritten to the graph
vocabulary. CONTEXT.md already has the terms (Modal-dispatch domain) — no
change needed there.

**Tests to update** (all found by grep this session — read each file's
current assertions before rewriting, don't guess): `SchemeCoreSmokeTests.swift`
(the largest — ~15 sticky-themed tests: re-arm, swallow-unknown, backspace-
at-root variants, nested sticky, enter-mode! interop, sticky-set registration
— rewrite each to the `'next`/`walk` vocabulary, preserving the *behaviour*
each test was actually verifying), `ConfigDslTests.swift` (`'sticky-target` →
`'next` on `key-cmd`; the sticky-target-key-transitions test), `LayoutDslTests.swift`
(`sticky-set` → `walk`, including the order-forwarding and fragment-composition
tests), `OverlayRenderTests.swift` (`entry-sticky-marker` → `entry-next-marker`;
the back-available-for-path comment/behaviour). Add a new regression test
per ADR-0015's "suspected per-press push wart": fire a cyclic (`'next 'self`)
leaf twice in a row and assert `modal-stack`'s length is unchanged (use
whatever swift-side accessor the existing tests use to read `modal-stack`, or
add a small one if none exists — check `SchemeCoreSmokeTests.swift` first,
several existing tests already assert on stack depth via `enter-mode!`
interop, mirror that idiom).

## Done when

- `swift test` passes (usual skips: `ModaliserAppsItermLibraryTests`,
  `HttpLibraryTests`).
- `./scripts/check-portable-surface.sh` passes.
- Grep guard: `grep -rn "'sticky\b\|sticky-set\|sticky-target" Sources/
  Tests/` (excluding CONTEXT.md's _Avoid_ note and git history) returns
  nothing.
- Live smoke: one Move Pane walk (e.g. herdr's, or iTerm's) — hjkl latches
  and keeps cycling on repeat presses, Escape exits from any depth, an
  unrelated key exits per `'exit-on-unknown`.
- `enter-mode!` still exported (deliberately deferred, see Notes).

## Notes

- Don't touch `terminal.sld` or any of the seven backend `*.sld` files
  (ghostty/kitty/wezterm/tmux/zellij/iterm/herdr)'s `focus-pane-by-digit`
  definitions or their `make-terminal-backend` calls — that's the next leaf.
  iterm.sld and herdr.sld ARE touched here, but only for their Focus-mode /
  Move-Pane sticky migration, not their digit-jump slot.
- If this still proves too big mid-session, the next natural split point is
  "core dispatch + dsl.sld" (state-machine.sld, dsl.sld, overlay renderer)
  vs "call-site migration + tests" (everything else) — but try to land it
  whole first; the two halves can't be tested independently anyway (the
  call sites won't parse against the old dsl.sld surface once it's split
  out mid-way).
