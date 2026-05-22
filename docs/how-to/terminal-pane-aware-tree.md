# How to vary the terminal tree by what's in the focused pane

You want F17 (the local leader) to show different bindings depending
on what is running in the focused iTerm split — e.g. an nvim-specific
tree when nvim is focused, a git tree when lazygit is focused. The
dispatcher already supports this through a *context suffix*; this guide
wires it up.

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

- iTerm2 as your terminal. The suffix hook itself is generic, but
  the built-in detection primitive (`focused-terminal-foreground-command`)
  is iTerm2-only today; for other terminals you supply the detection
  yourself — see the recipes in
  [terminal-detection.md](../reference/terminal-detection.md).
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
`(iterm:register!)` — keeps your bindings but **drops the suffix-hook
install**. Pane detection silently does nothing; you always get the
plain tree.

Two ways back:

**(a) Install your own hook** with `set-local-context-suffix!` (the
next section). Best if you want to keep managing the tree by hand — you
have already chosen to own it.

**(b) Revert to `(iterm:register!)`** and add your customisations
through its `'extra-bindings` option instead of inlining.

Recommendation: choose (a). The inlined tree reflects a deliberate
choice to own the bindings; the next section shows exactly what to add.

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
