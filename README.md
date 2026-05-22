# Modaliser

> Scheme-scriptable modal keyboard system for macOS.

Press a leader key, type a sequence, and Modaliser launches apps, manages windows, runs shell commands, searches files, or anything else you've wired up. Your configuration is Scheme code — actions are lambdas, the bundled stdlib is a set of `(modaliser …)` libraries you import à la carte, and the same `config.scm` can be split across multiple `.sld` files as it grows.

## Install

The quickest way to install Modaliser is with [Homebrew](https://brew.sh):

```bash
brew install --cask linkuistics/taps/modaliser
```

This auto-taps [`linkuistics/taps`](https://github.com/Linkuistics/homebrew-taps) and installs the pre-built `Modaliser.app` into `/Applications`. Requires macOS 14 or later — nothing else, since the cask ships a signed binary.

Modaliser needs Accessibility and Screen Recording permissions to run; it walks you through granting them on first launch (see [Usage](#usage)).

Prefer to compile it yourself? See [Build from source](#build-from-source).

## Build from source

Clone the repository and run the build scripts:

```bash
git clone https://github.com/Linkuistics/Modaliser.git
cd Modaliser
./scripts/build-app.sh    # builds .build/release/Modaliser.app
./scripts/install.sh      # builds and copies to /Applications
```

The build script code-signs with a "Modaliser Dev" certificate if available (preserves Accessibility TCC permissions across rebuilds), otherwise falls back to ad-hoc signing.

For development, build and run the debug binary directly:

```bash
swift build
swift test
.build/debug/Modaliser
```

Building from source requires macOS 14+ and Swift 5.9+ / Xcode 15+ — the Homebrew install needs neither.

## Usage

On first launch, Modaliser presents an onboarding window for Accessibility (with a deep-link button into System Settings, polling for the grant and auto-relaunching when it lands) and then triggers macOS's native Screen Recording prompt. Accessibility is required for global keyboard capture; Screen Recording, for reading window titles. After both are granted, the app runs as an accessory (no Dock icon) with a menu bar icon.

Modaliser also seeds `~/.config/modaliser/config.scm` from a bundled default on first launch. That file is your configuration — edit it, then pick **Relaunch** from the menu bar icon to apply changes (Modaliser does not reload config in place). The menu bar icon provides **Settings** (opens `config.scm` in the default editor), **Relaunch** (restart to apply config changes), and **Quit Modaliser**.

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

That's a complete config. `(modaliser dsl)` surfaces the DSL (`key`, `keys`, `group`, `category`, `selector`, `overlay`, `define-tree`, `λ`); `(modaliser leader)` adds `set-leaders!`; the bundled stdlib includes app-specific trees (`safari:`, `chrome:`, `iterm:`) and helpers (`window:`, `launcher:`, `web-search:`, `settings:`).

See the [Quick start](docs/quickstart/index.md) for a guided walkthrough and the [DSL reference](docs/reference/dsl.md) for the full surface.

## Architecture

Modaliser is a native Swift macOS app, but the majority of its logic lives in Scheme. On launch, Swift creates a [LispKit](https://github.com/objecthub/swift-lispkit) runtime and loads `root.scm`, which bootstraps the entire application: activation policy, permissions, status bar, keyboard capture, and user config.

The UI is rendered in WKWebView-backed NSPanels controlled from Scheme. Two panel types exist:

- **Overlay** — a non-activating floating panel showing available keybindings at the current position in the command tree (which-key style).
- **Chooser** — an activating panel with a search input, fuzzy-filtered result list, and optional action panel (used by selectors). Supports static sources (fuzzy-matched locally) and dynamic sources (results fetched from external APIs).

Swift provides native libraries that Scheme calls into: keyboard capture, window management, app management, shell execution, HTTP requests, clipboard, input emulation, fuzzy matching, clipboard history, WebView management, app lifecycle. Incremental DOM updates use a Display-PostScript-inspired pattern: Scheme builds data, pushes JSON to JavaScript, and JS renders directly into the DOM — full-page HTML replacement is avoided except for structural changes.

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

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
