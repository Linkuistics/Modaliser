# 010-diagnose-where-cmd-v-dies

**Kind:** planning

## Goal
Locate, with evidence, exactly where the Cmd-V keystroke is lost on the path
from physical keypress to the chooser input's paste action. Produce enough
findings to write the fix as one or more concrete work leaves at the right
layer (event tap, WKWebView responder chain, or chooser JS) — not as a guess.

## Context
Beyond the brief chain, this task reads:
- `Sources/Modaliser/WebViewManager.swift`, `WebViewLibrary.swift` — how the
  chooser webview is created, what configuration / first-responder behaviour
  is wired.
- The CGEvent tap installation site — grep for `CGEventTap`,
  `reInjectionMagic`, the modal catch-all referred to in
  `feedback_synthetic_event_tagging.md`.
- `Sources/Modaliser/Scheme/ui/chooser.js` and `chooser.scm` — any JS-side
  key handling that could preventDefault on the input.

## Done when
- The keystroke's fate is reproduced on demand against an installed build.
- One of these is established with direct evidence (not inference):
  - the event tap swallows or fails to forward Cmd-V; OR
  - the WKWebView doesn't become / hold first responder under modal; OR
  - the chooser JS intercepts and discards the event; OR
  - some other identified site.
- The next leaf (or, if the cause warrants splitting, a small sub-node) is
  written and committed: a work leaf `020-<fix-name>.md` (or a node
  `020-<thing>/` with its own `BRIEF.md`), scoped to fix the **whole class**
  of standard text-editing shortcuts, not Cmd-V alone.
- If the cause is hard to reverse, surprising, or a real trade-off, an ADR
  is raised under `docs/adr/`. Otherwise no ADR.

## Notes
- This is a *planning* task: deliverable is more tree, not a patch. Resist
  the urge to fix during diagnosis — record findings, write the next leaf,
  stop.
- Per CLAUDE memory: rebuild via `./scripts/install.sh`; "Relaunch" alone
  runs the stale `/Applications` bundle.
- Per CLAUDE memory: report observations, not inferences. If you didn't see
  the keystroke reach a given layer, say so; don't claim it did.

## Findings — session 1 (static analysis only)

Static read of the suspect sites. **No live reproduction yet** — needs an
installed build with instrumentation to pin the exact layer.

### Verified by reading code

1. **CGEvent tap does not swallow Cmd-V.** `KeyboardCapture.handleEvent`
   (`Sources/Modaliser/KeyboardCapture.swift:143`) only suppresses if the
   per-event dispatcher returns `.suppress`. The dispatcher
   (`KeyboardHandlerRegistry.dispatch`, `KeyboardHandlerRegistry.swift:144`)
   has four ways to suppress: capture buffer, armed leader, catch-all, hotkey
   match. None match Cmd-V when a chooser is open:
   - The modal catch-all is **explicitly bypassed for `.maskCommand`** —
     `KeyboardLibrary.swift:285-288` returns `false` (passThrough) for
     Cmd+anything before evaluating Scheme.
   - More to the point, the catch-all is **uninstalled before the chooser
     opens**: at `state-machine.sld:704-706` a selector child calls
     `(modal-exit)` (which calls `(unregister-all-keys!)` →
     `_catchAllHandler = nil`) *before* `(open-chooser child)`.
   - Default leaders are F18 / F17 (`default-config.scm:37`); no default
     binding registers Cmd-V as a hotkey.

2. **`feedback_synthetic_event_tagging.md` is not the cause for this bug.**
   The `reInjectionMagic` tag only matters for events Modaliser *re-injects*
   (arm-window Escape, optimistic-capture rollback). Nothing re-injects
   Cmd-V — it comes from a physical keypress. The brief flagged this as
   "prime suspect, not a conclusion"; static evidence demotes it.

3. **The chooser's JS does not intercept Cmd-V.** `chooser.js:29-49`
   handles only Arrow/Enter/Cmd-Enter/Escape/Tab. No `Cmd-V` branch,
   no blanket `preventDefault`. The fact that `e.key === 'Enter' && e.metaKey`
   *is* handled tells us Cmd-modified events reach the JS layer in general.

4. **No Swift-side `keyDown:` / `performKeyEquivalent:` / `paste:` overrides
   in `WebViewManager` / `KeyablePanel` / `ChooserSearchEngine`.** `KeyablePanel`
   only overrides `canBecomeKey` / `canBecomeMain` to `true`
   (`WebViewManager.swift:218-221`).

5. **Modaliser has no main menu.** `LSUIElement = true` (`Info.plist:21`),
   `setActivationPolicy(.accessory)` is the steady state, and `NSApp.mainMenu`
   is never assigned. The status-bar menu (`LifecycleLibrary.swift:73`) is a
   status-item menu, not a main menu. So there is **no Edit > Paste** key
   equivalent in the menu chain — Cmd-V must be handled by
   `WKWebView.performKeyEquivalent:` or the WebKit content directly.

6. **Typing in the chooser works** (the user can search), so `keyDown:` events
   *do* reach the WKWebView's responder chain. Whatever fails for Cmd-V is
   specific to the key-equivalent path or the `paste:` action.

### Remaining hypotheses (ranked by current confidence)

H1 (**most likely**, ~70%) — **The WKWebView never sees a `paste:` action
because there's no menu item with the Cmd-V key equivalent.** WKWebView on
macOS *does* implement `performKeyEquivalent:` for the editing class, but
that path can be brittle in borderless `NSPanel` hosts without a main menu.
If true, fix is either (a) install a minimal main menu with the standard
Edit submenu (Cut/Copy/Paste/SelectAll), or (b) override
`KeyablePanel.performKeyEquivalent:` to recognise the standard text-editing
shortcuts class and dispatch the matching action selector down the
responder chain.

H2 (~15%) — **The WKWebView is in the responder chain but `paste:` action
validation fails.** Would require `validateUserInterfaceItem:` to return
true for `paste:` on the focused responder. Less likely because the input
is a content-editable `<input>` and Modaliser is unsandboxed.

H3 (~10%) — **An earlier layer drops Cmd-V** despite all four KeyEventDispatch
suppress paths having been ruled out statically. Possible only if a runtime
state I haven't reasoned about installs a Cmd-V hotkey, or the catch-all
remains set when the chooser opens (against the code I read). Worth a single
log line to falsify.

H4 (~5%) — **WKWebView pasteboard access is silently denied.** Unsandboxed
app should have access; unlikely but cheap to test (paste from a non-text
source, e.g., copy a string from another app).

### How session 2 pins the cause

Outlined in `020-fix-text-editing-shortcuts.md` — the fix leaf is structured
verify-first: install with three `NSLog` taps (event tap, panel sendEvent,
panel performKeyEquivalent), reproduce in two chooser types, then pick the
branch matching which log fires last.
