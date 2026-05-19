# Inline-style → data-attrs cleanup — Fresh-Session Kickoff

> **For agentic workers:** This is a *kickoff* prompt for a fresh
> Claude Code session. Read it end-to-end before touching code.

## Background

Two recent refactors moved Modaliser's CSS authoring surface entirely
into `.css` files: chip styling moved to `.chip` / `.chip.faded` rules
(merge `96e8d75`), and `set-host-header!` / `set-overlay-css!` were
deleted in favour of `~/.config/modaliser/theme.css` (merge `9fcd216`).
The stated principle is now:

> Scheme code may set classes on elements. It must not emit CSS
> strings. All CSS lives in `.css` files, and theme-able values are
> exposed via CSS custom properties.

One Scheme-side CSS-string emission remains. This slice removes it.

## Scope

`Sources/Modaliser/Scheme/ui/overlay.scm` — the `render-overlay-default`
function emits an inline `style="--overlay-cols: N; --entry-key-ch: M"`
attribute on the `.overlay-entries` `<ul>` (currently line 257-263). It's
the only place Scheme still concatenates a CSS string.

The data flowing through that inline style is dynamic and computed in
Scheme (`overlay-column-count` reads the user's target aspect ratio;
`max-key-chars` walks the entries). The values reach CSS via the
custom properties `--overlay-cols` and `--entry-key-ch`, which are
referenced in `base.css` (lines 123 + 141) via `var(...)`.

**In scope:** convert the Scheme → CSS bridge from inline style to
data attributes that JS reads and applies via
`element.style.setProperty(...)`. Same pattern `overlay.js` already
uses on the incremental-update path (lines 91-94).

**Out of scope:**
- `(modaliser blocks which-key)` block JS already calls
  `cols.style.setProperty('--overlay-cols', …)` (`which-key.js:80`).
  Don't refactor that — it's downstream of the JSON payload, not from
  a Scheme HTML attr.
- The diagram-panel block — it doesn't emit inline styles from Scheme.
- Any CSS in `.css` files — those are the authoring surface and stay
  as-is.

## Files to touch

1. `Sources/Modaliser/Scheme/ui/overlay.scm` (line 257-263):

   Current:
   ```scheme
   (entries-attrs
     (list (cons 'class "overlay-entries")
           (cons 'style
             (string-append "--overlay-cols: "  (number->string n-cols)
                            "; --entry-key-ch: " (number->string key-ch)))))
   ```

   Target shape:
   ```scheme
   (entries-attrs
     (list (cons 'class "overlay-entries")
           (cons 'data-cols   (number->string n-cols))
           (cons 'data-key-ch (number->string key-ch))))
   ```

2. `Sources/Modaliser/Scheme/ui/overlay.js` — add a one-time DOM-ready
   pass that mirrors the update-path code (lines 91-94):

   ```js
   function applyOverlayEntryProps() {
     const ul = document.querySelector('.overlay-entries');
     if (!ul) return;
     const cols  = ul.dataset.cols;
     const keyCh = ul.dataset.keyCh;   // dataset converts data-key-ch → keyCh
     if (cols)  ul.style.setProperty('--overlay-cols',  cols);
     if (keyCh) ul.style.setProperty('--entry-key-ch', keyCh);
   }
   ```

   Call it from `DOMContentLoaded` (or wherever overlay.js wires its
   initial render hooks — read the file before deciding).

3. `Tests/ModaliserTests/OverlayRenderTests.swift` (lines 55-102 — three
   tests pinning the literal `--overlay-cols: N` / `--entry-key-ch: N`
   strings in HTML):

   - `renderOverlayBodyEmitsColumnCountStyle` → assert
     `html.contains("data-cols=\"2\"")`.
   - `renderOverlayBodyEmitsKeyChFromWidestKey` → assert
     `html.contains("data-key-ch=\"3\"")`.
   - `renderOverlayBodyKeyChClampsToTwo` → assert
     `html.contains("data-key-ch=\"2\"")`.

   Update the test names + failure messages too so they say
   "data-cols / data-key-ch attribute" instead of "inline style".

## Workflow

1. **Open a worktree.** `superpowers:using-git-worktrees`, branch name
   `data-attrs-cleanup`. Verify it's based on local `main` (tip should
   be `9fcd216`), not stale `origin/main`.
2. **Baseline.** `swift test` — should report 481/481 passing. If not,
   stop.
3. **Read `Sources/Modaliser/Scheme/ui/overlay.js` in full.** Find the
   DOM-ready / initial-render hook. The function `applyOverlayEntryProps`
   needs to run at the same point that would correctly observe a
   freshly-set HTML payload.
4. **Apply the three edits above** in this order: Scheme edit, JS edit,
   test edit. Run `swift test` after each — should stay 481/481.
5. **Verify zero CSS-string emission in Scheme.** Final check:
   `grep -rE "string-append.*--[a-z]|cons 'style" Sources/Modaliser/Scheme/`
   should return zero lines.
6. **Code review.** `superpowers:requesting-code-review` — focus on (a)
   the JS hook fires before the user can see an unstyled flash on
   first paint, (b) `dataset.keyCh` actually corresponds to the
   `data-key-ch` attribute name (case-conversion rule), (c) no
   regressions in test coverage for the two CSS variables.
7. **Finish.** `superpowers:finishing-a-development-branch`.

## Anti-traps

- **Don't switch the consuming CSS to read from the attribute.**
  CSS `attr()` for non-`content` properties is still effectively
  experimental in WebKit. Keep `base.css` referencing `var(--overlay-cols, 1)`
  and `var(--entry-key-ch, 2)` exactly as today — only the *source* of
  those custom-property values changes.
- **Don't add a third "load" hook.** `overlay.js` may already have a
  DOMContentLoaded handler — extend it rather than wiring a new one.
- **Don't emit the attribute when the value would be the fallback.**
  Specifically: `data-cols` and `data-key-ch` should still always be
  emitted (the values are always computed). The CSS fallback only
  catches the "JS hasn't run yet" race.
- **First-paint race.** WKWebView runs scripts after parsing. There's a
  tiny window where the `<ul>` exists with the data attr but the
  `--overlay-cols` custom property isn't set yet. The CSS fallback
  (`var(--overlay-cols, 1)` → 1 column) covers this. Keep the
  fallback; don't try to make the JS run synchronously somehow.
- **Don't touch the update path.** `push-overlay-update` already sends
  `cols`/`keyCh` in the JSON payload and `overlay.js:91-94` already
  applies them via `setProperty`. The incremental render flow is
  unaffected.
- **Don't migrate `which-key.js:80` style.setProperty call.** It's
  applying values from the block's JSON payload, not from an HTML
  attribute. Different concern.

## Definition of done

- `Sources/Modaliser/Scheme/ui/overlay.scm:render-overlay-default` emits
  `data-cols` and `data-key-ch` HTML attributes, not an inline `style`
  attribute.
- `Sources/Modaliser/Scheme/ui/overlay.js` reads those data attributes
  on initial render and applies them via `style.setProperty`.
- `grep -rE "string-append.*--[a-z]|cons 'style" Sources/Modaliser/Scheme/`
  returns zero matches.
- The three `OverlayRenderTests.swift` tests assert the data attributes
  rather than the inline style string.
- `swift test` reports 481/481 passing.
- Smoke test: launch the overlay (F18 → any group), confirm columns
  and key column width still look right (no visual change is the goal).

## Source-of-truth files

- `Sources/Modaliser/Scheme/ui/overlay.scm` — current emission site.
- `Sources/Modaliser/Scheme/ui/overlay.js` — JS-side update path
  precedent + the place to add the initial-render hook.
- `Sources/Modaliser/Scheme/base.css` — the `var(--overlay-cols)` /
  `var(--entry-key-ch)` consumers. **Don't edit** — they stay as-is.
- `Tests/ModaliserTests/OverlayRenderTests.swift` — three tests to
  migrate.
