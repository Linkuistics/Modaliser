# How to add a fuzzy-finder for a custom data source

The `(selector …)` form opens a chooser with fuzzy filtering, a
selection list, and a Tab-toggled action panel. Use it whenever you
have a list of items the user should pick from by typing.

## You'll need

- A way to produce a list of items in Scheme — either a literal list,
  a procedure that returns one, or a shell command you can wrap with
  `run-shell`.
- For form-by-form detail: [reference/dsl.md](../reference/dsl.md)
  (`(selector …)` and `(action …)`).

## Steps

1. **Bind a selector** with `(key K L (selector …))`. The `selector`
   form returns an *undecorated* node — the wrapping `key` macro
   supplies the key/label:

   ```scheme
   (key "s" "Snippets"
        (selector 'prompt "Snippet…"
                  'source   (λ () '("apology" "thanks" "address"))
                  'on-select (λ (item)
                               (set-clipboard! (snippet-text item))
                               (send-keystroke '(cmd) "v"))))
   ```

   `'source` is a *thunk* — called when the chooser opens. Wrapping a
   static list in `(λ () …)` is the canonical way to feed a literal
   list; for dynamic sources, the thunk's body does the work
   (`run-shell`, AppleScript, HTTP…).

2. **Use alist items** when each item needs more than a display string
   — e.g. a separate identifier or path that the action consumes:

   ```scheme
   (define projects
     (list
       (list (cons 'name "Modaliser") (cons 'path "~/Development/Modaliser"))
       (list (cons 'name "Notes")     (cons 'path "~/Notes"))
       (list (cons 'name "Dotfiles")  (cons 'path "~/.config"))))

   (key "p" "Projects"
        (selector 'prompt   "Project…"
                  'source   (λ () projects)
                  'id-field "path"
                  'remember "projects"
                  'on-select (λ (item)
                               (open-with "Zed" (cdr (assoc 'path item))))))
   ```

   The chooser fuzzy-matches against the `'name` field; `'id-field`
   identifies items for the `'remember` MRU bucket so the last-picked
   project floats to the top next time. For a dynamic list, the
   `'source` thunk can compute the alist from `directory-list`,
   `run-shell`, or any other Scheme that returns a list of alists.

3. **Add secondary actions** so the same item supports more than one
   verb. `(action …)` entries land in the Tab-toggled panel:

   ```scheme
   (key "p" "Projects"
        (selector 'prompt   "Project…"
                  'source   list-projects
                  'id-field "path"
                  'actions
                    (list
                      (action "Open in Editor"
                        'description "Open with Zed"
                        'key 'primary
                        'run (λ (i) (open-with "Zed" (cdr (assoc 'path i)))))
                      (action "Reveal"
                        'description "Show in Finder"
                        'key 'secondary
                        'run (λ (i) (reveal-in-finder (cdr (assoc 'path i)))))
                      (action "Copy Path"
                        'description "Copy full path"
                        'run (λ (i) (set-clipboard! (cdr (assoc 'path i))))))))
   ```

   `'key 'primary` is fired by Return; `'key 'secondary` by
   Cmd-Return; other actions are listed in the Tab panel with their
   bound shortcut. The bundled `(modaliser launchers)` factories use
   exactly this shape — read its `.sld` for a longer example.

4. **Save and relaunch.**

## Verify it worked

Press the leader, then your selector key. The chooser appears with
your prompt. Confirm:

- Typing filters the list (fuzzy match — characters can be
  non-contiguous, in order).
- Return fires `'on-select` (or the `'primary` action).
- Tab toggles the action panel; Cmd-Return fires the `'secondary`
  action.
- Escape dismisses without selecting.

## Variations

**Live remote search.** Use `'dynamic-search` instead of `'source`
when the items depend on the query (web search, language servers).
The procedure is called per keystroke with the current query and
returns a fresh list of items. The bundled `(modaliser web-search)`
library is the worked example — read its `.sld` and prefer importing
`web-search:google` and friends, only writing your own when you need
a custom backend.

**Restrict to file roots.** For file pickers, `'file-roots` confines
matches to a list of directories — `launcher:find-file` from
`(modaliser launchers)` is the worked example.

## Related

- [reference/dsl.md](../reference/dsl.md) — `(selector …)` and
  `(action …)` keyword sets.
- [reference/libraries.md](../reference/libraries.md) — bundled
  selector factories (`launcher:find-application`,
  `launcher:find-file`, `web-search:google`).
- [reference/keyboard.md](../reference/keyboard.md) — chooser-specific
  navigation keys (Tab, Cmd-Return, …).
