# Modaliser

> Scheme-scriptable modal keyboard system for macOS.

Press a leader key, type a sequence, and Modaliser launches apps, manages windows, runs shell commands, searches files, or anything else you've wired up. Your configuration is Scheme code — actions are lambdas, the bundled stdlib is a set of `(modaliser …)` libraries you import à la carte, and the same `config.scm` can be split across multiple `.sld` files as it grows.

## Documentation

- [Configuration](docs/configuration.md) — DSL primer (commands, groups, selectors), leader keys, app-local trees, themes, selectors deep-dive, file/web search, the windows-diagram overlay, AX hint flows.
- [Scheme API](docs/scheme-api.md) — every bundled `(modaliser …)` library and native primitive, with signatures.
- [User libraries](docs/user-libraries.md) — splitting configs across `.sld` files, the `~/.config/modaliser/` layout, the `sys/` mirror of bundled libraries, library lookup order, `prepend-library-path!`.
- [Portability](docs/portability.md) — what configurations can rely on and what's deliberately host-specific.
- [Keyboard reference](docs/keyboard.md) — modal navigation keys, chooser controls, menu bar.

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
        (prefix (modaliser apps safari)     safari:)
        (prefix (modaliser window-actions)  window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(set-overlay-delay! 0.3)

(define-tree 'global
  (key "s" "Safari"   (lambda () (launch-app "Safari")))
  (key "t" "Terminal" (lambda () (launch-app "iTerm")))
  (window:actions))            ; bundled window manager + diagram overlay on "w"

(safari:register!)              ; app-local tree (F17 while Safari is focused)
```

That's a complete config. The `(modaliser …)` imports surface the DSL, native primitives, and the bundled stdlib of app-specific trees (`safari:`, `iterm:`, `chrome:`) and helpers (`window:`, `space:`, `launcher:`, `web-search:`). See [Configuration](docs/configuration.md) for the full primer and [User libraries](docs/user-libraries.md) for how to split your config as it grows.

## Menu bar

The menu bar icon provides **Settings** (opens `config.scm` in the default editor), **Relaunch** (restart to apply config changes), and **Quit Modaliser**.

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
