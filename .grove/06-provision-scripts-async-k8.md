# provision-scripts-async-k8

**Kind:** work

## Goal

Cut the three backend `configure-entry` provisioning scripts — fired from
inside `dialog-confirm`'s continuation once the user clicks Continue — over
to `run-shell-async`, so they stop blocking the Scheme thread. Same failure
mode ADR-0014 exists to prevent, just moved one step later than the dialog
itself: a leader press during the blocking window still stalls the
keyboard tap.

## Context

- Surfaced while implementing `error-dialogs-async-k3`: that leaf made the
  *dialog* (`dialog-confirm`) fire async, but each backend's continuation
  still runs its provisioning via synchronous `run-shell`:
  - `apps/iterm.sld` `iterm-provision-script` — quits iTerm, then polls
    `pgrep -x iTerm2` up to 60×0.1s (~6s worst case) before editing prefs and
    relaunching. The slowest of the three by far — the quit-wait loop is a
    real multi-second blocking window.
  - `apps/kitty.sld` `kitty-provision-script` — sed/grep edits to
    `kitty.conf`, no app-quit wait. Fast (sub-second) in practice.
  - `apps/alacritty.sld` — a single `xattr -d` call. Fast, likely not worth
    touching.
  - Prioritize iTerm's; re-assess whether kitty/alacritty are worth the
    conversion once iTerm's is done (the failure mode needs a genuinely
    long blocking window to matter — a sub-second shell-out may not be
    worth the CPS-ification cost).
- Each provisioning script currently ends by calling its own
  `*-refresh-configured!` synchronously right after `run-shell` returns;
  converting to `run-shell-async` means that refresh call moves into the
  async callback.
- No dialog/keyboard-input concern here (ADR-0015's release-before-action
  already covers that); this is purely ADR-0014's "any long-running
  external process" clause, applied to a call site the dialog conversion
  didn't reach.

## Done when

- `iterm-provision-script` (at minimum) fires via `run-shell-async`; its
  `iterm-refresh-configured!` call moves into the callback.
- A test seam exists (mirror `current-dialog-runner` / the herdr async-
  runner idiom) so no test spawns a real provisioning script.
- `swift test` green (usual skips); portable-surface check passes.
- Live spot-check: trigger the iTerm configure flow, click Continue, and
  confirm the leader stays responsive during the quit-wait window (the
  window this leaf exists to close).

## Notes

- Low urgency: the window this leaf closes only matters for the small
  fraction of users who both haven't configured their terminal app yet
  *and* press a leader key in the few seconds after clicking Continue.
  Fine to defer behind higher-value work.
