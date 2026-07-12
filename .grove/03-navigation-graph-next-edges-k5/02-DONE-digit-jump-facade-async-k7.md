# digit-jump-facade-async-k7

**Kind:** work

## Goal

Migrate the seven `focus-pane-by-digit` backend slots off the imperative
`(enter-mode! 'xxx-pane-digit)` call to a declarative, fire-time-resolved
`'next` edge (ADR-0015 Context item 3), and finally un-export `enter-mode!`
(truly framework-internal once these are the last callers gone). Depends on
`next-edge-core-and-migration-k6` having landed (needs `node-next`/terminal
dispatch + procedure-valued `'next` support already in `state-machine.sld`).

## Context

**Current shape, identical across all seven backends** (`ghostty.sld:312-313`,
`iterm.sld:660-661`, `kitty.sld:685-686`, `wezterm.sld:354-355`,
`tmux.sld:375-376`, `zellij.sld:417-418`, `herdr.sld:275-276`):
```scheme
(define (focus-pane-by-digit)
  (enter-mode! 'xxx-pane-digit))
```
passed positionally into that backend's `make-terminal-backend` call.

**New shape.** Delete the wrapper function entirely; pass the literal quoted
mode-id symbol directly in the `make-terminal-backend` call, e.g.
`'herdr-pane-digit` in herdr.sld's call, `'iterm-pane-digit` in iterm.sld's,
etc. The record field (`terminal-backend-focus-pane-by-digit`) now holds a
plain symbol, not a thunk. This is safe for the capability predicates
(`supports-digit-jump?`, `supports?`, `op-configured?`) unchanged — they only
check truthiness of the accessor's return value, never call it. Alacritty's
`#f` slot (unsupported) is untouched.

**`terminal.sld` façade.** The op-shim `focus-pane-by-digit` (currently
`(dispatch "focus-pane-by-digit" terminal-backend-focus-pane-by-digit)`,
~line 286) can no longer generically `(thunk)`-call the slot (it's a symbol
now, not callable) — this is the ONE op-shim that changes shape; the other 13
stay thunks, dispatch unchanged for them. Repurpose the SAME exported name
`focus-pane-by-digit` (keep the name — a config author's mental model
"resolve + go to the digit-jump mode of whichever backend is frontmost"
doesn't change, only where in a `(key …)` form it's plugged in) into a 0-arg
resolver procedure:
```scheme
(define (focus-pane-by-digit)
  (let ((b (active-backend)))
    (and b (terminal-backend-focus-pane-by-digit b))))
```
This is exactly the shape a procedure-valued `'next` needs (0 args, returns
symbol-or-`#f`). A config now writes:
```scheme
(key "g" "Goto pane" (lambda () (if #f #f)) 'next terminal:focus-pane-by-digit)
```
(no-op action — the action's old job, transitioning, is now entirely the
edge's). Fail-safe already lands correctly via k6's dispatch: no active
backend, or the active backend's slot is `#f` (unsupported) → resolver
returns `#f` → dispatch's fail-safe branch → `(modal-exit)`, capture kept
through the (no-op) action, matches ADR-0015 exactly.

**`enter-mode!` un-export.** After all seven backends stop calling it
directly, grep confirms it: `grep -rn "enter-mode!" Sources/Modaliser/Scheme/`
should show only `state-machine.sld`'s own definition/internal-use lines.
Remove it from state-machine.sld's export list. Update the "framework-
internal" note in the ADR/CONTEXT if either still documents it as
config-facing (check `docs/reference/state-machine.md` and `dsl.md`, which
k6 already rewrote — this leaf just removes any lingering `enter-mode!`
config-facing mention there, or confirms k6 already did).

**Docs:** `docs/how-to/terminal-pane-aware-tree.md` (~line 291) — the
generic-capability-tree recipe's `(key "g" "Goto pane"
terminal:focus-pane-by-digit)` example → the new two-arg-position form above.

## Done when

- All seven backends' `focus-pane-by-digit` slot is a plain digit-mode-id
  symbol, no wrapper thunk; `terminal.sld`'s façade export is the fire-time
  resolver.
- `enter-mode!` is no longer exported from `(modaliser state-machine)`.
- `swift test` green (usual skips); portable-surface check passes.
- Live smoke: a config using the generic recipe (`(key "g" "Goto pane" …
  'next terminal:focus-pane-by-digit)`) against a live terminal backend
  (e.g. iTerm) — pressing g releases capture, enters the digit-jump chip
  mode, a digit press focuses the pane and exits cleanly.
- Grep guard: `grep -rn "enter-mode!" Sources/Modaliser/Scheme/` shows only
  state-machine.sld.

## Notes

- Nothing in the default shipped config (`default-config.scm` /
  `app-trees/com.googlecode.iterm2.scm` / herdr's `build-herdr-tree`)
  currently exercises this generic recipe — both iTerm's and herdr's own
  trees use `pane-list-block`'s digit-chips path instead, wired directly, not
  through this façade. This leaf's live-smoke therefore needs a throwaway
  test config (or a temporary addition to a scratch app-tree) rather than
  exercising the shipped default — don't mistake "not reachable from the
  default config" for "not real product surface": it's documented in
  `docs/how-to/terminal-pane-aware-tree.md` as the supported generic pattern
  for a user's own config.
- Test files likely touched: `ModaliserTerminalLibraryTests.swift` (the
  façade's `focus-pane-by-digit` export shape) and each backend's own test
  file if any asserts on the record field being callable — grep
  `focus-pane-by-digit` across `Tests/ModaliserTests/` at implementation
  time rather than trusting this list.
