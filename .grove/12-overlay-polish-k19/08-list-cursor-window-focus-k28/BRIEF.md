# list-cursor-window-focus-k28 — brief

## Goal

Extend the k25 selection-cursor **Cursor seed** mechanism to the **global Windows
list** (`window:list-block 'chips? #t`): when the Windows overlay opens, the
cursor starts on the **Focused window**, not spatial row 0. Settled by grilling on
2026-06-24; the design below is approved — the implementation child executes it.

## Done when

- Opening the Windows overlay highlights the currently-focused window; `⏎`
  activates it (a no-op re-focus when it is already frontmost); arrow/`k j` moves
  still work and survive re-renders.
- Verified **live** for the Windows list (`./scripts/install.sh` then Relaunch);
  detection failure degrades to row 0, never worse than today.
- Tests cover the focused-index derivation (Scheme matcher) and the new Swift
  primitive; `check-portable-surface.sh` green.

## Decomposition

One child — the change is small (~one Swift primitive + one Scheme thunk + a
one-line wrapper append) and the primitive and its consumer are tightly coupled
(the thunk matches against the alist the primitive returns), so they are built and
tested together; splitting would ship an unused primitive at a seam.

1. **focused-window-seed-k29** — add the `focused-window` primitive, the
   `window-focused-index` thunk, wire it into `window-actions.sld`'s `list-block`,
   tests, live verify.

## Settled design (approved 2026-06-24)

**Decision 1 — semantics.** Keep parity with the iTerm Tab/Panes lists: seed the
Windows cursor to the focused window. `⏎` on it harmlessly re-focuses the already
frontmost window. Detection failure → row 0 (never worse than today).

**Decision 2 — match strategy: windowId, then PID+frame, else `#f`→row 0.**

> Why windowId is trustworthy *here* despite the AX-id flakiness the k28 leaf
> flagged: that flakiness is **AX-id vs CGWindowList `kCGWindowNumber`** — a
> *cross-source* comparison `window-visible-at?` is forced into. Our match is
> **AX-id vs AX-id**: the window-list rows fill `windowId` via
> `_AXUIElementGetWindow` (`WindowEnumerator.swift:48-49`), and the
> `focused-window` primitive derives its `windowId` from the *same* call on the AX
> focused element. Same source ⇒ they agree by construction. PID+frame is the
> fallback for the one residual case — `_AXUIElementGetWindow` returning `0`.

Matcher (in `window-focused-index`, evaluated against
`(window-list-current-targets)`, which the on-render snapshot has already
refreshed by the time `block-json` offers the cursor — same instant, so frames are
consistent):
  1. if focused `windowId` ≠ 0 → first row whose `windowId` equals it;
  2. else → first row with `ownerPid` = focused pid **and** origin `(x,y)` equal to
     the focused frame origin;
  3. else (`ownerPid` alone, single-window app) is acceptable; otherwise `#f`.

**Decision 3 — primitive shape.** One new `(modaliser window)` primitive
`focused-window` → alist `((ownerPid . p) (windowId . w) (x . X) (y . Y) (w . W)
(h . H))`, or `#f` when nothing is focused / not a regular window. A full alist
(not a narrow `focused-window-id`) lets the Scheme matcher layer strategies from a
single primitive. Built by reusing `WindowManipulator.focusedWindowAndFrame`'s
logic (frontmost-app → `kAXFocusedWindow`/`kAXMainWindow`, cold-AX-safe) plus
`_AXUIElementGetWindow` for the id; coordinates are AX top-left, matching
`list-current-space-windows`.

**Wiring.** In `window-actions.sld`'s `list-block`, the live branch appends
`(cons 'cursor-initial-index-fn window-focused-index)` — the exact one-line shape
the iTerm `pane-list-block`/`tab-list-block` wrappers already use. No cursor-core
change (`list-cursor.sld` is untouched).

## Pointers

- ADRs: none. The match-strategy rationale lives in this brief and belongs in a
  code comment on the matcher; raise an ADR only if a future session wants to
  revisit windowId trust (the self-consistency argument is the thing to preserve).
- Glossary (CONTEXT.md): **Focused window**, **Cursor seed**, **Selection cursor**.
- Files: `WindowLibrary.swift` (+ `WindowManipulator` for the focused-window
  identity); `lib/modaliser/window-actions.sld` (`list-block` wrapper +
  `window-focused-index`); `blocks/window-list.sld` exports
  `window-list-current-targets` (the rows to scan). Model to mirror:
  `apps/iterm.sld` `pane-focused-index` / `pane-list-block`.

## Notes

- Independent of elide-general-panel-k27 and util-extraction-audit-k26.
- Live verification needs a human (a leader-triggered system overlay can't be
  self-driven headlessly): build + install, then the user opens the Windows
  overlay and confirms the highlight lands on the focused window.
