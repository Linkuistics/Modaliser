# capture-release-signal-k4

**Kind:** planning

## Goal

Decide, and if warranted implement, a *structural* (tree-level) way for a
command to signal "running me releases modal capture" — instead of the
current design where a dialog-raising action releases capture imperatively,
from inside its own body, by calling `(modal-exit)` as its first statement.
Grill toward either (a) a real static signal — most likely a new DSL/tree
node kind, e.g. modelled on `selector?` — or (b) an explicit, well-justified
conclusion that no such signal is safely expressible and the current
per-action self-release (already implemented, see below) is correct as-is.

This surfaced mid-session while executing `herdr-dialogs-async-k2` (now
renumbered to `03-herdr-dialogs-async-k2.md`) and blocks that leaf's final
shape: whether `(modaliser dialogs)`'s public surface is plain CPS procedures
(current draft) or DSL node constructors (the alternative this leaf grills).
Suggested to use a stronger reasoning tier for this session — the design
space has several dead ends that look tempting at first (see below).

## Context

### The question, precisely

`modal-handle-key` (`state-machine.sld`) runs a command's `action` **before**
deciding whether to clean up modal state afterward (exit, or reset-to-sticky-
ancestor, or transition via `'sticky-target`). That ordering exists so an
action can call `(enter-mode! ...)` and have the framework push the still-
live calling context onto `modal-stack` — see the long comment at
`state-machine.sld:723-733`.

ADR-0014 (this grove, `docs/adr/0014-dialogs-release-capture-and-run-async.md`)
needed dialog-raising commands to release capture (unregister the catch-all
key handler) *before* the dialog shows, regardless of that ordering. It
resolved this by having `(modaliser dialogs)` call `(modal-exit)` itself, as
literally the first line of `dialog-prompt` / `dialog-confirm` / `dialog-info`
— correct, but the "release" decision is made *imperatively inside the
action's own body*, not visible anywhere in the tree/DSL structure. This
leaf's question: can/should that decision instead be a **static property of
the tree node**, discoverable before any action runs — the same way
`selector?` nodes already are?

### Dead ends already ruled out this session (don't re-derive these)

1. **"Release before any action, period."** Breaks dialogs fired from a
   sticky context: the framework's post-action default for a sticky node is
   `modal-reset-to-sticky-ancestor` (stays captured), so a blanket release
   would need to special-case sticky anyway — see next point.

2. **"Release before any *non-sticky* action."** Counter-example:
   `focus-pane-by-digit` — implemented identically in **all seven** terminal
   backends (`apps/ghostty.sld:313`, `apps/iterm.sld:661`,
   `apps/kitty.sld:686`, `apps/wezterm.sld:355`, `muxes/tmux.sld:376`,
   `muxes/zellij.sld:418`, `muxes/herdr.sld:281` at time of writing) — is a
   plain, non-sticky, non-`sticky-target` command whose action is just
   `(enter-mode! '*-pane-digit)`. It's also the **documented canonical
   example** of the pattern in `dsl.sld:527`. Releasing before it runs means
   `enter-mode!` takes its `(not modal-active?)` branch (`state-machine.sld:545`)
   instead of the "push calling context onto `modal-stack`" branch — Escape
   from the digit-jump mode then exits the whole modal instead of returning
   to the calling tree. Silent regression, present everywhere this pattern
   is used.

3. **"Statically predict which non-sticky commands will exit after."** Dead
   on arrival: `focus-pane-by-digit` and `rename-focused-tab!` are
   *structurally identical* at the tree level (both plain commands, no
   `sticky-target`, non-sticky context) — every static fact available before
   either runs is the same for both, yet one needs capture to **stay live**
   (`enter-mode!` needs it) and the other needs it **released** (the dialog
   needs it). The only thing that differs is what the action's body actually
   does, which is unknowable without running it — the same "can't know when
   an action finishes / what it needs" problem already conceded infeasible,
   just moved earlier.

### The promising precedent: `selector?`

Selectors (the fuzzy-finder chooser) already have exactly this problem —
opening the chooser also needs the keyboard, unconditionally, regardless of
sticky context — and it's *already solved structurally*, not imperatively:

- `(selector ...)` (`dsl.sld:424`) is a **node constructor**, not an action
  procedure. `(key K L (selector ...))` embeds a `'kind 'selector` alist
  directly as the key's child — see `key-build` / `decorate-node`
  (`dsl.sld:86-126`) for how `key` dispatches on a procedure vs. a node.
- `modal-handle-key`'s dispatch (`state-machine.sld:798-800`) checks
  `(selector? child)` **before** running anything, and unconditionally calls
  `(modal-exit)` then `(open-chooser child)` — no per-call reminder, no
  sticky-context special-casing, because the node's *kind* carries the fact.
- `open-chooser` itself is a **hook**, not a direct call into a chooser-
  specific library: `state-machine.sld` defines `open-chooser-impl` as a
  mutable cell (default no-op, `state-machine.sld:401`) plus a setter
  `set-open-chooser!` (`state-machine.sld:411`), and the host-specific
  chooser UI (`ui/chooser.scm`) installs the real implementation at boot.
  This is exactly the pattern that would let `state-machine.sld` dispatch to
  dialog-firing logic **without** a circular import — `(modaliser dialogs)`
  already imports `(modaliser state-machine)` for `modal-exit`, so
  `state-machine.sld` cannot import `dialogs.sld` back; a `set-dialog-runner!`-
  style hook (mirroring `set-open-chooser!`) sidesteps that.

The open design work, if this direction is taken: what the new node kind's
shape is (one `'kind 'dialog` with a sub-tag for prompt/confirm/info, vs.
three separate kinds); whether `key`'s third-arg dispatch
(`dsl.sld:56-63`, "does NOT defer side-effecting calls") needs a variant for
a node whose *firing* is deferred but whose *construction* must still be
side-effect-free at tree-build time (today's `dialog-prompt` etc. fire
immediately when called — becoming a node constructor means splitting
"build the (title/message + continuation) node" from "actually run
`current-dialog-runner`", the latter living behind the new hook); and
whether `sticky-target` composition on a dialog node means anything (does a
dialog ever need to leave the user in a *different* sticky mode after the
continuation resolves? — check the four herdr call sites and the three
leaf-04 error-dialog sites for whether any need this).

### Already built — a working fallback, not yet committed

This session got as far as a complete, ADR-0014-correct implementation using
the **current** (imperative self-release) design, sitting **uncommitted** in
the worktree:

- `Sources/Modaliser/Scheme/lib/modaliser/dialogs.sld` — new library:
  `dialog-prompt` / `dialog-confirm` / `dialog-info`, `current-dialog-runner`
  parameter, `sq-escape` (exported), `as-escape` (internal). Each dialog
  function's first statement is `(modal-exit)`.
- `Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld` — the four dialog
  call sites (`rename-focused-tab!`, `rename-focused-workspace!`,
  `new-worktree!`, `remove-focused-worktree!`) converted to CPS, importing
  `dialog-prompt` / `dialog-confirm` / `sq-escape` from the new library;
  local `sq-escape` / `prompt-text` / `as-escape` / `osascript-run` /
  `confirm-dialog` definitions removed.
- No tests, no docs update, no `swift test` run yet — `swift build` passes
  (doesn't validate Scheme).

If this leaf concludes the imperative design is correct after all (or
correct enough not to warrant a redesign), `herdr-dialogs-async-k2` resumes
straight from this state — tests + docs + live verify is what's left. If the
node-kind redesign is adopted, this implementation is the concrete "here's
what door #1 costs" reference to redesign against, not a wasted detour.

## Done when

- The capture-release question has a decided answer, recorded either as a
  revision to ADR-0014 in place (if the decision changes it) or an explicit
  note that ADR-0014 stands as originally written (if it doesn't).
- If a new node kind is adopted: its shape (predicate, constructor location,
  hook mechanism) is settled well enough that `herdr-dialogs-async-k2` can
  implement against it without further design questions — a spec
  (`docs/specs/`) if the increment warrants one per `SPEC-FORMAT.md`.
- `herdr-dialogs-async-k2`'s task file (`03-herdr-dialogs-async-k2.md`)
  updated if its Context/Notes need to reflect the decided shape.

## Notes

- Started as a live design discussion inside `herdr-dialogs-async-k2`'s own
  session; externalized here per the grove Decompose step rather than
  absorbed inline, since it reopens a decision ADR-0014 already made after a
  dedicated grilling pass (`01-DONE-plan-k1.md`) and has a blast radius wider
  than that leaf (touches `state-machine.sld`, `dsl.sld`, all seven terminal
  backends' digit-jump pattern, and the public DSL surface documented at
  `dsl.sld:527`).
- Follow the grilling procedure (`grilling.md`): one question at a time,
  recommended answer each time, no tree growth until shared understanding is
  reached.
