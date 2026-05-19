# Quick start

Modaliser is a Scheme-scriptable modal keyboard system for macOS. Press
a leader key, type a sequence, and Modaliser launches an app, manages
a window, runs a shell command, or anything else you've wired up. The
configuration is plain Scheme; the bundled `(modaliser …)` libraries
provide the DSL, native primitives (keyboard capture, window management,
shell execution, …), and a stdlib of ready-to-use trees and helpers.

This page walks you from install to first edit in five minutes.

## 1. Install

```bash
git clone https://github.com/<your-fork>/Modaliser
cd Modaliser
./scripts/install.sh
```

That builds `Modaliser.app` and copies it to `/Applications`. The build
code-signs with a `Modaliser Dev` certificate if one is available
(preserves Accessibility TCC permissions across rebuilds) and falls back
to ad-hoc signing otherwise.

Requirements: macOS 14+, Swift 5.9+ / Xcode 15+.

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

F18 is the default global leader. Tap it once — a *which-key* overlay
appears showing every binding at the root of the global tree:

```
1..    Switch Space
,      Settings
w      Windows
   Instant Apps         AI               Search           Apps
   b   Browser          c   ChatGPT      g   Google       j   Jump Desktop
   e   Editor           C   Claude…      a   Find App     m   Mail
   t   Terminal                          f   Find File    n   Notes
                                                          o   Obsidian
                                                          z   Zotero
```

Type one of those keys to fire its action (or descend into the
subgroup). Press <kbd>Escape</kbd> at any time to dismiss the modal.

The overlay appears after a short delay (0.3 s in the seeded config)
so muscle-memory keypresses produce no UI at all — the modal still
captures and dispatches the key, the user just never sees a flash.

## 4. Edit one binding

Open `~/.config/modaliser/config.scm` (the menu bar icon's **Settings**
item launches it in your default editor). Find this block:

```scheme
(category "Instant Apps"
  (key "b" "Browser"          (λ () (launch-app "Dia")))
  (key "e" "Editor"           (λ () (launch-app "Zed")))
  (key "t" "Terminal"         (λ () (launch-app "iTerm"))))
```

A few things to notice:

- **`(key K L body)`** is the core binding form. `K` is the key string
  (single character or a name like `"F1"`); `L` is the label shown in
  the overlay; `body` is the action.
- **`(λ () …)`** is the Unicode alias for `(lambda () …)`. Wrap any
  side-effecting call in a thunk so it fires on key press, not at
  config-load. `(key "b" "Browser" (launch-app "Dia"))` *without* the
  `λ` would launch Dia every time Modaliser starts.
- **`(category …)`** groups a slice of the overlay under a label. The
  state machine treats categories as transparent — typing `b` still
  fires the Browser binding regardless of the category wrapping.

Change one label or app:

```scheme
(category "Instant Apps"
  (key "b" "Safari"           (λ () (launch-app "Safari")))   ; was Dia
  (key "e" "Editor"           (λ () (launch-app "Zed")))
  (key "t" "Terminal"         (λ () (launch-app "iTerm"))))
```

Save the file.

## 5. Relaunch

Modaliser doesn't reload config in place. From the menu bar icon, pick
**Relaunch**. The app restarts with your edits applied.

Tap F18 again, then `b` — Safari should open.

## What's next

You now have the loop: edit `config.scm`, relaunch, try the binding.

- **The DSL** — every form available inside `define-tree`, including
  `keys` for multi-key bindings, `group` for nested submenus, `selector`
  for fuzzy-finder choosers, and `overlay` for custom block layouts.
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
