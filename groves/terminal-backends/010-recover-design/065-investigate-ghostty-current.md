---
kind: work
---

# 065 — Investigate Ghostty (current release from ghostty.org)

The 060 task used brew's cask (Ghostty 1.3.1) and concluded
"detection-only — workarounds gated on 1.4+." User intervention:
**we can install Ghostty 1.4+ outside of brew** by downloading
the signed DMG from ghostty.org.

This task re-investigates the same surface with the current
release, where the user-recalled workarounds should be present.

## Install

Download the signed DMG from `https://ghostty.org/download`.
Verify the actual version is ≥ 1.4. Copy `Ghostty.app` to
`/Applications/`. Eject the DMG.

## Probe

Re-run the entire 060 audit against the new binary. Specifically
look for things 1.3.1 didn't have:

- **Control socket / IPC** — is there a `ghostty` CLI subcommand
  for talking to a running instance? (1.3.1 only had `+actions`
  like list-fonts.)
- **AX subview exposure** — does Ghostty's GUI window expose per-
  split AX nodes a la iTerm's `AXScrollArea > AXStaticText`?
  TCC required; can probe via Modaliser's existing AX helpers.
- **`new_split:left`/`up` action arg validity** — confirm by
  temporary keybind override.
- **`move_split:<dir>` action** — does this exist (1.3.1 didn't
  have it)?
- **`select_split` by id** — does this exist (for digit-jump)?

Goal: determine whether Ghostty ≥ 1.4 is a full **splitting
backend** or remains detection-only.

## Capture

Write `notes/ghostty-current.md` with:
- Exact version probed (`ghostty --version`).
- Updated capability matrix row.
- Each previously-missing op marked confirmed or still missing.
- If a control socket / IPC exists, document the message
  vocabulary.
- Comparison to 060's findings (what changed between 1.3.1 and
  current).

## Teardown

The user authorised the install but didn't authorise the
uninstall. Default: leave Ghostty.app installed (consistent with
the user's stated need to actually test ghostty workarounds in
future implementation phases). Ask before uninstalling.

Update root `BRIEF.md` machine-state.
