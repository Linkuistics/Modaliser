# herdr-backend-k2

**Kind:** work

## Goal

Build the herdr `'mux` terminal-backend in `lib/modaliser/muxes/herdr.sld` (match-key
`"herdr"`), driven by herdr's JSON socket-API CLI — **after** validating the
load-bearing detection assumptions with a live herdr-in-iTerm client.

## Context

Read the root `BRIEF.md` for the whole design. Model on `muxes/tmux.sld` and
`muxes/zellij.sld` (both export only `register!` + `backend`). This leaf is the
foundation: once the backend registers, the façade's pane ops route to herdr when a
herdr pane is the focused iTerm pane.

**Validate FIRST (needs the user's live herdr session in iTerm; a herdr *server* alone
isn't enough — attach a client):**
1. An iTerm pane running herdr reports tty foreground command `herdr` (via
   `focused-terminal-foreground-command`). If not, the whole detection approach changes
   — stop and **decompose this leaf**.
2. `herdr pane current` (server global focus) tracks the OS-focused iTerm client.
3. Does the socket API scope per client / tty / session? If not → multi-herdr-client is
   a documented v1 non-goal (record it; the common single-client case is unambiguous).

**Then build:**
- The `<terminal-backend>` record (kind `'mux`): 14 pane ops via `herdr pane …`
  (`focus/swap --direction`; split right/down native, **left/up = split down/right
  `--focus` then `swap` targeting the pane_id RETURNED by split**, R7 — avoids the
  race); `detect-fg-command` (from `herdr pane process-info --current`),
  `focused-pane-id` (`herdr pane current`), `focus-pane-by-digit`, `toggle-pane-zoom`
  (`herdr pane zoom --toggle`), `configured? #t`.
- A **compact/nested JSON extractor** — herdr emits single-line JSON; zellij's multiline
  awk parser does NOT transfer (R5). First check for an existing portable JSON helper in
  the tree (the renderer pushes JSON); a small pure-Scheme reader may beat awk for
  nested `layout.panes[].rect`. Must stay portable (no lispkit json lib in `lib/modaliser`).
- PATH-prefixed `run-shell` (herdr is in /opt/homebrew/bin; GUI Modaliser has minimal PATH).
- `register!` = `register-backend!` + digit-jump mode register (chips deferred to
  leaf 4 content; a basic list/focus is enough here).

## Done when

- Validations #1/#2/#3 recorded (in an ADR note or the leaf's notes → promoted at retire).
- Backend registers; with a herdr pane focused in iTerm, `(terminal:focus-pane-left)`
  etc. drive herdr panes. Split-left/up refocuses correctly (no race).
- Test mirrors `Muxes{Tmux,Zellij}LibraryTests` (op dispatch) **+ a JSON-extractor test**.
- `swift test` green (mind [[project_iterm_tests_crash.md]] pre-existing skips);
  `scripts/check-portable-surface.sh` green.

## Notes
