# CONTEXT — Modaliser glossary

The Ubiquitous Language for this repo. Append terms inline as they
harden. Glossary only — no implementation detail.

## Terminal-pane domain

**Pane / split** — interchangeable. The unit of focus inside a terminal
or multiplexer. Each backend has its own native term (iTerm "session",
tmux/zellij/WezTerm "pane", Kitty "window"); externally we say "pane."

**Focused pane** — the pane currently receiving keystrokes. Determined
in principle by the foreground process group of its controlling tty.

**Host terminal** — the OS-level terminal emulator (iTerm2, WezTerm,
Kitty, Ghostty, Alacritty). What macOS reports as the frontmost app.

**Multiplexer (mux)** — a process running *inside* a host terminal that
provides its own panes (tmux, zellij).

**Backend** — an implementation of the terminal-backends abstraction
for one host terminal or one multiplexer.

**Splitting backend** — a backend that exposes the directional
focus/split/move ops + digit-jump (and optionally `toggle-pane-zoom`).
Implies the terminal/mux supports native splits. See the PRD
`docs/prd/terminal-backends.md` for the authoritative op list.

**Detection-only backend** — a backend that exposes the detection
primitive (process running in the focused/only pane) but not the
splitting op surface. Used for host terminals without native splits;
users add a mux inside for splits.

**Focused-terminal path** — alist keyed by backend symbol with
`#(pane <id> fg <cmd>)` vector values, representing the chain from
the host terminal down through any mux to the innermost foreground
command. Each backend symbol appears at most once. See ADR-0008.

**Chip** — the digit-label overlay painted on each pane by
`focus-pane-by-digit`. **Always a native macOS overlay window**
drawn by `(modaliser hints)` `hints-show`, never injected text or
escape sequences into the terminal stream. The per-backend job is
producing the `(label, screen-rect)` pairs `hints-show` consumes;
chips themselves are uniform. "Indirect and inexact" refers to
whether a backend can produce screen-accurate rects (e.g. when
cell-pixel dimensions must be derived rather than read).

**Suffix hook** — the per-app context handler installed via
`set-local-context-suffix!`; returns a string like `/nvim` that
selects a variant tree. See `docs/how-to/terminal-pane-aware-tree.md`.

## Window-switching domain

**Window chip** — the digit-label overlay painted over an on-screen
*window* (not a terminal pane) so the user can focus that window by
typing its digit. Same overlay machinery as the pane **Chip** above
(`hints-show` native windows); the distinction is the labelled target:
a top-level OS window vs. a pane inside a terminal. Triggered by
`(window:list-block 'chips? #t)`. Source: `window-list.sld`.
_Avoid_ bare "chip" when the window-vs-pane distinction matters.

**Same-app overlap** — the failure this grove addresses: two or more
windows of the *same* application whose on-screen frames overlap, so
their window chips land on top of each other and become unreadable /
un-aimable. Observed with iTerm and Dia; treated as generic, not
app-specific.

**Chip placement** — the two-stage pipeline that turns a window into a
`(label, screen-rect)` pair for `hints-show`: (1) a Swift geometric
stage that subtracts occluder rects from the window to find a clear
fragment (`ChipPlacement.swift`), then (2) a Scheme reactive stage that
"dodges" chips which still collide (`window-list.sld`).

**Chip cascade** — the fallback tier of chip placement: when a window
has no usable visible area for an on-window chip, its chip is placed
into a **slot lattice** anchored near the occluded window's natural
corner, filling the nearest free lattice slot. Co-located same-app
windows therefore produce a local stack of chips by their cluster. The
cascade is what keeps a fully-occluded window selectable.
_Avoid_: "cascade" for the on-window dodge — that is the first tier.

**Slot lattice** — a screen-covering tiling of chip-sized cells
(step = chip side + padding) used to assign non-overlapping fallback
positions. Finite cells + the ≤10-chip cap (`default-window-labels`)
make the no-overlap invariant a counting argument, not a fixpoint.

**Strong invariant** — the correctness contract this grove enforces:
(1) no two window chips ever overlap, and (2) every listed window keeps
exactly one chip (a fully-occluded window is relocated, never dropped).
Label readability and selectability win over keeping a chip at its
window's natural corner.

## Chooser domain

**Chooser** — an activating modal panel built on a `WKWebView`, containing
a single text input above a filtered result list. The user types to filter,
selects with arrows/hjkl, activates with Enter. Sources: `chooser.scm`,
`chooser.js`, `ChooserSearchEngine.swift`. The only Modaliser surface that
hosts a focused text input.

**Chooser input** — the single `<input id="chooser-input">` element
each chooser hosts. The lone keyboard-text-entry site in Modaliser; if
clipboard paste fails anywhere in Modaliser, it fails here.
_Avoid_: "search box", "filter field" — use "chooser input."

**Standard text-editing shortcuts** — the full Cocoa class of keyboard
behaviours a focused `NSTextField` / `<input>` gives a macOS user without
opt-in: Cmd-V/C/X/A, option-arrows for word movement, Cmd-arrows for
line/document jumps, Cmd-Z/Shift-Cmd-Z undo, etc. Treated as one class
because they share an event path; failing one usually means failing all.
A chooser input should support the whole class.

## Window-layout domain

**Window-layout op** — a `w`-menu action that repositions or resizes the
*focused* OS window (thirds, halves, two-thirds, maximise, center,
fullscreen, restore) via the Accessibility API. Changes geometry, not
focus — distinct from the window-switching chips, which only change which
window is focused. Sources: `WindowManipulator.swift`, `window-actions.sld`.
_Avoid_: bare "window movement" when precision matters — it is the colloquial
name (and this grove's name) but conflates geometry with focus-switching.

**EUI flip** (AXEnhancedUserInterface flip) — the disable→write→restore dance
Modaliser performs around AX position/size writes for apps that set
`AXEnhancedUserInterface` (Electron and some others). While that flag is on,
AX geometry writes silently no-op; Modaliser flips it off, issues the writes,
then restores it. Source: `withResizableApp`.

**EUI-settle race** — the failure this grove addresses: on some machines the
Electron app has not finished applying the EUI-off transition (or processing
the geometry writes) before Modaliser issues or restores them, so the writes
are dropped and the window never moves. Timing-sensitive across CPU
generations — hence it works on one machine and silently fails on another.
The fixed `usleep(50_000)` settle delay in the EUI flip is the fragile
assumption at its core.
