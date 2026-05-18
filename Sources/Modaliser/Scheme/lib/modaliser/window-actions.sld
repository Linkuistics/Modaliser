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
    ;; fractional inset from each window's top-left corner). Three-line
    ;; chip: large bold digit on top, app name and window title beneath
    ;; at half the font size. App + title let the user disambiguate
    ;; occluded windows even when most of the window is hidden behind
    ;; another. Width auto-fits the widest line, height fits the stack.
    (define default-window-chip-options
      (list (cons 'offset-x-frac 0.05)
            (cons 'offset-y-frac 0.05)
            (cons 'font-size 28)
            (cons 'sub-font-size 14)
            (cons 'padding 8)
            (cons 'corner-radius 6)
            (cons 'color "white")
            (cons 'background "dodgerblue")
            ;; dodgerblue (#1e90ff) at ~50% alpha. Chips sitting on a
            ;; window that's occluded at the chip's anchor render with
            ;; this background so the user sees at a glance which
            ;; numbered windows are partially or fully hidden.
            (cons 'faded-background "#1e90ff80")
            (cons 'border-width 1)
            (cons 'border-color "black")
            ;; Truncation budgets — keep chips a sensible size even
            ;; for verbose apps ("Microsoft Word") or long titles.
            (cons 'app-name-max-chars 18)
            (cons 'window-title-max-chars 22)))

    ;; (truncate-with-ellipsis s n) → string of length ≤ n
    ;; Trims to n-1 chars + … when over budget. The ellipsis is one
    ;; character wide visually so the total reads as n chars.
    (define (truncate-with-ellipsis s n)
      (if (> (string-length s) n)
        (string-append (substring s 0 (- n 1)) "\x2026;")
        s))

    ;; (window-chip-for digit window opts) → chip alist for hints-show
    ;; Horizontal chip:  digit  | App
    ;;                          | Window Title
    ;; — large bold digit on the left, app + window title stacked to
    ;; the right at half the digit's font size. The digit drives the
    ;; user's keypress; the sub-text disambiguates when several windows
    ;; sit at overlapping positions. Chip is placed at the ratio-based
    ;; offset inside the window.
    (define (window-chip-for digit win opts)
      (let* ((wx (cdr (assoc 'x win)))
             (wy (cdr (assoc 'y win)))
             (ww (cdr (assoc 'w win)))
             (wh (cdr (assoc 'h win)))
             (font-size (cdr (assoc 'font-size opts)))
             (sub-font-size (cdr (assoc 'sub-font-size opts)))
             (padding (cdr (assoc 'padding opts)))
             (offx (cdr (assoc 'offset-x-frac opts)))
             (offy (cdr (assoc 'offset-y-frac opts)))
             (chip-x (+ wx (exact (round (* ww offx)))))
             (chip-y (+ wy (exact (round (* wh offy)))))
             (app-max (cdr (assoc 'app-name-max-chars opts)))
             (title-max (cdr (assoc 'window-title-max-chars opts)))
             (app (truncate-with-ellipsis (cdr (assoc 'subText win)) app-max))
             (title (truncate-with-ellipsis (cdr (assoc 'text win)) title-max))
             (sub-label (if (string=? title "")
                          app
                          (string-append app "\n" title)))
             ;; 0.62 ≈ average char-width / point-size for the system
             ;; semibold sans face. Width = digit + gap + widest sub-line
             ;; + 2*padding; the gap matches HintsLibrary's stack spacing
             ;; (0.75 × padding).
             (digit-w (exact (round (* font-size 0.62 (string-length digit)))))
             (app-w   (exact (round (* sub-font-size 0.62 (string-length app)))))
             (title-w (exact (round (* sub-font-size 0.62 (string-length title)))))
             (gap (max 4 (exact (round (* padding 0.75)))))
             (chip-w (+ digit-w gap (max app-w title-w) (* 2 padding)))
             ;; Height = taller of (digit, sub-line stack) + 2*padding.
             (sub-line-count (if (string=? title "") 1 2))
             (digit-h (exact (round (* font-size 1.2))))
             (sub-stack-h (* sub-line-count
                             (exact (round (* sub-font-size 1.2)))))
             (chip-h (+ (max digit-h sub-stack-h) (* 2 padding))))
        (list (cons 'label digit)
              (cons 'sub-label sub-label)
              (cons 'sub-font-size sub-font-size)
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

    ;; (resolve-occluded-against-visible chips initial-placed sw sh)
    ;;   → list of resolved chips (in input order)
    ;; Iteratively shifts each chip past any conflict with already-placed
    ;; chips (down first, then right if the down move would leave the
    ;; screen). The `initial-placed` list seeds the placed accumulator —
    ;; used so visible-window chips can be pinned and occluded chips
    ;; route around them. Stops at chip-resolve-max-attempts per chip;
    ;; pathological clusters degrade to "accept the last position"
    ;; rather than infinite-loop.
    (define (resolve-occluded-against-visible chips initial-placed sw sh)
      (let outer ((rest chips)
                  (placed (let r ((xs initial-placed) (a '()))
                            (if (null? xs) a (r (cdr xs) (cons (car xs) a)))))
                  (new-count 0))
        (cond
          ((null? rest)
            ;; New chips are at the front of placed in reverse input order;
            ;; walk new-count of them, consing into acc gives input order.
            (let collect ((p placed) (remaining new-count) (acc '()))
              (cond
                ((zero? remaining) acc)
                (else (collect (cdr p) (- remaining 1) (cons (car p) acc))))))
          (else
            (let* ((c0 (clamp-chip-to-screen (car rest) sw sh))
                   (natural-y (cdr (assoc 'y c0))))
              (let inner ((c c0) (attempts 0))
                (cond
                  ((>= attempts chip-resolve-max-attempts)
                   (outer (cdr rest) (cons c placed) (+ new-count 1)))
                  (else
                    (let ((conflict (find-overlapping placed c)))
                      (cond
                        ((not conflict)
                         (outer (cdr rest) (cons c placed) (+ new-count 1)))
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

    ;; (chip-with-background chip new-bg) → chip alist with 'background
    ;; replaced. Used to mark chips whose window is occluded at the chip
    ;; anchor point.
    (define (chip-with-background chip new-bg)
      (map (lambda (entry)
             (if (eq? (car entry) 'background)
               (cons 'background new-bg)
               entry))
           chip))

    ;; (resolve-chips-with-visibility annotated sw sh) → resolved chips in
    ;; input order. annotated is ((visible? . chip) ...). Visible chips
    ;; pin to their natural (clamped) position so the user's frontmost
    ;; windows always show their chip exactly where they expect it.
    ;; Occluded chips resolve against the visible set plus any already-
    ;; placed occluded chips.
    (define (resolve-chips-with-visibility annotated sw sh)
      (let split ((rest annotated) (visible-rev '()) (occluded-rev '()))
        (cond
          ((null? rest)
            (let* ((visible-chips (reverse visible-rev))
                   (occluded-chips (reverse occluded-rev))
                   (occluded-resolved (resolve-occluded-against-visible
                                        occluded-chips visible-chips sw sh)))
              (let reassemble ((src annotated)
                               (vp visible-chips)
                               (op occluded-resolved)
                               (acc '()))
                (cond
                  ((null? src) (reverse acc))
                  ((car (car src))
                   (reassemble (cdr src) (cdr vp) op (cons (car vp) acc)))
                  (else
                   (reassemble (cdr src) vp (cdr op) (cons (car op) acc)))))))
          ((car (car rest))
            (split (cdr rest)
                   (cons (clamp-chip-to-screen (cdr (car rest)) sw sh) visible-rev)
                   occluded-rev))
          (else
            (split (cdr rest)
                   visible-rev
                   (cons (cdr (car rest)) occluded-rev))))))

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
             (raw-chips
               (map (lambda (lw)
                      (window-chip-for (car lw) (cdr lw)
                                       default-window-chip-options))
                    labelled))
             (faded-bg (cdr (assoc 'faded-background
                                    default-window-chip-options)))
             ;; Annotate each chip with visibility — is the chip's own
             ;; window the topmost at the chip's anchor point? Occluded
             ;; chips render with the washed-out bg so the user sees
             ;; which numbered windows are hidden.
             (annotated
               (map (lambda (lw chip)
                      (let* ((win (cdr lw))
                             (wid (cdr (assoc 'windowId win)))
                             (cx (cdr (assoc 'x chip)))
                             (cy (cdr (assoc 'y chip)))
                             (visible? (window-visible-at? wid cx cy))
                             (styled (if visible?
                                       chip
                                       (chip-with-background chip faded-bg))))
                        (cons visible? styled)))
                    labelled raw-chips))
             (screen (primary-screen-size))
             (chips (resolve-chips-with-visibility
                      annotated
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
