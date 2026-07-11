# error-dialogs-async-k3

**Kind:** work

## Goal

Cut the three backend error/info dialogs over to `(modaliser dialogs)` —
`apps/iterm.sld:437`, `apps/kitty.sld:402`, `apps/alacritty.sld:224` — so
their Return/OK dismissal is no longer swallowed by the modal catch-all.

## Context

Same defect class as k2, lower severity: info-only dialogs (no typed input,
no continuation payload), currently raised via blocking `run-shell`
osascript. Use `dialog-info` (or equivalent) from the library k2 built.
Mechanical; the library and its seam already exist.

## Done when

- All three sites go through the library; their local osascript/escaping
  duplication is gone.
- Touched backend tests still pass through the `current-dialog-runner` seam;
  build + suite green (usual skips); portable-surface check passes.
- Live spot-check of one site (e.g. trigger the iTerm error dialog) — OK /
  Return dismisses it while Modaliser is running.

## Notes
