# Keyboard reference

## Modal navigation

| Key | Action |
|-----|--------|
| F18 | Toggle global modal (default — configurable via `set-leaders!`) |
| F17 | Toggle app-local modal (default — configurable via `set-leaders!`) |
| Escape | Exit modal |
| Delete | Step back one level |
| Any letter/digit | Execute command or descend into group |

In sticky modes (a group with `'sticky #t`, or a key with `'sticky-target`), firing a command returns navigation to the sticky group instead of exiting — so e.g. hjkl pane navigation can chain without re-pressing the leader. The overlay paints a `↻` marker on keys that transition into a sticky mode.

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

- **Settings** — opens `~/.config/modaliser/config.scm` in the default editor.
- **Relaunch** — restarts the application to apply config changes.
- **Quit Modaliser**.

The bundled `(modaliser settings-menu)` library exposes the same actions as a Modaliser group (default key `","`) so they're reachable from the keyboard too without going through the menu bar.
