# How to split your config across files

`config.scm` grows fast once you have a few per-app trees and
selectors. Pull pieces into their own libraries under
`~/.config/modaliser/` so each file stays small enough to read at a
glance.

## You'll need

- An existing `~/.config/modaliser/config.scm` you'd like to thin out.
- For lookup-path rules and the `sys/` mirror: [reference/library-system.md](../reference/library-system.md).

## Steps

1. **Pick a prefix for your libraries.** Anything except `scheme`,
   `srfi`, or `modaliser` (those have well-known meanings). The prefix
   becomes the first segment of every library name and a subdirectory
   under `~/.config/modaliser/`.

   This guide uses `me` — your config dir will end up with a `me/`
   subfolder.

2. **Decide what to move out.** Good candidates: a per-app tree, a
   selector factory you're tuning, theming Scheme glue (rare —
   theming usually lives in `theme.css`). Anything self-contained.

3. **Create the library file.** A library called `(me windows)` must
   live at `~/.config/modaliser/me/windows.sld`:

   `(modaliser window)` is the raw window-management library
   (`list-windows`, `focus-window`); `(modaliser window-actions)`
   provides the layout blocks (`window:layout-block`,
   `window:list-block`). Same prefix in your config, different
   libraries:

   ```scheme
   (define-library (me windows)
     (export window-panels)
     (import (scheme base)
             (modaliser dsl)
             (modaliser window)            ; list-windows, focus-window
             (prefix (modaliser window-actions) window:))  ; blocks
     (begin
       (define window-panels
         (fragment
           (panel "Layout"
             (window:layout-block
               (("d" "f" "g"))
               (("D" "F" "G")
                ("C" "V" "B"))
               (("e" "e" #f))
               ((#f "t" "t"))
               (("m"))
               (center "c")))
           (panel "Select"
             (key "s" "Select Window"
                  (selector 'prompt "Window…"
                            'source list-windows
                            'on-select focus-window)))
           (panel "Windows"
             (window:list-block 'chips? #t))))))
   ```

   The library exports `window-panels` as a **fragment** — a reusable
   chunk of layout (here, three panels). A fragment is transparent:
   whatever container you splice it into hoists its panels in place, so
   the result is identical to writing them inline.

4. **Import it from `config.scm`** and splice it into a drill-down:

   ```scheme
   (import (me windows))

   (screen 'global
     ;; …other panels…
     (open "w" "Windows" window-panels))
   ```

   `(open "w" "Windows" …)` makes a navigable sub-screen; the
   `window-panels` fragment supplies its grid. You can splice the same
   fragment into any number of screens, panels, or `open`s.

5. **Save and relaunch.** Tap F18 → `w` to confirm the imported
   drill-down still renders.

## Verify it worked

The Console (or `log` view of Modaliser launches) shows any LispKit
import errors. If your file isn't found, double-check that the file
path matches the library name segment-for-segment: `(me windows)` →
`me/windows.sld` (singular `.sld`, lowercase, matching segments).

## File layout

A larger config might end up as:

```
~/.config/modaliser/
├── config.scm                  ; entry point — imports + screen calls
├── theme.css                   ; user CSS overrides
├── me/
│   ├── windows.sld             ; (me windows)
│   ├── zed.sld                 ; (me zed)         — per-app tree for Zed
│   └── search.sld              ; (me search)      — fuzzy-finder factories
└── sys/
    └── modaliser/              ; auto-mirrored from the .app — read-only
        ├── dsl.sld
        ├── apps/safari.sld
        ├── …
```

`sys/modaliser/` is rewritten on every Modaliser launch when the
bundle's fingerprint changes — **don't edit anything inside it**.
Browse it freely to read bundled libraries.

## Forking a bundled library

When you need to change a bundled library's behaviour beyond what its
options expose, copy the file out of `sys/` into your prefix:

```bash
mkdir -p ~/.config/modaliser/modaliser/apps
cp ~/.config/modaliser/sys/modaliser/apps/iterm.sld \
   ~/.config/modaliser/modaliser/apps/iterm.sld
```

The user-config root sits *before* `sys/` on the lookup path, so your
fork wins. Edit your copy — Modaliser will pick it up on next launch.

Keep forks rare: every bundle update is a chance for upstream drift,
so a fork is now your responsibility to maintain. Prefer raising a
library option (or an issue) when the customisation you want feels
broadly useful.

## Related

- [reference/library-system.md](../reference/library-system.md) —
  lookup path order, the `sys/` mirror, `prepend-library-path!`.
- [reference/portability.md](../reference/portability.md) — which
  bindings are portable Scheme vs. LispKit-specific.
- [reference/libraries.md](../reference/libraries.md) — bundled
  `(modaliser …)` libraries and their exports.
