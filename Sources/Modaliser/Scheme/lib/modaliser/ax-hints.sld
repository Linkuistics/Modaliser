;; (modaliser ax-hints) — AX-based hint flows for any app.
;;
;; Compose these primitives in your config to wire up "see a chip, type a
;; letter, focus that thing" UX over any app's accessible elements:
;;
;;   1. ax-find-labelled  — query AX for elements of a role in an app's
;;                          focused window; pair them with labels in
;;                          reading order. Returns ((label . elem) ...).
;;   2. ax-target-bindings — convert that list into (key ...) bindings
;;                           that fire your action with the AX handle.
;;   3. ax-target-hints   — convert that list into the hint-list shape
;;                          (modaliser hints) hints-show consumes.
;;
;; Wire (2) into a tree's children and (3) into its on-enter / on-leave
;; hooks. See bundled default-config.scm's iTerm tree for an end-to-end
;; example.

(define-library (modaliser ax-hints)
  (export default-hint-options
          label-pairs
          ax-find-labelled
          ax-target-bindings
          ax-target-hints)
  (import (scheme base)
          (modaliser dsl)
          (modaliser accessibility)
          (modaliser theming))
  (begin

    ;; ─── Hint chip appearance ──────────────────────────────────────
    ;;
    ;; Sensible smallish defaults. Override per-tree by passing your own
    ;; opts alist to ax-target-hints — the iTerm tree in default-config.scm
    ;; shows one tuned for very large pane chips.
    ;;
    ;; Keys (all optional):
    ;;   font-size, padding, corner-radius, border-width  — pixels
    ;;   color, background, border-color  — CSS colour: "#rgb"/"#rrggbb"/
    ;;     "#rrggbbaa", or any CSS named colour ("red", "tomato", etc.)
    ;;
    ;; Chip placement inset (distance from the anchor corner) is not
    ;; configurable here — it uses the canonical `(chip-host-padding)`
    ;; from (modaliser theming) so AX-hint chips and window-list chips
    ;; have the same visual rhythm. Which corner is the anchor IS a
    ;; per-call opt: 'anchor 'top-left (default, unchanged) or
    ;; 'top-right — a mini-chip painted top-left of a narrow sidebar
    ;; row/tab title sits directly over the start of its label; 'top-right
    ;; anchors it past the label's end instead (mini-chip-size-and-label-
    ;; anchor-k38), reading the entry's own 'w to place it flush with the
    ;; element's right edge.
    (define default-hint-options
      (list (cons 'font-size 24)
            (cons 'padding 6)
            (cons 'corner-radius 6)
            (cons 'color "#000000")
            (cons 'background "#ffffff")
            (cons 'border-width 1)
            (cons 'border-color "#000000")))

    ;; ─── Helpers ──────────────────────────────────────────────────

    ;; (label-pairs labels elements) → ((label . elem) ...)
    ;; Truncates at min length: extra labels or extra elements are dropped.
    (define (label-pairs labels elements)
      (let loop ((ls labels) (es elements) (acc '()))
        (cond
          ((or (null? ls) (null? es)) (reverse acc))
          (else (loop (cdr ls) (cdr es)
                      (cons (cons (car ls) (car es)) acc))))))

    (define (hint-opt opts key default)
      (let ((p (assoc key opts)))
        (if p (cdr p) default)))

    ;; ─── Public API ───────────────────────────────────────────────

    ;; (ax-find-labelled bundle-id role labels) → ((label . elem-alist) ...)
    ;;
    ;; Probe AX for elements of `role` inside the focused window of `bundle-id`,
    ;; then pair them with the supplied label list in reading order
    ;; (top-to-bottom, left-to-right). Returns '() if the app isn't running
    ;; or has no matching elements. Truncates at min(len(labels), len(elements)).
    (define (ax-find-labelled bundle-id role labels)
      (label-pairs labels (ax-find-elements bundle-id role)))

    ;; (ax-target-bindings labelled-elements label-prefix action-fn) → (key ...)
    ;;
    ;; For each (label . elem) pair, produce a (key label display-label thunk)
    ;; entry suitable for splicing into a tree's children. The thunk calls
    ;; (action-fn handle) where handle is the AX handle from the elem alist.
    ;; display-label = label-prefix ++ label (e.g. "Pane a", "Tab f").
    (define (ax-target-bindings labelled-elements label-prefix action-fn)
      (let loop ((ps labelled-elements) (acc '()))
        (if (null? ps)
          (reverse acc)
          (let* ((entry (car ps))
                 (label (car entry))
                 (elem  (cdr entry))
                 (handle (cdr (assoc 'handle elem))))
            (loop (cdr ps)
                  (cons (key label
                             (string-append label-prefix label)
                             (lambda () (action-fn handle)))
                        acc))))))

    ;; (ax-target-hints labelled-elements opts) → list ready for hints-show
    ;;
    ;; Default anchor ('top-left, every caller before mini-chip-size-and-
    ;; label-anchor-k38): each chip is sized to a call-wide (font-size +
    ;; 2*padding) square and placed (chip-host-padding) pixels in from the
    ;; element's top-left corner — the same canonical inset window-list
    ;; chips use, so AX-hint chips (iTerm panes today, browser tabs
    ;; tomorrow) share the visual rhythm. Panes never overlap so no
    ;; occlusion search is needed; the placement is just top-left +
    ;; padding. font-size/padding are exact here, never adjusted per entry.
    ;;
    ;; opts 'anchor 'right (mini-chips: a chip painted over a herdr sidebar
    ;; row or tab title, not a whole pane) is sized and placed PER ENTRY
    ;; instead, fitted to that element's own live 'h/'w — top-left's fixed
    ;; call-wide square would either sit on top of the label's own text
    ;; (wrong corner) or, sized to look reasonably large, overflow a short
    ;; row's real pixel height at whatever font size the user's terminal
    ;; happens to be (ui-layout-chip-entries computes 'w/'h from the SAME
    ;; live host-frame/canvas ratio pane chips use, so there is no fixed
    ;; cell-size assumption to lean on here either — see that function's
    ;; own header). font-size/padding become a CEILING instead of an exact
    ;; size: chip-size is capped to the element's own height, and font-size
    ;; is re-derived from whatever chip-size that clamp yields, so the chip
    ;; is never taller than its row regardless of terminal font size — it
    ;; sits flush with the element's right edge (a small fixed inset, much
    ;; tighter than chip-host-padding, which assumes clearing a whole pane
    ;; not a text row) and vertically centred within the row rather than
    ;; top-anchored, since a clamped-down chip should centre in the space
    ;; it fits rather than hug one edge.
    ;;
    ;; opts MAY also carry 'consumed (a positive int) and 'dim-color: when
    ;; present they're stamped onto EVERY entry, so HintsLibrary.swift's
    ;; per-char styling (mini-chip-renderer-k29) renders each chip's
    ;; leading CONSUMED characters in dim-color — narrowing's vimium-style
    ;; "typed prefix recedes" look (narrowing-dim-state-k30). One call-wide
    ;; value, not per-entry: every chip painted by a single ax-target-hints
    ;; call shares the same consumed count (e.g. "1" for every surviving
    ;; two-key label once its leader has been typed). Absent or non-
    ;; positive (every caller before this key existed) omits both keys
    ;; entirely — HintsLibrary.swift's makeHintPanel already renders the
    ;; plain single-colour path when 'consumed is absent, so output is
    ;; byte-identical to before.
    (define (ax-target-hints labelled-elements opts)
      (let* ((requested-font-size (hint-opt opts 'font-size 24))
             (padding   (hint-opt opts 'padding 6))
             (corner    (hint-opt opts 'corner-radius 6))
             (color     (hint-opt opts 'color "#000000"))
             (background (hint-opt opts 'background "#ffffff"))
             (border-width (hint-opt opts 'border-width 0))
             (border-color (hint-opt opts 'border-color color))
             (consumed  (hint-opt opts 'consumed 0))
             (dim-color (hint-opt opts 'dim-color color))
             (anchor    (hint-opt opts 'anchor 'top-left))
             (requested-chip-size (+ requested-font-size (* 2 padding)))
             ;; 'right's edge gap: much tighter than chip-host-padding, which
             ;; is sized for clearing a whole pane, not a text row.
             (edge-inset 2)
             ;; 'right's fit-to-height clamp used to fill the ENTIRE element
             ;; height with no slack — for two rows packed with zero gap in
             ;; cell-space (the common case: a tightly-listed sidebar), that
             ;; produced chips touching edge-to-edge with mathematically
             ;; zero overlap, which nonetheless reads as chips "colliding"
             ;; (no visible separation at all — confirmed against the live
             ;; painted rects, mini-chip-size-and-label-anchor-k38). Reserve
             ;; a small margin so the clamp leaves genuine breathing room —
             ;; split top/bottom by the vertical-centring below.
             (row-margin 4)
             (host-pad (chip-host-padding)))
        (let loop ((ps labelled-elements) (acc '()))
          (if (null? ps)
            (reverse acc)
            (let* ((entry (car ps))
                   (label (car entry))
                   (elem  (cdr entry))
                   (px (cdr (assoc 'x elem)))
                   (py (cdr (assoc 'y elem)))
                   (chip-size (if (eq? anchor 'right)
                                  (min requested-chip-size
                                       (max 1 (- (cdr (assoc 'h elem)) row-margin)))
                                  requested-chip-size))
                   (font-size (if (eq? anchor 'right)
                                  (max 1 (- chip-size (* 2 padding)))
                                  requested-font-size))
                   (hx (if (eq? anchor 'right)
                           (- (+ px (cdr (assoc 'w elem))) chip-size edge-inset)
                           (+ px host-pad)))
                   (hy (if (eq? anchor 'right)
                           (+ py (quotient (- (cdr (assoc 'h elem)) chip-size) 2))
                           (+ py host-pad))))
              (loop (cdr ps)
                    (cons (append
                            (list (cons 'label label)
                                  (cons 'x hx) (cons 'y hy)
                                  (cons 'w chip-size) (cons 'h chip-size)
                                  (cons 'color color)
                                  (cons 'background background)
                                  (cons 'font-size font-size)
                                  (cons 'padding padding)
                                  (cons 'corner-radius corner)
                                  (cons 'border-width border-width)
                                  (cons 'border-color border-color))
                            (if (> consumed 0)
                                (list (cons 'consumed consumed)
                                      (cons 'dim-color dim-color))
                                '()))
                          acc)))))))))
