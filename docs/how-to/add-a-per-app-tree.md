# How to add a per-app tree

You want bindings that only fire when a specific app is frontmost —
e.g. tab-navigation bindings for Safari, vim-style window moves for
your editor. The local leader (F17 in the seeded config) opens the
per-app tree for the currently-focused app, falling back to the
global tree when that app has no screen of its own.

## You'll need

- An idea of which app you want to target.
- Its bundle identifier — e.g. `com.apple.Safari`,
  `com.googlecode.iterm2`, `dev.zed.Zed`. Run
  `osascript -e 'id of app "Safari"'` if you don't know it.
- For form-by-form detail: [reference/dsl.md](../reference/dsl.md)
  (`screen`).

## Steps

1. **Pick your starting point.** No bundled library ships a screen
   (ADR-0021), so you always write the tree — the only question is
   whether you copy one first:

   - Copy a screen out of the seeded `config.scm`. It authors eleven
     of them (Safari, Dia, Finder, Mail, Slack, Zed, Signal, Messages,
     Telegram, Obsidian, Zotero) and they are yours to edit.
   - Copy `sys/scheme/examples/chrome.scm` — a standalone per-app
     screen, marked up to show which two blocks to lift.
   - Write a fresh tree with `(screen 'com.your.app …)`.

   Any machinery the app needs is imported from a library — e.g.
   `(modaliser apps dia)` exports the tab-switcher helpers Dia's
   screen composes, and `(modaliser apps iterm)` exports the pane ops
   and live-list blocks iTerm's does.

2. **Write the screen** and name it in your `configuration` call:

   ```scheme
   (define safari-screen
     (screen 'com.apple.Safari
       (group "t" "Tabs"
         (key "n" "New Tab"   (λ () (send-keystroke '(cmd) "t")))
         (key "w" "Close Tab" (λ () (send-keystroke '(cmd) "w"))))
       (group "b" "Browser"
         (key "l" "Focus Address Bar" (λ () (send-keystroke '(cmd) "l")))
         (key "f" "Find on Page"      (λ () (send-keystroke '(cmd) "f"))))))

   (configuration
     …
     safari-screen)
   ```

   Press F17 while Safari is frontmost to see it.

3. **Add bindings** by writing more rows — there is no `'extra-bindings`
   option to reach for, because the whole tree is already yours:

   ```scheme
   (define safari-screen
     (screen 'com.apple.Safari
       …
       (key "/" "Search Page" (λ () (send-keystroke '(cmd) "f")))
       (key "R" "Hard Reload" (λ () (send-keystroke '(cmd shift) "r")))))
   ```

4. **For an app with no factory,** write a screen from scratch. Use the
   app's bundle ID as the scope symbol, and group the rows into
   `(panel …)` cards:

   ```scheme
   (screen 'dev.zed.Zed
     (panel "Editor"
       (key "p" "Command Palette"
            (λ () (send-keystroke '(cmd shift) "p")))
       (key "f" "Find in Project"
            (λ () (send-keystroke '(cmd shift) "f"))))
     (group "g" "Git"
       (key "s" "Status" (λ () (send-keystroke '(ctrl) "g")))
       (key "b" "Blame"  (λ () (send-keystroke '(ctrl shift) "g")))))
   ```

   Same DSL as the global screen; only the scope differs. (A loose
   `(key …)` outside any panel renders bare in the loose region above
   the grid — wrapping them in a named `(panel …)` gives them a titled
   card instead.) `screen` returns a tree fragment — include it in
   your `configuration` call like any other. Tap
   F17 with Zed frontmost to see it.

5. **Save and relaunch** from the menu bar icon.

## Verify it worked

Focus the app you targeted, tap F17, wait for the overlay. Your
bindings should appear with the app's name in the breadcrumb. If the
overlay shows the *global* tree instead, the local leader fell back —
either the scope ID is wrong, or the fragment never made it into your
`configuration` call.

`osascript -e 'tell application "System Events" to bundle identifier of
first application process whose frontmost is true'` prints the bundle
ID of the frontmost app — run it (after switching back) to verify what
F17 will dispatch against.

## Notes

**One tree per scope.** Two trees for the same scope error at
`configuration` time (unless they are the identical value) — there is
no override and no last-wins. Since every screen is authored in your
config, the usual cause is copying an example in beside a screen you
already had for that app: keep one and delete the other.

**Global vs local.** F18 fires the global tree regardless of frontmost
app; F17 fires the per-app tree for the frontmost app, falling back to
the global tree when that app has no screen. Both leader keys are
independently configurable —
see `(leaders …)` in [reference/dsl.md](../reference/dsl.md).

**Terminal contexts.** On a terminal-like screen (iTerm and friends),
F17 can land in an *inner tool's* tree instead — nvim, herdr, a mux —
chosen by what runs in the focused pane via the Terminal context map.
For the full walkthrough, see
[terminal-pane-aware-tree.md](terminal-pane-aware-tree.md).

## Related

- [reference/dsl.md](../reference/dsl.md) — `(screen …)` signature and
  keyword set.
- [reference/libraries.md](../reference/libraries.md) — the bundled
  libraries, and which apps need one at all.
- [walk-mode.md](walk-mode.md) — for app-modes where one binding
  should keep firing (e.g. iTerm pane focus).
