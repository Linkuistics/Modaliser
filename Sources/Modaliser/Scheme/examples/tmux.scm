;; Modaliser example — tmux in an iTerm host.
;;
;; ⚠️ THIS FILE IS NEVER LOADED. Modaliser reads exactly one user file,
;; `~/.config/modaliser/config.scm`; everything in `examples/` is
;; reference material that arrives fresh with each installed build (via
;; the `sys/` mirror) and sits there inert. Nothing you change here has
;; any effect, and nothing here can go stale in your config.
;;
;; It exists because a fresh install seeds herdr, zellij and nvim but
;; NOT tmux — the seed can only carry one set of choices, and choices
;; are the one thing Modaliser's libraries deliberately do not make for
;; you (docs/adr/0021-decision-free-libraries.md). `(modaliser muxes
;; tmux)` ships every tmux operation as a named op; this file is one
;; readable way to bind them.
;;
;; TO USE IT, one of:
;;
;;   • Copy the four marked ▶ blocks below into your own
;;     `~/.config/modaliser/config.scm` — the import, the screen, and
;;     the two lines for the `(configuration …)` call at its bottom.
;;   • Or copy this whole file over `config.scm` as a starting point: it
;;     is a complete, working configuration in its own right (that is
;;     also how the test suite proves it still composes).
;;
;; Then relaunch Modaliser. With tmux running in an iTerm pane, F17
;; lands directly in the tmux screen; backspace steps back out to
;; iTerm's; "." steps inward.
;;
;; Host assumption: tmux paints inside ONE terminal view, so its
;; digit-jump chips derive their geometry from the focused iTerm split.
;; The ops themselves are host-independent — swap `(iterm:wiring)` for
;; `(kitty:wiring)`, `(wezterm:fragment)`, … and everything except chip
;; placement follows.

;; ▶ 1/4 — the import.
(import (modaliser dsl)
        (modaliser configuration)
        (modaliser handoff)
        (modaliser keyboard)
        (modaliser app)
        (prefix (modaliser apps iterm) iterm:)
        (prefix (modaliser muxes tmux) tmux:))

;; ▶ 2/4 — the tmux screen. Every `tmux:`-prefixed name is one of the
;; fourteen ops exported by (modaliser muxes tmux), each a tmux CLI
;; invocation; the keys, labels and grouping are preference, so rebind,
;; drop or regroup any of it.
;;
;; THE SCOPE SYMBOL 'tmux IS MACHINERY, not preference: (tmux:wiring)'s
;; context entry resolves to it, so renaming it fails reference-closure
;; validation at load rather than silently unbinding the screen.
;;
;; Digit jump needs no binding — tmux's backend record names its own
;; 'tmux-pane-digit tree, and the host's pane-list block fires it.
(define tmux-screen
  (screen 'tmux
    'display-name "tmux"

    ;; hjkl focus, each re-arming in place ('next 'self), so one leader
    ;; press starts a run of moves.
    (panel "Focus"
      (key "h" "Focus Left"  tmux:focus-pane-left  'next 'self)
      (key "j" "Focus Down"  tmux:focus-pane-down  'next 'self)
      (key "k" "Focus Up"    tmux:focus-pane-up    'next 'self)
      (key "l" "Focus Right" tmux:focus-pane-right 'next 'self))

    ;; Splits fire and exit — you almost never want two in a row.
    (group "n" "New Split"
      (key "h" "Split Left"  tmux:split-pane-left)
      (key "j" "Split Down"  tmux:split-pane-down)
      (key "k" "Split Up"    tmux:split-pane-up)
      (key "l" "Split Right" tmux:split-pane-right))

    ;; Move swaps the focused pane with its neighbour, so it latches like
    ;; Focus; 'exit-on-unknown means a stray key leaves rather than traps.
    ;; tmux's `{left-of}` selectors no-op at the edge of the layout.
    (group "m" "Move Pane"
      'exit-on-unknown #t
      (key "h" "Left"  tmux:move-pane-left  'next 'self)
      (key "j" "Down"  tmux:move-pane-down  'next 'self)
      (key "k" "Up"    tmux:move-pane-up    'next 'self)
      (key "l" "Right" tmux:move-pane-right 'next 'self))

    (key "z" "Toggle Zoom" tmux:toggle-pane-zoom)))

;; ─── The rest is a minimal host config, so this file stands alone ──

;; iTerm's own screen, kept small on purpose: with tmux inside, tmux owns
;; the panes and iTerm mostly holds the window. The scope symbol
;; 'com.googlecode.iterm2 is the backend record's match-key — it is what
;; makes this screen terminal-like, and therefore what makes it consult
;; the context map and find tmux.
(define iterm-screen
  (screen 'com.googlecode.iterm2
    (key "c" "Copy Mode"   iterm:copy-mode)
    (key "z" "Toggle Zoom" iterm:toggle-pane-zoom)
    (key "C-I" "Configure iTerm" iterm:configure! 'hidden iterm:configured?)
    (panel "Panes" (iterm:pane-list-block 'chips? #t))))

(define global-screen
  (screen 'global
    (panel "Applications"
      (key "t" "Terminal" (λ () (launch-app "iTerm"))))))

(modaliser:start!
  (configuration
    (leaders
      (leader 'global F18)
      (leader 'local  F17))
    (overlay-delay 0.3)
    global-screen

    ;; iTerm's integration: the backend record and its digit-jump tree.
    (iterm:wiring)

    ;; ▶ 3/4 — the Terminal context map entry. Add (tmux:wiring) to the
    ;; (terminal-contexts …) call you already have.
    (terminal-contexts
      (tmux:wiring))       ; backend + map entry; the screen is above

    iterm-screen

    ;; ▶ 4/4 — the screen itself, composed into the configuration value.
    tmux-screen))
