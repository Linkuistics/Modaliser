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
swift build                          # debug build → .build/debug/Modaliser
swift test                           # the full suite — no skip needed
swift test --filter KeyCodeTests     # one suite
swift test --filter 'KeyCodeTests/f18HasCorrectValue'   # one test
.build/debug/Modaliser               # run the debug binary directly

./scripts/build-app.sh            # release build → .build/release/Modaliser.app
./scripts/install.sh              # build + copy to /Applications
./scripts/check-portable-surface.sh   # enforce the portability contract (see below)
./scripts/check-decision-free.sh      # enforce the decision-free library contract
```

The suite is **swift-testing** (`@Suite` / `@Test`), not XCTest — no file imports
XCTest — so `--filter` is a regex matched against test IDs (`SuiteType` or
`SuiteType/functionName`), not an XCTest class path. A plain `swift test` is green
and needs **no skip**: the whole suite runs offline and reaches nothing outside
the process — not the network, not the developer's own tmux/terminals, not a live
herdr (ADR-0023, ADR-0020). That is structural, not per-test discipline, and it is
worth keeping: if you add a test that needs an outward call, install a canned
runner on the relevant seam rather than reaching past it. To re-verify the
property rather than trust it, ADR-0023's Consequences record the two-instrument
method that established it — a choke-point recorder for *what* leaks, a
process-boundary sandbox denial for *is that all*.

Requires macOS 14+ and Swift 5.9+. `build-app.sh` code-signs with a "Modaliser Dev"
certificate when present (this preserves Accessibility TCC grants across rebuilds),
else falls back to ad-hoc signing. `scripts/release-*.sh` drive the Homebrew-cask
release flow — **`docs/RELEASING.md` is the runbook**; the scripts carry the
reasoning for individual guards, that page carries the procedure.

There is no CI in this repository and no separate lint step.
`check-portable-surface.sh` and `check-decision-free.sh` are the two bespoke
invariant checks; nothing runs them for you, so running both after touching
`lib/modaliser` is a local discipline. A third invariant has no script of its own
because it belongs to packaging: `build-app.sh` wipes the `.app` before
assembling it and then **fails the build** unless the bundled `Scheme/` tree
matches `Sources/Modaliser/Scheme/` exactly (ADR-0019).

## Architecture

### The Swift ↔ Scheme bridge

Native capabilities are exposed to Scheme as LispKit `NativeLibrary` subclasses, one
per Swift `*Library.swift` file (e.g. `ShellLibrary` → `(modaliser shell-native)`,
`WindowLibrary` → `(modaliser window)`). Each declares a `name` like
`["modaliser", "window"]` and `define`s `Procedure`s. They are registered and imported
in `SchemeEngine.init` (`Sources/Modaliser/SchemeEngine.swift`) — **that initializer is
the canonical list of what native primitives Scheme can call.** Adding a native
primitive means: add/extend a `*Library.swift`, then register + import it in
`SchemeEngine.init`.

Registration proves the procedures **resolve**, not that they work — a registered
library can be reachable and still answer nothing. The clipboard-history library
shipped in v3.3.0 with all five of its primitives resolving at the Scheme prompt
and permanently returning null, because the `var store` / `var monitor` they
guard on were declared and never assigned. Deleting that is a correctness fix,
not a tidy-up, and the shape is invisible to a sweep that asks only whether a
type is referenced from `Sources/` — the registration *is* a reference. So when
auditing the bridge, ask both questions: is the type referenced at all (which
finds orphans), and is its backing state ever assigned (which finds this).

Two native libraries are deliberately *not* reachable from the library tree, both
because they reach outside the process: `(modaliser shell-native)` and
`(modaliser http-native)`. Shelling out is how Modaliser drives the user's real
tmux/zellij/terminal apps, and fetching is how web search reaches Google, so the
tree calls the portable `(modaliser shell)` / `(modaliser http)` instead — seams
whose runners are **not installed by default**, wired to the native ones by
`root.scm` at boot and therefore inert under `swift test` (ADR-0023). Before they
existed, one green run put 419 commands onto the developer's machine and fetched
a third-party endpoint. The `-native` suffix is the marker the check script
enforces on.

The non-`*Library` Swift files are the implementations those libraries wrap:
window geometry (`WindowManipulator`, `WindowEnumerator`, `ChipPlacement`), keyboard
capture (`KeyboardCapture`, `KeystrokeEmitter`, `KeyCode`), fuzzy matching
(`FuzzyMatcher`), WebView panels (`WebViewManager`), app scanning, etc.

**Evaluation threading contract.** All evaluation of one engine must be serialized;
in the app the main run loop provides that (every callback dispatches to the main
queue), and a per-engine fence (`ModaliserContext.evalLock` in `SchemeEngine.swift`)
enforces it where the run loop can't — under `swift test`, @Test bodies evaluate on
cooperative-pool threads while the main queue keeps draining callbacks. Any native
callback that re-enters the evaluator (timers, async completions, event handlers)
must dispatch to the main queue and wrap the `evaluator.execute` call in
`context.withEvalLockNonBlocking` — never block the main thread on the fence (see
the doc comments on `ModaliserContext` for the deadlock reasoning).

### The Scheme layer (two tiers, deliberately separated)

- `Sources/Modaliser/Scheme/lib/modaliser/**.sld` — the **portable library tree**.
  R7RS `define-library` files that form the user-facing stdlib (`dsl`,
  `configuration`, `handoff`, `activation`, `fsm`, `window-actions`,
  `terminal`, `apps/*`, `blocks/*`, `muxes/*`, `wms/*`, …).
- `Sources/Modaliser/Scheme/ui/*.scm` (`css.scm`, `overlay.scm`, `chooser.scm`) —
  **host-specific** UI plumbing, flat-`include`d by `root.scm` (not `import`ed). These
  lean on LispKit-specific bindings (WebView, JSON) and intentionally stay outside the
  portable tree.

Beside them, `Sources/Modaliser/Scheme/examples/*.scm` are complete, **never-loaded**
configurations for setups a fresh install does not seed (tmux, Chrome, paneru) — reference
material a user copies from, carried by the `sys/` mirror like everything else. They
are load-tested (`ConfigDslTests.exampleConfigsLoadWithoutErrors`) so an example that
stops composing is a red suite rather than silent rot.

### Portability contract (load-bearing invariant)

The `lib/modaliser` tree must depend **only** on `(scheme …)`, `(srfi …)`, and other
`(modaliser …)` libraries — **never `(lispkit …)`**. This is what lets user configs be
written against a portable surface. `scripts/check-portable-surface.sh` enforces it by
grepping for the literal `(lispkit ` — which also means **prose comments in those files
must avoid that literal string** (write "the LispKit hashtable library", not the
parenthesized form). See `docs/reference/portability.md`.

The same script carries a second rule with the same textual-grep mechanics (and
so the same prose convention — write "the native shell library", "the native HTTP
library"): **no file under `lib/modaliser` may import a `(modaliser …-native)`
library**. Outward-reaching native capability is quarantined behind an
inert-by-default seam that `root.scm` installs at boot — `(modaliser shell)` for
spawning, `(modaliser http)` for fetching. Importing a native form re-opens the
path that let a green test run drive the developer's live tmux, zellij, wezterm,
kitty, iTerm2 and Ghostty, or fetch a third-party endpoint. The rule is stated
over the **`-native` suffix**, not a list of names, so a new quarantine is a
naming decision rather than a script edit. See ADR-0023.

### Decision-free library contract (load-bearing invariant)

A `lib/modaliser` library may hold a **facility** — anything whose correctness is
fixed by the tool it wraps or the machinery it implements — but never a
**decision**, anything whose correctness is fixed only by the user's preference.
Operationally: **no file under `lib/modaliser` authors a key or a label.**
Libraries export ops, blocks, providers and wiring; the user's `config.scm`
binds them into screens. `scripts/check-decision-free.sh` enforces it at
**strict zero** — one authored key or label fails the check, exactly as one
`(lispkit …)` import fails the portability check. See ADR-0021.

### Library path resolution, seeding & the `sys/` mirror

At startup `SchemeEngine` builds the library search path, ordered (first wins):
user config root (`~/.config/modaliser/`) → synced `sys/scheme/lib/` mirror → app
bundle → LispKit's R7RS/SRFI. In a *production* `.app` run, `SysSync` mirrors the
whole Scheme tree into `~/.config/modaliser/sys/scheme/` (wiped + re-copied per bundle
fingerprint, generated `sys/README.md`) and production reads the tree from the mirror;
dev/test runs read straight from `Sources/Modaliser/Scheme/` and never write to `sys/`
(gated by `isProductionBundlePath`). User-first ordering is what lets a user shadow any
bundled library. Seeding is separate and one-shot: first run copies
`default-config.scm` to the user's `config.scm` — one user-owned file, never rewritten;
everything shipped arrives always-fresh via the mirror, so a stale seed can only be
stale *preference*, never stranded machinery (ADR 0019 is the contract). LispKit ships
its own R7RS/SRFI `.sld`s but SPM excludes them from bundling, so `build-app.sh`
vendors them into `Contents/Resources/LispKitLibraries` and `SchemeEngine` adds that
path — see `locateLispKitLibrariesFallback`.

### UI rendering

The overlay (which-key) and chooser (fuzzy finder) are `WKWebView`-backed `NSPanel`s
driven from Scheme. DOM updates use a Display-PostScript-inspired pattern: Scheme builds
data, pushes JSON to JavaScript, and JS renders into the DOM — full-page HTML
replacement is avoided except for structural change. Blocks (`blocks/*`) pair a `.sld`
(Scheme spec) with `.js`/`.css` assets. See `docs/reference/renderer-protocol.md`.

## Repository conventions

- **grove workflow.** Long workstreams are driven via the `grove` skill: a
  git-tracked task tree under `.grove/`, one task per session, with decisions
  landing in `docs/adr/` and designs in `docs/specs/`. The tree is process state
  and is deleted when the grove finishes; the durable output is the ADRs, specs,
  docs and `CONTEXT.md` entries it leaves behind.
- **ADR filenames stay numbered** (`docs/adr/00NN-slug.md`) and citations stay
  bare (`ADR-0018`), not paths. This deliberately inverts the usual slug-only
  advice, because here the **number is the stable handle and the slug is the
  volatile one**: ADRs get reworked *in place* as the design moves — 0011, 0013,
  0014 and 0015 were each rewritten inside one three-day window, keeping the
  number and resharpening the slug — and none of the several hundred bare
  `ADR-00NN` citations across the repo broke. Slug-only naming would have charged
  that toll four times over already, and again on every future rework. Don't
  "fix" this to slugs.
- **`CONTEXT.md` is the Ubiquitous Language glossary** and is load-bearing against
  terminology drift across sessions — read it when working in the terminal-pane,
  window-switching, chooser, or window-layout domains, and append terms inline as they
  harden. It is glossary-only (no implementation detail).
- **`docs/` is the source of truth** for behaviour. `docs/reference/` (dsl, libraries,
  state-machine, library-system, portability, theming, renderer-protocol, keyboard,
  terminal-detection) is ground-truthed against the `.sld` sources; `docs/how-to/`
  holds task recipes; `docs/adr/` records decisions and `docs/specs/` describes how
  areas work. Update the relevant doc when you change the surface it documents.
- **Tests mirror sources** under `Tests/ModaliserTests/`, covering both Swift units and
  end-to-end Scheme evaluation (`*LibraryTests`, `ConfigDslTests`, `EndToEndSchemeModalTests`).
  Scheme library behaviour is exercised by loading it through a real LispKit context, so
  a `.sld` change with a behavioural effect generally needs a matching test.

## Gotchas

- **No in-place config reload — by doctrine, not by omission.** The menu bar offers
  **Relaunch**; the running app never re-reads config, so changes to a user's
  `~/.config/modaliser/config.scm` require a relaunch. Hot reload was considered and
  **rejected** (ADR-0018, option 4): partial teardown of live visit/chips/capture state
  is exactly the orphan-state trap reload-by-relaunch avoids, and the handoff latches
  once by design. Don't build it back; ADR-0018 records what would reopen the question.
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
