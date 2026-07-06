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

### Detection validations — RESOLVED (live, against a herdr client in iTerm)

- **#1 CONFIRMED (live).** An iTerm pane running the herdr *client* reports tty
  foreground command **`herdr`** (the client is the `herdr` binary as a foreground
  TUI; enumerated across all iTerm session ttys → `ttys010 → herdr`). So the
  façade's mux match-key `"herdr"` resolves it — no special detection path. The
  detection approach holds; **no decompose needed.**
- **#2 CONFIRMED (single-client).** `herdr pane current` answers from the server's
  *global* focus and reflects the sole client's focused pane (it answered `w9:p1`
  even with **no** client attached — proving it's server-state, not per-client).
- **#3 RESOLVED.** The socket API scopes **per session (per socket)** — one default
  session = one `herdr.sock`; pane commands scope only by `--session`, and
  `--current` = the server's global focused pane. There is **no per-client / per-tty
  scope**. ⇒ Two herdr clients on one session share one global focus and can't be
  disambiguated: **multi-herdr-client-on-one-session is a documented v1 non-goal**
  (the common single-client case is unambiguous). No tty correlation (cf. ADR-0006
  tmux/zellij) is needed for herdr.

### Live op verification (controlled split→close on the user's session)

All ops drive herdr panes. **split-left recipe (split `--direction right --focus`
then swap `--direction left --current`) verified race-free**: the new pane landed
leftmost (x=26) with focus on it; original pushed right (x=119). Focus round-trip
(right→original, left→new) and zoom toggle (True→False) both correct. Created pane
closed; baseline restored exactly.

### Deliverables

- `lib/modaliser/json.sld` — new portable recursive-descent JSON reader
  (object→alist, array→vector); `(scheme base)`/`(scheme char)` only. Chosen over a
  python3 shell-out (kitty's pattern) because it is Scheme-testable, dependency-free,
  and reusable for leaf 4's `layout.panes[].rect`. Tests: `ModaliserJsonLibraryTests`.
- `lib/modaliser/muxes/herdr.sld` — the `'mux` backend, match-key `"herdr"`, 14 ops,
  `register!`/`backend`. Tests: `ModaliserMuxesHerdrLibraryTests` (mirrors the
  tmux/zellij suites + the match-key guard).

### Follow-ups discovered → for leaf 4 (chips/layout)

- **No universal "focus pane <id>" CLI in herdr.** Pane focus is directional-only;
  `herdr agent focus <target>` resolves a target *only* when an agent is reported in
  that pane (a bare shell pane → `agent_not_found`). This leaf ships a **basic
  (no-chip) digit-jump** that focuses via `agent focus <pane_id>` — correct for agent
  panes (herdr's core case), a harmless no-op on a shell pane. **Leaf 4** should add
  the chip rects (from `pane layout`, area-offset by the sidebar, x≥26) **and** a
  universal (agent-independent) pane focus — most likely a rect/directional walk over
  `pane neighbor`, since no direct focus-by-id exists.
