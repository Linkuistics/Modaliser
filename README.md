# Modaliser

> Scheme-scriptable modal keyboard system for macOS.

Press a leader key, type a sequence, and Modaliser launches apps, manages windows, runs shell commands, searches files, or anything else you've wired up. Your configuration is Scheme code — actions are lambdas, the bundled stdlib is a set of `(modaliser …)` libraries you import à la carte, and the same `config.scm` can be split across multiple `.sld` files as it grows.

## Documentation

- **[Quick start](docs/quickstart/index.md)** — install → first launch → edit one binding → relaunch, in five minutes.
- **Reference**
  - [DSL](docs/reference/dsl.md) — every form from `(modaliser dsl)`: `key`, `keys`, `group`, `category`, `selector`, `overlay`, `define-tree`, leader setters, …
  - [Libraries](docs/reference/libraries.md) — bundled `(modaliser …)` libraries: launchers, web-search, settings-menu, window-actions, apps/safari, apps/chrome, apps/iterm, blocks.
  - [State machine](docs/reference/state-machine.md) — modal lifecycle, transient vs. sticky, `'sticky-target`, `'exit-on-unknown`, hook gating, dispatch precedence.
  - [Renderer protocol](docs/reference/renderer-protocol.md) — block spec shape, `on-render-fn` return-and-merge, chrome envelope, writing a custom block.
  - [Theming](docs/reference/theming.md) — CSS variables, class inventory, worked dark-mode override.
  - [Library system](docs/reference/library-system.md) — splitting configs across `.sld` files, the `sys/` mirror, lookup order, `prepend-library-path!`.
  - [Portability](docs/reference/portability.md) — what configurations can rely on, what's deliberately host-specific.
  - [Keyboard](docs/reference/keyboard.md) — modal navigation, chooser controls, menu bar.

## Architecture

Modaliser is a native Swift macOS app, but the majority of its logic lives in Scheme. On launch, Swift creates a [LispKit](https://github.com/objecthub/swift-lispkit) runtime and loads `root.scm`, which bootstraps the entire application: activation policy, permissions, status bar, keyboard capture, and user config.

The UI is rendered in WKWebView-backed NSPanels controlled from Scheme. Two panel types exist:

- **Overlay** — a non-activating floating panel showing available keybindings at the current position in the command tree (which-key style).
- **Chooser** — an activating panel with a search input, fuzzy-filtered result list, and optional action panel (used by selectors). Supports static sources (fuzzy-matched locally) and dynamic sources (results fetched from external APIs).

Swift provides native libraries that Scheme calls into: keyboard capture, window management, app management, shell execution, HTTP requests, clipboard, input emulation, fuzzy matching, clipboard history, WebView management, app lifecycle. Incremental DOM updates use a Display-PostScript-inspired pattern: Scheme builds data, pushes JSON to JavaScript, and JS renders directly into the DOM — full-page HTML replacement is avoided except for structural changes.

## Requirements

- macOS 14+
- Swift 5.9+ / Xcode 15+
- Accessibility permissions (for global keyboard capture)
- Screen Recording permissions (for reading window titles)

## Install

```bash
./scripts/build-app.sh    # builds .build/release/Modaliser.app
./scripts/install.sh      # builds and copies to /Applications
```

The build script code-signs with a "Modaliser Dev" certificate if available (preserves Accessibility TCC permissions across rebuilds), otherwise falls back to ad-hoc signing.

For development:

```bash
swift build
swift test
.build/debug/Modaliser
```

On first launch, Modaliser presents an onboarding window for Accessibility (with a deep-link button into System Settings, polling for the grant and auto-relaunching when it lands) and then triggers macOS's native Screen Recording prompt. After both are granted, the app runs as an accessory (no Dock icon) with a menu bar icon.

## Quick start

On first launch, Modaliser seeds `~/.config/modaliser/config.scm` from a bundled default. Edit that file and pick **Relaunch** from the menu bar icon to apply changes.

A minimal modern config:

```scheme
(import (modaliser dsl)
        (modaliser app)
        (modaliser leader)
        (prefix (modaliser apps safari) safari:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(set-overlay-delay! 0.3)

(define-tree 'global
  (category "Apps"
    (key "s" "Safari"   (λ () (launch-app "Safari")))
    (key "t" "Terminal" (λ () (launch-app "iTerm")))))

(safari:register!)              ; app-local tree (F17 while Safari is focused)
```

That's a complete config. `(modaliser dsl)` surfaces the DSL (`key`, `keys`, `group`, `category`, `selector`, `overlay`, `define-tree`, `λ`); `(modaliser leader)` adds `set-leaders!`; the bundled stdlib includes app-specific trees (`safari:`, `chrome:`, `iterm:`) and helpers (`window:`, `launcher:`, `web-search:`, `settings:`). See the [Quick start](docs/quickstart/index.md) for a guided walkthrough and the [DSL reference](docs/reference/dsl.md) for the full surface.

## Menu bar

The menu bar icon provides **Settings** (opens `config.scm` in the default editor), **Relaunch** (restart to apply config changes), and **Quit Modaliser**.

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
