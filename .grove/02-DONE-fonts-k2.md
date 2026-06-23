# fonts-k2

**Kind:** work

## Goal

Bundle **IBM Plex Sans + IBM Plex Mono** `.woff2` in the app so the overlay and
chooser WebViews load them with **no network**, and wire `@font-face` + the build
copy step + the Swift base-URL/font path so the `--font-family` / `--font-mono`
tokens resolve. (Spec §7 "Web font bundling".)

## Context

- `scripts/build-app.sh` vendors LispKit libraries via `ditto --noextattr` into
  `Contents/Resources/LispKitLibraries` — **mirror that pattern** for the fonts.
- `base.css` has **no `@font-face`** today; the font is `"Menlo","SF Mono",
  monospace` (`base.css:17`).
- Confirm how the overlay HTML's **base URL** is set (SchemeEngine /
  WebViewManager / `webview-set-html!`) so bundle-relative `@font-face` URLs
  resolve in the `WKWebView`.
- The hidden **chip-probe WebView** ((modaliser theming)) must still resolve
  `.chip` computed styles at boot — don't break it.
- **Dev vs production path divergence is real** (CLAUDE.md gotcha): fonts must
  resolve both under `swift run` (reads `Sources/Modaliser/Scheme/`) and in the
  installed `.app`.

## Done when

- IBM Plex `.woff2` files vendored under `Contents/Resources` (+ the OFL license
  file); `build-app.sh` copies them with the `ditto` pattern.
- `@font-face` rules in `base.css` load IBM Plex Sans + Mono from bundle-relative
  URLs; `--font-family` / `--font-mono` tokens defined.
- Overlay + chooser render in IBM Plex with networking off; the chip-probe boot
  path still works; both dev and installed `.app` resolve the fonts.

## Notes

- Sequenced **first**: DOM-agnostic, lowest-risk, de-risks WebView font loading
  early. The full aesthetic (colors/bands/keycaps) is [[visual-skin-k5]] — here,
  only the typeface swap + plumbing.
