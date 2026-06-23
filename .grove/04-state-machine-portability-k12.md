# state-machine-portability-k12

**Kind:** work

## Goal

Restore the **portability invariant** so `check-portable-surface.sh` goes green
again. `state-machine.sld` imports `(only (lispkit core)
procedure-arity-includes?)` (line ~45), which the gate forbids — the
`(modaliser …)` tree must import only `(scheme …)` / `(srfi …)` / `(modaliser …)`
(see `docs/reference/portability.md`).

## Context

- **Not introduced by this grove.** It came in on `main` via commit `4801172`
  (2026-06-20, "feat(modal): pass exit reason to on-leave hooks; Return
  confirms") — one of the in-flight `state-machine.sld` changes the **root
  BRIEF** flags as a rebase/coordination point. `lowering-k10` surfaced it: the
  gate is red on the baseline, independent of the layout-DSL work.
- The single use is in `run-on-leave` (state-machine.sld ~270–276):
  `procedure-arity-includes?` decides whether to pass the exit `reason` to a
  1-arg on-leave hook vs. call a 0-arg hook. There is **no R7RS-portable arity
  primitive**, so the import can't just be swapped for a `(scheme …)` form.
- The codebase already has a **clean precedent for host primitives**: the
  overlay/chooser hooks are *injected by mutation* from the host side
  (`set-show-overlay!` etc., state-machine.sld ~355–404), keeping the library
  body portable. An arity-check shim can follow the same shape — a mutable cell
  defaulting to "assume 0-arg" (or "always pass reason"), with the host
  installing the real `procedure-arity-includes?`-backed predicate at boot
  (root.scm), the way `set-modal-key-handler!` is wired.

## Done when

- `state-machine.sld` no longer contains the literal `(lispkit …)` import;
  `scripts/check-portable-surface.sh` exits 0 (green).
- `run-on-leave`'s reason-vs-no-reason dispatch still works: a 1-arg on-leave
  hook receives the exit reason ('confirm / 'cancel / 'exit / 'navigate), a
  0-arg hook is called with none. Covered by a test (the existing reason-aware
  on-leave tests must still pass).
- The host installs the real arity predicate at boot (mirror the overlay-hook
  injection wiring in `root.scm`); the portable default is safe if uninstalled.
- Full `swift test` stays green.

## Notes

- Coordinate with `main`: if `main` is fixing this independently, prefer
  rebasing onto that fix over a divergent shim. Confirm at merge time.
- Keep the change **minimal and state-machine-local** — this is an invariant
  repair, not a redesign of the on-leave hook protocol.
