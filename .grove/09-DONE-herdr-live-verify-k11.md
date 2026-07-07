# herdr-live-verify-k11

**Kind:** work

## Goal

The single consolidated **live visual confirmation** of the whole herdr-in-iTerm
path, deferred through leaves 3 / k9 / k10 (each shipped JSON-verifiable + unit-
tested code but left the on-screen check for one installed-app pass). Confirm the
variant trees switch and the control surface + chips actually work against the
user's real herdr-in-iTerm client. **Human-driven** — needs the user's live herdr
window frontmost, and pressing the leader takes over the keyboard/screen, so it is
its own low-context session rather than an automated step.

## Context

Read the root `BRIEF.md` and the retired `04-herdr-tree-content-k4/BRIEF.md`
(herdr JSON shapes + the area-relative chip offset). The code is all committed and
green (`swift test`, `check-portable-surface.sh`); this leaf only *observes* it live.

Setup: `./scripts/install.sh` (release build → /Applications; code-signs with the
"Modaliser Dev" cert to preserve the Accessibility TCC grant — see
[[feedback_codesigning]] / [[feedback_install_flow]]), **Relaunch** from the menu
bar, then make the herdr-in-iTerm window frontmost and press the leader (F17).

## Done when

Confirmed live from Modaliser (fix or file a follow-up leaf for anything that
misbehaves):

- **Variant switch.** herdr sole current-tab split → the **replace** tree
  (`/herdr`, zero iTerm controls). herdr + another iTerm split in the same tab →
  the **augment** tree (`/herdr+split`, herdr tree + the `i` iTerm-splits drill).
  Neither → today's plain iTerm tree.
- **Controls (k9).** hjkl focus (sticky latch), x split (incl. left/up split-then-
  swap), m move, z zoom, d close; the Tabs (t) / Workspaces (w) drills with
  n/r/d + the live lists; digit-jump focuses the right pane/tab/workspace.
- **Chips (k10).** Drilling to the Panes panel paints digit chips over the on-screen
  herdr panes, **correctly placed in replace mode** (area-relative, no sidebar
  shift); leaving the panel hides them. Augment-mode chips may be misplaced — that
  is the **documented** limitation (`docs/reference/terminal-detection.md`), not a
  bug to fix here; just confirm hjkl focus + digit-jump still work there.

## Notes

- If the variant trees don't switch, start at the composed context-suffix hook in
  the user config (`app-trees/com.googlecode.iterm2.scm`) and `terminal:in-chain?
  'herdr` — the resolve path was unit-verified (k3) but this is its first *live* run.
- Overlay/chip visual-layout gotchas: [[reference_overlay_layout_verification]],
  [[feedback_chips_are_overlays]] (chips are native overlay windows, never text
  into the terminal).
