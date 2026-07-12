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
suffix matches. You register the variant trees with `screen`.

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
  (`screen`).

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

(screen 'com.googlecode.iterm2/nvim
  (panel "nvim"
    (key "w" "Write"  (λ () (nvim-remote-send ":w<CR>")))
    (key "q" "Close"  (λ () (nvim-remote-send "<Esc>:q<CR>")))))
```

Tap F17 with nvim in the focused split — the `/nvim` tree appears.
Switch the split to a plain shell — the plain `com.googlecode.iterm2`
tree appears instead.

## If you've inlined your iTerm tree

Inlining the iTerm tree by hand — writing a
`(screen 'com.googlecode.iterm2 …)` instead of calling
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

;; Register the iTerm backend record + focus Walk + digit-pick
;; mode + suffix handler with the façade, but leave the tree to us.
(iterm:register! 'install-tree? #f)

(screen 'com.googlecode.iterm2
  (panel "Focus"
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
Add this alongside your `(screen 'com.googlecode.iterm2 …)`
(your config already imports `(modaliser dsl)` for `screen`,
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

(screen 'com.googlecode.iterm2/lazygit
  (panel "lazygit"
    (key "p" "Push"  (λ () (send-keystroke '() "P")))
    (key "f" "Pull"  (λ () (send-keystroke '() "p")))))
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

## Worked example: herdr replace/augment variant trees

[herdr](https://herdr.dev) — an "agent multiplexer" run *inside* an
iTerm split — is the first production user of variant trees, and a
complete worked example of composing the suffix hook (the
[One hook total](#notes) note below). When the focused iTerm pane
runs herdr, F17 shows one of two herdr **variant trees** instead of
the plain iTerm tree:

- **Replace** (`/herdr`) — herdr is the *sole* iTerm split in the
  current tab, so it owns the whole window: a herdr-only tree, no
  iTerm controls.
- **Augment** (`/herdr+split`) — the current tab holds *other* iTerm
  splits too, so the herdr tree gains an `i` drill for those iTerm
  splits.

herdr owns the top-level `hjkl` (pane focus) in both, so muscle
memory is identical; augment is literally the replace tree plus the
iTerm-splits drill. See
[ADR-0013](../adr/0013-herdr-replace-vs-augment-tree.md) for why the
three choices below bind the way they do.

`(herdr:build-herdr-tree)` returns the whole herdr control surface —
what the overlay shows on `/herdr`:

- **`hjkl`** — focus the pane in that direction (first press crosses
  into a focus Walk, so subsequent `hjkl` keep moving focus).
- **`x`** then `hjkl` — split a new pane that direction (left/up split
  the opposite native way then swap back).
- **`m`** then `hjkl` — Move Walk: swap the focused pane with its
  neighbour.
- **`z`** / **`d`** — toggle zoom / close the focused pane.
- **`t` Tabs**, **`w` Workspaces** — each a drill with `n`/`r`/`d`
  (new / rename / close) plus a live list whose digits switch.
- **`g` Worktrees** — `n` new (prompt a branch), `d` remove the
  focused worktree (behind a confirm), plus a live list whose digits
  *smart-switch* (focus a live workspace, or open a dormant worktree).
- **`b` Jump to Blocked** — focus the next blocked agent in one press
  (round-robin; a toast when none are blocked).
- **`a` Agents** — the agents live list, status-badged and
  blocked-first; a digit focuses that agent's pane.
- **Panes panel** — the panes live list plus digit **chips** over the
  on-screen panes (replace-mode-correct; see below).

Augment (`/herdr+split`) adds one more: an **`i`** drill for the other
iTerm splits.

```scheme
(import (modaliser dsl)
        (modaliser event-dispatch)                   ; set-local-context-suffix!
        (prefix (modaliser terminal)    terminal:)   ; in-chain?
        (prefix (modaliser apps iterm)  iterm:)
        (prefix (modaliser muxes herdr) herdr:))

;; 1. Register both backends. iterm:register! installs the iTerm
;;    backend record but NOT its tree/suffix (we compose our own);
;;    herdr:register! makes (terminal:in-chain? 'herdr) resolve when
;;    the focused iTerm split runs the herdr client.
(iterm:register! 'install-tree? #f 'install-context-suffix? #f)
(herdr:register!)

;; 2. Register the two variant screens. build-herdr-tree returns the
;;    node list; the augment screen appends the iTerm-splits drill,
;;    which binds iterm-DIRECT ops — in augment mode the (modaliser
;;    terminal) façade resolves to herdr, so its shims would drive the
;;    wrong layer.
(apply screen 'com.googlecode.iterm2/herdr (herdr:build-herdr-tree))
(apply screen 'com.googlecode.iterm2/herdr+split
  (append (herdr:build-herdr-tree)
          (list (iterm:build-iterm-splits-drill))))

;; 3. One composed suffix hook (the global slot is last-write-wins,
;;    so herdr must compose, not install a second hook). herdr focused
;;    → classify replace vs augment by the CURRENT-TAB split count; the
;;    (in-chain? 'herdr) gate short-circuits the AppleScript count query
;;    when herdr is absent. Otherwise delegate to iTerm's own
;;    nvim/zellij handler.
(set-local-context-suffix!
 (lambda (bundle-id)
   (or (and (equal? bundle-id "com.googlecode.iterm2")
            (terminal:in-chain? 'herdr)
            (herdr:classify-herdr-variant
             (length (iterm:iterm-list-session-ids))))
       (iterm:context-suffix-handler bundle-id 'rebuild? #f))))
```

`classify-herdr-variant` keys on the **current-tab** split count
(`iterm-list-session-ids` = `sessions of current tab`), *not* an
all-tabs `AXScrollArea` count — a herdr window with a second
background tab would otherwise miscount and wrongly pick augment.

**Pane chips are replace-mode-correct only.** The herdr tree's Panes
panel paints digit chips over the on-screen herdr panes; in augment
mode the host-frame heuristic can target the wrong split, so chips may
be misplaced (`hjkl` focus and digit-jump by pane id are unaffected).
See [herdr pane chips](../reference/terminal-detection.md#herdr-pane-chips-replace-mode-only).

## One tree across every backend: capability predicates

The 14-op surface on `(modaliser terminal)` lets a single tree
drive any registered terminal — at call time the façade routes to
whichever backend's `register!` thunk matched the frontmost app.
But not every backend supports every op (Kitty has no zoom,
Ghostty has no `move-pane-*`, Alacritty has no splits at all),
so a static tree that hard-codes every op will surface entries
that silently no-op on backends that don't support them.

The capability predicates let the tree omit those entries
on the backends where they wouldn't work. `screen` is a
regular procedure, so the canonical splice idiom is `apply` +
`append` — the same pattern the bundled `(modaliser apps iterm)`
module uses for its own conditional children:

```scheme
(import (modaliser dsl)
        (prefix (modaliser terminal) terminal:))

(define (rebuild-terminal-tree!)
  (apply screen 'com.googlecode.iterm2
    (append
      (list
        (panel "Focus"
          (key "h" "Left"  terminal:focus-pane-left)
          (key "j" "Down"  terminal:focus-pane-down)
          (key "k" "Up"    terminal:focus-pane-up)
          (key "l" "Right" terminal:focus-pane-right)))

      ;; Move-pane only when the active backend supports it.
      (if (terminal:supports-move-pane?)
          (list
            (group "m" "Move"
              'exit-on-unknown #t
              (key "h" "Left"  terminal:move-pane-left  'next 'self)
              (key "j" "Down"  terminal:move-pane-down  'next 'self)
              (key "k" "Up"    terminal:move-pane-up    'next 'self)
              (key "l" "Right" terminal:move-pane-right 'next 'self)))
          '())

      ;; Digit-jump only on backends that paint chips. The façade's
      ;; focus-pane-by-digit is a fire-time resolver (ADR-0015): the
      ;; action is a no-op, and 'next takes the edge to whichever
      ;; backend's digit-mode is active.
      (if (terminal:supports-digit-jump?)
          (list (key "g" "Goto pane" (lambda () (if #f #f))
                  'next terminal:focus-pane-by-digit))
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
- [ADR-0013](../adr/0013-herdr-replace-vs-augment-tree.md) — why the
  herdr replace/augment trees bind backend-direct ops and compose the
  suffix hook.
