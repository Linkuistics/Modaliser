# A failed config degrades, and the guard lives in the host

A user config that fails to load must leave Modaliser **usable**: the status-bar
menu is built and fully enabled, the error is on it and in a dialog, and the
bundled `default-config.scm` is armed in the broken config's place so leader
keys still respond. The load is **sequenced by the host**, not guarded in
Scheme: `SchemeEngine.loadConfiguration` evaluates the user's config, and on an
abort evaluates the bundled default, then `root.scm`'s
`modaliser:config-load-finished!` receives the outcome (`'loaded` / `'degraded`
/ `'failed` — the last meaning the bundled default aborted too) and builds the
menu around it. `ModaliserAppDelegate`'s modal alert survives for one case
only — `root.scm` itself failing, where there is no menu and no capture to
degrade to.

## Why it binds

**Scheme cannot catch its own config failing.** LispKit implements `raise` in
Scheme (`_wind-up-raise` in its dynamic-control library), so `guard` sees only
conditions a Scheme program raised deliberately. All three ways a config
actually fails — a read error, a type error, an unbound variable — are thrown
out of the virtual machine as host errors and unwind past every Scheme handler;
each was measured escaping a `guard` before this was designed. Nor can a native
primitive wrap the load: `evaluator.execute` asserts top level, so a nested
evaluation from inside a primitive is a precondition failure, and catching a
throw mid-`apply` would leave the machine's stack pointer dirty for the
still-running outer evaluation. Two *sequential* top-level evaluations, with the
host looking at the abort in between, is the only shape that works. This is the
one place the Scheme-first doctrine does not reach, and the reason is a property
of the interpreter, not a preference.

**The fallback is safe because of the Handoff.** `modaliser:start!` validates
before it installs and latches only on success (ADR-0018), so a config that dies
mid-file installed *nothing* — the config-error state is defined as "nothing was
ever installed". The bundled default therefore loads into a clean engine instead
of colliding with half of the user's graph. Stray top-level `define`s from the
partial evaluation survive in the global environment and are harmless; the graph,
the backends, and the leaders are untouched.

This is a **precondition for ADR-0021**, not a nicety. Widening user-facing
authoring surface from ~15 named library symbols to ~150 multiplies the ways a
config can name something the running binary no longer binds. While that wedged
the app, deleting an export converted a working install into a dead one; now that
it degrades, deleting one is **survivable but not free** — a config naming the
removed symbol falls back to the bundled default until its owner migrates it.

## Considered options

1. **`guard` around the load in `root.scm`.** Rejected: it does not catch — see
   above. Reopened by: LispKit routing host `RuntimeError`s through the Scheme
   exception-handler stack.
2. **A native `(load-guarded path)` primitive**, keeping the sequencing in
   `root.scm`. Rejected: it needs a nested evaluation, which `execute`'s
   top-level assertion forbids, and the non-asserting `apply` path leaves the VM
   stack inconsistent after a caught throw. Reopened by: a LispKit API for
   re-entrant evaluation with clean unwind.
3. **Keep the modal alert, improve its text.** Rejected: `NSAlert.runModal`
   disables the status-bar menu for the duration and every exit path terminates,
   which is the observed "error visible, app inert" dead end. Reopened by:
   nothing.
4. **Transactional reload — keep the previous good state when a *re*-load
   fails.** Rejected: it presupposes hot reload, which ADR-0018 rejected by
   doctrine (reload is relaunch), so there is no
   previous live state to keep. Reopened by: a hot-reload design that owns full
   runtime teardown — the same trigger that reopens ADR-0018's option 4.
5. **Fall back to nothing — report the error and leave leaders unarmed.**
   Rejected: a Modaliser with no leader keys is indistinguishable from a
   Modaliser that failed to launch, and the bundled default is a fully working
   configuration since the seed carries every screen (ADR-0021). Reopened by:
   nothing.

## Consequences

- The status bar is created **once**, in `modaliser:config-load-finished!`, so
  the error item is part of the menu rather than an update to it. Every item is
  enabled in every outcome: Open Config, Reveal Config in Finder, Reset Config to
  Bundled Default (timestamped backup, then relaunch), Relaunch, Quit.
- The error surfaces three ways: an `os.Logger` line in the app's subsystem under
  the `config` category, a dismissible non-blocking dialog at launch, and a
  permanent menu item that re-opens the full text. `root.scm` logs the boot
  outcome through `log-line`, not `(modaliser util)`'s `log` — the latter is
  `display` + `newline`, which reaches the context delegate's `NSLog` and is
  invisible in the unified log from an installed `.app`.
- The user's config is no longer `include`d by `root.scm`. `root.scm` still owns
  *where* it lives — the host reads `user-config-path` and `default-config-path`
  back out of Scheme rather than restating them.
- Hot reload stays rejected. Robustness was reached without it, so the two are
  no longer coupled: a config error is recovered from by relaunching into the
  bundled default, never by re-loading in place.
