# Docs Restructure — Diátaxis Layout

**Status:** Brainstorm settled; awaiting fresh-session execution.

## Goal

Reorganise Modaliser's user-facing docs into a Diátaxis-style structure (quick-start / tutorials / how-to / reference), and refresh the prose to reflect the current DSL. The existing docs largely pre-date a major DSL overhaul (key macro, `keys`, `category`, auto-pack, undecorated selector, λ, etc.) and silently teach forms that no longer exist.

## Starting slice (confirmed)

- **Phase 1**: Quick-start + Reference (DSL + libraries + state-machine + theming + renderer protocol).
- **Phase 2** (deferred): How-tos.
- **Phase 3** (deferred): Tutorials.

Phase 1 anchors the new structure and retires the most stale prose. Phases 2 and 3 build on top once Phase 1 is in.

## Target layout

```
docs/
  quickstart/
    index.md                  ← install → press F18 → modify config → relaunch, 5 minutes
  tutorials/                  ← created with placeholder; populated in Phase 3
  how-to/                     ← created with placeholder; populated in Phase 2
  reference/
    dsl.md                    ← every DSL form, current shape, examples
    libraries.md              ← bundled (modaliser …) libraries (or split per library if large)
    state-machine.md          ← modal concepts: transient/sticky, modal-stack, sticky-target, exit-on-unknown
    theming.md                ← CSS classes + variables, override patterns
    renderer-protocol.md      ← block protocol: 'type, 'block-children, 'on-render-fn, hooks
    library-system.md         ← user-libraries.md migrated here
    portability.md            ← unchanged content, just moved
    keyboard.md               ← unchanged content, just moved
```

## Migration of existing docs

| Current file | Action |
|---|---|
| `README.md` | **Rewrite light** — trim to a brief overview + links into the new structure. |
| `docs/configuration.md` | **Delete.** Content is stale; pieces redistribute into `quickstart/`, `reference/dsl.md`, `reference/libraries.md`, `reference/state-machine.md`, `reference/theming.md`. |
| `docs/scheme-api.md` | **Delete.** Splits into `reference/dsl.md` + `reference/libraries.md`. |
| `docs/user-libraries.md` | **Move → `reference/library-system.md`** with light edits. Mostly still accurate. |
| `docs/keyboard.md` | **Move → `reference/keyboard.md`** unchanged. |
| `docs/portability.md` | **Move → `reference/portability.md`** unchanged. |

## What's currently true about the DSL (so the writer doesn't re-mislead)

All of this changed during the recent branch — verify against code, don't trust historical docs:

- **`key` is a macro with runtime dispatch.** `(key K L body)` — when `body` is a `(lambda …)` or `(λ …)`, it's the action thunk; otherwise body is evaluated eagerly and dispatched on result type (procedure → action, pair → decorated node). For inline side-effecting calls like `(launch-app "X")`, wrap in `(λ () …)`.
- **`λ` (U+03BB) is a Unicode alias for `lambda`** — exported from `(modaliser dsl)`.
- **`keys` is the multi-key sibling.** `(keys KEYLIST LABEL ACTION-FN)` where ACTION-FN gets `(matched-key index keylist)`. KEYLIST supports `'("a" .. "z")` (inclusive single-char range) and `'("1" ..)` (digit open-end → `n..9`). Display key is computed: contiguous → `"a..b"`; digit-range ending at 9 → `"n.."`; otherwise `"a/b/c/…"`.
- **`category`** is allowed anywhere `(key …)` is. Auto-pack at top level (and inside `(overlay …)`) splits mixed runs into TWO `(which-key-block …)`s: uncategorised first, categorised second. Explicit `(which-key-block …)` from the user is preserved as authored (we don't re-shuffle).
- **`selector` is undecorated.** `(selector 'prompt … 'source … 'on-select …)` returns a kindless node; bind via `(key K L (selector …))` — same pattern as `(key K L (overlay …))`.
- **`overlay` is in `(modaliser dsl)`**, generic (no window-specific knowledge), accepts mixed blocks + nodes (auto-packs the node runs).
- **`define-tree` at top level** auto-packs its content into a block-list group (`'renderer 'blocks`). So top-level trees render with the block-list renderer; sub-groups still use the default list renderer.
- **`(modaliser space-switching)` is deleted** — `keys` directly handles space-switching at the config level.
- **Selector factories return undecorated nodes** — `web-search:google`, `launcher:find-application`, `launcher:find-file`. Bind with `(key "g" "Google" (web-search:google))` etc.
- **Sort order is case-insensitive primary, lowercase-first tiebreak**: `a A b B …` (not ASCII `A B … a b`). Implemented in `sort-key-lt?` in `Sources/Modaliser/Scheme/ui/overlay.scm`.
- **Theming vocabulary (current)**: `base.css` defines `--color-key`, `--color-label`, `--color-group`, `--color-category`, `--color-arrow`, `--color-header`, `--color-separator`, plus overlay/chooser sizing vars. `which-key.css`, `window-list.css`, `window-diagram.css` consume them and add a couple of their own (`--diagram-line`, `--diagram-cell-bg`, `--overlay-cols`).
- **Chrome on block-list pushes**: `push-overlay-update` now sends `rootSegments`, `path`, `sticky`, `footer` alongside the block body so back-hint + breadcrumb refresh on navigation into nested block-list overlays.
- **LispKit gotcha**: `.scm` files loaded outside a `define-library` cannot reliably read mutable library-exported cells (they capture a stale binding). Wrap in an accessor procedure defined inside the library. Captured in `feedback_lispkit_library_scope.md`.

## Source-of-truth files to read

When writing reference, the writer should ground each section in the current code:

- **DSL forms**: `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld`
- **State machine**: `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld`
- **Renderer protocol**: `Sources/Modaliser/Scheme/ui/overlay.scm` (`block-list-payload-json`, `block-json`, `which-key-payload-json`, the `'block-children` / `'on-render-fn` / `'on-enter-fn` / `'on-leave-fn` conventions)
- **Bundled libraries**: each file under `Sources/Modaliser/Scheme/lib/modaliser/`
  - `apps/safari.sld`, `apps/chrome.sld`, `apps/iterm.sld`
  - `blocks/which-key.sld`, `blocks/window-list.sld`, `blocks/window-diagram.sld`
  - `launchers.sld`, `web-search.sld`, `settings-menu.sld`, `window-actions.sld`, `window.sld`
  - `leader.sld`, `keyboard.sld`, `event-dispatch.sld`
- **CSS theming**: `base.css`, `lib/modaliser/blocks/*.css`
- **Config example** (current, canonical): `~/.config/modaliser/config.scm` — same byte-for-byte as `Sources/Modaliser/Scheme/default-config.scm`

The current installed config is the source of truth for the seed (per `feedback_config_sync.md`). Do NOT edit `default-config.scm` without mirroring from the user config.

## Concrete write-list (Phase 1)

### `docs/quickstart/index.md`

Single page. Sections roughly:
1. What Modaliser is — one paragraph.
2. Install (`./scripts/install.sh`).
3. First launch — accessibility / screen-recording grants.
4. Press F18 — see the overlay.
5. Edit `~/.config/modaliser/config.scm` — add or rename one binding.
6. Relaunch — from the menu bar icon.
7. Next steps — link into reference and (future) how-tos.

Keep under ~150 lines. Real `config.scm` snippet using current DSL (`(key …)`, `(category …)`).

### `docs/reference/dsl.md`

One section per surface form. For each: signature, what it returns, where to put it, optional keywords, examples. Order roughly:

- `(define-tree SCOPE [keyword value]... . content)` — including the auto-pack semantics
- `(set-leaders! …)` / `(set-leader! …)` (legacy)
- `(set-overlay-delay! …)`, `(set-overlay-aspect-ratio!)`, `(set-host-header! …)`, `(set-overlay-css! …)`
- `(key K L body [keyword value]...)` — macro rules; lambda/λ short-circuit; eager-eval branch; `'sticky-target`
- `(λ …)` alias note
- `(keys KEYLIST LABEL ACTION-FN [keyword value]...)` — `..` shorthand, display-key computation, `'display-key` override
- `(key-range DISPLAY LABEL KEYS ACTION-FN)` — lower-level form; when to reach for it vs `keys`
- `(group K L [keyword value]... . children)` — `'on-enter`, `'on-leave`, `'sticky`, `'exit-on-unknown`, opaque-extras passthrough
- `(category LABEL . children)` — placement rules, sort behaviour
- `(selector [keyword value]...)` — `'prompt`, `'source`, `'on-select`, `'dynamic-search`, `'file-roots`, `'actions`, `'remember`, `'id-field`
- `(action NAME [keyword value]...)` — `'description`, `'key`, `'run`
- `(overlay [keyword value]... . content)` — `'key`, `'label`, `'on-enter`, `'on-leave`, auto-pack of node runs, block ordering
- `(which-key-block . children)` — explicit form; preserved as authored
- `(modifier-symbols->mask SYMS)` — helper

Cross-reference into `state-machine.md` for navigation semantics, `renderer-protocol.md` for blocks.

### `docs/reference/libraries.md`

Or split per library if the file gets unwieldy (>500 lines). For each bundled library, document:

- Import path and recommended prefix
- Exports (signature + one-line description)
- One concrete usage example per useful export
- Defaults table where applicable (e.g. chip-options for iterm/window-list)

Cover: `window-actions`, `blocks/which-key`, `blocks/window-list`, `blocks/window-diagram`, `launchers`, `web-search`, `settings-menu`, `apps/safari`, `apps/chrome`, `apps/iterm`, `window`, `leader`. Skip libraries that are pure native FFI (`keyboard`, `input`, `shell`, `app`, `pasteboard`, `lifecycle`, `accessibility`, `hints`, `ax-hints`, `terminal`, `webview`, `dom`, etc.) — those go in a brief "native primitives" section pointing at the source.

### `docs/reference/state-machine.md`

- Modal lifecycle: arm → handle-key → descend / fire / pop / exit.
- Transient vs sticky semantics — when does the modal stay alive after a leaf fires?
- `'sticky-target` on a `(key …)` — declarative `enter-mode!` from the binding.
- `modal-stack` — pushed by `enter-mode!`, popped by backspace at root.
- `'exit-on-unknown` — when unknown keys exit the modal vs. get swallowed.
- `'on-enter` / `'on-leave` hooks — only fire when the overlay is actually visible.
- `find-child` — literal key wins over a `range-command` that includes it.
- Category transparency — categories flatten through `find-child`.

### `docs/reference/theming.md`

- The current CSS variable vocabulary (inventory from `base.css` + block CSS).
- The current class names (`.overlay`, `.overlay-entry`, `.entry-key`, `.entry-label`, `.group-label`, `.wk-row`, `.wk-category-label`, `.wk-misc`, `.block-which-key`, `.block-window-list`, `.block-window-diagram`, `.chooser`, `.chooser-row`, …).
- How `(set-overlay-css! …)` works (last in CSS load order, wins specificity).
- How `(set-host-header! …)` translates to `--color-host-bg` / `--color-host-fg` / `--color-host-sep`.
- Worked example: a dark-mode theme.

### `docs/reference/renderer-protocol.md`

- The `'blocks` renderer dispatch in `ui/overlay.scm`.
- Block spec shape: `'type`, `'block-children`, optional `'on-render-fn`, `'on-enter-fn`, `'on-leave-fn`.
- `'on-render-fn` return-and-merge semantics (LispKit excludes `set-cdr!`; blocks return alists rather than mutating spec).
- The which-key payload shape (segments, kinds, cols hint).
- The chrome envelope on push-updates: `rootSegments`, `path`, `sticky`, `footer`.
- How to write a custom block — the contract.

### Migrated files (light edit pass)

- `docs/reference/library-system.md` (was `user-libraries.md`)
- `docs/reference/keyboard.md` (was `keyboard.md`)
- `docs/reference/portability.md` (was `portability.md`)

For these, mostly: rewrite the cross-link URLs and drop references to removed forms (e.g. `space-switching`, `make-which-key-block`).

### `README.md` (rewrite light)

- Brief description (one para).
- Install instructions (the existing block is fine).
- Permissions / first launch (the existing block is fine).
- Link into the new docs structure (replace the current 5-bullet links).
- Quick-start mini-snippet stays as a teaser, but with current DSL (`(category …)`, `(λ …)`, no `make-…` prefixes).

## Verification

- `swift test` after any code touches (unlikely in this slice, but if anything moves into reference that requires DSL stubs to be added or stale syntax to be cleaned up, retest).
- Markdown lint / dead-link check — at least open every relative link manually.
- Render-check: open the rendered markdown in a previewer to confirm structure reads cleanly.
- Cross-check every code snippet against the current source. The temptation to copy-paste from the legacy `configuration.md` will be strong — *don't*, that's the trap this whole refactor exists to fix.

## Stopping points / decision gates

Stop and check with the user at these points:

1. **After directory skeleton + migrations.** Show: `tree docs/`. Confirms layout before fresh prose lands.
2. **After `quickstart/index.md` is drafted.** It anchors tone for the rest.
3. **After `reference/dsl.md` is drafted.** Largest single piece; review before writing the rest of `reference/`.
4. **Before deleting `configuration.md` / `scheme-api.md`.** Confirm nothing depends on those URLs externally.

Phase 2 (how-tos) and Phase 3 (tutorials) are not part of this slice — surface as next-up at completion.

## Non-goals

- **Theming refactor.** That's a separate slice (move `chip-options` / `hint-options` from inline-style DSL options to CSS classes + variables). `reference/theming.md` documents the *current* state; the refactor lands later.
- **Tutorials.** Deferred to Phase 3.
- **How-tos.** Deferred to Phase 2.
- **Auto-generated reference.** The reference docs are hand-written for now; a doc-generator out of the .sld files is a possible future, not this slice.
