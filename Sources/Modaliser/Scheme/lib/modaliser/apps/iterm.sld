;; (modaliser apps iterm) — iTerm dynamic-pane builder and sticky focus mode.
;;
;; The dynamic iTerm tree is rebuilt on every leader press (via
;; set-local-context-suffix!) so pane bindings track the current pane
;; layout. Pane chips are painted while the overlay is visible; each
;; chip's digit focuses that pane by UUID (race-free, no event injection).
;;
;; Quick start (prefix-style import — recommended; bare exports like
;; `register!`, `tree`, etc. collide with peer libraries):
;;   (import (prefix (modaliser apps iterm) iterm:))
;;   (iterm:register!)
;;
;; Chip appearance (font size, colour, border, etc.) lives in the .chip
;; CSS rule in base.css / ~/.config/modaliser/theme.css — see
;; (modaliser theming). Pass overrides by editing CSS, not by threading
;; option alists through the library.
;;
;; Defaults mirror the bundled seed: digit pane labels 1..0, transient
;; tree with "c Copy Mode"; "h/j/k/l Focus <dir>" (each fires the
;; corresponding Cmd+Alt+arrow keystroke AND transitions into the
;; sticky 'iterm-panes-focus mode, so subsequent hjkl presses keep
;; moving without another leader press); "z Toggle Zoom"; and a "x
;; Split" group. The sticky 'iterm-panes-focus tree contains only the
;; Cmd+Alt+arrow hjkl focus moves.
;;
;; If you've already installed your own (set-local-context-suffix! …),
;; pass 'install-context-suffix? #f and call context-suffix-handler
;; from inside your own composed handler.
;;
;; Pane selection bridges AX → iTerm AppleScript by walk-order index:
;; AX gives us each pane's frame (chip placement) and a 0-based 'idx
;; field; AppleScript's `id of every session of current tab` returns
;; session UUIDs in the same order (iTerm's session enumeration is the
;; NSView subview-tree DFS, same as AX walks). The N-th pane corresponds
;; to the N-th UUID. We resolve at discovery time so each chip action
;; binds directly to its UUID — race-free, no event injection. UUIDs are
;; URL-safe (alphanumeric + hyphens), so inlining into AppleScript
;; source needs no escaping.

(define-library (modaliser apps iterm)
  (export rebuild-tree!
          focus-mode-tree
          focus-mode-register!
          context-suffix-handler
          register!
          default-pane-labels
          pane-list-block
          select-session-by-id)
  (import (scheme base)
          (modaliser dsl)
          (modaliser state-machine)
          (modaliser event-dispatch)
          (modaliser util)
          (modaliser shell)
          (modaliser input)
          (modaliser accessibility)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser terminal)
          (modaliser theming)
          (modaliser blocks iterm-panes))
  (begin

    (define default-pane-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; Returns a thunk that fires send-keystroke on call. The thunk
    ;; lands cleanly as the third arg of `(key K L …)`: the macro
    ;; evaluates the call eagerly, gets a procedure back, and uses it
    ;; as the action thunk.
    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    ;; Query iTerm for the UUIDs of every session in the focused window's
    ;; current tab. iTerm's `id of every session` returns "U1, U2, ..."
    ;; (one line, comma-space separated). UUIDs don't contain commas, so
    ;; the parse is safe.
    (define (iterm-list-session-ids)
      (let* ((out (run-shell
                    (string-append
                      "osascript -e 'tell application \"iTerm\" to "
                      "id of every session of current tab of current window' "
                      "2>/dev/null")))
             (trimmed (string-trim out)))
        (if (string=? trimmed "")
          '()
          (let loop ((parts (string-split trimmed ",")) (acc '()))
            (cond
              ((null? parts) (reverse acc))
              (else
                (let ((s (string-trim (car parts))))
                  (loop (cdr parts)
                        (if (string=? s "") acc (cons s acc))))))))))

    ;; UUIDs are URL-safe — inline into AppleScript source without
    ;; escaping. Only the pre-validated UUID is interpolated; no name
    ;; interpolation, no shell quoting hazards.
    (define (iterm-select-session-by-id session-id)
      (run-shell
        (string-append
          "osascript -e 'tell application \"iTerm\" to "
          "tell first session of current tab of current window "
          "whose id is \"" session-id "\" to select' "
          "2>/dev/null")))

    ;; Build a single (key-range ...) node covering every labelled pane.
    ;; Display key is "<first>.." reflecting actually-bound count (so a
    ;; 3-pane window reads "1.." rather than the full label list). If
    ;; AppleScript returns fewer UUIDs than AX found scroll areas, those
    ;; panes are dropped from the range. Returns a 0- or 1-element list
    ;; so the caller's (append (iterm-pane-bindings …) …) keeps splicing
    ;; cleanly.
    (define (iterm-pane-bindings labelled-panes session-ids range-label)
      (let loop ((ps labelled-panes) (label->sid '()) (keys '()))
        (cond
          ((null? ps)
           (cond
             ((null? keys) '())
             (else
               (let* ((alist  label->sid)
                      (ks     (reverse keys))
                      (first  (car ks))
                      (display (string-append first ".."))) ; e.g. "1.."
                 (list
                   (key-range display range-label
                     ks
                     (lambda (k)
                       (let ((entry (assoc k alist)))
                         (when entry
                           (iterm-select-session-by-id (cdr entry)))))))))))
          (else
            (let* ((entry (car ps))
                   (label (car entry))
                   (pane  (cdr entry))
                   (idx   (cdr (assoc 'idx pane)))
                   (sid   (and (< idx (length session-ids))
                               (list-ref session-ids idx))))
              (loop (cdr ps)
                    (if sid (cons (cons label sid) label->sid) label->sid)
                    (if sid (cons label keys)                  keys)))))))

    ;; Rebuild and re-register the 'com.googlecode.iterm2 tree from
    ;; the current iTerm pane layout. Cheap when iTerm isn't running
    ;; (AX returns empty, no panes contribute to the range).
    ;;
    ;; Chip styling is no longer threaded through opts. Hint chips read
    ;; their resolved appearance from (current-chip-theme), driven by
    ;; the .chip rule in base.css + ~/.config/modaliser/theme.css. The
    ;; old 'hint-options keyword raises a migration error.
    (define (rebuild-tree! . opts)
      (let ((alist (apply props->alist opts)))
        ;; Guard runs before any AX / AppleScript work so a stale config
        ;; passing the legacy keyword fails fast instead of paying the
        ;; full discovery cost first.
        (when (assoc 'hint-options alist)
          (error
            "rebuild-tree!: 'hint-options removed — edit .chip in ~/.config/modaliser/theme.css instead"))
        (let* ((labels       (alist-ref alist 'pane-labels default-pane-labels))
               (range-label  (alist-ref alist 'pane-range-label "Focus Pane <n>"))
               (sticky-id    (alist-ref alist 'sticky-mode-id 'iterm-panes-focus))
               (raw-panes    (ax-find-elements-named
                               "com.googlecode.iterm2" "AXScrollArea" "AXStaticText"))
               (panes        (label-pairs labels raw-panes))
               (session-ids  (iterm-list-session-ids)))
        (apply define-tree 'com.googlecode.iterm2
          'on-enter (lambda ()
                      (hints-show
                        (ax-target-hints panes (current-chip-theme 'normal))))
          'on-leave (lambda () (hints-hide))
          (append
            (iterm-pane-bindings panes session-ids range-label)
            (list
              (key "c" "Copy Mode" (keystroke '(cmd shift) "c"))
              (key "z" "Toggle Zoom" (keystroke '(cmd shift) "return"))
              ;; hjkl: focus-move AND transition into the sticky focus
              ;; mode in a single press. First leader → h moves left and
              ;; lands the user in 'iterm-panes-focus, so subsequent hjkl
              ;; keys keep moving without another leader. The overlay
              ;; paints a ↻ marker on each (via 'sticky-target). Grouped
              ;; into a "Focus" category so the cluster reads as one
              ;; semantic unit at the top of the overlay.
              (category "Focus"
                (key "h" "Left"  (keystroke '(cmd alt) "left")
                  'sticky-target sticky-id)
                (key "j" "Down"  (keystroke '(cmd alt) "down")
                  'sticky-target sticky-id)
                (key "k" "Up"    (keystroke '(cmd alt) "up")
                  'sticky-target sticky-id)
                (key "l" "Right" (keystroke '(cmd alt) "right")
                  'sticky-target sticky-id))
              (group "x" "Split"
                (key "h" "Left"  (keystroke '(cmd ctrl shift) "h"))
                (key "j" "Down"  (keystroke '(cmd ctrl shift) "j"))
                (key "k" "Up"    (keystroke '(cmd ctrl shift) "k"))
                (key "l" "Right" (keystroke '(cmd ctrl shift) "l")))))))))

    ;; Sticky focus-mode children. Pure hjkl focus moves, entered from
    ;; the transient tree via any of its hjkl keys (each carries a
    ;; 'sticky-target → here) or via (enter-mode! 'iterm-panes-focus).
    (define (focus-mode-tree)
      (list
        (key "h" "Left"  (keystroke '(cmd alt) "left"))
        (key "j" "Down"  (keystroke '(cmd alt) "down"))
        (key "k" "Up"    (keystroke '(cmd alt) "up"))
        (key "l" "Right" (keystroke '(cmd alt) "right"))))

    (define (focus-mode-register! . opts)
      (let* ((alist     (apply props->alist opts))
             (id        (alist-ref alist 'sticky-mode-id 'iterm-panes-focus))
             (disp-name (alist-ref alist 'display-name "Focus")))
        (apply define-tree id
          'sticky #t
          'exit-on-unknown #t
          'display-name disp-name
          (focus-mode-tree))))

    ;; Variant string for the focused iTerm pane, used by the
    ;; (modaliser event-dispatch) dispatcher to select sub-tree variants
    ;; like 'com.googlecode.iterm2/nvim. Returns #f if no variant applies.
    ;; Side-effect: rebuilds the iTerm tree so subsequent lookups see the
    ;; current pane layout.
    ;;
    ;; Accepts the same trailing opts as rebuild-tree! ('pane-labels,
    ;; 'pane-range-label, 'sticky-mode-id). They are forwarded to the
    ;; rebuild call so per-press registrations honour the user's
    ;; customisation rather than reverting to the library's neutral
    ;; defaults. register! captures opts in a closure for this reason;
    ;; users composing their own handler can pass opts at call site too.
    (define (context-suffix-handler bundle-id . opts)
      (cond
        ((equal? bundle-id "com.googlecode.iterm2")
         (apply rebuild-tree! opts)
         (let ((cmd (focused-terminal-foreground-command)))
           (cond
             ((not cmd) #f)
             ((string-contains? cmd "nvim") "/nvim")
             ((or (string-contains? cmd "zellij")
                  (string-contains? cmd "zj"))
              (if (focused-nvim-socket) "/zellij+nvim" "/zellij"))
             (else #f))))
        (else #f)))

    ;; One-stop convenience: register the dynamic iTerm tree, the sticky
    ;; focus mode, and install the context-suffix handler. Pass
    ;; 'install-context-suffix? #f if you compose your own handler — your
    ;; handler can then call (context-suffix-handler bid …opts) to
    ;; delegate the iTerm branch.
    (define (register! . opts)
      (let* ((alist (apply props->alist opts))
             (install? (alist-ref alist 'install-context-suffix? #t))
             (forwarded
               (let loop ((kvs opts) (acc '()))
                 (cond
                   ((null? kvs) (reverse acc))
                   ((null? (cdr kvs))
                    (error "register!: odd keyword/value list"))
                   ((eq? (car kvs) 'install-context-suffix?)
                    (loop (cddr kvs) acc))
                   (else
                    (loop (cddr kvs)
                          (cons (cadr kvs) (cons (car kvs) acc))))))))
        (apply rebuild-tree! forwarded)
        (apply focus-mode-register! forwarded)
        (when install?
          (set-local-context-suffix!
            (lambda (bundle-id)
              (apply context-suffix-handler bundle-id forwarded))))))

    ;; ─── Block-based pane selection ────────────────────────────────
    ;;
    ;; Companion to (modaliser blocks iterm-panes). Mirrors the
    ;; window-actions:list-block shape: wrap the block constructor,
    ;; bundle a hidden 1.. key-range so digits dispatch to the
    ;; freshly-snapshotted pane UUIDs every time the overlay renders.
    ;;
    ;; Usage from config.scm:
    ;;
    ;;   (define-tree 'com.googlecode.iterm2
    ;;     (overlay
    ;;       (key "c" "Copy Mode" …)
    ;;       …
    ;;       (iterm:pane-list-block 'chips? #t)))
    ;;
    ;; The 1.. range is marked 'hidden so the which-key strip doesn't
    ;; surface a redundant "1.. → Pane <n>" row — the pane list block
    ;; already shows the mapping.

    ;; Public passthrough so config-level code can dispatch by UUID
    ;; without reaching into library internals.
    (define (select-session-by-id session-id)
      (iterm-select-session-by-id session-id))

    (define (focus-by-digit d)
      (let ((entry (assoc d (iterm-panes-current-targets))))
        (when entry
          (iterm-select-session-by-id (cdr entry)))))

    (define (pane-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              default-pane-labels
              (lambda (k) (focus-by-digit k)))))

    (define (pane-list-block . opts)
      (let ((base (apply make-iterm-panes-block opts)))
        (append base (list (cons 'block-children
                                 (list (pane-range)))))))))

