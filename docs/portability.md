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

3. **`(modaliser …)` libraries.** The full bundled set lives in
   `Sources/Modaliser/Scheme/lib/modaliser/`. The split into
   *pure-Scheme* vs *native* matters for porting:
   - *Pure-Scheme* libraries (`dsl`, `keymap`, `state-machine`,
     `event-dispatch`, `util`, `ax-hints`, `terminal`, `leader`,
     `window-actions`, `space-switching`, `apps/iterm`, `apps/safari`,
     `apps/chrome`) port verbatim across hosts.
   - *Native* libraries (`shell`, `app`, `keyboard`, `window`,
     `webview`, `input`, `accessibility`, `hints`, `fuzzy`,
     `http`, `pasteboard`, `lifecycle`, `clipboard-history`,
     `library-path`) are Swift implementations bound under
     `(modaliser …)` names. A port to a different host would
     re-implement these in whatever the host uses, keeping the same
     names and signatures.

## What's intentionally *not* portable

Two pieces of the bundled tree are *not* expected to port:

1. **Internal `.scm` modules** at `Sources/Modaliser/Scheme/ui/` and
   `Sources/Modaliser/Scheme/lib/web-search.scm`. These are loaded by
   `root.scm` via `(include …)` and may use `(lispkit …)` bindings
   freely. They handle overlay rendering, the chooser UI, and the
   Google-search helper — pieces that lean on LispKit's WebView and
   JSON bindings. Phase D leaves these alone by design (spec
   non-goal: "Internal pieces that are unlikely to port (e.g.
   WebView, AX) can continue to lean on Foundation / AppKit through
   the existing native libraries; only the user-facing surface needs
   to be portable.").

2. **The native libraries' Swift implementations.** Portability means
   the *names* `(modaliser shell)` etc. are stable contracts — the
   Swift code behind them is not.

User configurations that need to interoperate with those internal
pieces (e.g., to call `web-search-handler` from a selector) will be
host-specific to that extent. The bundled `default-config.scm` does
this in two places (the "Google Search" selector and the
"Applications"/"Files" selectors that use `find-installed-apps` /
`activate-app` / `reveal-in-finder`) and is itself a LispKit-only
configuration as a result. That's an accepted trade-off for the seed
config; library-izing those helpers is a possible future phase.

## The convention (for new `(modaliser …)` libraries)

Any new `.sld` file added under `Sources/Modaliser/Scheme/lib/modaliser/`
**must not** import from `(lispkit …)`. The import section can only
mention `(scheme …)`, `(srfi …)`, and other `(modaliser …)`
libraries. If you find yourself wanting a LispKit-only primitive,
the right answer is one of:

- Implement it locally in pure Scheme (as Phase D did for
  `string-split` / `string-trim`).
- Re-export it from `(modaliser util)` through a portable backend
  (as Phase D did for the hashtable primitives via SRFI 69).
- Expose it as a *new* `(modaliser …)` native library on the Swift
  side, with the contract that future hosts will re-implement it.

## How to audit

```
./scripts/check-portable-surface.sh
```

The script greps `Sources/Modaliser/Scheme/lib/modaliser/` for
`(lispkit ` and exits non-zero if it finds anything. Run it before
opening a PR that touches the library tree. CI is the long-term
home for this check.

**Scope.** The audit covers only `.sld` files under
`Sources/Modaliser/Scheme/lib/modaliser/`. The `.scm` files under
`Sources/Modaliser/Scheme/ui/` and `Sources/Modaliser/Scheme/lib/`
(loaded via `(include …)`) are out of scope by design — those are
the internal modules the "What's intentionally *not* portable"
section enumerates. If you `(include …)` such a file into your own
library, the portability check won't catch any `(lispkit …)`
bindings you pick up that way.

## See also

- [`docs/user-libraries.md`](user-libraries.md) — user-side guide to
  splitting configs and shadowing libraries.
- [`docs/superpowers/specs/2026-05-16-modular-config-architecture-design.md`](superpowers/specs/2026-05-16-modular-config-architecture-design.md) — umbrella spec.
- [`docs/superpowers/prompts/2026-05-16-modular-config-kickoff.md`](superpowers/prompts/2026-05-16-modular-config-kickoff.md) — phase plan.
