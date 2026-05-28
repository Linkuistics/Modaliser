# 020-fix-text-editing-shortcuts

**Kind:** work

## Goal
Make a focused chooser input support the **full standard-text-editing-shortcuts
class** end-to-end: Cmd-V/C/X/A, option-arrows, Cmd-arrows, Cmd-Z/Shift-Cmd-Z.
Fix at the actual death-site (confirmed by instrumentation in this task's first
step), not at a guessed layer.

## Why verify-first
Session-1 diagnosis (see `010-diagnose-where-cmd-v-dies.md`'s "Findings")
ruled out the CGEvent tap and the chooser JS from code reading. The remaining
candidates all live in the AppKit ↔ WKWebView layer of the chooser's
`KeyablePanel`. They share an event path, so the right fix probably handles
the whole shortcut class at once — but the *exact* path differs by
death-site, so jumping straight to a fix would risk patching the wrong layer.

## Step 1 — instrument

Add three temporary `NSLog`s (delete in the same commit that lands the fix):

1. **`KeyboardCapture.handleEvent`** (`Sources/Modaliser/KeyboardCapture.swift`,
   in the existing method) — log on Cmd-modified keyDowns:
   `NSLog("tap: cmd-keyDown kc=%d -> %@", keyCode, result == .suppress ? "suppress" : "passThrough")`
   Place it after `let result = onKeyEvent(captured)` and before the switch.

2. **`KeyablePanel.sendEvent:`** (override in
   `Sources/Modaliser/WebViewManager.swift`) — log Cmd-modified `keyDown`:
   `NSLog("panel.sendEvent: cmd-keyDown kc=%d", event.keyCode)` then
   `super.sendEvent(event)`.

3. **`KeyablePanel.performKeyEquivalent:`** (override on the same subclass) —
   log entry + the boolean result of `super.performKeyEquivalent(with:)`:
   `NSLog("panel.performKeyEquivalent: kc=%d cmd=%@ -> %@", ...)`.

Build + install via `./scripts/install.sh` (per CLAUDE memory: "Relaunch"
runs the stale `/Applications` bundle).

## Step 2 — reproduce in two chooser types

Per the root brief's "Done when" #3:

- App launcher chooser.
- One other (e.g. a file-finder selector, or the clipboard-history chooser if
  it uses the same surface).

In each: copy a known string from another app, open the chooser, press
Cmd-V. Capture the log via Console.app or
`log stream --predicate 'process == "Modaliser"' --info`.

## Step 3 — pick the fix branch from the log

| Last log line                                       | Diagnosis                                                | Fix                                                                                                                                                                                                                          |
|-----------------------------------------------------|----------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `tap: cmd-keyDown ... -> suppress`                  | The tap *is* dropping it; H1-H2 are wrong.               | Trace which dispatcher branch fires and remove the suppression — fixes the whole class because every shortcut shares the modifier-mask test.                                                                                 |
| `tap: ... -> passThrough` only (no panel log)       | macOS doesn't route the key to the chooser's panel.      | Likely activation policy or `becomeKey` ordering — investigate `NSApp.activate` vs `makeKeyAndOrderFront` timing in `WebViewManager.createPanel`.                                                                            |
| `panel.sendEvent: ...` fires, no `performKeyEquivalent` | `NSPanel` isn't translating it to a key equivalent.  | Either install a hidden main menu containing the standard Edit submenu, *or* override `KeyablePanel.performKeyEquivalent:` to forward the standard text-editing shortcut class to the WKWebView responder chain.             |
| `panel.performKeyEquivalent: ... -> false`          | The WKWebView's `performKeyEquivalent:` is declining.    | Make the WKWebView first responder when the panel becomes key (`panel.makeFirstResponder(webView)` after `makeKeyAndOrderFront`), and re-test. If still false, install the minimal main menu (the cleaner long-term answer). |
| `panel.performKeyEquivalent: ... -> true` then nothing pastes | WKWebView accepts the equivalent but `paste:` fails. | Action validation. Check `validateUserInterfaceItem:` on the focused content. Usually unsandboxed apps don't hit this; double-check entitlements aren't being inferred.                                                       |

The fix is **one of** the above — chosen by evidence, not guess. Apply it,
remove the three instrumentation `NSLog`s in the same commit, and verify the
*whole shortcut class* (not just Cmd-V):
Cmd-V/C/X/A, option-left/right, Cmd-left/right, Cmd-Z, Shift-Cmd-Z.

## Done when

- Cmd-V/C/X/A, option-arrows, Cmd-arrows, undo/redo all behave like a stock
  `NSTextField` in two distinct chooser configurations.
- Instrumentation `NSLog`s are removed; the fix landed in a single focused
  commit.
- Root-cause naming: if the fix is "surprising, hard to reverse, or a real
  trade-off" (e.g. installing a hidden main menu just to satisfy WKWebView's
  key-equivalent routing), raise an ADR under `docs/adr/`. Otherwise leave
  the cause in the commit message / a single source comment.

## Notes

- "Chooser type" here means a distinct **selector configuration** (different
  source/dynamic-search). The chooser surface is one impl (`chooser.scm`),
  per `CONTEXT.md`. Don't go hunting for a second chooser implementation.
- Per CLAUDE memory: rebuild via `./scripts/install.sh`, not "Relaunch".
- Per CLAUDE memory: report observations, not inferences. If a log line
  doesn't appear, don't claim the layer was reached.
