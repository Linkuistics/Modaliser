# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Modaliser is

A Scheme-scriptable modal keyboard system for macOS: press a leader key, type a
sequence, and Modaliser launches apps, manages windows, runs shell commands, drives
terminal panes, etc. The user's configuration *is* Scheme code.

**The central architectural fact:** Swift is a thin native shell; the majority of the
application logic lives in Scheme, interpreted at runtime by an embedded
[LispKit](https://github.com/objecthub/swift-lispkit). `main.swift` →
`ModaliserAppDelegate` → `SchemeEngine` is the entire Swift entry path (~3 files);
everything after that — activation policy, permissions onboarding, status bar,
keyboard capture, config loading — is bootstrapped by **`Sources/Modaliser/Scheme/root.scm`**,
the only Scheme file Swift loads directly. When orienting in this codebase, read
`SchemeEngine.swift` and `root.scm` first; `main.swift`/`ModaliserAppDelegate.swift`
are nearly empty.

## Commands

```bash
swift build                       # debug build → .build/debug/Modaliser
swift test                        # full test suite (XCTest)
swift test --filter KeyCodeTests  # single test class (or Class/testMethod)
.build/debug/Modaliser            # run the debug binary directly

./scripts/build-app.sh            # release build → .build/release/Modaliser.app
./scripts/install.sh              # build + copy to /Applications
./scripts/check-portable-surface.sh   # enforce the portability contract (see below)
```

Requires macOS 14+ and Swift 5.9+. `build-app.sh` code-signs with a "Modaliser Dev"
certificate when present (this preserves Accessibility TCC grants across rebuilds),
else falls back to ad-hoc signing. `scripts/release-*.sh` drive the Homebrew-cask
release flow.

There is no separate lint step; `check-portable-surface.sh` is the one bespoke
invariant check and should be treated as a required gate (wire it into CI / run it
after touching `lib/modaliser`).

## Architecture

### The Swift ↔ Scheme bridge

Native capabilities are exposed to Scheme as LispKit `NativeLibrary` subclasses, one
per Swift `*Library.swift` file (e.g. `ShellLibrary` → `(modaliser shell)`,
`WindowLibrary` → `(modaliser window)`). Each declares a `name` like
`["modaliser", "shell"]` and `define`s `Procedure`s. They are registered and imported
in `SchemeEngine.init` (`Sources/Modaliser/SchemeEngine.swift`) — **that initializer is
the canonical list of what native primitives Scheme can call.** Adding a native
primitive means: add/extend a `*Library.swift`, then register + import it in
`SchemeEngine.init`.

The non-`*Library` Swift files are the implementations those libraries wrap:
window geometry (`WindowManipulator`, `WindowEnumerator`, `ChipPlacement`), keyboard
capture (`KeyboardCapture`, `KeystrokeEmitter`, `KeyCode`), fuzzy matching
(`FuzzyMatcher`), WebView panels (`WebViewManager`), clipboard, app scanning, etc.

### The Scheme layer (two tiers, deliberately separated)

- `Sources/Modaliser/Scheme/lib/modaliser/**.sld` — the **portable library tree**.
  R7RS `define-library` files that form the user-facing stdlib (`dsl`, `leader`,
  `state-machine`, `window-actions`, `terminal`, `apps/*`, `blocks/*`, `muxes/*`, …).
- `Sources/Modaliser/Scheme/ui/*.scm` (`css.scm`, `overlay.scm`, `chooser.scm`) —
  **host-specific** UI plumbing, flat-`include`d by `root.scm` (not `import`ed). These
  lean on LispKit-specific bindings (WebView, JSON) and intentionally stay outside the
  portable tree.

### Portability contract (load-bearing invariant)

The `lib/modaliser` tree must depend **only** on `(scheme …)`, `(srfi …)`, and other
`(modaliser …)` libraries — **never `(lispkit …)`**. This is what lets user configs be
written against a portable surface. `scripts/check-portable-surface.sh` enforces it by
grepping for the literal `(lispkit ` — which also means **prose comments in those files
must avoid that literal string** (write "the LispKit hashtable library", not the
parenthesized form). See `docs/reference/portability.md`.

### Library path resolution & the `sys/` mirror

At startup `SchemeEngine` builds the library search path, ordered (first wins):
user config root (`~/.config/modaliser/`) → synced `sys/` mirror → app bundle →
LispKit's R7RS/SRFI. In a *production* `.app` run, `SysSync` mirrors the whole Scheme
tree into `~/.config/modaliser/sys/` so users can browse/fork every bundled file;
dev/test runs read straight from `Sources/Modaliser/Scheme/` and never write to `sys/`
(gated by `isProductionBundlePath`). User-first ordering is what lets a user shadow any
bundled library. LispKit ships its own R7RS/SRFI `.sld`s but SPM excludes them from
bundling, so `build-app.sh` vendors them into `Contents/Resources/LispKitLibraries`
and `SchemeEngine` adds that path — see `locateLispKitLibrariesFallback`.

### UI rendering

The overlay (which-key) and chooser (fuzzy finder) are `WKWebView`-backed `NSPanel`s
driven from Scheme. DOM updates use a Display-PostScript-inspired pattern: Scheme builds
data, pushes JSON to JavaScript, and JS renders into the DOM — full-page HTML
replacement is avoided except for structural change. Blocks (`blocks/*`) pair a `.sld`
(Scheme spec) with `.js`/`.css` assets. See `docs/reference/renderer-protocol.md`.

## Repository conventions

- **grove workflow.** Long workstreams are driven via the `grove` skill
  (`.claude/skills/grove/`): a git-tracked task tree under `.grove/`, one task per
  session, ADRs in `docs/adr/`, PRDs in `docs/prd/`. Worktrees live under
  `.grove-worktrees/`.
- **`CONTEXT.md` is the Ubiquitous Language glossary** and is load-bearing against
  terminology drift across sessions — read it when working in the terminal-pane,
  window-switching, chooser, or window-layout domains, and append terms inline as they
  harden. It is glossary-only (no implementation detail).
- **`docs/` is the source of truth** for behaviour. `docs/reference/` (dsl, libraries,
  state-machine, library-system, portability, theming, renderer-protocol, keyboard) is
  ground-truthed against the `.sld` sources; `docs/how-to/` holds task recipes;
  `docs/adr/` records decisions. Update the relevant doc when you change the surface it
  documents.
- **Tests mirror sources** under `Tests/ModaliserTests/`, covering both Swift units and
  end-to-end Scheme evaluation (`*LibraryTests`, `ConfigDslTests`, `EndToEndSchemeModalTests`).
  Scheme library behaviour is exercised by loading it through a real LispKit context, so
  a `.sld` change with a behavioural effect generally needs a matching test.

## Gotchas

- **No in-place config reload.** The menu bar offers **Relaunch**; the running app does
  not re-read config (see `TODO.md` for the planned hot-reload). Changes to a user's
  `~/.config/modaliser/config.scm` require a relaunch.
- **Dev vs. production divergence is real.** Scheme-directory resolution, `sys/`
  mirroring, and LispKit library location all branch on whether the binary is inside an
  `.app`. A bug that only reproduces in the installed app (not under `swift run`) is
  usually one of these paths — start at `SchemeEngine.resolveSchemeDirectory` /
  `isProductionBundlePath`.
- **Window layout ops on Electron/Chromium apps** depend on accessibility quirks
  (cold-AX resolution, the EUI flip) documented at length in `CONTEXT.md` and
  `docs/adr/` — consult those before touching `WindowManipulator`.
- The user-facing config lives in `~/.config/modaliser/`, which has its **own**
  `CLAUDE.md` scoped to editing configuration rather than the app.
