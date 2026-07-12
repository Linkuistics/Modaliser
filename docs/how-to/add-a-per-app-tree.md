# How to add a per-app tree

You want bindings that only fire when a specific app is frontmost —
e.g. tab-navigation bindings for Safari, vim-style window moves for
your editor. The local leader (F17 in the seeded config) opens the
per-app tree for the currently-focused app. If that app has no
per-app tree, the local leader does nothing — it does *not* fall back
to the global tree; the global leader (F18) is always there for that.

## You'll need

- An idea of which app you want to target.
- Its bundle identifier — e.g. `com.apple.Safari`,
  `com.googlecode.iterm2`, `dev.zed.Zed`. Run
  `osascript -e 'id of app "Safari"'` if you don't know it.
- For form-by-form detail: [reference/dsl.md](../reference/dsl.md)
  (`screen`).

## Steps

1. **Pick your starting point.** Three options, in order of effort:

   - Use a bundled factory: `(modaliser apps safari)`, `(modaliser
     apps chrome)`, or `(modaliser apps iterm)` — see
     [reference/libraries.md](../reference/libraries.md).
   - Extend a bundled factory via its `'extra-bindings` option.
   - Write a fresh tree with `(screen 'com.your.app …)`.

2. **For a bundled app (Safari shown):**

   ```scheme
   (import (prefix (modaliser apps safari) safari:))
   (safari:register!)
   ```

   That registers a default tree under `'com.apple.Safari` with Tabs
   and Browser submenus. Press F17 while Safari is frontmost to see it.

3. **Add bindings on top of a bundled factory** with `'extra-bindings`:

   ```scheme
   (safari:register!
     'extra-bindings
       (list
         (key "/" "Search Page"
              (λ () (send-keystroke '(cmd) "f")))
         (key "R" "Hard Reload"
              (λ () (send-keystroke '(cmd shift) "r")))))
   ```

   The extras are appended to the factory's defaults — they appear
   after the factory's own panels in the overlay.

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
   card instead.) Tap
   F17 with Zed frontmost to see it.

5. **Save and relaunch** from the menu bar icon.

## Verify it worked

Focus the app you targeted, tap F17, wait for the overlay. Your
bindings should appear with the app's name in the breadcrumb. If the
overlay shows the *global* tree instead, the local leader fell back —
either the scope ID is wrong, or the `screen` form didn't run.

`osascript -e 'tell application "System Events" to bundle identifier of
first application process whose frontmost is true'` prints the bundle
ID of the frontmost app — run it (after switching back) to verify what
F17 will dispatch against.

## Notes

**One tree per scope.** A second `(screen 'com.apple.Safari …)`
replaces the first — there's no merging across calls. Reach for
`'extra-bindings` on a bundled factory if you want to add without
replacing.

**Global vs local.** F18 fires the global tree regardless of frontmost
app; F17 fires the per-app tree for the frontmost app, or does nothing
if that app has no per-app tree — the local leader does not fall back
to the global tree. Both leader keys are independently configurable —
see `(set-leaders! …)` in [reference/dsl.md](../reference/dsl.md).

**Bundle variants.** A scope like `'com.googlecode.iterm2/nvim` lets
the dispatcher pick a sub-tree based on app state (the iTerm factory
uses this to swap the tree based on whether neovim is focused inside
the terminal). The variant suffix comes from `set-local-context-suffix!`
— see `(modaliser event-dispatch)` in
[reference/libraries.md](../reference/libraries.md). For a full
walkthrough of pane-aware variant trees, see
[terminal-pane-aware-tree.md](terminal-pane-aware-tree.md).

## Related

- [reference/dsl.md](../reference/dsl.md) — `(screen …)` signature and
  keyword set.
- [reference/libraries.md](../reference/libraries.md) — `(modaliser
  apps safari | chrome | iterm)` factory APIs.
- [walk-mode.md](walk-mode.md) — for app-modes where one binding
  should keep firing (e.g. iTerm pane focus).
