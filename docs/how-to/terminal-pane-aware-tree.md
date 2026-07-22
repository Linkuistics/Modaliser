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

## Worked example: the herdr nested entry point

[herdr](https://herdr.dev) — an "agent multiplexer" run *inside* an
iTerm split — is a worked example of a **different** mechanism from
everything above: a **nested entry point** (ADR-0013), not a
context-suffix variant tree. The two don't compose the same way, so
read this section on its own terms:

- A **context-suffix tree** (`/nvim` above) is resolved by
  `resolve-app-tree` trying a suffixed scope before falling back to
  the plain one — the suffix hook decides, every leader press.
- A **nested entry point** is a second, independent activation target
  in the FSM's entry table (CONTEXT.md "Entry table" / "Entry point"):
  leader activation picks whichever passing entry is most specific,
  and specificity here comes from a real graph edge — the nested
  node's **up edge** into its container — not a suffix string.

When the focused iTerm pane runs herdr, F17 activates the **herdr
entry node** directly instead of the plain iTerm tree; backspace from
it walks back to the iTerm node over that same up edge, so the full
iTerm splits/panes/tabs surface is always one keystroke away — there
is no second "augment" tree duplicating it. See
[ADR-0013](../adr/0013-nested-context-entry-points.md) for the full
rationale.

`(herdr:build-herdr-tree)` returns the whole herdr control surface —
what the overlay shows at the herdr entry node. Its top level follows
the **plane rule** (`docs/specs/herdr-jump-navigation.md`): capitals
name the drills/Quit, and `b` is the one lowercase key kept at this
level — it is a jump (Jump to Blocked), not a drill. Every other
lowercase letter belongs to the **jump space** — see below the drill
list for how it dispatches and paints chips.

- **`P` Panes** — the entire pane surface, drilled:
  - **`hjkl`** — focus the pane in that direction (first press crosses
    into a focus Walk, so subsequent `hjkl` keep moving focus; `[`/`]`
    cycling below also works mid-walk).
  - **`n`** then `hjkl` — split a new pane that direction (left/up
    split the opposite native way then swap back).
  - **`m`** then `hjkl` — Move Walk: swap the focused pane with its
    neighbour.
  - **`[`** / **`]`** — Prev/Next: cycle focus through the displayed
    (tab-scoped) panes, wrapping at both ends.
  - **`z`** / **`d`** — toggle zoom / close the focused pane.
  - **Panes panel** — the panes live list plus digit **chips** over
    the on-screen panes (correct when herdr is the sole current-tab
    split; see below).
- **`T` Tabs**, **`S` Spaces** — each a drill with `n`/`r`/`d`
  (new / rename / close), `[`/`]` Prev/Next cycling (tabs are
  workspace-scoped; spaces are global), plus a live list whose
  digits switch. "Spaces" is the user-facing label everywhere
  (matching herdr's own UI term); the code identifiers underneath
  keep herdr's `workspace` stem.
- **`W` Worktrees** — `n` new (prompt a branch), `d` remove the
  focused worktree (behind a confirm), plus a live list whose digits
  *smart-switch* (focus a live workspace, or open a dormant worktree).
  No `[`/`]` — cycling covers four groups, not five.
- **`b` Jump to Blocked** — focus the next blocked agent in one press
  (round-robin; a toast when none are blocked).
- **`A` Agents** — `[`/`]` Prev/Next cycling over the displayed
  (status-banded) order, plus the agents live list, status-badged and
  blocked-first; a digit focuses that agent's pane.
- **`Q` Quit** — `d` Detach (ends the herdr *client* only, emitted as
  herdr's own `prefix+q` keystroke — `ctrl+b` then `q`) or `s` Stop
  Server (ends the herdr *server*, behind a confirm dialog since
  herdr's CLI stops it immediately with no confirm of its own). See
  CONTEXT.md's Detach/Stop glossary entries for the distinction.

**The jump space (every other lowercase letter).** Typing a target's
assigned label focuses it directly, no drill in between
(`docs/specs/herdr-jump-navigation.md`). Targets are gathered fresh on
every visit — a `'provider` on the herdr entry node's own state,
`herdr-jump-provider` — across four axes in stable-axis order (spaces →
agents → tabs → panes), visual order within an axis. Two visible targets
naming the same destination (an agent whose pane is already on-screen)
each keep their own independent label rather than collapsing to one — a
stable target set keeps label assignment stable too
(`include-focused-targets-for-stability-k39`). Each axis assigns labels
from its OWN reserved letter pool — panes `h j k l ;`, spaces `a s d f
g`, agents then tabs sharing the top row (agents first, so agent churn
only ever shifts tab labels) — escalating to two-key labels, led by the
axis's own letters, only once that axis's pool is exhausted (the general
`jump-labels-assign` utility, `(modaliser jump-labels)`, called once per
axis).

- **Full-size letter chips** paint over the current tab's on-screen
  panes the instant the herdr entry node is reached — an unconditional
  `'entry`/`'exit` pair (`paint-jump-chips!`/`clear-jump-chips!`, [state-
  machine.md](../reference/state-machine.md#unconditional-hooks-entry--exit))
  reusing the same chip pipeline the `P` drill's digit chips use (see the
  split-tab caveat below). `'entry`/`'exit` fire regardless of
  `modal-overlay-delay` — chips never wait out the which-key overlay's
  no-flash delay the way a gated `'on-enter`/`'on-leave` pair would.
- **Typing a two-key label's first (leader) key narrows**: the modal
  moves to a resting prefix state whose only live edges are that
  leader's second keys plus backspace (un-narrows back to the top
  level) and Escape (clears and exits, as usual). The design's
  vimium-style chip *dimming* during narrowing
  (`docs/specs/herdr-jump-navigation.md` "Narrowing", CONTEXT.md
  "Narrowing") isn't painted yet — chips stay full-brightness through a
  narrowing; that visual lands with the mini-chips work.
- **A jump firing is Terminal** — focus moves and the modal exits
  immediately, exactly like `b` Jump to Blocked.
- **Only the Panes axis has a visible chip today.** The Spaces/Agents/
  Tabs axes are already gathered, labelled, and dispatch correctly if
  you know their assigned key, but nothing paints a chip over the
  sidebar/tab-bar entries until the mini-chips work lands.

```scheme
(import (modaliser dsl)
        (modaliser state-machine)                     ; register-tree-up-edge!,
                                                        ; register-tree-entry-gated!
        (modaliser event-dispatch)                    ; set-local-context-suffix!
        (prefix (modaliser terminal)    terminal:)    ; in-chain?
        (prefix (modaliser apps iterm)  iterm:)
        (prefix (modaliser muxes herdr) herdr:))

;; 1. Register both backends. iterm:register! installs the iTerm
;;    backend record but NOT its tree/suffix (we compose our own);
;;    herdr:register! makes (terminal:in-chain? 'herdr) resolve when
;;    the focused iTerm split runs the herdr client.
(iterm:register! 'install-tree? #f 'install-context-suffix? #f)
(herdr:register!)

(define (herdr-detected?) (terminal:in-chain? 'herdr))

;; 2. The plain iTerm screen (elsewhere in your config, e.g. the
;;    "If you've inlined your iTerm tree" section above) and the herdr
;;    screen. 'auto-entry #f suppresses the automatic bundle-id/suffix
;;    entry row — this scope contains "/", which would otherwise be
;;    treated as a suffix variant of "com.googlecode.iterm2" gated on the
;;    suffix hook; the two calls below register the real thing.
;;    'provider wires the jump space's per-visit FSM edges (dynamic
;;    lowercase key edges + narrowing prefix states, gathered fresh on
;;    every visit); 'entry/'exit paint and clear the jump-letter chips
;;    over the on-screen panes, unconditionally — not gated behind
;;    modal-overlay-delay the way 'on-enter/'on-leave would be.
(apply screen 'com.googlecode.iterm2/herdr 'auto-entry #f
  'provider herdr:herdr-jump-provider
  'entry herdr:paint-jump-chips!
  'exit herdr:clear-jump-chips!
  (herdr:build-herdr-tree))

;; 3. The outward up edge (backspace: herdr entry node -> iTerm node)
;;    and the entry point's own gate. fsm-entry-more-specific?'s
;;    up-edge-containment check is what then ranks this entry above the
;;    plain iTerm one whenever both pass — no suffix/'refines needed.
(register-tree-up-edge! 'com.googlecode.iterm2/herdr 'com.googlecode.iterm2)
(register-tree-entry-gated! 'com.googlecode.iterm2/herdr herdr-detected?)

;; 4. Step in from the plain iTerm tree with "." while herdr is running
;;    (add this key inside your (screen 'com.googlecode.iterm2 …)):
;;      (step-in "." "Herdr" 'com.googlecode.iterm2/herdr herdr-detected?)

;; 5. The composed suffix hook — herdr no longer routes through it, so
;;    this is just iTerm's own nvim/zellij delegation (the [One hook
;;    total](#notes) note still applies if you add more branches).
(set-local-context-suffix!
 (lambda (bundle-id)
   (iterm:context-suffix-handler bundle-id 'rebuild? #f)))
```

**Pane chips are correct only when herdr is the sole current-tab
split.** The herdr tree's Panes panel paints digit chips over the
on-screen herdr panes, and the top-level jump space's letter chips
reuse that exact same pipeline; when the iTerm tab holds other splits
too, the host-frame heuristic can target the wrong one, so either kind
of chip may be misplaced (`hjkl` focus, digit-jump, and jump-letter
dispatch by id are all unaffected) — a plain pane-chip-pipeline
geometry concern now, not a tree-model one.
See [herdr pane chips](../reference/terminal-detection.md#herdr-pane-chips).

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
- [ADR-0013](../adr/0013-nested-context-entry-points.md) — why the
  herdr entry node binds backend-direct ops and activates via an
  outward up edge rather than a merged variant tree.
