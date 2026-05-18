;; (modaliser window-actions) — window-management binding builder.
;;
;; Builds the Windows group as a diagrammatic panel: each direction key
;; sits at the screen region it targets (declared via a matrix of key
;; strings), plus Center (inward arrows) and Maximise (filled), plus
;; text entries for the Named selector (n), numbered window picker
;; (1..), and Restore (r).
;;
;; Compose with other groups in your config:
;;
;;   (import (modaliser dsl) (prefix (modaliser window-actions) window:))
;;   (define-tree 'global
;;     (window:actions)
;;     (key "i" "iTerm" (lambda () (launch-app "iTerm"))))
;;
;; Override the default layout by passing your own panels:
;;
;;   (window:actions
;;     'panels (list (window:divisions '(("h" "l")))      ; halves
;;                   (window:divisions '(("a" "s" "d" "f"))))) ; quarters

(define-library (modaliser window-actions)
  (export actions
          register!
          divisions
          center-panel)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser window)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser diagram-panel))
  (begin

    ;; JS-friendly key conversion for grid cells: parse-matrix returns
    ;; col-span / row-span (Scheme/kebab) but diagram-panel.js reads
    ;; colSpan / rowSpan (JS/camel). Convert before emitting so the
    ;; renderer sees the expected payload shape.
    (define (js-cell cell)
      (list (cons 'key      (cdr (assoc 'key cell)))
            (cons 'col      (cdr (assoc 'col cell)))
            (cons 'row      (cdr (assoc 'row cell)))
            (cons 'colSpan  (cdr (assoc 'col-span cell)))
            (cons 'rowSpan  (cdr (assoc 'row-span cell)))))

    ;; (divisions matrix) → (panel-spec key-node-list)
    ;; Parse the matrix, compute (move-window x y w h) for each unique
    ;; key from its bounding box, and produce both the grid panel-spec
    ;; (for the diagram renderer) and the list of key nodes (for the
    ;; group's children).
    (define (divisions matrix)
      (let* ((rows (length matrix))
             (cols (length (car matrix)))
             (cells (parse-matrix matrix))
             (spec (make-grid-panel-spec cols rows (map js-cell cells)))
             (keys (map (lambda (cell)
                          (let* ((k (cdr (assoc 'key cell)))
                                 (c (cdr (assoc 'col cell)))
                                 (r (cdr (assoc 'row cell)))
                                 (cs (cdr (assoc 'col-span cell)))
                                 (rs (cdr (assoc 'row-span cell)))
                                 (x  (/ (- c 1) cols))
                                 (y  (/ (- r 1) rows))
                                 (w  (/ cs cols))
                                 (h  (/ rs rows)))
                            (key k k
                              (lambda () (move-window x y w h)))))
                        cells)))
        (list spec keys)))

    ;; (center-panel key) → (panel-spec key-node-list-of-one)
    ;; Distinct from divisions because center-window doesn't fit a grid.
    (define (center-panel k)
      (list (make-center-panel-spec k)
            (list (key k "Center" (lambda () (center-window))))))

    ;; Helpers to unpack the (panel-spec keys) pair.
    (define (panel-spec-of p) (car p))
    (define (panel-keys-of p) (cadr p))

    ;; Default panel layout matching the v19 mockup:
    ;;   Row 1: full thirds (d/f/g), half thirds (D/F/G over C/V/B),
    ;;          two-thirds spans (e and t — two separate panels).
    ;;   Row 2: maximise fill (m), center (c), text-entries (n/1../r).
    (define (default-panels)
      (list
        (divisions '(("d" "f" "g")))                ; full thirds
        (divisions '(("D" "F" "G")
                     ("C" "V" "B")))                ; half thirds
        (divisions '(("e" "e" #f)))                 ; first two-thirds
        (divisions '((#f "t" "t")))                 ; last two-thirds
        (divisions '(("m")))                        ; maximise (single cell)
        (center-panel "c")))                        ; center

    ;; Per-launch state: ((label . window-alist) ...) — set by
    ;; paint-window-chips! on every leader press, read by focus-by-digit
    ;; so the same digit press resolves to whichever window had that
    ;; label at paint time.
    (define current-window-targets '())

    (define default-window-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; iTerm-style ratio-based chip placement (chip top-left sits at a
    ;; fractional inset from each window's top-left corner) plus app-name
    ;; label so the user can disambiguate occluded windows. Chip width
    ;; scales with label length; height stays at font + 2×padding.
    (define default-window-chip-options
      (list (cons 'offset-x-frac 0.05)
            (cons 'offset-y-frac 0.05)
            (cons 'font-size 20)
            (cons 'padding 8)
            (cons 'corner-radius 6)
            (cons 'color "white")
            (cons 'background "dodgerblue")
            (cons 'border-width 1)
            (cons 'border-color "black")
            ;; App-name truncation budget. macOS app names are usually
            ;; short ("Safari", "Mail") but a few are long ("Microsoft
            ;; Excel"); cap so chips don't blow past their window's width.
            (cons 'app-name-max-chars 16)))

    ;; (truncate-with-ellipsis s n) → string of length ≤ n
    ;; Trims to n-1 chars + … when over budget. The ellipsis is one
    ;; character wide visually so the total reads as n chars.
    (define (truncate-with-ellipsis s n)
      (if (> (string-length s) n)
        (string-append (substring s 0 (- n 1)) "\x2026;")
        s))

    ;; (window-chip-for label window opts) → chip alist for hints-show
    ;; Places the chip at the ratio-based offset inside the window and
    ;; sizes its width from the label length (chip-w = font * ~0.62 per
    ;; char + 2*padding). Matches the iTerm pattern's offset semantics
    ;; without forcing a square chip (windows need wider chips so the
    ;; app name fits).
    (define (window-chip-for label win opts)
      (let* ((wx (cdr (assoc 'x win)))
             (wy (cdr (assoc 'y win)))
             (ww (cdr (assoc 'w win)))
             (wh (cdr (assoc 'h win)))
             (font-size (cdr (assoc 'font-size opts)))
             (padding (cdr (assoc 'padding opts)))
             (offx (cdr (assoc 'offset-x-frac opts)))
             (offy (cdr (assoc 'offset-y-frac opts)))
             (chip-x (+ wx (exact (round (* ww offx)))))
             (chip-y (+ wy (exact (round (* wh offy)))))
             (label-chars (string-length label))
             ;; 0.62 ≈ average char-width / point-size for the system
             ;; semibold sans face. Slightly generous so the label has
             ;; breathing room before the right edge.
             (chip-w (+ (exact (round (* font-size 0.62 label-chars)))
                        (* 2 padding)))
             (chip-h (+ font-size (* 2 padding))))
        (list (cons 'label label)
              (cons 'x chip-x) (cons 'y chip-y)
              (cons 'w chip-w) (cons 'h chip-h)
              (cons 'font-size font-size)
              (cons 'padding padding)
              (cons 'corner-radius (cdr (assoc 'corner-radius opts)))
              (cons 'color (cdr (assoc 'color opts)))
              (cons 'background (cdr (assoc 'background opts)))
              (cons 'border-width (cdr (assoc 'border-width opts)))
              (cons 'border-color (cdr (assoc 'border-color opts))))))

    ;; ─── Chip overlap resolution ─────────────────────────────────
    ;;
    ;; Windows can stack at similar screen positions (z-stacked, occluded);
    ;; chips painted at each window's natural ratio offset would then
    ;; overlap and become unreadable. Resolve by processing in input order
    ;; (most-recent-focused first via list-current-space-windows's sort) —
    ;; the focused window keeps its natural chip position, occluded chips
    ;; migrate to free space (below the conflict by default, right of it
    ;; if that runs off the bottom). When neither direction has room, the
    ;; chip accepts the overlap rather than going offscreen.
    ;;
    ;; Uses primary-screen-size as the clamp boundary — matches the
    ;; existing AX-to-Cocoa flip in HintsLibrary which also assumes the
    ;; primary screen. Multi-display setups inherit that limitation.

    (define chip-overlap-gap 4)
    (define chip-resolve-max-attempts 64)

    (define (chips-overlap? a b)
      (let ((ax (cdr (assoc 'x a))) (ay (cdr (assoc 'y a)))
            (aw (cdr (assoc 'w a))) (ah (cdr (assoc 'h a)))
            (bx (cdr (assoc 'x b))) (by (cdr (assoc 'y b)))
            (bw (cdr (assoc 'w b))) (bh (cdr (assoc 'h b))))
        (and (< ax (+ bx bw))
             (< bx (+ ax aw))
             (< ay (+ by bh))
             (< by (+ ay ah)))))

    (define (chip-with-position c nx ny)
      (map (lambda (entry)
             (cond
               ((eq? (car entry) 'x) (cons 'x nx))
               ((eq? (car entry) 'y) (cons 'y ny))
               (else entry)))
           c))

    (define (clamp-chip-to-screen c sw sh)
      (let* ((cx (cdr (assoc 'x c)))
             (cy (cdr (assoc 'y c)))
             (cw (cdr (assoc 'w c)))
             (ch (cdr (assoc 'h c)))
             (nx (max 0 (min cx (- sw cw))))
             (ny (max 0 (min cy (- sh ch)))))
        (chip-with-position c nx ny)))

    (define (find-overlapping placed c)
      (cond
        ((null? placed) #f)
        ((chips-overlap? c (car placed)) (car placed))
        (else (find-overlapping (cdr placed) c))))

    ;; (resolve-chip-overlaps chips sw sh) → adjusted chips
    ;; Iteratively shifts each chip past any conflict (down first, then
    ;; right if the down move would leave the screen). Stops at
    ;; chip-resolve-max-attempts per chip — pathological clusters degrade
    ;; gracefully to "accept the last position" rather than infinite-loop.
    (define (resolve-chip-overlaps chips sw sh)
      (let outer ((rest chips) (placed '()))
        (cond
          ((null? rest) (reverse placed))
          (else
            (let* ((c0 (clamp-chip-to-screen (car rest) sw sh))
                   (natural-y (cdr (assoc 'y c0))))
              (let inner ((c c0) (attempts 0))
                (cond
                  ((>= attempts chip-resolve-max-attempts)
                   (outer (cdr rest) (cons c placed)))
                  (else
                    (let ((conflict (find-overlapping placed c)))
                      (cond
                        ((not conflict)
                         (outer (cdr rest) (cons c placed)))
                        (else
                          (let* ((cw (cdr (assoc 'w c)))
                                 (ch (cdr (assoc 'h c)))
                                 (cx (cdr (assoc 'x c)))
                                 (cf-x (cdr (assoc 'x conflict)))
                                 (cf-y (cdr (assoc 'y conflict)))
                                 (cf-w (cdr (assoc 'w conflict)))
                                 (cf-h (cdr (assoc 'h conflict)))
                                 (try-y (+ cf-y cf-h chip-overlap-gap))
                                 (try-x-right (+ cf-x cf-w chip-overlap-gap))
                                 (new-c
                                   (cond
                                     ;; Prefer moving below the conflict.
                                     ((<= (+ try-y ch) sh)
                                      (chip-with-position c cx try-y))
                                     ;; Off the bottom — try right of conflict
                                     ;; at the chip's natural Y.
                                     ((<= (+ try-x-right cw) sw)
                                      (chip-with-position c try-x-right natural-y))
                                     ;; No room either way — keep current
                                     ;; position and let the loop exit on
                                     ;; the attempt count.
                                     (else c))))
                            (inner new-c (+ attempts 1))))))))))))))

    ;; (paint-window-chips!) → ()
    ;; Paint a "<digit> <App>" chip on each visible window. App name lets
    ;; the user pick the right window when several are occluded — digit
    ;; alone isn't enough when windows hide behind each other. Chips that
    ;; would overlap are pushed to clear space via resolve-chip-overlaps
    ;; so every label stays readable. label-pairs trims to min(labels,
    ;; windows) so a single-window space gets only "1", a two-window
    ;; space "1" and "2", etc.
    (define (paint-window-chips!)
      (let* ((ws (list-current-space-windows))
             (labelled (label-pairs default-window-labels ws))
             (max-app-chars (cdr (assoc 'app-name-max-chars
                                        default-window-chip-options)))
             (raw-chips
               (map (lambda (lw)
                      (let* ((digit (car lw))
                             (win (cdr lw))
                             (app-raw (cdr (assoc 'subText win)))
                             (app (truncate-with-ellipsis app-raw max-app-chars))
                             (label (string-append digit " " app)))
                        (window-chip-for label win default-window-chip-options)))
                    labelled))
             (screen (primary-screen-size))
             (chips (resolve-chip-overlaps raw-chips
                                            (cdr (assoc 'w screen))
                                            (cdr (assoc 'h screen)))))
        (set! current-window-targets labelled)
        (hints-show chips)))

    (define (hide-window-chips!)
      (hints-hide))

    ;; (focus-by-digit digit-str) → ()
    ;; Look up the window for the pressed digit and focus it.
    (define (focus-by-digit d)
      (let ((entry (assoc d current-window-targets)))
        (when entry
          (focus-window (cdr entry)))))

    ;; Dynamic window-range for 1.. — paint-window-chips! refreshes
    ;; current-window-targets on every leader press into the group, so
    ;; the same digit labels map to whichever windows are visible now.
    (define (window-range)
      (key-range "1.." "Window <n>"
        default-window-labels
        (lambda (k) (focus-by-digit k))))

    ;; (actions . opts) → group node with 'renderer 'diagram
    (define (actions . opts)
      (let* ((alist        (apply props->alist opts))
             (group-key    (alist-ref alist 'key "w"))
             (group-label  (alist-ref alist 'label "Windows"))
             (custom-panels (alist-ref alist 'panels #f))
             (panels        (or custom-panels (default-panels)))
             (panel-specs   (map panel-spec-of panels))
             (panel-keys    (apply append (map panel-keys-of panels)))
             (text-entries
               (list
                 (selector "n" "Named…"
                   'prompt "Select window…"
                   'source list-windows
                   'on-select focus-window
                   'actions
                     (list
                       (action "Focus" 'description "Select window" 'key 'primary
                         'run (lambda (c) (focus-window c)))))
                 (window-range)
                 (key "r" "Restore" (lambda () (restore-window)))))
             (children (append panel-keys text-entries)))
        (apply group group-key group-label
               'renderer 'diagram
               'panels panel-specs
               'on-enter (lambda () (paint-window-chips!))
               'on-leave (lambda () (hide-window-chips!))
               children)))

    (define (register! . opts)
      (let* ((alist (apply props->alist opts))
             (scope (alist-ref alist 'tree-scope 'global)))
        (define-tree scope (apply actions opts))))))
