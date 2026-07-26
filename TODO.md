# TODO

Open work, one paragraph each, describing what is true today and what would
change. Deliberately **no embedded agent prompts**: a prompt pins file paths and
line numbers that rot within weeks, and a session picking an item up re-derives
the approach from current code faster than it can re-ground a stale sketch.

## Additional dynamic search sources

The dynamic chooser infrastructure (`'dynamic-search` callback +
`chooser-push-results`) supports any external data source, but only a few are
wired. Candidates: DuckDuckGo search, dictionary/thesaurus lookup, a calculator,
emoji search, or a general REST endpoint the user points at.

## Dark mode CSS theme

`Sources/Modaliser/Scheme/base.css` defines the overlay and chooser palette as
CSS custom properties under one `:root`, and no file in the Scheme tree contains
a `@media (prefers-color-scheme: dark)` block — so both surfaces stay light
under macOS dark mode. The work is a dark override of those properties; block
CSS under `lib/modaliser/blocks/` reads the same variables, so the override
belongs in `base.css` rather than being repeated per block.

## Multi-monitor support for panel positioning

`WebViewManager` centres the overlay and chooser panels on `NSScreen.main`, so
on a multi-display setup they open on the main display rather than the one the
user is working on. They should follow the focused window's screen, falling back
to today's behaviour when no focused window resolves.

## Search memory persistence

Selectors accept `'remember` (an MRU bucket name) and `'id-field`, and
`launchers.sld` populates both — but nothing consumes them. `ui/chooser.scm`
holds no MRU read or write, and neither does the Swift side, so the properties
reach the selector alist and stop there. The work is the persistence itself:
recently-selected items boosted to the top on subsequent opens, identified by
`id-field` and bucketed by `remember`.

## Overlay auto-sizing

The overlay panel is a fixed 340px wide (`overlay-panel-width`,
`ui/overlay.scm`). Height already auto-sizes — `overlay.js` reports content
height through a `ResizeObserver` and the panel resizes natively — so the work
is extending that existing path to width, with a min/max clamp so a long label
widens the panel instead of wrapping.

## Window switcher as built-in selector

The window switcher composes `list-windows` with `focus-window` in the user's
config and works. It could show app icons — the chooser already understands a
`bundleId` icon type in alists — and handle cross-space listing better;
`WindowCache` already tracks focus history and lists windows across spaces.

## Pixel-exact size restoration on cross-display window move

`display:` move (`move-focused-window-to-display`) re-derives the window's frame
as a fraction of the target display's visible area. That is the right default
for moving a window to a display it has not been on, and it round-trips closely,
but not exactly: the fraction rounds to integer pixels, and apps with resize
increments (terminals snap to whole character cells) land a few pixels off. The
work is optional pixel-exact restoration — remember, per window and display, the
frame the window actually last had there, restore it verbatim when a move lands
the window back on a remembered display, and fall back to the proportional remap
on first visit. The hard parts are window identity (`windowId` is per-session,
titles are unstable) and when to invalidate.
