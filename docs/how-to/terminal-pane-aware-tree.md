# How to vary the terminal tree by what's in the focused pane

You want F17 (the local leader) to show different bindings depending
on what is running in the focused terminal pane — e.g. an
nvim-specific tree when nvim is focused, a git tree when lazygit is
focused. The dispatcher already supports this through a *context
suffix*; this guide wires it up. The same pattern works whether the
focused terminal is iTerm, WezTerm, Kitty, Ghostty, or a multiplexer
inside one of them, because the detection primitive
(`focused-terminal-path`) is generic across all registered backends.

## How it works

On every local-leader press, a hook installed via
`set-local-context-suffix!` is called with the focused app's bundle ID
and returns a suffix string (e.g. `/nvim`) or `#f`.
`resolve-app-tree` (called internally by the leader handler) then
prefers the tree registered under `"com.googlecode.iterm2/nvim"`,
falling back to the plain `"com.googlecode.iterm2"` tree when no
suffix matches. You register the variant trees with `define-tree`.

For how detection works — what the TTY probe does, which terminals
support it, and the nvim RPC route — see
[`../reference/terminal-detection.md`](../reference/terminal-detection.md).

## You'll need

- A registered terminal backend — one of iTerm, WezTerm, Kitty,
  Ghostty, Alacritty, tmux, or zellij. The detection primitives
  (`focused-terminal-foreground-command`, `focused-terminal-path`,
  `in-chain?`) work across all of them.
- For nvim-variant trees: the `FocusGained`/`FocusLost` autocmds in
  your nvim config — see [The nvim side](
  ../reference/terminal-detection.md#the-nvim-side) in the
  detection reference.
- For form-by-form detail: [reference/dsl.md](../reference/dsl.md)
  (`define-tree`).

## The quick path: `(iterm:register!)`

If you use the bundled iTerm factory, `(iterm:register!)` installs the
suffix hook for you. It already returns `/nvim`, `/zellij`, and
`/zellij+nvim` based on the focused split's foreground command. You only
need to register the matching variant trees:

```scheme
(import (modaliser dsl)
        (modaliser terminal)                  ; nvim-remote-send
        (prefix (modaliser apps iterm) iterm:))
(iterm:register!)

(define-tree 'com.googlecode.iterm2/nvim
  (key "w" "Write"  (λ () (nvim-remote-send ":w<CR>")))
  (key "q" "Close"  (λ () (nvim-remote-send "<Esc>:q<CR>"))))
```

Tap F17 with nvim in the focused split — the `/nvim` tree appears.
Switch the split to a plain shell — the plain `com.googlecode.iterm2`
tree appears instead.

## If you've inlined your iTerm tree

Inlining the iTerm tree by hand — writing a
`(define-tree 'com.googlecode.iterm2 …)` instead of calling
`(iterm:register!)` — keeps your bindings but **drops two
behaviours the library would otherwise install**:

1. The **iTerm backend record** registers with `(modaliser
   terminal)`. Without this, `(terminal:focus-pane-left)` and the
   other 13 façade ops have no backend to dispatch to and raise an
   error at call time. (Pre-cutover the bare `(iterm:focus-pane-*)`
   procedures didn't need this — they were direct calls.)
2. The **context-suffix handler** lets `/nvim`-style variant trees
   activate. Pane detection silently does nothing without it; you
   always get the plain tree.

The fix for #1 is `(iterm:register! 'install-tree? #f)` — this calls
everything `register!` normally does **except** the
`rebuild-tree!` step that would clobber your inline tree:

```scheme
(import (modaliser dsl)
        (prefix (modaliser apps iterm) iterm:)
        (prefix (modaliser terminal)   terminal:))

;; Register the iTerm backend record + sticky focus mode + digit-pick
;; mode + suffix handler with the façade, but leave the tree to us.
(iterm:register! 'install-tree? #f)

(define-tree 'com.googlecode.iterm2
  (category "Focus"
    (key "h" "Left"  terminal:focus-pane-left)
    (key "j" "Down"  terminal:focus-pane-down)
    (key "k" "Up"    terminal:focus-pane-up)
    (key "l" "Right" terminal:focus-pane-right))
  …)
```

That single call covers #1 *and* #2 — the default suffix handler
(detecting nvim, zellij, tmux inside iTerm) installs automatically.
If you want a custom suffix handler instead, also pass
`'install-context-suffix? #f` and write your own per the next
section.

## Worked example: a custom context suffix

The general recipe — branch on the focused split's foreground command.
Add this alongside your `(define-tree 'com.googlecode.iterm2 …)`
(your config already imports `(modaliser dsl)` for `define-tree`,
`key`, and `λ`):

```scheme
(import (modaliser event-dispatch)   ; set-local-context-suffix!
        (modaliser terminal)         ; focused-terminal-foreground-command, nvim-remote-expr
        (modaliser input)            ; send-keystroke
        (modaliser util))            ; string-contains?

;; Runs on every F17 press. Probe the focused iTerm split and choose a
;; tree variant by what's running in it.
(set-local-context-suffix!
  (lambda (bundle-id)
    (and (equal? bundle-id "com.googlecode.iterm2")
         (let ((cmd (focused-terminal-foreground-command)))
           (cond
             ((not cmd)                        #f)
             ((string-contains? cmd "nvim")    "/nvim")
             ((string-contains? cmd "lazygit") "/lazygit")
             (else                             #f))))))

(define-tree 'com.googlecode.iterm2/lazygit
  (key "p" "Push"  (λ () (send-keystroke '() "P")))
  (key "f" "Pull"  (λ () (send-keystroke '() "p"))))
```

The suffix itself can go deeper — ask the focused nvim a question.
For example, branch on its filetype:

```scheme
((string-contains? cmd "nvim")
 (let ((ft (nvim-remote-expr "&filetype")))
   (cond ((equal? ft "rust") "/nvim-rust")
         (else               "/nvim"))))
```

This requires the nvim-side `FocusGained`/`FocusLost` autocmds — see
[The nvim side](../reference/terminal-detection.md#the-nvim-side).

## One tree across every backend: capability predicates

The 14-op surface on `(modaliser terminal)` lets a single tree
drive any registered terminal — at call time the façade routes to
whichever backend's `register!` thunk matched the frontmost app.
But not every backend supports every op (Kitty has no zoom,
Ghostty has no `move-pane-*`, Alacritty has no splits at all),
so a static tree that hard-codes every op will surface entries
that silently no-op on backends that don't support them.

The capability predicates let the tree omit those entries
on the backends where they wouldn't work. `define-tree` is a
regular procedure, so the canonical splice idiom is `apply` +
`append` — the same pattern the bundled `(modaliser apps iterm)`
module uses for its own conditional children:

```scheme
(import (modaliser dsl)
        (prefix (modaliser terminal) terminal:))

(define (rebuild-terminal-tree!)
  (apply define-tree 'com.googlecode.iterm2
    (append
      (list
        (category "Focus"
          (key "h" "Left"  terminal:focus-pane-left)
          (key "j" "Down"  terminal:focus-pane-down)
          (key "k" "Up"    terminal:focus-pane-up)
          (key "l" "Right" terminal:focus-pane-right)))

      ;; Move-pane only when the active backend supports it.
      (if (terminal:supports-move-pane?)
          (list
            (group "m" "Move"
              'sticky #t
              'exit-on-unknown #t
              (key "h" "Left"  terminal:move-pane-left)
              (key "j" "Down"  terminal:move-pane-down)
              (key "k" "Up"    terminal:move-pane-up)
              (key "l" "Right" terminal:move-pane-right)))
          '())

      ;; Digit-jump only on backends that paint chips.
      (if (terminal:supports-digit-jump?)
          (list (key "g" "Goto pane" terminal:focus-pane-by-digit))
          '())

      ;; Zoom only on backends with a native zoom toggle.
      (if (terminal:supports-zoom?)
          (list (key "z" "Toggle Zoom" terminal:toggle-pane-zoom))
          '()))))
```

Call `rebuild-terminal-tree!` from a suffix hook (the worked
example above) so the tree shape tracks the active backend on
every leader press.

The five capability predicates are:

- `(terminal:supports-splits?)` — backend exposes `split-pane-*`
- `(terminal:supports-move-pane?)` — backend exposes `move-pane-*`
- `(terminal:supports-digit-jump?)` — backend exposes `focus-pane-by-digit`
- `(terminal:supports-zoom?)` — backend exposes `toggle-pane-zoom`
- `(terminal:supports? 'focus-pane-left)` — universal introspection by op name

They're evaluated whenever the tree is built — typically inside a
suffix hook, so the answer reflects whichever backend is frontmost
*at that moment* — and so the tree shape stays in sync with the
active backend.

## Verify it worked

1. Focus an iTerm split running nvim, tap F17: the nvim variant tree
   should appear.
2. Switch the split to a plain shell, tap F17: the plain
   `com.googlecode.iterm2` tree.

If you always get the plain tree, the hook is not installed (did you
inline the tree without calling `set-local-context-suffix!`?) or the
variant tree's scope symbol is misspelt — e.g.
`com.googlecode.iterm2/Nvim` vs `com.googlecode.iterm2/nvim`.

## Notes

**One hook total.** `set-local-context-suffix!` replaces any
previously installed hook — it is not additive. If you use both the
iTerm factory and your own hook, compose them: call
`(iterm:register! 'install-context-suffix? #f)` and have your hook
delegate the iTerm branch to
`(iterm:context-suffix-handler bundle-id)`:

```scheme
(import (prefix (modaliser apps iterm) iterm:)
        (modaliser event-dispatch))

(iterm:register! 'install-context-suffix? #f)

(set-local-context-suffix!
  (lambda (bundle-id)
    (cond
      ((equal? bundle-id "com.googlecode.iterm2")
       (iterm:context-suffix-handler bundle-id))
      ;; … handle other bundle IDs here …
      (else #f))))
```

**Save and relaunch** from the menu bar icon after any config change.
In-place reload is not supported — relaunch is the reload.

## Related

- [`../reference/terminal-detection.md`](../reference/terminal-detection.md)
  — how pane detection works, which terminals are supported, the nvim
  RPC route.
- [`add-a-per-app-tree.md`](add-a-per-app-tree.md) — registering
  per-app trees without pane-awareness.
