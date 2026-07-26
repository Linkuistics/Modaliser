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
2. `~/.config/modaliser/sys/scheme/lib/` — the bundled `(modaliser …)`
   libraries, inside the mirror of the whole bundled Scheme tree that
   Modaliser keeps under `sys/` (see ["The sys/ mirror"](#the-sys-mirror)
   below)
3. `<Modaliser.app>/Contents/Resources/Scheme/lib/` — same bundled
   libraries, straight from the .app, kept as a fallback if `sys/`
   can't be populated
4. The host's R7RS + SRFI directory — auto-registered by LispKit

User-first ordering means you can shadow any bundled library by
dropping a same-named file under `~/.config/modaliser/`. Useful for
local patches; otherwise stay clear of the `modaliser` prefix.

## The sys/ mirror

On launch, Modaliser mirrors the *entire* bundled Scheme tree — the
`(modaliser …)` libraries, `root.scm`, the UI plumbing, assets, and the
current `default-config.scm` — from inside its .app bundle into
`~/.config/modaliser/sys/scheme/`. The fingerprint (file paths +
mtimes) is cached in `~/.config/modaliser/sys/.bundle-fingerprint`; if
it matches the bundle, no file touch happens. When it doesn't — any newly
installed build — the next launch wipes and re-copies the mirror and
writes a generated `sys/README.md` restating this contract beside it.
Production runs *read* the tree from the mirror, so what you browse
there is exactly the code that runs (unless you've shadowed a file
with a fork of your own — see below).

Two reasons to look in `sys/`:

- **Reading**: every bundled file is browsable from your config dir,
  no `cd` into the .app needed, and your editor can jump into it from
  your config.
- **Forking a library locally**: copy the file out of `sys/scheme/`
  and into the user-config root (e.g.
  `cp ~/.config/modaliser/sys/scheme/lib/modaliser/launchers.sld ~/.config/modaliser/modaliser/launchers.sld`),
  then edit your copy. The user-config root shadows `sys/` on the
  lookup path so your fork wins.

**Don't edit files inside `sys/` directly.** Edits there are silently
overwritten on the next sync. The mirror is intentionally treated as
disposable.

LispKit's R7RS + SRFI standard libraries are not part of the mirrored
tree — they continue to be served from the bundle because they're not
specific to this app.

## The upgrade contract

Installing a new Modaliser build updates the two halves of your config
dir in opposite ways, by design
([ADR-0019](../adr/0019-seeding-and-upgrade.md)):

- **`config.scm` is seeded exactly once** — copied from the bundled
  default on first run, user-owned from then on, never rewritten.
- **Everything under `sys/` is always fresh** — re-synced whenever the
  installed bundle changes.

The seeded file holds only composition and preference (keys, labels,
panels); every piece of machinery it composes arrives through the
always-current `(modaliser …)` libraries. An upgrade therefore can't
strand stale machinery in your config: library improvements simply
arrive on the next launch after an install. Preference improvements —
new defaults, new example screens — never auto-apply; diff your
`config.scm` against `sys/scheme/default-config.scm` when you're
curious what a fresh install would seed. A breaking library change
fails loudly at config load with nothing installed — your config either
runs against the current libraries or errors; there is no
silently-stale in-between.

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
                                    ; action, screen, panel, open, splice,
                                    ; walk, step-in, tree-root, λ,
                                    ; modifier-symbols->mask
(import (prefix (modaliser display-dsl) d:))
                                    ; the bare display surface: with-display,
                                    ; panel, loose, block, span, order, cols,
                                    ; layout, embed, display-name (prefixed —
                                    ; `panel` exists on both surfaces)
(import (modaliser configuration))  ; configuration, leaders, leader,
                                    ; overlay-delay, terminal-contexts,
                                    ; tree/backend/context/setting,
                                    ; configuration-* accessors
(import (modaliser handoff))        ; modaliser:start!, modaliser:configuration
(import (modaliser fsm))            ; node predicates, modal-* introspection
(import (modaliser util))           ; alist-ref, props->alist, string-join,
                                    ; read-file-text, log
(import (modaliser keymap))         ; has-cmd?, has-shift?, has-alt?,
                                    ; has-ctrl?
```

See [dsl.md](dsl.md) for the full DSL surface with signatures and
examples. The native `(modaliser app)`, `(modaliser keyboard)`, etc. are also
importable from a user `.sld`, as are `(modaliser shell)` for `run-shell` and
`(modaliser http)` for `http-get` — which are portable seams over the native
spawn and fetch, not native libraries themselves
([ADR-0023](../adr/0023-native-reach-is-host-installed.md)).

## Bundled stdlib libraries

Modaliser ships an opt-in stdlib of per-app factories and helpers.
Each factory exports **pure constructors returning fragments** —
printable pieces of configuration ([ADR-0018](../adr/0018-configuration-as-one-explicit-value.md)) —
plus its building blocks (trees, blocks, action procedures) for
composing your own. Constructors accept alist-style keyword options;
the simplest call is always zero-arg. Nothing happens until the
returned fragment is included in the `configuration` value you hand to
`modaliser:start!`.

The factory libraries use bare-name exports (`fragment`, `wiring`,
`backend`, `focus-pane-left`, …). Import them with R7RS's `prefix`
modifier so call sites read as `<lib>:<verb>` and bare names from
different libraries don't collide:

```scheme
(import (prefix (modaliser apps iterm)      iterm:)    ; iterm:wiring,
                                                       ; iterm:focus-pane-left,
                                                       ; iterm:pane-list-block, …
        (prefix (modaliser apps dia)        dia:)      ; dia:tab-source, dia:tab-step, …
        (prefix (modaliser muxes herdr)     herdr:)    ; herdr:wiring, herdr:backend,
                                                       ; herdr:focus-pane-left, …
        (prefix (modaliser muxes tmux)      tmux:)     ; tmux:wiring,
                                                       ; tmux:focus-pane-left, …
        (prefix (modaliser window-actions)  window:)   ; window:layout-block,
                                                       ; window:list-block,
                                                       ; window:default-layout-block
        (prefix (modaliser launchers)       launcher:) ; launcher:find-application,
                                                       ; launcher:find-file
        (prefix (modaliser settings-menu)   settings:) ; settings:open-config-dir!
        (prefix (modaliser web-search)      web-search:) ; web-search:google
        (modaliser ax-hints)                           ; ax-find-labelled, …
        (modaliser terminal))                          ; focused-terminal-foreground-command, …
```

Foundational libraries (`configuration`, `handoff`, `ax-hints`,
`terminal`, `dsl`, `util`, …) keep unique long names and are imported
unprefixed because they're the vocabulary that runs throughout the
config.

Customisation example. A `fragment` / `wiring` constructor carries the
**integration** — a backend record, a context-map entry, a
machinery-named side tree — and nothing you would want to choose. The
**screen** is yours, built from the library's exported ops and blocks
(ADR-0021):

```scheme
(import (prefix (modaliser apps iterm) iterm:))

;; The integration, taken whole — nothing here is preference.
(configuration … (iterm:wiring) …)

;; The screen, authored from the exported ops. Rebind, drop or regroup
;; any of it; the scope symbol is the one part that is machinery (it is
;; the backend record's match-key).
(define iterm-screen
  (screen 'com.googlecode.iterm2
    (key "z" "Toggle Zoom" iterm:toggle-pane-zoom)
    (panel "Splits"
      (key "h" "Focus Left"  iterm:focus-pane-left)
      (key "l" "Focus Right" iterm:focus-pane-right))
    (panel "Panes" (iterm:pane-list-block 'chips? #t))))
```

Customization is composition, never patching an installed tree — and
because no library ships a screen, there is no installed tree to patch.

See the bundled `default-config.scm` (seeded to
`~/.config/modaliser/config.scm` on first run, and always readable at
`sys/scheme/default-config.scm`) for an end-to-end example that
combines all of these.

For a task-oriented walkthrough of pulling pieces out of `config.scm`
into your own libraries, see
[how-to/split-your-config.md](../how-to/split-your-config.md).

## What lives outside the library tree

The remaining UI plumbing under `Sources/Modaliser/Scheme/ui/`
(`css.scm`, `overlay.scm`, `chooser.scm`) is loaded by `root.scm` via
`(include …)` rather than `(import …)`, so its bindings live at the
top level of the engine environment. The bundled `default-config.scm`
no longer references any of them — it is authored entirely from
`(modaliser …)` library imports.

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
