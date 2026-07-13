# The herdr iTerm tree switches replace vs augment on the current-tab split count

- **Status:** accepted

When the frontmost iTerm pane runs the herdr client, the local-leader (F17)
tree is swapped for one of two herdr **variant trees** instead of the plain
`com.googlecode.iterm2` tree, chosen on every press by the herdr situation in
the focused window:

- **Replace** (`/herdr`) — herdr is the **sole** iTerm split in the current
  tab, so it owns the whole window: a herdr-only tree, zero iTerm controls.
- **Augment** (`/herdr+split`) — the current tab holds **other** iTerm splits
  besides the herdr pane, so the herdr tree gains an `i` drill for those iTerm
  splits.

Both trees splice the same `build-herdr-tree` — the whole herdr surface,
including the `p` Panes drill that holds every pane op (focus hjkl, split,
move, zoom, close, the panes list) — so muscle memory is identical; augment is
literally the replace tree plus the `i` iTerm-splits drill.

## Why it binds

Three non-obvious choices make this costly to reverse and easy to "fix"
wrongly:

- **The classifier keys on the tab-scoped current-tab session count**
  (`sessions of current tab of current window`), *not* an all-tabs
  `AXScrollArea` count. `(modaliser apps iterm)` already computes an
  `AXScrollArea` count for chip placement, so reusing it is the tempting
  shortcut — but AX walks the whole window **across all tabs**, so a window
  with one visible herdr split plus a second background tab would miscount ≥2
  and wrongly pick augment. The tab-scoped AppleScript count
  (`iterm-list-session-ids`) is the only source that reflects *visible* splits.
- **The variant trees bind backend-DIRECT ops, never the `(modaliser
  terminal)` façade.** In augment mode the focused pane runs herdr, so the
  façade's `active-backend` resolves to **herdr** — a façade `focus-pane-*`
  would drive herdr, not iTerm. So the herdr tree binds herdr-direct ops and
  the `i` drill binds iTerm-direct ops (`build-iterm-splits-drill`, which is
  why `(modaliser apps iterm)` exports its otherwise-internal pane ops).
- **The suffix hook is composed in the user config, not installed by herdr.**
  `set-local-context-suffix!` is a single global slot (last-write-wins), so a
  second install would silently clobber iTerm's nvim/zellij handler. The
  config passes `'install-context-suffix? #f` to `iterm:register!` and installs
  **one** composed hook: herdr branch first (gated on
  `(terminal:in-chain? 'herdr)`, which short-circuits the AppleScript count
  query when herdr is absent), then delegating to
  `iterm:context-suffix-handler` for the nvim/zellij branches.

## Considered options

1. **Classifier via the existing AX scroll-area count.** Rejected: spans all
   tabs (see above); miscounts a herdr window that has any second tab.
2. **Façade ops in the variant trees** (a single tree that works for any
   backend via `(modaliser terminal)`). Rejected for augment: with herdr
   focused the façade resolves to herdr, so the iTerm-splits drill would drive
   herdr. Direct ops per layer are mandatory when two backends are live in one
   window.
3. **A separate `set-local-context-suffix!` install for herdr.** Rejected:
   last-write-wins would drop iTerm's nvim/zellij handler. Composition is the
   only correct shape for the single global slot.
4. **One merged herdr tree with a runtime "has other splits?" flag** instead of
   two registered variant screens. Rejected: the variant-screen mechanism
   (`resolve-app-tree` + suffix) already exists and keeps the two shapes
   statically inspectable; herdr is simply its first production user.

## Consequences

- `resolve-app-tree`'s context-suffix variant path — implemented but **never
  exercised in production** before now (no `/nvim` or `/zellij` screen ships in
  the bundled config) — becomes load-bearing. A test asserts the variant
  actually *resolves* rather than silently falling back to the plain tree.
- **Augment-mode pane chips are a known v1 limitation.** The host-frame helper
  takes the first `AXScrollArea`; augment is by definition multi-split, so the
  chip rect can target the wrong split. `hjkl` focus is unaffected (it drives
  herdr directly); accurate augment chips need a focused-iTerm-session-frame
  primitive that does not yet exist.
- Each iTerm leader press pays one AppleScript session-count query **only when
  herdr is focused** (the `in-chain?` gate). `walk-path` is uncached, so herdr
  detection adds a socket round-trip per press; acceptable, revisit if sluggish.
- Portability preserved: the classifier and tree-builder live in
  `(modaliser muxes herdr)` and `(modaliser apps iterm)`, both inside the
  portable `lib/modaliser` tree — `check-portable-surface.sh` stays green.
