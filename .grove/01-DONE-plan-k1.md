# plan-k1

**Kind:** requirements

## Goal

Establish what "add paneru controls" means, by grilling, and grow the tree from
the result.

## Context

"Paneru" appeared nowhere in the repo at the start of this session — it is an
external tool the user brought. Grounding was established before any question was
asked, and empirically rather than from documentation, because paneru turned out
to be installed *and running* on this machine with a live socket:

- **Control surface** — `paneru send-cmd <space-separated command>` over
  `/tmp/paneru.socket`; `paneru query state --json`; `paneru subscribe --json`.
  The underscored spelling (`window_focus_east`) is the TOML *binding name*, not
  the wire form.
- **Payload schema** — read off the live daemon, not the docs. Windows carry
  `window_id`, `bundle_id`, `app_name`, `title`, `focused`, `floating`, nested
  under `virtual_workspaces[].windows`. Crucially: **no column index**.
- **Id space** — paneru's `window_id` values were compared against
  `CGWindowListCopyWindowInfo` on the same machine and matched exactly, and
  Modaliser's own ids come from `_AXUIElementGetWindow`. One number space. This
  is the fact ADR-0024 rests on.
- **The user's `paneru.toml` has an empty `[bindings]` section** — paneru has no
  keyboard layer today, which is what this workstream supplies.

The architectural tension found: Modaliser and paneru **both** claim the window
domain, with vocabularies that do not map — absolute geometry (thirds, halves,
centre) against relative motion on an infinite strip. That ruled out the obvious
"paneru as a backend behind the existing w-menu" shape early.

## Done when

- [x] Grilling session held; every decision put to the user with a recommendation.
- [x] `CONTEXT.md` gains the **Paneru-window-management domain** — Paneru,
      Column, Paneru op, Paneru-installed composition, Strip listing.
- [x] ADR-0024 raised for the one decision that clears the when-to-write test.
- [x] Test seams sketched and agreed before design: one seam
      (`current-shell-runner`) plus pure parse and join functions.
- [x] Root brief records the nine decisions and their reasoning.
- [x] Tree grown: one design review chain and three impl leaves.

## Notes

Nine decisions, listed in the root brief. Two are worth flagging as *changes of
direction* rather than confirmations:

- The user's opening framing was "when paneru is **running**". Grilling moved
  that to "when paneru is **installed**" — the user raised the startup-order race
  themselves mid-session, and ADR-0017's existing doctrine answered it. The
  glossary records "is paneru running?" as the phrasing to avoid.
- The user's framing was also "replace the window options with commands for
  `paneru send-cmd`", which read naturally as *including* the jump targets. The
  payload's missing column index made that silently wrong under stacked and
  floating windows, so targeting moved off paneru's own command onto the id join.
  ADR-0024 exists because that departure from the obvious mechanism is
  surprising without the reasoning.

No research pair was cut: the survey work this workstream needed was done here
against the live daemon, and a second corpus would have added nothing a
`query state --json` call did not already settle.
