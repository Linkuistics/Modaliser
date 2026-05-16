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

## What's not in this phase

The opt-in stdlib of per-app trees and helpers — `(modaliser apps iterm)`,
`(modaliser apps safari)`, `(modaliser window-actions)`,
`(modaliser space-switching)`, `(modaliser leader)` — is Phase C work.
Until then, copy the relevant block out of the bundled
`default-config.scm` and adapt it inline.

The user-facing tree under `ui/` (overlay rendering, chooser) is still
`include`-style and not yet importable as `(modaliser …)` libraries —
also Phase C.
