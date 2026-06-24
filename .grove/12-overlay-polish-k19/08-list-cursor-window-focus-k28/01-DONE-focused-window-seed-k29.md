# focused-window-seed-k29

**Kind:** work

## Goal

Seed the global Windows overlay's selection cursor to the **Focused window**, by
adding a `focused-window` native primitive and a `window-focused-index` thunk
wired into `window-actions.sld`'s `list-block`. Implements the approved design in
the parent brief — read it first (Settled design §, three decisions).

## Context

- **Read the parent brief's "Settled design"** — it has the three resolved
  decisions and the windowId self-consistency argument (why AX-id matching is
  trustworthy *here*: AX-id vs AX-id, same `_AXUIElementGetWindow` source as the
  list rows — `WindowEnumerator.swift:48-49`).
- **Swift primitive** — add `focused-window` to `WindowLibrary.swift` (register the
  `Procedure` in `declarations()`, near `window-visible-at?`). Reuse the
  `focusedWindowAndFrame` logic in `WindowManipulator.swift:132` (frontmost-app →
  `kAXFocusedWindow` ?? `kAXMainWindow`, cold-AX-safe) and add `_AXUIElementGetWindow`
  for the id + `ownerPid`. Return an alist `((ownerPid . p)(windowId . w)(x)(y)(w)(h))`
  via `SchemeAlistLookup.makeAlist`, or `#f`. `focusedWindowAndFrame` is `private` —
  expose what's needed (a sibling that also yields pid+id, or relax visibility).
- **Scheme thunk** — `window-focused-index` in `window-actions.sld`: call
  `(focused-window)`; `#f` → `#f`. Else scan `(window-list-current-targets)`
  (rows are `(label . window-alist)`, alist carries `windowId`/`ownerPid`/`x`/`y`)
  per the matcher: windowId-exact (id≠0) → ownerPid+origin → `#f`. Mirror
  `apps/iterm.sld` `pane-focused-index` (iterm.sld:732).
- **Wire** — in `list-block` (window-actions.sld:186) live branch, append
  `(cons 'cursor-initial-index-fn window-focused-index)`, exactly like
  `pane-list-block` (iterm.sld:747).
- `(modaliser window)` must export `focused-window`; window-actions already imports
  `(modaliser window)` and uses `window-list-current-targets`.

## Done when

- `swift build` clean; `swift test` green (skip the pre-existing crashers:
  `ModaliserAppsItermLibraryTests`, `HttpLibraryTests`).
- New tests: the `window-focused-index` matcher (windowId-hit, id=0→PID+frame
  fallback, no-match→`#f`) against a stubbed targets list; a smoke test for the
  Swift primitive's alist shape if feasible without a live window server.
- `./scripts/check-portable-surface.sh` green (no `(lispkit ` literal reaches
  `lib/modaliser`).
- **Live verify (needs the user):** `./scripts/install.sh`, Relaunch, open the
  Windows overlay — cursor highlights the focused window; `⏎` activates; arrows
  still move and survive re-render. Detection miss degrades to row 0.

## Notes

- TDD: write the matcher test first (pure Scheme, stubbed targets) — it's the part
  with branching logic and no window-server dependency.
- No `list-cursor.sld` change — the seed mechanism already exists (k25).
- One focused commit; handle `focused-window-seed-k29`.
