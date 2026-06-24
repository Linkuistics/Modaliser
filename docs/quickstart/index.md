# Quick start

Modaliser is a Scheme-scriptable modal keyboard system for macOS. Press
a leader key, type a sequence, and Modaliser launches an app, manages
a window, runs a shell command, or anything else you've wired up. The
configuration is plain Scheme; the bundled `(modaliser …)` libraries
provide the DSL, native primitives (keyboard capture, window management,
shell execution, …), and a stdlib of ready-to-use trees and helpers.

This page walks you from install to first edit in five minutes.

## 1. Install

Install Modaliser with [Homebrew](https://brew.sh):

```bash
brew install --cask linkuistics/taps/modaliser
```

This installs the pre-built `Modaliser.app` into `/Applications`.
Requires macOS 14+ — the cask ships a signed binary, so there is
nothing to compile.

### Build from source instead

If you would rather compile Modaliser yourself, clone the repository
and run the install script:

```bash
git clone https://github.com/Linkuistics/Modaliser.git
cd Modaliser
./scripts/install.sh
```

That builds `Modaliser.app` and copies it to `/Applications`. The build
code-signs with a `Modaliser Dev` certificate if one is available
(preserves Accessibility TCC permissions across rebuilds) and falls back
to ad-hoc signing otherwise. Building from source additionally requires
Swift 5.9+ / Xcode 15+.

## 2. First launch

Open `/Applications/Modaliser.app`. On first run you'll see an
onboarding window asking for two macOS permissions:

- **Accessibility** — required for global keyboard capture. The window
  has a deep-link button into System Settings; once you grant the
  permission, Modaliser detects it and auto-relaunches.
- **Screen Recording** — required for reading window titles. macOS
  shows its native prompt after Accessibility is granted.

After both grants, Modaliser runs as an accessory app: no Dock icon,
just a menu bar icon. On first run it also seeds
`~/.config/modaliser/config.scm` from a bundled default.

## 3. Press F18

F18 is the default global leader. Tap it once — the overlay appears.
Read it like a reference card. The seeded global screen opens with a
handful of **loose rows** at the top — rendered bare, with no card:

- `1..` Switch Space, `,` Settings, `␣` Highlight Cursor, and `w ›`
  Windows (a drill-down into its own screen).

Below them sits a grid of banded **panels**, one card per group:

- **Applications** — `b` Browser, `e` Editor, `t` Terminal, … one key
  per app.
- **AI** — `c` ChatGPT, `C` Claude Desktop.
- **Search** — `g` Google, `a` Find Application, `f` Find File.

Each card bands its label across the top; a `›` on a row marks a
drill-down into a sub-screen.

Type one of those keys to fire its action (or, on a `›` row, descend
into the sub-screen). Press <kbd>Escape</kbd> at any time to dismiss
the modal.

The overlay appears after a short delay (0.3 s in the seeded config)
so muscle-memory keypresses produce no UI at all — the modal still
captures and dispatches the key, the user just never sees a flash.

## 4. Edit one binding

Open `~/.config/modaliser/config.scm` (the menu bar icon's **Settings**
item launches it in your default editor). Find the `Applications`
panel — a `(panel "Applications" …)` block, abridged here:

```scheme
(panel "Applications"
  (key "b" "Browser"          (λ () (launch-app "Dia")))
  (key "e" "Editor"           (λ () (launch-app "Zed")))
  (key "t" "Terminal"         (λ () (launch-app "iTerm")))
  …)                          ; more app keys follow
```

A few things to notice:

- **`(key K L body)`** is the core binding form. `K` is the key string
  (single character or a name like `"F1"`); `L` is the label shown in
  the overlay; `body` is the action.
- **`(λ () …)`** is the Unicode alias for `(lambda () …)`. Wrap any
  side-effecting call in a thunk so it fires on key press, not at
  config-load. `(key "b" "Browser" (launch-app "Dia"))` *without* the
  `λ` would launch Dia every time Modaliser starts.
- **`(panel …)`** is a banded card in the screen's grid. It's
  *transparent* for dispatch — typing `b` still fires the Browser
  binding regardless of the panel wrapping; the panel only shapes how
  the rows are grouped and drawn.

Change one label or app:

```scheme
(panel "Applications"
  (key "b" "Safari"           (λ () (launch-app "Safari")))   ; was Dia
  (key "e" "Editor"           (λ () (launch-app "Zed")))
  (key "t" "Terminal"         (λ () (launch-app "iTerm")))
  …)
```

Save the file.

## 5. Relaunch

Modaliser doesn't reload config in place. From the menu bar icon, pick
**Relaunch**. The app restarts with your edits applied.

Tap F18 again, then `b` — Safari should open.

## What's next

You now have the loop: edit `config.scm`, relaunch, try the binding.

- **Tutorial** — [Modal Thinking — build a window-manager leader](../tutorials/modal-thinking.md).
  30–60 minutes; the natural next step if you want to *understand*
  the system rather than look up recipes for specific tasks. Walks
  through the launcher and modal patterns by building a `w` drill-down
  from a one-key stub up to something close to `default-config.scm`.
- **How-to guides** — task-oriented recipes for adding bindings,
  per-app trees, sticky modes, fuzzy-finders, theming, and debugging.
  → [how-to/index.md](../how-to/index.md)
- **The DSL** — the layout forms (`screen`, `panel`, `open`,
  `fragment`) you author the overlay with, plus the dispatch atoms they
  hold: `key`, `keys` for multi-key bindings, `group` for flat nested
  submenus, and `selector` for fuzzy-finder choosers.
  → [reference/dsl.md](../reference/dsl.md)
- **Bundled libraries** — `(modaliser launchers)` for app/file pickers,
  `(modaliser web-search)` for web queries, `(modaliser apps safari)` /
  `(modaliser apps iterm)` for per-app trees, `(modaliser window-actions)`
  for window management.
  → [reference/libraries.md](../reference/libraries.md)
- **State machine** — transient vs. sticky modes, `'sticky-target`,
  `'exit-on-unknown`, `on-enter` / `on-leave` hooks.
  → [reference/state-machine.md](../reference/state-machine.md)
- **Theming** — edit `~/.config/modaliser/theme.css` to override any
  CSS variable, class, or chip rule. Setting `--color-host-bg` alone
  recolours the overlay header, chooser header, and every chip.
  → [reference/theming.md](../reference/theming.md)
- **Splitting configs across files** — `(import …)` from your own
  `.sld` libraries under `~/.config/modaliser/`, the `sys/` mirror of
  bundled libraries, lookup order.
  → [reference/library-system.md](../reference/library-system.md)
- **Portability contract** — what's portable Scheme vs.
  LispKit-specific.
  → [reference/portability.md](../reference/portability.md)
- **Keyboard reference** — every navigation key in the modal and
  chooser.
  → [reference/keyboard.md](../reference/keyboard.md)
