# cannot-paste-into-input-fields-in-choosers — brief

## Goal
Chooser inputs should behave like any other macOS text field for keyboard text
editing. Today, Cmd-V silently vanishes; the user observation extends, by
construction, to the full class of standard text-editing shortcuts (Cmd-V/C/X/A,
option-arrows, Cmd-arrows, undo, etc.) since they share one event path. The
chooser input is the only focused-text-input surface in Modaliser, so this is
the single site that needs to work.

## Done when
- A focused chooser input supports the standard text-editing shortcuts class
  end-to-end. Concretely, in any chooser: Cmd-V pastes the system clipboard,
  Cmd-C / Cmd-X / Cmd-A behave as on a normal `NSTextField`, option-arrows
  move by word, Cmd-arrows jump to line/document ends.
- The root cause is named (not just patched around) and recorded — either in
  an ADR if it is a real trade-off, or otherwise inline in the relevant
  source comment / commit message.
- Manual verification covers at least two distinct chooser types (e.g. app
  launcher and one other), so we're not papering over a chooser-specific
  quirk.

## Decomposition

- `010-diagnose-where-cmd-v-dies.md` — planning, **retired** (see
  `done/`). Static-analysis findings ruled out the CGEvent tap and the
  chooser JS; remaining candidates live in the AppKit ↔ WKWebView layer.
- `020-fix-text-editing-shortcuts.md` — work. Verify-first: instrument the
  three remaining candidate layers, reproduce in two chooser configurations,
  then apply the fix matching the death-site (table of branches in the leaf).
  Scoped to the **whole** standard-text-editing-shortcuts class.

## Pointers
- Glossary terms in play: **Chooser**, **Chooser input**, **Standard
  text-editing shortcuts** (see `CONTEXT.md`).
- Memory worth surfacing during diagnosis (not yet promoted into the repo):
  `feedback_synthetic_event_tagging.md` — synthetic CGEvents need
  `reInjectionMagic` tagging, otherwise the modal catch-all swallows them on
  return through Modaliser's own tap. This is the prime suspect, **not a
  conclusion** — Leaf 010 must verify before any fix.
- Code surface to inspect first: `Sources/Modaliser/WebViewManager.swift`,
  `Sources/Modaliser/WebViewLibrary.swift`, the CGEvent tap (search for
  `CGEventTap` / `reInjectionMagic`), and `Sources/Modaliser/Scheme/ui/chooser.{js,scm}`.

## Notes
- Bug applies to the install-from-source build (`./scripts/install.sh`),
  per `feedback_install_flow.md` — reproduce against an actually-installed
  bundle, not a stale `/Applications` copy.
- The grove name says "input fields" (plural). That's user-facing phrasing;
  internally there is exactly one input per chooser. Don't let the plural
  mislead a future session into hunting for a second input.
