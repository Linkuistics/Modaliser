# Portability

Modaliser's *configuration language* is portable Scheme — the same
`config.scm` and the same `(modaliser …)` library set work on any
[R7RS](https://small.r7rs.org/) Scheme implementation that ships
SRFI 69 and has implementations of Modaliser's native libraries
available. The current build runs on
LispKit; a future Chez or Racket build would swap out the
`Sources/Modaliser/` Swift sources but leave
`Sources/Modaliser/Scheme/lib/modaliser/` untouched.

This document describes what user configurations and bundled
`(modaliser …)` libraries are allowed to assume — and what is
deliberately off-limits to keep that promise.

## The portable surface

Code under `Sources/Modaliser/Scheme/lib/modaliser/` and any
user-shipped `.sld` file may import from:

1. **R7RS standard libraries** that LispKit ships and that every
   serious R7RS host provides:
   - `(scheme base)` — core forms, numbers, lists, strings, ports.
   - `(scheme bitwise)` — `bitwise-and`, `bitwise-or`, `arithmetic-shift`.
     Used by `(modaliser dsl)` and `(modaliser keymap)` for
     modifier-mask construction.
   - `(scheme char)` — `char-whitespace?` and friends.
   - `(scheme file)` — `open-input-file`, `file-exists?`.
   - `(scheme write)` — `display`, `write`, `newline`.

2. **SRFI 69** (basic hash tables) — `make-hash-table`,
   `hash-table-set!`, `hash-table-ref/default`, `string-hash`. Widely
   supported across R7RS hosts.

3. **`(modaliser …)` libraries.** The split into *pure-Scheme* vs
   *native* matters for porting:
   - *Pure-Scheme* libraries are everything under
     `Sources/Modaliser/Scheme/lib/modaliser/` (`dsl`,
     `configuration`, `handoff`, `fsm`, `window-actions`, `terminal`,
     the `apps/*` / `muxes/*` / `wms/*` / `tools/*` / `blocks/*`
     sets, …). This
     whole tree obeys the convention below and ports verbatim across
     hosts.
   - *Native* libraries (`shell-native`, `http-native`, `app`,
     `keyboard`, `window`, `webview`, `input`, `accessibility`, `hints`,
     `fuzzy`, `pasteboard`, `lifecycle`, `cursor`, `log`,
     `library-path`) are Swift implementations bound under
     `(modaliser …)` names, registered in `SchemeEngine.init` (the
     canonical list). A port to a different host would re-implement
     these in whatever the host uses, keeping the same names and
     signatures.

## What's intentionally *not* portable

Two pieces of the bundled tree are *not* expected to port:

1. **Internal `.scm` modules** at `Sources/Modaliser/Scheme/ui/`
   (`css.scm`, `overlay.scm`, `chooser.scm`). These are loaded by
   `root.scm` via `(include …)` and may use `(lispkit …)` bindings
   freely. They handle overlay rendering and the chooser UI — pieces
   that lean on LispKit's WebView and JSON bindings. The portability
   slice leaves these alone by design (spec non-goal: "Internal pieces
   that are unlikely to port (e.g. WebView, AX) can continue to lean
   on Foundation / AppKit through the existing native libraries; only
   the user-facing surface needs to be portable.").

2. **The native libraries' Swift implementations.** Portability means
   the *names* `(modaliser shell)` etc. are stable contracts — the
   Swift code behind them is not.

User configurations that reach for those internal pieces' top-level
bindings will be host-specific to that extent. The bundled
`default-config.scm` no longer does: it is authored entirely from
`(modaliser …)` library imports (the search and launcher helpers it
once leaned on now live in the portable `(modaliser web-search)` and
`(modaliser launchers)` libraries), so the seed itself stays on the
portable surface.

## The convention (for new `(modaliser …)` libraries)

Any new `.sld` file added under `Sources/Modaliser/Scheme/lib/modaliser/`
**must not** import from `(lispkit …)`. The import section can only
mention `(scheme …)`, `(srfi …)`, and other `(modaliser …)`
libraries. If you find yourself wanting a LispKit-only primitive,
the right answer is one of:

- Implement it locally in pure Scheme (as the portability slice did for
  `string-split` / `string-trim`).
- Re-export it from `(modaliser util)` through a portable backend
  (as the portability slice did for the hashtable primitives via SRFI 69).
- Expose it as a *new* `(modaliser …)` native library on the Swift
  side, with the contract that future hosts will re-implement it.

## Semantic constraints (beyond imports)

A clean import section is necessary but not sufficient: the portable
tree also has to run on the *current* host, so anything R7RS specifies
but LispKit omits is off-limits too. Four constraints shape real code:

1. **No mutable pairs.** LispKit excludes `set-car!` / `set-cdr!` — a
   reference to them parses cleanly and errors only at call time.
   Structure that needs in-place mutation (graph nodes and back-edges,
   caches, registries) lives in SRFI 69 hashtables, never in list
   structure; pure list code returns new lists (return-and-merge)
   instead of splicing in place. The FSM graph in `fsm.sld`
   is the worked example: nodes, edges, and back-references are
   hashtable entries keyed by name.

2. **Read shared mutable state through procedures, not variables.**
   When one library exposes mutable state to another, it exports an
   accessor procedure (often paired with a `set-…!` installer the host
   calls at boot) rather than the variable itself, so every read
   observes the current value instead of an import-time snapshot.
   `overlay-open?` / `set-overlay-open!` in `fsm.sld` is the
   worked example — its comments describe reading "through the
   procedure so the mutation is always seen, never snapshotted".

3. **No procedure-arity introspection.** R7RS has no portable way to
   ask a procedure how many arguments it accepts. Where the tree must
   dispatch on that — a hook the user may write nullary *or* 1-arg —
   the library exports a predicate cell holding the conservative
   answer, plus a `set-…!` installer the host calls at boot with the
   real check (LispKit's `procedure-arity-includes?`). `fsm.sld`'s
   `set-on-leave-accepts-reason!` and `set-fsm-accepts-arg!` are the
   two instances, both installed by `root.scm`; see
   [state-machine.md](state-machine.md#the-exit-reason). Note what the
   default buys and what it does not: it keeps every *nullary* hook
   working in an uninstalled engine, but a hook that does declare an
   argument raises there. The shape is the one
   [ADR-0023](../adr/0023-native-reach-is-host-installed.md) uses for
   outward reach, but the motive is different and so is the fallback —
   there the uninstalled default is *inert by design*, a safety
   property; here it is merely backwards compatibility.

4. **Never scan a string by index.** `(string-ref s k)` inside a loop
   guarded by `(string-length s)` is Θ(n²) on this host — LispKit
   stores strings as `NSMutableString` and both primitives bridge the
   whole thing on every call, so one pass copies ~2n² bytes. Convert
   once and scan the conversion: `string->list` for a sequential walk
   (`escape-string` in `util.sld`), `string->vector` +
   `vector-ref` / `vector->string` when the scanner needs lookahead or
   substring lifts (`json-parse` in `json.sld`). The forbidden shape is
   the **loop**: a constant number of indexings — a length test, a
   first-character check, one `substring` — is a linear cost like any
   other, and indexing a *bounded literal the code owns* is fine at any
   count. It cost a 53-second leader press before it was written down —
   see [ADR-0025](../adr/0025-portable-scheme-never-indexes-a-string.md).
   Unlike the import rules, this one has **no enforcement at all**:
   `string-ref` is not always wrong, and telling the wrong use from the
   right one means recognising a loop, which a grep cannot do. Review is
   what holds it. The tripwire in `(modaliser instrument)` is a
   diagnostic, not a checker — it fires only at sites whose author called
   `instrument-sample!`, only with instrumentation on, and only for input
   someone exercised, so it tells you *which* site is carrying the payload
   once something is already slow rather than warning you that a new
   scanner exists. See
   [measure-a-leader-press.md](../how-to/measure-a-leader-press.md).

## How to audit

```
./scripts/check-portable-surface.sh
```

The script greps `Sources/Modaliser/Scheme/lib/modaliser/` for two
patterns and exits non-zero if it finds either. Run it before opening a
PR that touches the library tree. CI is the long-term home for this
check.

1. `(lispkit ` — the portability rule above.
2. `(modaliser …-native` — the **outward-reach** rule
   ([ADR-0023](../adr/0023-native-reach-is-host-installed.md)). A native
   capability that reaches outside the process is quarantined behind a
   seam whose runner is **not installed by default**; only `root.scm`
   holds the native one. Two exist: `(modaliser shell)` over
   `(modaliser shell-native)` for spawning, and `(modaliser http)` over
   the native HTTP library for fetching. A library importing a native
   form would re-open the path that put 419 commands onto the
   developer's machine during a green test run — at a live iTerm2,
   Ghostty, wezterm, zellij, kitty and tmux, plus 216 spawns of the
   user's own login shell — or the path that fetched a third-party
   endpoint on every run.

   The rule is stated over the **`-native` suffix**, not over a list of
   library names, so quarantining a future capability is a naming
   decision and needs no edit to the script. The corollary for anyone
   adding a native library: a name ending in `-native` is a promise that
   nothing in the portable tree imports it.

Both patterns are matched textually, which means **prose in the tree
must avoid writing either in parenthesised form** — say "the LispKit
hashtable library", "the native shell library", "the native HTTP
library". The convention is enforced by the check itself: if a comment
trips it, rephrase the comment.

### The sibling check

`scripts/check-decision-free.sh` guards the same tree along the other
axis, and the two are run together:

```
./scripts/check-portable-surface.sh
./scripts/check-decision-free.sh
```

Portability constrains what a library may **depend on**; the
decision-free contract ([ADR-0021](../adr/0021-decision-free-libraries.md))
constrains what a library may **contain** — a **facility**, whose
correctness is fixed by the tool it wraps, but never a **decision**,
whose correctness is fixed only by the user's preference. Its
operational test is that no file under `lib/modaliser` authors a key or
a label, and like the portability check it is strict: one authored
binding fails it, exactly as one `(lispkit …)` import fails this one.

The two invariants are independent but pull the same way. Portability
is what lets a configuration be written against a stable surface at
all; decision-freedom is what keeps that surface worth writing
against, by holding the user's keymap in user space where a host swap
cannot reach it.

**Scope.** The audit covers only `.sld` files under
`Sources/Modaliser/Scheme/lib/modaliser/`. The `.scm` files under
`Sources/Modaliser/Scheme/ui/` and `Sources/Modaliser/Scheme/lib/`
(loaded via `(include …)`) are out of scope by design — those are
the internal modules the "What's intentionally *not* portable"
section enumerates. If you `(include …)` such a file into your own
library, the portability check won't catch any `(lispkit …)`
bindings you pick up that way.

## See also

- [library-system.md](library-system.md) — user-side guide to
  splitting configs and shadowing libraries.
- [dsl.md](dsl.md) — the DSL forms exported from `(modaliser dsl)`.
