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
2. `<Modaliser.app>/Contents/Resources/Scheme/lib/` — bundled `(modaliser …)`
3. The host's R7RS + SRFI directory — auto-registered by LispKit

User-first ordering means you can shadow any bundled library by
dropping a same-named file under `~/.config/modaliser/`. Useful for
local patches; otherwise stay clear of the `modaliser` prefix.

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

Phase B published the foundational set. From a user `.sld` or
`config.scm` you can:

```scheme
(import (modaliser dsl))            ; key, key-range, group, selector,
                                    ; action, define-tree, set-leader!,
                                    ; modifier-symbols->mask
(import (modaliser state-machine))  ; lookup-tree, modal-* introspection,
                                    ; set-host-header!, set-overlay-delay!
(import (modaliser event-dispatch)) ; set-local-context-suffix!
(import (modaliser util))           ; alist-ref, props->alist, string-join,
                                    ; read-file-text, log
(import (modaliser keymap))         ; has-cmd?, has-shift?, has-alt?,
                                    ; has-ctrl?
```

Plus the native `(modaliser shell)`, `(modaliser app)`,
`(modaliser keyboard)`, etc. — those were already importable.

## Bundled stdlib libraries (Phase C)

Phase C ships an opt-in stdlib of per-app trees and helpers. Each
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
        (prefix (modaliser window-actions)  window:)   ; window:actions, window:register!
        (prefix (modaliser space-switching) space:)    ; space:switch-actions, space:register!
        (prefix (modaliser launchers)       launcher:) ; launcher:find-application,
                                                       ; launcher:find-file
        (prefix (modaliser settings-menu)   settings:) ; settings:actions
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

## What lives outside the library tree

The user-facing tree under `Sources/Modaliser/Scheme/ui/` (overlay
rendering, chooser) and the Google web-search helper at
`Sources/Modaliser/Scheme/lib/web-search.scm` are loaded by
`root.scm` via `(include …)` rather than `(import …)`. They expose
their bindings (`web-search-handler`, `web-search-on-select`,
`find-installed-apps`, `activate-app`, `reveal-in-finder`,
`open-with`) at the top level so the bundled `default-config.scm`
seed can use them without an `(import …)` line.

These modules are intentionally *not* exposed as `(modaliser …)`
libraries: they lean on LispKit-specific bindings (WebView, JSON) and
the spec's Phase D non-goal explicitly keeps them that way — only
the user-facing **library** surface needs to be portable, not every
internal `.scm` file. See [`docs/portability.md`](portability.md)
for the formal portability contract.

If you want to use any of those top-level helpers from your own
`(import …)`-based config, you have two options:

1. Reference them directly — they're in scope after `root.scm` runs,
   so `config.scm` can call `web-search-handler` without any
   `(import …)`. (The seed config does this.) Your config becomes
   host-specific to that extent.
2. Re-implement the helper in pure Scheme inside your own library
   and import that instead.
