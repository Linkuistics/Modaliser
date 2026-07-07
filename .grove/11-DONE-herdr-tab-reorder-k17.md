# herdr-tab-reorder-k17

**Kind:** work (opens with a capability confirmation — may resolve to "defer")

## Goal

Let the user **rearrange tabs** (move the focused tab up/left, down/right) from
the herdr Tabs drill — the second gap surfaced during live-verify (k11). Today
the `t` Tabs drill offers New / Rename / Close + digit-jump focus, but no way to
**reorder** a tab, mirroring the existing `m` Move Pane affordance for panes.

## Context

Read the root `BRIEF.md`. **Start by confirming the capability — this may not be
buildable in herdr v0.7.1.** The grounding done when this leaf was filed:

- **`herdr tab` CLI (v0.7.1) exposes only:** `list · create · get · focus ·
  rename · close`. There is **no `tab move` / `tab reorder` / `tab swap`**.
- **herdr's keybindings** (`herdr --default-config`) only *navigate* tabs —
  `previous_tab`, `next_tab`, `switch_tab`, `new_tab`, `rename_tab`, `close_tab`.
  **No tab-move/swap/reorder binding exists.** (`pane move --tab <id>` moves a
  *pane* between tabs; it does not reorder tabs.)

So on the evidence gathered, **herdr appears to have no tab-reorder primitive at
all** — neither socket-API CLI nor TUI keybinding. If that holds, this control
cannot be built on the JSON socket API (the design charter's rule: drive herdr
via CLI, never keystrokes/AppleScript).

**First task: reconfirm, don't assume.** Re-check against the *installed* herdr
(the probe above was one CLI/config read): `herdr tab --help`, `herdr --help`,
the full `herdr --default-config`, and the socket API for any undocumented
tab-order verb or a `position`/`index` field on `tab get`/`tab list` that a
`rename`-style mutation could set. Check herdr.dev / release notes for a newer
version that adds tab reordering.

**Then, per outcome:**
- **If a primitive exists** (CLI verb, or a settable order field) — wire a
  `Move Tab` affordance into the `t` Tabs drill in `muxes/herdr.sld`
  `build-herdr-tree` (~line 670): e.g. directional keys → reorder the focused
  tab. Follow the tab/worktree-op patterns already in the file (reissue the JSON
  query at keystroke time; parse with `(modaliser json)`; source-pin by focused
  workspace where relevant). Add a matching test; sync config both ways
  ([[feedback_config_sync]]); keep `check-portable-surface.sh` green.
- **If confirmed absent** — do **not** hack it via injected keystrokes (violates
  the socket-API-only charter and would be fragile). Instead **document the gap**:
  a short note in `docs/reference/terminal-detection.md` (herdr capability table)
  and/or the `muxes/herdr.sld` header listing tab-reorder as a **v1 exclusion
  blocked on upstream herdr**, and consider filing an upstream herdr feature
  request. Then this leaf is done as "confirmed-and-deferred" — a legitimate,
  committed outcome, not a failure.

## Done when

Either the Move-Tab control works live against herdr-in-iTerm (tabs actually
reorder), **or** the absence is reconfirmed and recorded as a documented v1
exclusion (with an upstream pointer). Tests/portability green in the wiring case;
docs updated in the defer case.

## Notes

- "move up/left, down/right" likely mirrors the pane-move mnemonic (h/j/k/l);
  for a linear tab strip that reduces to move-earlier / move-later. Clarify the
  intended key(s) with the user if wiring proceeds.
- Related sibling: [[herdr-copy-mode-k16]] (the other post-live-verify gap).
