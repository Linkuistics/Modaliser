# herdr-dialogs-async-k2

**Kind:** work

## Goal

Cut the four herdr interactive ops — `rename-focused-tab!`,
`rename-focused-workspace!`, `new-worktree!`, `remove-focused-worktree!`
(`muxes/herdr.sld`) — over to async fire-and-forget: fire the herdr verb
*without* its argument through `run-shell-async`; herdr's own UI does the
prompting (ADR-0014). Capture release is already dispatch's job by then
(ADR-0015 via `navigation-graph-next-edges-k5` — these are plain terminal
leaves).

## Context

- **Reshaped at k4.** The original plan (osascript `dialog-prompt` CPS via a
  new `(modaliser dialogs)`) was discarded: no Modaliser-raised prompt at
  all for these ops. The k2-era CPS draft was dropped uncommitted; reusable
  snippets live in `05-error-dialogs-async-k3.md`.
- Each op keeps its cheap synchronous guard (`focused-tab-id` /
  `focused-workspace-id` — no-op when herdr is unreachable), then fires the
  verb async: e.g. `herdr tab rename <id>`, `herdr workspace rename <id>`,
  `herdr worktree create --workspace <id>`,
  `herdr worktree remove --workspace <id>`. No continuation payload — the
  argument-gathering and any confirm are herdr's UI.
- `herdr-cmd` today is synchronous (`run-shell`); add/route an async variant
  (`ShellLibrary.swift` `run-shell-async`, callback on main queue) — fire
  and forget, callback at most logs/toasts on failure.
- The remove-confirm safety that lived in the Modaliser dialog (default
  Cancel, no `--force`) must be re-judged: keep no `--force` so herdr/git
  still refuse dirty removals; the confirm UX itself is herdr-side.
- **External dependency:** herdr 0.7.3 requires the arguments positionally
  (`tab rename <tab_id> <label>`); prompt-on-missing-arg is herdr-repo work.
  Until it ships, the verbs error harmlessly (stderr swallowed) — Modaliser's
  side is still fully verifiable (release + non-blocking).

## Done when

- The four ops fire their verbs through the async path; the local
  `prompt-text` / `confirm-dialog` / `osascript-run` / `as-escape` helpers
  in `herdr.sld` are gone (`sq-escape` stays — worktree create/open still
  interpolate user-derived strings into shell words).
- Tests through the agreed seam: a parameterized captured-command runner
  (mirror the `current-frontmost-bundle-id` idiom in
  `ModaliserMuxesHerdrLibraryTests`) asserts the exact verb strings and
  that the guard no-ops without a focused id. No test spawns herdr.
- `swift test` green (usual skips), portable-surface check passes.
- Live verify via ./scripts/install.sh: fire a rename with capture released
  (leader still responsive immediately after; no stalled tap). Typing into
  herdr's prompt is verified when herdr ships prompt-on-missing-arg.
