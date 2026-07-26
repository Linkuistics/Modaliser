# Keyboard reference

## Modal navigation

| Key | Action |
|-----|--------|
| F18 | Toggle global modal (default — configurable via the `leaders` setting) |
| F17 | Toggle app-local modal (default — configurable via the `leaders` setting) |
| Escape | Exit modal |
| Delete | Step back one level |
| Any letter/digit | Execute command or descend into group |

A command leaf's `'next` keyword declares its post-action transition — `'next 'self` re-arms the containing collection (a **Walk**) instead of exiting, so e.g. hjkl pane navigation can chain without re-pressing the leader; `'next TARGET` crosses into a different registered Walk. A leaf with no `'next` is **Terminal** and exits normally. The overlay paints a `↻` marker on any key carrying `'next`.

## Chooser

| Key | Action |
|-----|--------|
| Up / Down | Navigate items |
| Return | Select (primary action) |
| Cmd+Return | Secondary action |
| Tab | Toggle action panel |
| Escape | Cancel |

The action panel — visible when the selector declares `'actions` and the user presses Tab — lists every configured action with its key shortcut. Each action is a `(action name …)` form with a `'key` slot (`'primary`, `'secondary`, or a literal key string) and a `'run` thunk that receives the chosen item.

## Menu bar

The menu bar icon provides:

- **Config error: …** — present only when the configuration failed to load; opens the full error. See below.
- **Open Config…** — opens `~/.config/modaliser/config.scm` in the default editor.
- **Reveal Config in Finder** — opens `~/.config/modaliser/`, so you can pick between `config.scm`, `theme.css`, and your own libraries.
- **Reset Config to Bundled Default…** — confirms, copies your `config.scm` aside as `config.scm.backup-<timestamp>`, replaces it with the bundled default, and relaunches.
- **Relaunch** — restarts the application to apply config changes.
- **Quit Modaliser**.

Every item stays enabled whatever the configuration did. A config that fails to load — a syntax error, an error during evaluation, or a reference to something the running binary no longer provides — does not wedge the app: Modaliser arms the bundled default configuration instead, so leader keys keep working, and reports the error in a dialog, on the menu, and in the unified log (`log show --predicate 'subsystem == "dev.antony.Modaliser"'`). See ADR-0022.

The seeded `config.scm` reaches the same two actions from the keyboard, as a `","` group — `(modaliser settings-menu)` exports the op that opens the config directory, `(modaliser lifecycle)` exports `relaunch!`, and the group that binds them is yours to move or rename:

```scheme
(group "," "Settings"
  (key "e" "Edit"   (λ () (settings:open-config-dir! 'editor "Zed")))
  (key "r" "Reload" relaunch!))
```
