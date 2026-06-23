# User libraries

Modaliser ships with R7RS `import` wired up so you can split your
configuration across multiple files under `~/.config/modaliser/`.

## File layout

The only fixed name is `~/.config/modaliser/config.scm` — the entry
point Modaliser loads at startup. Everything else is your choice:

- **Plain `.scm` files** are pulled in via `(include "path/to/file.scm")`.
  Paths resolve relative to the file containing the `include` form.

- **Library files** are R7RS `define-library` definitions in `.sld`
  files. Their location is dictated by the library name: a library
  called `(my-prefix helpers)` lives at `my-prefix/helpers.sld` under
  `~/.config/modaliser/`.

You pick the first segment of your library names. Recommended: anything
except `scheme`, `srfi`, or `modaliser` (those have well-known meanings).

## Lookup path order

`(import …)` consults this ordered list of roots, first match wins:

1. `~/.config/modaliser/` — your config
2. `~/.config/modaliser/sys/` — the bundled `(modaliser …)` libraries,
   mirrored here from the .app on every launch so you can read or fork
   them in place (see ["Bundled libraries under sys/"](#bundled-libraries-under-sys)
   below)
3. `<Modaliser.app>/Contents/Resources/Scheme/lib/` — same bundled
   libraries, kept as a fallback if `sys/` can't be populated
4. The host's R7RS + SRFI directory — auto-registered by LispKit

User-first ordering means you can shadow any bundled library by
dropping a same-named file under `~/.config/modaliser/`. Useful for
local patches; otherwise stay clear of the `modaliser` prefix.

## Bundled libraries under sys/

On launch, Modaliser mirrors the `(modaliser …)` libraries from inside
its .app bundle into `~/.config/modaliser/sys/modaliser/`. The
fingerprint (file paths + mtimes) is cached in
`~/.config/modaliser/sys/.bundle-fingerprint`; if it matches the
bundle, no file touch happens.

Two reasons to look in `sys/`:

- **Reading**: every bundled library is browsable from your config dir,
  no `cd` into the .app needed.
- **Forking a library locally**: copy the file out of `sys/` and into
  the user-config root (e.g.
  `cp ~/.config/modaliser/sys/modaliser/launchers.sld ~/.config/modaliser/modaliser/launchers.sld`),
  then edit your copy. The user-config root shadows `sys/` on the
  lookup path so your fork wins.

**Don't edit files inside `sys/` directly.** Edits there are silently
overwritten on the next launch whenever the bundle changes (every
install / every dev rebuild). The mirror is intentionally treated as
disposable.

Only Modaliser's own `(modaliser …)` libraries get mirrored — LispKit's
R7RS + SRFI standard libraries continue to be served from the bundle
because they're not specific to this app.

## Extending the path

Need an additional root (a sibling checkout, a team-shared directory)?
Call this from `config.scm`:

```scheme
(prepend-library-path! "/abs/path/to/extra/libraries")
```

The path is prepended in front of the user-config root, so additional
roots win against everything. A path that doesn't exist is silently
skipped — safe to call unconditionally.

## Example

Save this as `~/.config/modaliser/example/hello.sld`:

```scheme
(define-library (example hello)
  (export greet)
  (import (scheme base))
  (begin
    (define (greet) "hello from example/hello")))
```

Then from `~/.config/modaliser/config.scm`:

```scheme
(import (example hello))
(display (greet)) (newline)
```

When Modaliser starts, it logs `hello from example/hello` to Console.

## What `(modaliser …)` libraries you can import

The foundational set is always available. From a user `.sld` or
`config.scm` you can:

```scheme
(import (modaliser dsl))            ; key, keys, key-range, group, selector,
                                    ; action, screen, panel, open, fragment,
                                    ; sticky-set, λ, set-leader!, set-theme!,
                                    ; set-overlay-delay!, modifier-symbols->mask
(import (modaliser state-machine))  ; lookup-tree, modal-* introspection
(import (modaliser event-dispatch)) ; set-local-context-suffix!
(import (modaliser util))           ; alist-ref, props->alist, string-join,
                                    ; read-file-text, log
(import (modaliser keymap))         ; has-cmd?, has-shift?, has-alt?,
                                    ; has-ctrl?
```

See [dsl.md](dsl.md) for the full DSL surface with signatures and
examples. The native `(modaliser shell)`, `(modaliser app)`,
`(modaliser keyboard)`, etc. are also importable from a user `.sld`.

## Bundled stdlib libraries

Modaliser ships an opt-in stdlib of per-app trees and helpers. Each
library exports a builder returning a tree node plus a convenience
that registers the tree under a sensible default scope. Builders
accept alist-style keyword options; the simplest call is always
zero-arg.

The factory libraries use bare-name exports (`register!`, `actions`,
`tree`, `find-application`, …). Import them with R7RS's `prefix`
modifier so call sites read as `<lib>:<verb>` and bare names from
different libraries don't collide:

```scheme
(import (prefix (modaliser apps iterm)      iterm:)    ; iterm:register!,
                                                       ; iterm:rebuild-tree!,
                                                       ; iterm:focus-mode-register!,
                                                       ; iterm:context-suffix-handler
        (prefix (modaliser apps safari)     safari:)   ; safari:tree, safari:register!
        (prefix (modaliser apps chrome)     chrome:)   ; chrome:tree, chrome:register!
        (prefix (modaliser window-actions)  window:)   ; window:layout-block,
                                                       ; window:list-block,
                                                       ; window:default-layout-block
        (prefix (modaliser launchers)       launcher:) ; launcher:find-application,
                                                       ; launcher:find-file
        (prefix (modaliser settings-menu)   settings:) ; settings:actions
        (prefix (modaliser web-search)      web-search:) ; web-search:google
        (modaliser leader)                             ; set-global-leader!,
                                                       ; set-local-leader!, set-leaders!
        (modaliser ax-hints)                           ; ax-find-labelled, …
        (modaliser terminal))                          ; focused-terminal-foreground-command, …
```

Foundational libraries (`leader`, `ax-hints`, `terminal`, `dsl`,
`util`, …) keep unique long names and are imported unprefixed because
they're the vocabulary that runs throughout the config.

Customisation example:

```scheme
(import (prefix (modaliser apps safari) safari:))
(safari:register!)                              ; defaults

(safari:register!                               ; or customised
  'extra-bindings
    (list (key "/" "Search"
            (lambda () (send-keystroke '(cmd) "f")))))
```

See the bundled `default-config.scm` (copied to your config dir on
first run) for an end-to-end example that combines all of these.

For a task-oriented walkthrough of pulling pieces out of `config.scm`
into your own libraries, see
[how-to/split-your-config.md](../how-to/split-your-config.md).

## What lives outside the library tree

The remaining UI plumbing under `Sources/Modaliser/Scheme/ui/`
(`css.scm`, `overlay.scm`, `chooser.scm`) is loaded by `root.scm` via
`(include …)` rather than `(import …)`. It exposes its bindings at the
top level so the bundled `default-config.scm` seed can use them
without an `(import …)` line.

These modules are intentionally *not* exposed as `(modaliser …)`
libraries: they lean on LispKit-specific bindings (WebView, JSON) and
the portability contract explicitly keeps them that way — only the
user-facing **library** surface needs to be portable, not every
internal `.scm` file. See [portability.md](portability.md) for the
formal portability contract.

If you want to use any of those top-level helpers from your own
`(import …)`-based config, you have two options:

1. Reference them directly — they're in scope after `root.scm` runs,
   so `config.scm` can call them without any `(import …)`. Your config
   becomes host-specific to that extent.
2. Re-implement the helper in pure Scheme inside your own library
   and import that instead.
