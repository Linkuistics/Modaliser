# Modular config architecture

## Problem

The user configuration today is a single file (`~/.config/modaliser/config.scm`)
loaded by `(include "~/.config/modaliser/config.scm")` from the bundled
`root.scm`. It runs in the top-level evaluation environment and has direct
access to every Modaliser DSL form (`key`, `key-range`, `group`, `selector`,
`define-tree`, `set-leader!`, etc.) plus every OS primitive
(`run-shell`, `launch-app`, `send-keystroke`, `webview-create`, …).

Three problems with that shape:

1. **Single-file growth.** A real configuration accumulates per-app trees,
   shared helpers, custom data — quickly outgrowing one file. Today there is
   no clean way to split it.

2. **No encapsulation for shared helpers.** Helpers used by multiple parts
   of the config are forced into the global namespace; users can't write a
   utility that exposes one public function and keeps three private ones
   hidden.

3. **Implementation lock-in.** The configuration code reaches for whatever
   bindings happen to be present in LispKit's top-level environment. If
   Modaliser later swaps the Scheme runtime (e.g. to Chez or Racket via
   [APIAnyware-MacOS](../../../../APIAnyware-MacOS)), every user
   configuration has to be inspected and rewritten because there is no
   declared dependency surface.

Compounding (3): Modaliser ships a substantial pile of useful, opinionated
Scheme today (the iTerm pane tree, the Safari/iTerm/window helpers, the
overlay machinery) baked into `default-config.scm`. There is no way for a
user to selectively pull in the "iTerm local menu" piece and tweak just
the pane labels — they either inherit the whole default or start from
scratch.

## Goals

1. **Splittable config.** A user can break their configuration across
   multiple files in `~/.config/modaliser/` using standard R7RS forms.

2. **Shippable, parameterizable stdlib.** Modaliser ships a curated set of
   reusable libraries (per-app menus, window helpers, etc.) that the user
   imports and parameterizes. A user gets the iTerm local menu by importing
   it and supplying their pane labels and chip styling — not by copying the
   whole `iterm-pane-bindings` block into their own config.

3. **Visibility control for user utilities.** When a user writes a helper
   library, they choose which bindings are public and which are private,
   using R7RS `define-library` / `export` / `import`.

4. **Portability across Scheme implementations.** The configuration
   language is plain R7RS plus `(modaliser …)` libraries. Nothing in user
   code or in the Modaliser stdlib references a host-specific library
   (`(lispkit …)`). Switching the runtime swaps the *implementation* of
   the OS-primitive libraries; the user's configuration ports verbatim
   (modulo per-host packaging — file extensions, optional `#lang` lines).

5. **No regression in capability.** Anything possible in the existing
   single-file config remains possible — including reading files,
   shelling out, AX queries, dynamic tree rebuilds.

Non-goals:

- A package manager for third-party libraries. Users place files in
  `~/.config/modaliser/`; that is the entirety of the discovery mechanism.
- Recreating R7RS-Large's `(scheme …)` libraries that LispKit doesn't
  already expose. Configuration code uses what is available.
- Eliminating every LispKit-specific code path in the bundled Modaliser
  source. Internal pieces that are unlikely to port (e.g. WebView, AX)
  can continue to lean on Foundation / AppKit through the existing native
  libraries; only the *user-facing* surface needs to be portable.

## Layered architecture

The codebase divides into three layers with clear responsibilities and
import directions. Higher layers depend on lower layers, never the
reverse.

### Layer 1 — Core runtime

The Modaliser execution engine and DSL primitives.

- **Native libraries** (Swift, already in place): `(modaliser shell)`,
  `(modaliser app)`, `(modaliser keyboard)`, `(modaliser window)`,
  `(modaliser webview)`, `(modaliser input)`, `(modaliser accessibility)`,
  `(modaliser hints)`, `(modaliser fuzzy-match)`, `(modaliser http)`,
  `(modaliser pasteboard)`, `(modaliser lifecycle)`,
  `(modaliser clipboard-history)`. Each is a `NativeLibrary` subclass
  whose bindings get registered into the LispKit context at startup.
- **Pure-Scheme libraries** (the part that needs refactoring):
  `(modaliser dom)`, `(modaliser css)`, `(modaliser keymap)`,
  `(modaliser state-machine)`, `(modaliser event-dispatch)`,
  `(modaliser overlay)`, `(modaliser chooser)`, `(modaliser dsl)`,
  `(modaliser util)`, plus existing helpers `(modaliser web-search)`,
  `(modaliser ax-hints)`, `(modaliser terminal)`. Each becomes a
  `define-library` form in its own `.sld` file, importing only
  `(scheme base)` and other `(modaliser …)` libraries.

`(modaliser dsl)` is the surface most user code touches: it exports
`key`, `key-range`, `group`, `selector`, `action`, `define-tree`,
`set-leader!`, `set-host-header!`, `set-overlay-delay!`,
`set-overlay-css!`, `modifier-symbols->mask` and the constants
`MOD-CMD`, `MOD-SHIFT`, `MOD-ALT`, `MOD-CTRL`.

### Layer 2 — Modaliser stdlib

Reusable, parameterizable libraries built on top of Layer 1. Pure Scheme.

- `(modaliser apps iterm)` — exports a builder that produces an iTerm
  local tree given pane labels, chip options, and extra bindings.
- `(modaliser apps safari)`, `(modaliser apps chrome)`, etc. — same shape
  for other common apps.
- `(modaliser window-actions)` — the third / half / center / maximise
  helpers as a library.
- `(modaliser space-switching)` — a builder that emits the `1..N` Space
  binding under whichever keystroke convention the user picks.
- `(modaliser leader)` — small conveniences around `set-leader!`.

These ship inside the application bundle, under
`Resources/Scheme/lib/modaliser/`. Users import them by name; no path
juggling.

### Layer 3 — User configuration

Per-user files in `~/.config/modaliser/`. The only file Modaliser
expects to find is `config.scm` — everything else is the user's choice.

- `config.scm` — entry point. Imports what it wants from Layers 1 and 2.
  Defines top-level trees with `define-tree`, registers leaders.

The user organises supporting files however they like. Two things to
know:

- **Plain `.scm` files** are pulled in via `(include "any/path.scm")`.
  Paths are interpreted relative to the directory of the file
  containing the `include` form, so the user nests files however they
  prefer. No directory name is reserved or required.

- **Libraries** are R7RS `define-library` files. Their *location on
  disk* is dictated by the library *name* the user chooses: a library
  named `(my-prefix helpers)` lives at `my-prefix/helpers.sld` under
  the search root (the user-config dir). This is R7RS's standard
  path-matching — not a Modaliser convention. The first segment of
  the name is whatever the user picks; we recommend not using
  `modaliser` (or `scheme` / `srfi`) for it unless the user is
  intentionally overriding a bundled library, which the lookup-path
  ordering supports (the user-config root is searched first — see
  "Lookup path configuration").

## File layout

Bundled (inside `Modaliser.app/Contents/Resources/Scheme/`):

```
Resources/Scheme/
├── base.css
├── root.scm                       # entry, imports core libs + user config
└── lib/
    └── modaliser/                 # search root for (modaliser …)
        ├── dsl.sld                # (modaliser dsl)
        ├── util.sld
        ├── keymap.sld
        ├── state-machine.sld
        ├── event-dispatch.sld
        ├── dom.sld
        ├── css.sld
        ├── overlay.sld
        ├── chooser.sld
        ├── web-search.sld
        ├── ax-hints.sld
        ├── terminal.sld
        ├── window-actions.sld
        ├── space-switching.sld
        ├── leader.sld
        └── apps/
            ├── iterm.sld          # (modaliser apps iterm)
            ├── safari.sld
            └── chrome.sld
```

User (`~/.config/modaliser/`) — illustrative shape, **not enforced**.
The user can flatten, deepen, or rename anything except `config.scm`:

```
~/.config/modaliser/                # whatever the user wants under here
├── config.scm                      # entry point (the only fixed name)
├── safari.scm                      # (include "safari.scm")
├── work/                           # user-chosen subdir for grouping
│   └── jira-bindings.scm           # (include "work/jira-bindings.scm")
└── mystuff/                        # whatever prefix the user picks
    └── helpers.sld                 # (import (mystuff helpers))
```

Both `Resources/Scheme/lib/` and `~/.config/modaliser/` are roots on
the same **library lookup path** — an ordered list of directories that
the R7RS `import` form consults. There is no separate mechanism for
"Modaliser libraries" vs "user libraries"; both resolve through the
same lookup. The library manager walks the path in order and matches
`(foo bar)` against `foo/bar.sld` under each root. The default order
is user-config first, then bundled Modaliser stdlib, then the host's
R7RS+SRFI directory; the path is extensible (see "Lookup path
configuration" below).

So `(modaliser apps iterm)` resolves to
`Resources/Scheme/lib/modaliser/apps/iterm.sld` because that's where
the first matching file lives, and `(mystuff helpers)` resolves to
`~/.config/modaliser/mystuff/helpers.sld` for the same reason. The
user chooses their first-segment prefix; we only ask that it not be
`modaliser`.

## Lookup path configuration

The library lookup path is an ordered list of directories. Same shape
as Chez's `library-directories` or Racket's `PLTCOLLECTS`.

Default order — **user first**, so the user can always override:

1. **User-config root** — `~/.config/modaliser/`, where the user's own
   libraries live. Searched first so a file the user dropped here
   wins against any same-named library shipped lower on the path.
2. **Bundled Modaliser stdlib root** — `<app-bundle>/Contents/Resources/Scheme/lib/`,
   where `(modaliser …)` libraries live.
3. **Host R7RS + SRFI root** — the Scheme implementation's own bundle
   of standard libraries. On LispKit this is `Resources/Libraries/`
   and is auto-registered during `FileHandler` init; it contains
   `scheme/base.sld`, `scheme/write.sld`, `srfi/1.sld`, etc. On a
   future Chez or Racket build the equivalent directory takes this
   slot. `(import (scheme base))` and `(import (srfi 1))` resolve
   here when not shadowed earlier.

All classes of imports — R7RS standard, SRFI, Modaliser stdlib, user —
resolve through the same R7RS `import` mechanism walking the same
path. There is no "Modaliser import", "SRFI import", or "user import";
just `import` and a list of roots.

First-match-wins is intentional. The user can:

- *Override* any bundled library — including a `(modaliser …)` one or
  a `(scheme …)` / `(srfi …)` one — by dropping a same-named file at
  the right path under `~/.config/modaliser/`. Useful for patching a
  bundled module locally, testing a fork in place, or pulling in a
  newer SRFI implementation than the host ships. Shadowing
  `(scheme …)` or `(srfi …)` is supported but strongly discouraged
  unless you know exactly what you're doing — the rest of the
  configuration assumes those mean what R7RS says they mean.
- *Extend* the path with additional roots (a sibling checkout for
  development, a team-shared directory, etc.) — prepended in front
  of the user-config root, so those win against everything.

### Extending the path

One mechanism for now:

- **Programmatic extension** — a Scheme primitive
  `(prepend-library-path! "/abs/path")` callable from `root.scm`,
  `config.scm`, or anywhere the user wants. The path is prepended in
  front of the user-config root, so additional roots can shadow it
  too. Supports conditional setup ("only add this root if the
  directory exists") trivially: the user writes the `cond`/`when`
  themselves. A path that doesn't exist is silently skipped — same
  forgiving behaviour as `prependLibrarySearchPath` already has in
  LispKit.

Env-var (e.g. `MODALISER_PATH`) and config-file-driven (e.g.
`~/.config/modaliser/load-path.txt`) extension are deferred: both add
maintenance surface, both have edge cases (GUI launch env, file
syntax), and the primitive covers the use cases we can foresee. Add
them when a concrete user need surfaces.

## Library naming and namespaces

Three prefixes have a "well-known" meaning:

- `(scheme …)` — R7RS standard libraries, provided by the host Scheme.
- `(srfi …)` — Scheme Requests for Implementation, also host-provided.
- `(modaliser …)` — Modaliser-bundled libraries.

The user can use any other first segment they like. Common shapes:

- A personal handle: `(antony shared keys)`.
- A descriptive prefix: `(work jira-bindings)`, `(home weather)`.
- A single throwaway name for a small config: `(mine helpers)`.

The library manager consults search paths in order, first match wins.
The default order has the user-config root first, so a user file at
`~/.config/modaliser/modaliser/apps/iterm.sld` *will* shadow the
bundled `(modaliser apps iterm)` — this is intentional, since
intercepting and patching a bundled library locally is a legitimate
workflow. The same is true for `(scheme …)` and `(srfi …)`. We
recommend keeping clear of those three prefixes in everyday use, but
the system never blocks the override.

## Path semantics

Two different load mechanisms with different path resolution rules:

1. **`include`** — compile-time splice. Path resolves relative to the
   directory of the file containing the `include` form. So a
   `config.scm` doing `(include "ui-keys.scm")` pulls
   `~/.config/modaliser/ui-keys.scm`; a deeper file doing
   `(include "../shared/keys.scm")` walks up relative to itself.
   Whatever directory shape the user picks, paths follow naturally.
   Already supported by LispKit (see `CoreLibrary.swift`'s `include`
   implementation passing `inDirectory:` for nested resolution).

2. **`import`** — declarative library reference. Path resolves through
   the library manager's search paths, not by file path. `(import
   (modaliser apps iterm))` matches `<search-root>/modaliser/apps/iterm.sld`.
   File extension is determined by the host (LispKit looks for `.sld`).

For per-app config files at Layer 3 — wherever the user puts them —
`include` is the right primitive: those files contain `define-tree`
calls intended to register into the global state machine, and
`include`-splicing them puts their effects at file scope. `load` is
the runtime equivalent but requires per-call `change-current-directory!`
to get the right path semantics; not worth the friction.

## File extensions across hosts

- LispKit: `.sld` for library files (hard-coded `libraryFilePath`
  scanner), `.scm` for everything else.
- Chez Scheme: `.sls` (or `.ss`) for libraries.
- Racket: `.rkt` with `#lang racket/base` or equivalent.

The library contents themselves (the `define-library` form) are
portable. Packaging is per-host. A future Chez/Racket build of
Modaliser ships the same logical libraries with renamed files and any
host-specific wrappers.

## Visibility / encapsulation

Encapsulation lives in `define-library`'s `export` form. Anything not
exported is private to the library. This is the only mechanism users
need; we are not introducing a custom `with-private` or similar.

Top-level `.scm` files (`config.scm` and anything it `include`s) run
in the global env post-include and have no encapsulation — that's by
design, since they exist to register effects (define-tree,
set-leader!) at app startup.

## Parameterization pattern for stdlib libraries

The pattern Modaliser stdlib libraries follow: **export a builder
procedure that returns a tree node, not a `define-tree` side-effect.**
Side-effects come from the user's `config.scm` calling the builder.

Example: the iTerm local-menu library:

```scheme
;; In Resources/Scheme/lib/modaliser/apps/iterm.sld
(define-library (modaliser apps iterm)
  (export iterm-local-tree iterm-register-default!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser shell)
          (modaliser hints)
          (modaliser ax-hints))
  (begin

    (define default-pane-labels
      '("1" "2" "3" "4" "5" "6" "7" "8" "9"))

    (define default-chip-options
      `((font-size . 56)
        (color    . "#cc0000")
        (background . "#ffffff")))

    ;; Public: returns the live tree definition so the caller can pass
    ;; it to define-tree under whatever scope they want. Keyword args
    ;; with sensible defaults so the simplest call is just
    ;; (iterm-local-tree).
    (define (iterm-local-tree . opts)
      (let ((labels       (alist-ref opts 'pane-labels default-pane-labels))
            (chip-options (alist-ref opts 'chip-options default-chip-options))
            (extra        (alist-ref opts 'extra-bindings '())))
        ;; …returns a tree node…
        ))

    ;; Convenience: registers the tree under the iTerm bundle ID using
    ;; the same options. For users who want the default behaviour with
    ;; one line of config.
    (define (iterm-register-default! . opts)
      (apply define-tree 'com.googlecode.iterm2
             (iterm-local-tree opts)))))
```

User config:

```scheme
;; ~/.config/modaliser/config.scm
(import (modaliser dsl)
        (modaliser apps iterm))

;; Simplest: take the defaults.
(iterm-register-default!)

;; OR customised: pass pane labels and an extra binding.
(iterm-register-default!
  'pane-labels '("a" "s" "d" "f" "g")
  'extra-bindings
  (list (key "?" "Help" (lambda () (run-shell "open https://iterm2.com/")))))
```

The library authors pick the parameterization knobs at design time. If
a user needs something the knobs don't cover, they fall back to:

```scheme
;; Skip the helper, build the tree by hand.
(define-tree 'com.googlecode.iterm2
  ;; …user's hand-written tree…
  )
```

Pre-built libraries are *opt-in conveniences*, not the only path.

## Migration plan

Done across separate branches; each phase is independently shippable.

**Phase A — Library lookup path with the user-config root on it.**
- Register the library lookup path during `SchemeEngine` init:
  user-config root (`~/.config/modaliser/`) first via
  `prependLibrarySearchPath`, then the bundled Modaliser stdlib root,
  then the host's R7RS+SRFI root (auto-added by LispKit).
- Expose `(prepend-library-path! "/abs/path")` as a Scheme primitive
  for additional roots.
- Document that users can write `.sld` files anywhere under any root
  on the path; the library name dictates the directory path
  (`(foo bar)` → `foo/bar.sld`). The user picks the first segment.
- These libraries can import `(scheme base)`, `(srfi 1)`,
  `(modaliser shell)`, etc. — they cannot yet import
  `(modaliser dsl)` because that doesn't exist yet.
- Scope: ~15 lines of Swift (path wiring + the primitive), a doc
  page, a starter example file.

**Phase B — Wrap Modaliser DSL into a portable library.**
- Convert `Sources/Modaliser/Scheme/lib/dsl.scm` into
  `lib/modaliser/dsl.sld` with explicit `import (scheme base)` and an
  `export` list covering the user-facing names.
- Identify and convert `dsl.scm`'s pure-Scheme dependencies the same
  way: at minimum `keymap.scm` (for `MOD-CMD` etc.) and a piece of
  `state-machine.scm` (for `register-tree!`).
- Update `root.scm` to `(import (modaliser dsl))` so the bundled
  `default-config.scm` and the user's `config.scm` still see the DSL
  at top level.
- Scope: meaningful refactor; care needed around what counts as a
  cross-library dependency. Tests follow each renamed module.

**Phase C — Carve `default-config.scm` into stdlib libraries.**
- `(modaliser apps iterm)` — the iTerm local-menu builder.
- `(modaliser apps safari)`, `(modaliser apps chrome)` — sibling apps.
- `(modaliser window-actions)` — third/half/center moves.
- `(modaliser space-switching)` — the new Spaces 1..N binding.
- `(modaliser leader)` — leader-key conveniences.
- The leftover `default-config.scm` becomes a thin example that imports
  the above and registers default trees. Used as the first-run seed for
  `~/.config/modaliser/config.scm` (per the existing seeding logic in
  `root.scm`).

**Phase D — User-facing portability cleanup.**
- Audit `~/.config/modaliser/config.scm` (seeded default) and the
  bundled `default-config.scm`: anything that references LispKit-only
  bindings gets replaced with the `(modaliser …)` equivalent or
  imported from `(scheme …)` explicitly.
- Document the portable surface (what can be assumed to exist) and the
  conventions for users.
- This is where the eventual Chez / Racket port begins consuming the
  configuration model, with a different Layer 1 implementation behind
  the same `(modaliser …)` library names.

Each phase has its own design discussion if needed; this document is
the umbrella spec linking them together.

## Open questions

1. **Bundling stdlib libraries.** Do bundled `.sld` files live under
   `Resources/Scheme/lib/modaliser/` (one search root) or do we use the
   existing `Sources/Modaliser/Scheme/lib/` layout? The path on disk
   doesn't matter to users; it matters for repo structure and for how
   the test harness loads modules. Recommendation: settle on
   `Resources/Scheme/lib/modaliser/` because it expresses the library
   prefix in the directory tree, but verify the SPM resource copy logic
   in `Package.swift` follows.

2. **Tests across library boundaries.** Existing tests `include` each
   `.scm` file directly; after the refactor they need to `(import …)`
   instead. The test bootstrap will need updating. Recommendation:
   add an `EngineTestKit` helper that imports the standard set of
   libraries; individual tests opt in to additional ones.

3. **Cross-implementation tests.** Should the test suite run against
   more than one Scheme host? Today it's LispKit only and that's
   appropriate. Cross-host tests can be added later when there's
   actually a second host to test against.

4. **Builder API conventions.** Two reasonable shapes for the
   parameterization API: keyword-style alists (as in `set-leader!`)
   or `(make-iterm-tree #:pane-labels ... )` keyword arguments. Pick
   the alist style for consistency with the existing Modaliser DSL.

5. ~~**Path extension mechanisms — which to actually ship.**~~
   Decided: ship only the `(prepend-library-path! "/abs/path")`
   Scheme primitive. Env-var and config-file mechanisms are deferred
   until a concrete user need surfaces.

5. **Deprecation policy.** Once Phase C lands, the bundled
   `default-config.scm` shape changes meaningfully. Existing user
   configs still work because the DSL surface is preserved, but the
   seeded default file gets replaced for new installs. Document this
   in the release notes.

## Constraints and trade-offs

- **LispKit's `.sld` requirement** is real: library files must use that
  extension. Acceptable today; per-host packaging step at port time.

- **`define-library` is hermetic.** A library body sees only its imports.
  This is fine — we deliberately route every cross-library access through
  `import`. Anything currently relying on global top-level bindings
  inside an `include`-spliced module needs explicit `import` lines after
  the refactor.

- **Top-level user files keep working.** Because `config.scm` is loaded
  via `(include …)` at the top level *after* `(import (modaliser dsl)
  …)` has run, the DSL names are in scope. This preserves the existing
  "just write the form, no ceremony" feel for simple configs.

- **No metaprogramming of imports.** Users explicitly list what they
  use. Some duplication across files; readability and portability win
  the trade.

- **First-run seeding.** The existing logic that copies
  `default-config.scm` into `~/.config/modaliser/config.scm` on first
  run continues to work; the copied file just imports stdlib libraries
  by name and uses them.
