# provider-state-id-k9

**Kind:** impl

## Goal

Give an **Edge provider** the id of the state it is lowered onto, and wire
`'provider` through `open`. Both are prerequisites for `paneru-strip-list-k7`:
without them a two-key jump label cannot mint a usable narrowing prefix state.

## Context

`docs/specs/paneru-window-management.md` decision 5 states the change and why the
three alternatives lost. The short version: a provided *resting* state's id must
read `<owner-id>/<leader>` and its `'up` edge must target `<owner-id>`, or
`strip-id-prefix` garbles the breadcrumb (or raises) and `ancestors-within-tree`
stops the climb early. `muxes/herdr.sld` gets away with hardcoding
`herdr-jump-scope` only because its provider sits on a registered screen whose
scope is machinery; a provider under `open` cannot know its owner, and
`%fsm-visit-owner` is set *after* the provider runs, so it is not a fallback.

The engine already has the value: `resolve-state-def` puts `'id` on every def —
permanent and provided alike — and `def-id` reads it. `classify-and-snapshot`
holds the def.

## Done when

- `classify-and-snapshot` invokes a provider with the owning state's id.
- The three existing providers accept the argument: `muxes/herdr.sld`'s root jump
  provider and its per-prefix-state provider, and `activation.sld`'s
  `compose-step-in-provider` (which must also pass it through to the authored
  provider it wraps). Only paneru's new provider will *use* it — herdr keeps
  `herdr-jump-scope` as-is; simplifying herdr onto the argument is a separate
  concern.
- `open` accepts `'provider`, threading it through its argument parse into the
  existing `dispatch-head` call, exactly as `group` and `screen` already do.
- The three sites that currently document the opposite are corrected in the same
  commit: `dsl.sld`'s `open` docstring (the `dsl-provider-wiring-k24` note),
  `docs/reference/dsl.md`, and `docs/reference/state-machine.md` — the last also
  gains the provider's new argument in its contract description.
- `CONTEXT.md` → **Edge provider** records the argument and why it exists.
- A lowering test covers `'provider` on `open` (`FsmLoweringTests` covers
  `group`/`tree-root` only today), and a test asserts a provider receives its
  owner's id.
- `swift test` is green — herdr's two providers are the regression surface, so
  check they are actually exercised and add coverage if they are not.
- `check-portable-surface.sh` and `check-decision-free.sh` both pass.

## Notes

This is engine machinery shared by every screen, so the change stays as narrow as
the spec states it: one call site in `fsm.sld`, one keyword in `dsl.sld`, three
provider signatures, and the docs that describe them. Do not take the opportunity
to refactor herdr's jump lowering — the spec records the criterion for extracting
that, and it is not met.
