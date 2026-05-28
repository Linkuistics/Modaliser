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
