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

**Splitting backend** — a backend that exposes the 13-op surface
(focus / split / move in hjkl directions + digit-jump). Implies the
terminal/mux supports native splits.

**Detection-only backend** — a backend that exposes the detection
primitive (process running in the focused/only pane) but not the
13-op surface. Used for host terminals without native splits; users
add a mux inside for splits.

**Chip** — the digit-label overlay painted on each pane by
`focus-pane-by-digit`. Position is exact when the backend exposes
pane geometry, "indirect and inexact" otherwise.

**Suffix hook** — the per-app context handler installed via
`set-local-context-suffix!`; returns a string like `/nvim` that
selects a variant tree. See `docs/how-to/terminal-pane-aware-tree.md`.
