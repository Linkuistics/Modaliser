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

```scheme
(import (modaliser apps iterm))      ; iterm-rebuild-tree!,
                                     ; iterm-focus-mode-register!,
                                     ; iterm-context-suffix-handler,
                                     ; iterm-register!
(import (modaliser apps safari))     ; safari-tree, safari-register!
(import (modaliser apps chrome))     ; chrome-tree, chrome-register!
(import (modaliser window-actions))  ; window-actions-group,
                                     ; window-actions-register!
(import (modaliser space-switching)) ; spaces-range-binding,
                                     ; spaces-1-9-register!
(import (modaliser leader))          ; set-global-leader!,
                                     ; set-local-leader!, set-leaders!
(import (modaliser ax-hints))        ; ax-find-labelled,
                                     ; ax-target-bindings,
                                     ; ax-target-hints, label-pairs,
                                     ; default-hint-options
(import (modaliser terminal))        ; focused-terminal-foreground-command,
                                     ; focused-nvim-socket,
                                     ; nvim-remote-send / nvim-remote-expr,
                                     ; modaliser-tool-path
```

Customisation example:

```scheme
(import (modaliser apps safari))
(safari-register!)                              ; defaults

(safari-register!                               ; or customised
  'extra-bindings
    (list (key "/" "Search"
            (lambda () (send-keystroke '(cmd) "f")))))
```

See the bundled `default-config.scm` (copied to your config dir on
first run) for an end-to-end example that combines all of these.

## What's not in this phase

The user-facing tree under `ui/` (overlay rendering, chooser) and the
Google web-search helper are still `include`-style and not yet
importable as `(modaliser …)` libraries. The bundled `default-config.scm`
seed still uses them — `web-search-handler`, `find-installed-apps`,
the file-chooser selector — but it references them as top-level
bindings rather than as imports. Phase D will library-ize chooser /
overlay / web-search and the seed will switch to explicit `(import …)`.
