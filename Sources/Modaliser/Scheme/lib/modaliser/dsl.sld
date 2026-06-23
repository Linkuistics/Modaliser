;; (modaliser dsl) — User-facing DSL.
;;
;; This is the surface user configs import:
;;
;;   (import (modaliser dsl))
;;
;; Then write (key …), (group …), (selector …), (action …),
;; (define-tree …), (set-leader! …) etc. directly in their config.scm
;; or in their own .sld libraries. The library is portable: imports
;; only (scheme …) and other (modaliser …) — no host-specific libraries.

(define-library (modaliser dsl)
  (export key key-range keys group selector action
          category overlay sticky-set
          screen panel open
          λ
          define-tree set-theme!
          modifier-symbols->mask set-leader!
          ;; Re-exported from (modaliser state-machine) so user configs
          ;; can do a single (import (modaliser dsl)) for the common case.
          set-overlay-delay! set-overlay-aspect-ratio!)
  (import (scheme base)
          (scheme bitwise)
          (modaliser state-machine)
          (modaliser event-dispatch)
          (modaliser keyboard)
          (modaliser blocks which-key))
  (begin

;; Pure Scheme node constructors for the command tree. These produce
;; alist nodes consumed by the modal state machine.

;; (key k label action [keyword value]...) → command alist
;;
;; Optional trailing keyword/value pairs:
;;   'sticky-target MODE-ID — after running `action`, transition modal
;;                            navigation into the sticky tree registered
;;                            under MODE-ID (a symbol). Equivalent to
;;                            having the action end with
;;                            (enter-mode! MODE-ID), but declarative so
;;                            the overlay renders a marker on the cell.
;;                            Composes with sticky ancestors (overrides
;;                            transient/sticky cleanup on this command).
;; `key` is a macro that dispatches on the shape AND runtime value of
;; the third arg:
;;
;;   (key K L (lambda …))             → command, lambda is the action thunk
;;   (key K L identifier [kw v …])    → identifier is evaluated; if a
;;                                       procedure, used as action thunk;
;;                                       if a pair (a node alist), the
;;                                       node is decorated with K/L
;;   (key K L (fn arg …) [kw v …])    → (fn arg …) is evaluated eagerly;
;;                                       same procedure-vs-pair dispatch
;;                                       on the result
;;
;; The third-arg call form is evaluated AT TREE-BUILD TIME. That works
;; cleanly for factories that return values without side effects (a
;; selector node, a thunk that fires the action later). It does NOT
;; defer side-effecting calls — for `(launch-app "X")` and friends,
;; wrap in an explicit `(lambda () …)` so the action fires on key press
;; rather than at config load. Symmetric thunk-returning helpers like
;; `keystroke` can be used directly: `(keystroke '(cmd) "c")` returns
;; a procedure, so it lands cleanly as the action.
(define-syntax key
  (syntax-rules (lambda λ)
    ((_ k label (lambda formals body ...) opts ...)
     (key-cmd k label (lambda formals body ...) opts ...))
    ((_ k label (λ formals body ...) opts ...)
     (key-cmd k label (lambda formals body ...) opts ...))
    ((_ k label (fn arg ...) opts ...)
     (key-build k label (fn arg ...) opts ...))
    ((_ k label id opts ...)
     (key-build k label id opts ...))))

;; (λ formals body ...) — Unicode alias for `lambda`. Useful for keeping
;; `(key K L (λ () (foo)))` compact in configs. Expands to `(lambda …)`.
(define-syntax λ
  (syntax-rules ()
    ((_ formals body ...) (lambda formals body ...))))

;; Runtime dispatch helper for `key`. Inspects the evaluated value:
;;   - procedure  → command with action = procedure
;;   - pair       → node, decorated with K/L (selector/group/overlay/…)
;; Anything else is a misuse — a side-effecting call that should have
;; been wrapped in `(lambda () …)`.
(define (key-build k label value . opts)
  (cond
    ((procedure? value) (apply key-cmd k label value opts))
    ((pair? value) (decorate-node k label value))
    (else
     (error "key: third arg must be a procedure or a node (was neither — wrap a side-effecting call in (lambda () …))" value))))

;; The runtime helper invoked by the `key` macro for command shapes.
;; Keep the alist-building logic here so the macro stays purely
;; syntactic. `opts` is the optional trailing 'sticky-target tail.
(define (key-cmd k label action . opts)
  (let loop ((rest opts) (acc (list (cons 'kind 'command)
                                    (cons 'key k)
                                    (cons 'label label)
                                    (cons 'action action))))
    (cond
      ((null? rest) acc)
      ((or (null? (cdr rest)) (not (symbol? (car rest))))
       (error "key: expected trailing keyword/value pairs" rest))
      ((eq? (car rest) 'sticky-target)
       (loop (cddr rest) (cons (cons 'sticky-target (cadr rest)) acc)))
      (else
       (error "key: unknown keyword" (car rest))))))

;; (decorate-node k label node) → node with its 'key and 'label
;; replaced. Used by the `key` macro for the (overlay …) / (group …)
;; sub-form dispatch — the wrapping `(key K L …)` decides how the node
;; appears in the parent tree.
(define (decorate-node k label node)
  (let loop ((rest node) (acc '()) (saw-key? #f) (saw-label? #f))
    (cond
      ((null? rest)
       (let* ((acc (if saw-key?   acc (cons (cons 'key k)     acc)))
              (acc (if saw-label? acc (cons (cons 'label label) acc))))
         (reverse acc)))
      ((eq? (car (car rest)) 'key)
       (loop (cdr rest) (cons (cons 'key k)     acc) #t saw-label?))
      ((eq? (car (car rest)) 'label)
       (loop (cdr rest) (cons (cons 'label label) acc) saw-key? #t))
      (else
       (loop (cdr rest) (cons (car rest) acc) saw-key? saw-label?)))))

;; (key-range display-key label keys action-fn) → range-command alist
;;
;; Binds multiple keys to a single shared action, displayed as one row in the
;; overlay. Useful for sequences like "1..9 Space <n>" or "a..p Pane <n>"
;; where listing every key would clutter the overlay.
;;
;;   display-key : string shown in the overlay's key column (e.g. "1..9").
;;                 Purely cosmetic — the actual dispatch keys are in `keys`.
;;   label       : string shown in the overlay's label column (e.g.
;;                 "Space <n>"). The <n> is literal text, not a placeholder
;;                 the system substitutes — readers infer "n varies per key".
;;   keys        : non-empty list of single-char key strings to bind. A
;;                 sibling (key …) for the same character wins, so a literal
;;                 binding can override one slot of a range.
;;   action-fn   : (lambda (matched-key) ...) — invoked with the actual key
;;                 string that fired the binding, so the action can vary per
;;                 key (e.g. switch space N) while sharing one closure.
(define (key-range display-key label keys action-fn)
  (list (cons 'kind 'range-command)
        (cons 'key display-key)
        (cons 'keys keys)
        (cons 'label label)
        (cons 'action action-fn)))

;; (keys KEYLIST LABEL ACTION-FN [keyword value]...) → range-command alist
;;
;; Higher-level surface form for binding many keys to one labelled action.
;; ACTION-FN is invoked as (ACTION-FN matched-key index keylist) so the
;; action can branch on slot without closing over the list itself.
;;
;; KEYLIST supports two abbreviations alongside literal lists:
;;
;;   '("a" .. "z")   — inclusive single-char range, by code point
;;   '("1" ..)       — open-ended digit range; expands to "n".."9"
;;
;; The display-key in the overlay is derived from the expanded keylist:
;;
;;   contiguous chars        → "<first>..<last>"      e.g. "a..c"
;;   digit range ending at 9 → "<first>.."             e.g. "1.."
;;   otherwise               → "/"-joined keys          e.g. "a/c/e"
;;
;; Examples:
;;   (keys '("1" ..) "Goto Space <n>"
;;     (lambda (k i ks) (send-keystroke '(ctrl) k)))
;;
;; Optional trailing keyword/value pairs:
;;   'display-key STRING — override the computed display key
(define (keys keylist label action-fn . opts)
  (let* ((expanded (expand-key-range keylist)))
    (let loop ((rest opts) (display #f))
      (cond
        ((null? rest)
         (let ((disp (or display (compute-keys-display expanded))))
           (key-range disp label expanded
             (lambda (k)
               (let scan ((tail expanded) (i 0))
                 (cond
                   ((null? tail)          (action-fn k -1 expanded))
                   ((equal? (car tail) k) (action-fn k i  expanded))
                   (else                  (scan (cdr tail) (+ i 1)))))))))
        ((or (null? (cdr rest)) (not (symbol? (car rest))))
         (error "keys: expected trailing keyword/value pairs" rest))
        ((eq? (car rest) 'display-key)
         (loop (cddr rest) (cadr rest)))
        (else
         (error "keys: unknown keyword" (car rest)))))))

;; Expand `..` shorthand inside a keylist:
;;   ("X" .. "Y" rest…) → splice (X X+1 … Y) before rest
;;   ("X" ..)           → splice (X X+1 … "9") when X is a digit
;; Plain entries pass through unchanged. Non-matching uses of `..` raise.
(define (expand-key-range keylist)
  (cond
    ((null? keylist) '())
    ((null? (cdr keylist)) keylist)
    ((eq? (cadr keylist) '..)
     (cond
       ;; ("X" ..) — trailing open-end. Requires X to be a single digit.
       ((null? (cddr keylist))
        (if (digit-key? (car keylist))
          (char-range-strings (car keylist) "9")
          (error "keys: trailing `..` requires a digit start key" (car keylist))))
       ;; ("X" .. "Y" rest…) — generic inclusive range.
       ((and (string? (car keylist)) (string? (car (cddr keylist)))
             (= 1 (string-length (car keylist)))
             (= 1 (string-length (car (cddr keylist)))))
        (append (char-range-strings (car keylist) (car (cddr keylist)))
                (expand-key-range (cdr (cddr keylist)))))
       (else
        (error "keys: `..` must sit between two single-char strings or trail a digit"
               keylist))))
    (else (cons (car keylist) (expand-key-range (cdr keylist))))))

(define (digit-key? s)
  (and (string? s) (= 1 (string-length s))
       (let ((c (char->integer (string-ref s 0))))
         (and (>= c 48) (<= c 57)))))

(define (char-range-strings from to)
  (let ((a (char->integer (string-ref from 0)))
        (b (char->integer (string-ref to 0))))
    (when (> a b)
      (error "keys: `..` range is empty (from > to)" from to))
    (let loop ((i b) (out '()))
      (if (< i a) out (loop (- i 1) (cons (string (integer->char i)) out))))))

;; Pick the overlay display key from an already-expanded keylist.
;; Singletons render as the key itself; contiguous single-char runs render
;; as "<first>..<last>" (or "<first>.." for digit runs ending at "9");
;; everything else falls through to a "/"-joined list.
(define (compute-keys-display keylist)
  (cond
    ((null? keylist) "")
    ((null? (cdr keylist)) (car keylist))
    ((all-single-char? keylist)
     (let* ((first (car keylist))
            (last  (last-of keylist)))
       (cond
         ((not (contiguous-single-chars? keylist))
          (slash-join keylist))
         ((and (digit-key? first) (string=? last "9"))
          (string-append first ".."))
         (else
          (string-append first ".." last)))))
    (else (slash-join keylist))))

(define (all-single-char? lst)
  (or (null? lst)
      (and (string? (car lst))
           (= 1 (string-length (car lst)))
           (all-single-char? (cdr lst)))))

(define (contiguous-single-chars? lst)
  (let loop ((rest lst) (prev #f))
    (cond
      ((null? rest) #t)
      ((not prev)
       (loop (cdr rest) (char->integer (string-ref (car rest) 0))))
      (else
       (let ((c (char->integer (string-ref (car rest) 0))))
         (and (= c (+ prev 1)) (loop (cdr rest) c)))))))

(define (last-of lst)
  (if (null? (cdr lst)) (car lst) (last-of (cdr lst))))

(define (slash-join lst)
  (cond
    ((null? lst) "")
    ((null? (cdr lst)) (car lst))
    (else (string-append (car lst) "/" (slash-join (cdr lst))))))

;; (group k label [keyword value]... . children) → group alist
;;
;; Optional leading keyword/value pairs. Recognized keywords:
;;   'on-enter THUNK        — called when modal navigates into this group
;;   'on-leave THUNK        — called when modal navigates out of this group
;;   'sticky          BOOL  — firing a command leaf at or below this group
;;                            returns navigation to this group instead of
;;                            exiting the modal. Composes with sticky
;;                            ancestors: the deepest sticky group on the
;;                            current path wins. See register-tree!'s
;;                            'sticky doc for full semantics.
;;   'exit-on-unknown BOOL  — unrecognised keys at or below this group
;;                            dismiss the modal instead of being swallowed.
;;                            Useful for sticky focus-movement modes where
;;                            typing a non-binding key should hand control
;;                            back to the underlying app.
;;
;; Args after the keyword pairs are children. Disambiguation: a child node
;; is always a pair whose first element is a pair (alist starting with
;; (kind . ...)); a keyword is a bare symbol. So leading bare symbols start
;; the keyword tail and the first non-symbol begins the children.
(define (group k label . rest)
  (let loop ((args rest)
             (on-enter #f) (on-leave #f)
             (sticky #f) (exit-unk #f)
             (extras '())            ; reverse-accumulated alist of unknown kw/val pairs
             (children '()))
    (cond
      ((null? args)
        (let* ((acc (list (cons 'kind 'group)
                          (cons 'key k)
                          (cons 'label label)
                          (cons 'children (expand-splices (reverse children)))))
               (acc (if exit-unk    (cons (cons 'exit-on-unknown exit-unk) acc) acc))
               (acc (if sticky      (cons (cons 'sticky sticky)            acc) acc))
               (acc (if on-leave    (cons (cons 'on-leave on-leave)        acc) acc))
               (acc (if on-enter    (cons (cons 'on-enter on-enter)        acc) acc))
               (acc (append (reverse extras) acc)))   ; extras carried through as-is
          acc))
      ((and (symbol? (car args)) (not (null? (cdr args))))
       (case (car args)
         ((on-enter)        (loop (cddr args) (cadr args) on-leave sticky exit-unk extras children))
         ((on-leave)        (loop (cddr args) on-enter (cadr args) sticky exit-unk extras children))
         ((sticky)          (loop (cddr args) on-enter on-leave (cadr args) exit-unk extras children))
         ((exit-on-unknown) (loop (cddr args) on-enter on-leave sticky (cadr args) extras children))
         (else
           ;; Unknown keyword — accumulate as opaque alist entry.
           ;; Used by renderer extensions like 'renderer 'blocks 'blocks (...).
           (loop (cddr args) on-enter on-leave sticky exit-unk
                 (cons (cons (car args) (cadr args)) extras)
                 children))))
      (else
       ;; Positional child node.
       (loop (cdr args) on-enter on-leave sticky exit-unk extras
             (cons (car args) children))))))

;; (category label . children) → category alist
;;
;; Category nodes group a slice of group children under a label for
;; rendering by the (modaliser blocks which-key) block. The state machine
;; treats them as TRANSPARENT for dispatch: find-child descends through
;; category nodes as if their children were hoisted into the parent.
;; This lets configs add visual grouping without changing key paths.
(define (category label . children)
  (list (cons 'kind 'category)
        (cons 'label label)
        (cons 'children (expand-splices children))))

;; (sticky-set MODE-ID DISPLAY-NAME key …) → splice node
;;
;; Define a reusable "act + latch" navigation set ONCE, then splice it
;; into any number of parents (DRY). It does two things:
;;
;;   1. Registers a sticky mode tree under MODE-ID (sticky + exit-on-
;;      unknown + DISPLAY-NAME breadcrumb) holding the bare keys — this is
;;      the latch target the walk repeats in.
;;   2. Returns a SPLICE node carrying the SAME keys, each decorated with
;;      'sticky-target MODE-ID. Placing it in a parent (define-tree /
;;      overlay / group / category) hoists those entry keys in place, so
;;      pressing one fires its action AND latches into the mode.
;;
;; The key list is thus written once and supplies both the mode and every
;; entry point. Use individual (key …) forms — not (keys …)/(key-range …)
;; — since 'sticky-target is a (key …)-only keyword.
;;
;;   (define split-nav
;;     (sticky-set 'iterm-split-walk "Splits"
;;       (key "h" "Focus Left" focus-left)
;;       (key "H" "Move Left"  move-left) …))
;;   (overlay 'key "s" 'label "Splits" split-nav (group "n" "New Split" …))
(define (sticky-set mode-id display-name . keys)
  (apply register-tree! mode-id
         'sticky #t
         'exit-on-unknown #t
         'display-name display-name
         keys)
  (list (cons 'kind 'splice)
        (cons 'children
              (map (lambda (k) (cons (cons 'sticky-target mode-id) k))
                   keys))))

;; (overlay [keyword value]... block...) → group alist with 'renderer 'blocks
;;
;; Generic block-list group constructor. Opts:
;;
;;   'key      STRING  — leader key (default "?")
;;   'label    STRING  — group label (default "Overlay")
;;   'on-enter THUNK   — user-supplied enter hook (composed with block hooks)
;;   'on-leave THUNK   — user-supplied leave hook (composed with block hooks)
;;
;; Positional args after the opts are block specs (alists carrying
;; ('type . SYM)). Each block can opt into the modal lifecycle and
;; dispatch via three optional fields read by `overlay`:
;;
;;   'block-children  — dispatch keys, lifted onto the group's 'children
;;   'on-enter-fn     — thunk run when the overlay becomes visible
;;   'on-leave-fn     — thunk run when the overlay closes
;;
;; User-supplied on-enter/on-leave run BEFORE the block-contributed
;; ones, then each block's hooks fire in declaration order. on-render-fn
;; is part of the rendering protocol (see ui/overlay.scm's
;; block-list-payload-json), not collected here.
(define (overlay . args)
  (let loop ((rest args) (key #f) (label #f) (user-on-enter #f) (user-on-leave #f))
    (cond
      ((and (pair? rest) (eq? (car rest) 'key) (pair? (cdr rest)))
       (loop (cddr rest) (cadr rest) label user-on-enter user-on-leave))
      ((and (pair? rest) (eq? (car rest) 'label) (pair? (cdr rest)))
       (loop (cddr rest) key (cadr rest) user-on-enter user-on-leave))
      ((and (pair? rest) (eq? (car rest) 'on-enter) (pair? (cdr rest)))
       (loop (cddr rest) key label (cadr rest) user-on-leave))
      ((and (pair? rest) (eq? (car rest) 'on-leave) (pair? (cdr rest)))
       (loop (cddr rest) key label user-on-enter (cadr rest)))
      (else
        ;; Everything from here is positional content. Consecutive
        ;; node-forms (e.g. (key …)) are auto-packed into a single
        ;; which-key-block; block forms pass through. This mirrors
        ;; define-tree, so the same structural shorthand works inside
        ;; nested overlays without explicit (which-key-block …).
        (let* ((blocks (pack-node-runs (expand-splices rest)))
               (block-children
                 (apply append
                   (map (lambda (b)
                          (let ((e (assoc 'block-children b)))
                            (if e (cdr e) '())))
                        blocks)))
               (on-enter-fns
                 (filter-fns blocks 'on-enter-fn))
               (on-leave-fns
                 (filter-fns blocks 'on-leave-fn))
               (composed-on-enter
                 (compose-hooks user-on-enter on-enter-fns))
               (composed-on-leave
                 (compose-hooks user-on-leave on-leave-fns)))
          (apply group
                 (or key "?")
                 (or label "Overlay")
                 'renderer 'blocks
                 'blocks blocks
                 'on-enter composed-on-enter
                 'on-leave composed-on-leave
                 block-children))))))

;; Collect the procedure values of `tag` across `blocks`, preserving order.
(define (filter-fns blocks tag)
  (let loop ((rest blocks) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      (else
        (let* ((b (car rest))
               (e (assoc tag b))
               (v (and e (cdr e))))
          (loop (cdr rest)
                (if (procedure? v) (cons v acc) acc)))))))

;; Compose user-thunk (or #f) with a list of block thunks into a single
;; thunk. Returns #f when nothing to run, so the state machine's
;; node-on-enter/leave accessors see a clean #f rather than a no-op proc.
(define (compose-hooks user-thunk block-thunks)
  (cond
    ((and (not user-thunk) (null? block-thunks)) #f)
    (else
      (lambda ()
        (when user-thunk (user-thunk))
        (for-each (lambda (fn) (fn)) block-thunks)))))

;; (selector . props) → selector alist (undecorated)
;;
;; Returns a selector node without 'key or 'label. Wrap with
;; `(key K L (selector …))` to bind it; the wrapping `key` macro
;; injects 'key/'label via `decorate-node`. Mirrors how `(key K L
;; (overlay …))` works for groups.
(define (selector . props)
  (let loop ((rest props) (entries (list (cons 'kind 'selector))))
    (if (or (null? rest) (null? (cdr rest)))
      (reverse entries)
      (loop (cdr (cdr rest))
            (cons (cons (car rest) (car (cdr rest))) entries)))))

;; (action name . props) → action alist
(define (action name . props)
  (let loop ((rest props) (entries (list (cons 'name name))))
    (if (or (null? rest) (null? (cdr rest)))
      (reverse entries)
      (loop (cdr (cdr rest))
            (cons (cons (car rest) (car (cdr rest))) entries)))))

;; (define-tree scope [keyword value]... . content) → registers tree
;;
;; A top-level tree behaves like an overlay: its content is a list of
;; blocks (alists with 'type) interleaved with node-forms (alists with
;; 'kind). Consecutive runs of node-forms are auto-packed into a single
;; (which-key-block …), so a config can write
;;
;;   (define-tree 'global
;;     (key "a" "X" …)
;;     (key "b" "Y" …)
;;     (key "w" "Windows" (overlay …)))
;;
;; and the three (key …) forms collapse into one which-key-block at the
;; root. Blocks pass through untouched. The registered group carries
;; 'renderer 'blocks so the top-level overlay always renders as a
;; block-list — uniform with nested overlays.
;;
;; Optional leading keyword/value pairs (same set as register-tree!):
;;   'on-enter THUNK / 'on-leave THUNK / 'sticky BOOL
;;   'display-name STRING / 'exit-on-unknown BOOL
(define (define-tree scope . args)
  (let loop ((rest args)
             (on-enter #f) (on-leave #f)
             (sticky #f) (display-name #f) (exit-unk #f))
    (cond
      ((and (pair? rest) (symbol? (car rest)) (pair? (cdr rest))
            (memq (car rest) '(on-enter on-leave sticky display-name exit-on-unknown)))
       (case (car rest)
         ((on-enter)        (loop (cddr rest) (cadr rest) on-leave sticky display-name exit-unk))
         ((on-leave)        (loop (cddr rest) on-enter (cadr rest) sticky display-name exit-unk))
         ((sticky)          (loop (cddr rest) on-enter on-leave (cadr rest) display-name exit-unk))
         ((display-name)    (loop (cddr rest) on-enter on-leave sticky (cadr rest) exit-unk))
         ((exit-on-unknown) (loop (cddr rest) on-enter on-leave sticky display-name (cadr rest)))))
      (else
        ;; rest is the positional content. Pack node-runs into which-key-blocks.
        (let* ((blocks (pack-node-runs (expand-splices rest)))
               (block-children
                 (apply append
                   (map (lambda (b)
                          (let ((e (assoc 'block-children b)))
                            (if e (cdr e) '())))
                        blocks)))
               (on-enter-fns (filter-fns blocks 'on-enter-fn))
               (on-leave-fns (filter-fns blocks 'on-leave-fn))
               (composed-on-enter (compose-hooks on-enter on-enter-fns))
               (composed-on-leave (compose-hooks on-leave on-leave-fns))
               (head (append
                       (if composed-on-enter (list 'on-enter composed-on-enter) '())
                       (if composed-on-leave (list 'on-leave composed-on-leave) '())
                       (if sticky            (list 'sticky sticky)              '())
                       (if display-name      (list 'display-name display-name)  '())
                       (if exit-unk          (list 'exit-on-unknown exit-unk)   '())
                       (list 'renderer 'blocks 'blocks blocks))))
          (apply register-tree! scope (append head block-children)))))))

;; Partition `items` into a list of blocks. Consecutive node-forms
;; (alists with a 'kind entry) are packed into which-key-blocks; explicit
;; block forms (alists with a 'type entry) pass through unchanged.
;;
;; Mixed runs split into TWO blocks — uncategorised entries first, then
;; categories — so the overlay renders the loose bindings as a single
;; section, with the category columns underneath. Categories preserve
;; declaration order across the split; miscs are collected together
;; regardless of where they appear in the source. A homogeneous run
;; (all misc OR all categories) produces a single block.
;;
;; We never re-nest existing (which-key-block …) forms — those are
;; passed through verbatim, honouring the author's explicit grouping.
(define (pack-node-runs items)
  (let loop ((rest items) (pending '()) (out '()))
    (cond
      ((null? rest)
       (reverse (append (flush-node-run pending) out)))
      ((node-form? (car rest))
       (loop (cdr rest) (cons (car rest) pending) out))
      (else
       (loop (cdr rest) '()
             (cons (car rest) (append (flush-node-run pending) out)))))))

;; Build 0..2 which-key-blocks from a pending run of node-forms.
;; Returned list is in REVERSE final order so it can be cons'd onto
;; `out` (which pack-node-runs reverses at the end).
(define (flush-node-run pending)
  ;; `pending` arrives in reverse-of-declaration order (pack-node-runs
  ;; conses onto it). Walking it and consing each item onto either
  ;; `miscs` or `cats` reverses that order back to declaration order
  ;; inside each bucket — so neither bucket needs a final reverse.
  (cond
    ((null? pending) '())
    (else
     (let split ((rest pending) (miscs '()) (cats '()))
       (cond
         ((null? rest)
          (let ((misc-block (and (not (null? miscs))
                                 (apply which-key-block miscs)))
                (cat-block  (and (not (null? cats))
                                 (apply which-key-block cats))))
            ;; Output order is uncategorised → categorised. The list we
            ;; return is reversed here so it cons'es cleanly onto
            ;; pack-node-runs's `out` accumulator.
            (cond
              ((and misc-block cat-block) (list cat-block misc-block))
              (misc-block                 (list misc-block))
              (cat-block                  (list cat-block))
              (else                       '()))))
         ((category? (car rest))
          (split (cdr rest) miscs (cons (car rest) cats)))
         (else
          (split (cdr rest) (cons (car rest) miscs) cats)))))))

(define (node-form? x)
  (and (pair? x) (pair? (car x)) (assoc 'kind x) #t))

;; ─── Layout DSL (presentation-first; ADR-0011 / ADR-0012) ────────
;;
;; Three container forms that LOWER — at construction time, like
;; category/group — to the operational alist nodes the state machine
;; already dispatches, with presentation metadata riding as opaque alist
;; entries the panel-grid renderer reads back via node-renderer-payload:
;;
;;   (panel  "label" ['span S] child…)    → 'kind 'category + 'span (+ 'list)
;;   (screen 'scope  [keywords…] panel…)  → register-tree! 'renderer 'panel-grid
;;   (open   KEY LABEL [keywords…] panel…)→ navigable 'group  'renderer 'panel-grid
;;
;; The dispatch atoms (key / keys / key-range / selector / group /
;; sticky-set) are kept verbatim — they ARE the operational IR. Panels are
;; categories, which stay transparent for dispatch, so flatten-categories /
;; find-child descend through them untouched. The old forms (define-tree /
;; category / overlay) keep working — this is purely additive. See ADR-0012.
;;
;; Co-designed contract with panel-grid-renderer-k4 — the metadata a screen
;; group / its panels carry, which the renderer reads (no JSON owned here):
;;   • screen / open group: 'renderer 'panel-grid, optional 'cols N.
;;   • each panel (category): 'span ('narrow|'wide|'full), 'label, 'children
;;     (the dispatch atoms), and — when it embeds a live list — 'list holding
;;     the single block-spec (ready for the renderer's block-json path).

;; A live-list block-spec (window:list-block / iterm:pane-list-block /
;; iterm:tab-list-block) is an alist carrying a 'type entry — distinct from a
;; node-form, which carries 'kind. A panel may embed one as a child.
(define (block-spec? x)
  (and (pair? x) (pair? (car x)) (assoc 'type x) #t))

(define (valid-span? s)
  (and (memq s '(narrow wide full)) #t))

;; Build a panel (a 'kind 'category node) from an ALREADY splice-expanded
;; child list. Children partition into dispatch atoms (node-forms) and at
;; most one embedded live-list block. The block's own 'block-children (its
;; hidden digit key-range — e.g. the "1.." pane/window focus range) are
;; lifted into the panel's dispatch children so find-child resolves the
;; digits transparently; the block-spec itself rides under 'list for the
;; renderer. SPAN is the explicit 'span value, or #f to default — 'narrow,
;; auto-'wide when a list block is present.
(define (make-panel-node label span children)
  (let loop ((rest children) (atoms '()) (block #f))
    (cond
      ((null? rest)
       (let* ((atoms (reverse atoms))
              (lifted (if block
                        (let ((e (assoc 'block-children block)))
                          (if e (cdr e) '()))
                        '()))
              (dispatch-children (append atoms lifted))
              (span* (or span (if block 'wide 'narrow)))
              (base (list (cons 'kind 'category)
                          (cons 'label label)
                          (cons 'span span*)
                          (cons 'children dispatch-children))))
         (if block
           (append base (list (cons 'list block)))
           base)))
      ((block-spec? (car rest))
       (if block
         (error "panel: at most one embedded live-list block per panel" label)
         (loop (cdr rest) atoms (car rest))))
      (else
       (loop (cdr rest) (cons (car rest) atoms) block)))))

;; (panel "label" ['span 'narrow|'wide|'full] child…) → category node.
;; Default span 'narrow; auto-'wide when a live-list block is embedded and no
;; explicit 'span is given. Children are dispatch atoms plus at most one
;; live-list block; splices (sticky-set / fragment) hoist via expand-splices.
;; A leading bare symbol is a keyword ('span only); the first non-symbol
;; begins the children.
(define (panel label . rest)
  (let loop ((args rest) (span #f))
    (cond
      ((and (pair? args) (eq? (car args) 'span) (pair? (cdr args)))
       (let ((v (cadr args)))
         (unless (valid-span? v)
           (error "panel: 'span must be 'narrow, 'wide or 'full" v))
         (loop (cddr args) v)))
      ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
       (error "panel: unknown keyword" (car args)))
      (else
       (make-panel-node label span (expand-splices args))))))

;; Lower a panel-grid body — the shared core of screen / open. Returns
;; (grid-children . list-blocks): explicit panels (categories) and nested
;; `open`s (panel-grid groups) pass through in declaration order, loose
;; top-level atoms collect into one leading "General" panel — the
;; presentation-first analogue of pack-node-runs' misc bucket. The returned
;; list-blocks are the live-list blocks embedded in this level's DIRECT
;; panels (used to compose on-enter/on-leave hooks, like define-tree); blocks
;; under a nested `open` are excluded — they compose onto that open's group.
(define (lower-panel-grid-body body)
  (let loop ((rest (expand-splices body)) (panels '()) (loose '()))
    (cond
      ((null? rest)
       (let* ((general (if (null? loose)
                         '()
                         (list (make-panel-node "General" #f (reverse loose)))))
              (grid (append general (reverse panels)))
              (blocks (collect-panel-list-blocks grid)))
         (cons grid blocks)))
      ((or (category? (car rest))
           (and (group? (car rest))
                (eq? (node-renderer (car rest)) 'panel-grid)))
       (loop (cdr rest) (cons (car rest) panels) loose))
      (else
       (loop (cdr rest) panels (cons (car rest) loose))))))

;; The live-list blocks across a grid's direct panels (categories), read back
;; from each panel's 'list entry. Opens are skipped — their lists live a level
;; deeper and compose onto the open group, not this one.
(define (collect-panel-list-blocks grid)
  (let loop ((rest grid) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((category? (car rest))
       (let ((e (assoc 'list (car rest))))
         (loop (cdr rest) (if e (cons (cdr e) acc) acc))))
      (else (loop (cdr rest) acc)))))

;; Assemble the leading keyword/value head (composed lifecycle hooks +
;; renderer marker + optional cols) shared by screen and open. BLOCKS are the
;; embedded list blocks whose on-enter-fn/on-leave-fn compose with the user
;; thunks — exactly as define-tree composes block hooks.
(define (panel-grid-head blocks on-enter on-leave sticky display-name exit-unk cols)
  (let* ((composed-on-enter (compose-hooks on-enter (filter-fns blocks 'on-enter-fn)))
         (composed-on-leave (compose-hooks on-leave (filter-fns blocks 'on-leave-fn))))
    (append
      (if composed-on-enter (list 'on-enter composed-on-enter) '())
      (if composed-on-leave (list 'on-leave composed-on-leave) '())
      (if sticky            (list 'sticky sticky)              '())
      (if display-name      (list 'display-name display-name)  '())
      (if exit-unk          (list 'exit-on-unknown exit-unk)   '())
      (if cols              (list 'cols cols)                  '())
      (list 'renderer 'panel-grid))))

;; (screen 'scope [keywords…] panel…) → registers a panel-grid tree under
;; 'scope (the define-tree analogue). Body is an implicit grid of panels;
;; loose top-level atoms pack into a leading "General" panel. Keywords mirror
;; define-tree (on-enter / on-leave / sticky / display-name / exit-on-unknown)
;; plus 'cols N — the authored column count (default CSS-intrinsic auto-fit,
;; resolved in the renderer leaf). The registered root carries
;; 'renderer 'panel-grid (+ 'cols) for the panel-grid renderer.
(define (screen scope . args)
  (let loop ((rest args)
             (on-enter #f) (on-leave #f) (sticky #f)
             (display-name #f) (exit-unk #f) (cols #f))
    (cond
      ((and (pair? rest) (symbol? (car rest)) (pair? (cdr rest))
            (memq (car rest) '(on-enter on-leave sticky display-name exit-on-unknown cols)))
       (case (car rest)
         ((on-enter)        (loop (cddr rest) (cadr rest) on-leave sticky display-name exit-unk cols))
         ((on-leave)        (loop (cddr rest) on-enter (cadr rest) sticky display-name exit-unk cols))
         ((sticky)          (loop (cddr rest) on-enter on-leave (cadr rest) display-name exit-unk cols))
         ((display-name)    (loop (cddr rest) on-enter on-leave sticky (cadr rest) exit-unk cols))
         ((exit-on-unknown) (loop (cddr rest) on-enter on-leave sticky display-name (cadr rest) cols))
         ((cols)            (loop (cddr rest) on-enter on-leave sticky display-name exit-unk (cadr rest)))))
      (else
       (let* ((lowered (lower-panel-grid-body rest))
              (grid    (car lowered))
              (blocks  (cdr lowered))
              (head    (panel-grid-head blocks on-enter on-leave sticky
                                        display-name exit-unk cols)))
         (apply register-tree! scope (append head grid)))))))

;; (open KEY LABEL [keywords…] panel…) → a navigable group drilling into a
;; sub-screen — the panel-native replacement for (key K L (overlay …)). Its
;; children are the lowered sub-grid; it carries 'renderer 'panel-grid (+
;; 'cols). Keywords: on-enter / on-leave / sticky / exit-on-unknown / cols —
;; not 'display-name, which is a breadcrumb-root override that a child group
;; (vs. a registered tree root) has no use for.
(define (open key label . args)
  (let loop ((rest args)
             (on-enter #f) (on-leave #f) (sticky #f) (exit-unk #f) (cols #f))
    (cond
      ((and (pair? rest) (symbol? (car rest)) (pair? (cdr rest))
            (memq (car rest) '(on-enter on-leave sticky exit-on-unknown cols)))
       (case (car rest)
         ((on-enter)        (loop (cddr rest) (cadr rest) on-leave sticky exit-unk cols))
         ((on-leave)        (loop (cddr rest) on-enter (cadr rest) sticky exit-unk cols))
         ((sticky)          (loop (cddr rest) on-enter on-leave (cadr rest) exit-unk cols))
         ((exit-on-unknown) (loop (cddr rest) on-enter on-leave sticky (cadr rest) cols))
         ((cols)            (loop (cddr rest) on-enter on-leave sticky exit-unk (cadr rest)))))
      (else
       (let* ((lowered (lower-panel-grid-body rest))
              (grid    (car lowered))
              (blocks  (cdr lowered))
              (head    (panel-grid-head blocks on-enter on-leave sticky
                                        #f exit-unk cols)))
         (apply group key label (append head grid)))))))

;; (set-theme! . args) → no-op stub for backward compatibility
;; Theming moves to CSS in Phase 3.
(define (set-theme! . args) (if #f #f))

;; Convert a list of modifier symbols (e.g. '(shift ctrl)) to the integer
;; bitmask expected by register-hotkey!. Unknown symbols are ignored.
(define (modifier-symbols->mask syms)
  (let loop ((s syms) (mask 0))
    (cond
      ((null? s) mask)
      ((eq? (car s) 'cmd)   (loop (cdr s) (bitwise-ior mask MOD-CMD)))
      ((eq? (car s) 'shift) (loop (cdr s) (bitwise-ior mask MOD-SHIFT)))
      ((eq? (car s) 'alt)   (loop (cdr s) (bitwise-ior mask MOD-ALT)))
      ((eq? (car s) 'ctrl)  (loop (cdr s) (bitwise-ior mask MOD-CTRL)))
      (else (loop (cdr s) mask)))))

;; (set-leader! mode keycode [keyword value]...) → registers a hotkey
;;
;; `mode` is required and must be 'global or 'local:
;;   (set-leader! 'global keycode)
;;   (set-leader! 'local  keycode)
;;
;; There is no modeless form — a leader is always scoped to either the
;; global tree or the focused app's local tree. The local mode does not
;; fall back to the global tree.
;;
;; Optional trailing keyword/value pairs:
;;   'modifiers <symbol-list>               ; e.g. '(shift) or '(cmd alt)
;;   'arm-when-frontmost <strs>             ; bundle IDs that trigger pass-and-arm
(define (set-leader! . args)
  (let ((mode (and (pair? args) (car args))))
    (when (not (or (eq? mode 'global) (eq? mode 'local)))
      (error "set-leader!: mode must be 'global or 'local; got" mode))
    (when (null? (cdr args))
      (error "set-leader!: missing keycode after mode"))
    (let ((keycode (cadr args))
          (tail    (cddr args)))
      (let loop ((rest tail) (mod-mask 0) (arm-bundle-ids '()))
        (cond
          ((null? rest)
           (register-hotkey! keycode
                             (make-leader-handler keycode mode)
                             mod-mask
                             arm-bundle-ids))
          ((eq? (car rest) 'modifiers)
           (loop (cddr rest) (modifier-symbols->mask (cadr rest)) arm-bundle-ids))
          ((eq? (car rest) 'arm-when-frontmost)
           (loop (cddr rest) mod-mask (cadr rest)))
          (else
           (error "set-leader!: unknown keyword" (car rest))))))))

)) ;; end begin / define-library
