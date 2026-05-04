;; lib/iterm.scm — Dynamic iTerm tree generation + pane-hint overlays
;;
;; iTerm panes don't survive between leader presses (user splits, closes,
;; resizes), so the local F17 tree must be rebuilt each time we show it.
;; We do this from local-context-suffix, which the dispatcher already calls
;; on every leader press: side-effect there to re-register the tree, then
;; return the suffix for variant lookup as before.
;;
;; Pane addressing: AX walks iTerm's window subtree and returns one
;; AXScrollArea per pane in reading order (top-to-bottom, left-to-right).
;; Each pane gets a home-row label; the user types the label to focus that
;; pane via AX kAXFocusedAttribute. No keystroke synthesis, no Python bridge
;; involvement — works whether or not iTerm has its own pane-by-number
;; bindings configured.
;;
;; Visual hints: when the user enters the "Pane" group, hints-show paints
;; one transparent NSPanel over each pane displaying its label, big and red.
;; on-leave (or modal-exit) closes them. The hint set is shadowed by the
;; modal overlay panel itself when the pane the overlay covers is the panel's
;; own pane — that's expected and harmless; the user can still pick by typing.

;; Default home-row label sequence. Override at the call site by passing a
;; different list to (build-iterm-tree!). Kept short and unambiguous: no
;; "h"/"j"/"k"/"l" because those are used for directional navigation
;; elsewhere in the iTerm tree, and labels need to be unique within "Pane".
(define iterm-default-pane-labels
  (list "a" "s" "d" "f" "g" ";" "q" "w" "e" "r" "t" "y" "u" "i" "o" "p"))

;; Cached pane data captured at modal-enter time. The hints overlay reads
;; this when on-enter fires; without caching we'd query AX twice per leader
;; press (once for tree build, once for hints) — both AX walks return the
;; same data for the same instant in time, but the cache keeps semantics
;; clear: the labels you see match the keys you can press.
(define iterm-current-panes '())  ;; list of (label . pane-alist)

;; Probe iTerm panes via the (modaliser accessibility) library.
;; Returns a list of alists ((handle . N) (x . N) (y . N) (w . N) (h . N))
;; in reading order, or '() when iTerm has no focused window.
;;
;; iTerm-specific knowledge: each pane is an AXScrollArea inside the
;; window's AXSplitGroup tree. Other terminals (Terminal.app, kitty, etc.)
;; share this shape, but the role choice belongs here, not in the generic
;; AX library.
(define (iterm-pane-frames)
  (ax-find-elements "com.googlecode.iterm2" "AXScrollArea"))

;; Pair labels with frames. If there are more panes than labels, extra panes
;; get no label (and so no binding) — better than wrapping around silently
;; and producing duplicate keys in the tree.
(define (label-panes labels panes)
  (let loop ((ls labels) (ps panes) (acc '()))
    (cond
      ((or (null? ls) (null? ps)) (reverse acc))
      (else (loop (cdr ls) (cdr ps)
                  (cons (cons (car ls) (car ps)) acc))))))

;; Build the children of the "Pane" group from the current pane set.
;; Each child binds a label to (ax-focus-handle handle).
(define (iterm-pane-bindings labelled-panes)
  (let loop ((ps labelled-panes) (acc '()))
    (if (null? ps)
      (reverse acc)
      (let* ((entry (car ps))
             (label (car entry))
             (pane  (cdr entry))
             (handle (cdr (assoc 'handle pane)))
             (display-label (string-append "Pane " label)))
        (loop (cdr ps)
              (cons (key label display-label
                         (lambda () (ax-click-handle handle)))
                    acc))))))

;; ─── Hint appearance config ───────────────────────────────────────
;;
;; Override any of these in your config.scm before the first leader press.
;; Positioning is fractional (0.0 = pane edge, 1.0 = far edge) so hints
;; track pane size; padding/font/corner are pixel values.
;;
;;   offset-x-frac, offset-y-frac
;;     Top-left corner of the hint chip, as a fraction of pane width/height.
;;     Default 0.02 / 0.02 — about 2% in from the pane's top-left.
;;   font-size, padding, corner-radius
;;     Pixels.
;;   color, background
;;     CSS hex strings. background is a SOLID colour — there's no opacity
;;     ramp here because the chip is meant to be readable on any pane.

(define iterm-pane-hint-options
  (list (cons 'offset-x-frac 0.02)
        (cons 'offset-y-frac 0.02)
        (cons 'font-size 56)
        (cons 'padding 16)
        (cons 'corner-radius 8)
        (cons 'color "#cc0000")
        (cons 'background "#ffffff")
        (cons 'border-width 1)
        (cons 'border-color "#cc0000")))

(define (iterm-hint-opt key default)
  (let ((p (assoc key iterm-pane-hint-options)))
    (if p (cdr p) default)))

;; Build the hints-show input list from the labelled pane set, applying the
;; current iterm-pane-hint-options. Each chip's bounding box is sized to
;; (font-size + 2*padding) — square — and positioned at the configured
;; fractional offset from the pane's top-left corner.
(define (iterm-pane-hint-list labelled-panes)
  (let* ((offx-frac (iterm-hint-opt 'offset-x-frac 0.02))
         (offy-frac (iterm-hint-opt 'offset-y-frac 0.02))
         (font-size (iterm-hint-opt 'font-size 14))
         (padding   (iterm-hint-opt 'padding 4))
         (corner    (iterm-hint-opt 'corner-radius 4))
         (color     (iterm-hint-opt 'color "#000000"))
         (background (iterm-hint-opt 'background "#ffffff"))
         (border-width (iterm-hint-opt 'border-width 0))
         (border-color (iterm-hint-opt 'border-color color))
         (chip-size (+ font-size (* 2 padding))))
    (let loop ((ps labelled-panes) (acc '()))
      (if (null? ps)
        (reverse acc)
        (let* ((entry (car ps))
               (label (car entry))
               (pane  (cdr entry))
               (px (cdr (assoc 'x pane)))
               (py (cdr (assoc 'y pane)))
               (pw (cdr (assoc 'w pane)))
               (ph (cdr (assoc 'h pane)))
               (hx (+ px (exact (round (* pw offx-frac)))))
               (hy (+ py (exact (round (* ph offy-frac))))))
          (loop (cdr ps)
                (cons (list (cons 'label label)
                            (cons 'x hx) (cons 'y hy)
                            (cons 'w chip-size) (cons 'h chip-size)
                            (cons 'color color)
                            (cons 'background background)
                            (cons 'font-size font-size)
                            (cons 'padding padding)
                            (cons 'corner-radius corner)
                            (cons 'border-width border-width)
                            (cons 'border-color border-color))
                      acc)))))))

;; on-enter / on-leave thunks for the Pane group.
;; They read iterm-current-panes, captured at tree-rebuild time, so that
;; the keys shown in the modal overlay match the labels painted on the panes.
(define (iterm-show-pane-hints)
  (hints-show (iterm-pane-hint-list iterm-current-panes)))

(define (iterm-hide-pane-hints)
  (hints-hide))

;; Re-register the iTerm tree based on the current pane layout.
;; Called from local-context-suffix on every leader press, so the tree is
;; always fresh. Cheap: a few AX calls plus a hashtable write.
;;
;; Top-level keys (no "Pane" subgroup — bindings hang directly off the
;; iTerm tree root so the hint→pick path is one keystroke):
;;   home-row labels (a/s/d/f/...)  → click the labelled pane
;;   h/j/k/l                        → directional focus (Cmd+Opt+Arrow)
;;   c                              → Select (Copy Mode)   (was "s")
;;   z                              → Toggle Zoom
;;   x                              → Split subgroup
;;
;; Labels deliberately exclude h/j/k/l so directional focus stays addressable
;; alongside hint-based selection without alpha collisions. "c" replaced "s"
;; for copy mode because "s" is now claimed as a hint label.
;;
;; Hint visibility is wired to the tree-root's on-enter/on-leave so chips
;; appear immediately on F17 and disappear when the modal exits or descends
;; into a subgroup (Split).
(define (rebuild-iterm-tree!)
  (let* ((panes (iterm-pane-frames))
         (labelled (label-panes iterm-default-pane-labels panes)))
    (set! iterm-current-panes labelled)
    (apply define-tree 'com.googlecode.iterm2
      'on-enter iterm-show-pane-hints
      'on-leave iterm-hide-pane-hints
      (append
        (iterm-pane-bindings labelled)
        (list
          (key "c" "Select (Copy Mode)" (keystroke '(cmd shift) "c"))
          (key "h" "Focus Left"  (keystroke '(cmd alt) "left"))
          (key "j" "Focus Down"  (keystroke '(cmd alt) "down"))
          (key "k" "Focus Up"    (keystroke '(cmd alt) "up"))
          (key "l" "Focus Right" (keystroke '(cmd alt) "right"))
          (key "z" "Toggle Zoom" (keystroke '(cmd shift) "return"))
          (group "x" "Split"
            (key "h" "Split Left"  (keystroke '(cmd ctrl shift) "h"))
            (key "j" "Split Down"  (keystroke '(cmd ctrl shift) "j"))
            (key "k" "Split Up"    (keystroke '(cmd ctrl shift) "k"))
            (key "l" "Split Right" (keystroke '(cmd ctrl shift) "l"))))))))
