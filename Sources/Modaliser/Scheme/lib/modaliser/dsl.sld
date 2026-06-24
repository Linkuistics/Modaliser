;; (modaliser dsl) — User-facing DSL.
;;
;; This is the surface user configs import:
;;
;;   (import (modaliser dsl))
;;
;; Then write (key …), (group …), (selector …), (action …),
;; (screen …), (set-leader! …) etc. directly in their config.scm
;; or in their own .sld libraries. The library is portable: imports
;; only (scheme …) and other (modaliser …) — no host-specific libraries.

(define-library (modaliser dsl)
  (export key key-range keys group selector action
          sticky-set fragment
          screen panel open
          λ
          set-theme!
          modifier-symbols->mask set-leader!
          ;; Re-exported from (modaliser state-machine) so user configs
          ;; can do a single (import (modaliser dsl)) for the common case.
          set-overlay-delay!)
  (import (scheme base)
          (scheme bitwise)
          (modaliser util)
          (modaliser state-machine)
          (modaliser event-dispatch)
          (modaliser keyboard))
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
;; replaced. Used by the `key` macro for the (selector …) / (group …)
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

;; (sticky-set MODE-ID DISPLAY-NAME key …) → splice node
;;
;; Define a reusable "act + latch" navigation set ONCE, then splice it
;; into any number of parents (DRY). It does two things:
;;
;;   1. Registers a sticky mode tree under MODE-ID (sticky + exit-on-
;;      unknown + DISPLAY-NAME breadcrumb) holding the bare keys — this is
;;      the latch target the walk repeats in.
;;   2. Returns a SPLICE node carrying the SAME keys, each decorated with
;;      'sticky-target MODE-ID. Placing it in a parent (screen / panel /
;;      open / group) hoists those entry keys in place, so
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
;;   (open "s" "Splits" split-nav (group "n" "New Split" …))
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

;; (fragment child …) → splice node
;;
;; A reusable, NAMED chunk of layout — panels (for screen-level reuse) or
;; command rows (for panel-level reuse) — bound once to a Scheme variable and
;; spliced into any number of screens/panels for DRY. It is sticky-set's
;; second half on its own: a 'kind 'splice node, with NO mode registration
;; and NO 'sticky-target decoration — pure structural reuse.
;;
;; expand-splices (run by the screen / panel / open / group constructors)
;; hoists the children in place, so nothing downstream ever sees the
;; fragment — the lowered tree is identical
;; to writing the children inline. Nested fragments / sticky-sets compose for
;; free, since expand-splices recurses through splice children.
;;
;;   (define window-ops
;;     (fragment
;;       (key "c" "Center"   center-window)
;;       (key "m" "Maximise" maximise-window)))
;;   (screen 'global (panel "Windows" window-ops …))   ; spliced here …
;;   (screen 'finder (panel "Layout"  window-ops …))   ; … and here
(define (fragment . children)
  (list (cons 'kind 'splice)
        (cons 'children children)))

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
;; injects 'key/'label via `decorate-node` — the same way it decorates
;; any bare node, e.g. a factory-returned group.
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
;; find-child descend through them untouched. See ADR-0012. (The legacy
;; define-tree / category / overlay forms these replaced were removed in the
;; post-k9 flag-day deletion.)
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

;; A screen's panel-packing mode. 'masonry (the default) flows panels into the
;; shortest lane (CSS grid-lanes); 'grid pins them to an aligned row/column grid
;; (the renderer emits 'masonry as no marker — see panel-grid-head).
(define (valid-layout? l)
  (and (memq l '(masonry grid)) #t))

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

;; The non-block node-forms of a loose region, declaration order preserved.
;; block-spec? distinguishes an embedded live-list / diagram block (carries
;; 'type) from a node-form (carries 'kind).
(define (loose-region-nodes loose)
  (let loop ((rest loose) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((block-spec? (car rest)) (loop (cdr rest) acc))
      (else (loop (cdr rest) (cons (car rest) acc))))))

;; The block-specs of a loose region, declaration order preserved.
(define (loose-region-blocks loose)
  (let loop ((rest loose) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((block-spec? (car rest)) (loop (cdr rest) (cons (car rest) acc)))
      (else (loop (cdr rest) acc)))))

;; Flatten the hidden dispatch keys ('block-children) of each loose block into
;; one list, so find-child resolves them at the screen/open root — the
;; loose-block analogue of make-panel-node's lift for a panel-embedded block.
(define (lift-loose-block-children blocks)
  (let loop ((rest blocks) (acc '()))
    (cond
      ((null? rest) acc)
      (else
        (let* ((b (car rest))
               (e (assoc 'block-children b)))
          (loop (cdr rest) (append acc (if e (cdr e) '()))))))))

;; Lower a panel-grid body — the shared core of screen / open. Returns a
;; (children loose-region blocks) list:
;;   • children      — the dispatch children of the screen/open group, in
;;                     declaration order: loose atoms / folded top-level opens,
;;                     the lifted hidden keys of loose blocks, then the real
;;                     panels (categories). find-child / flatten-categories
;;                     descend through all of them transparently.
;;   • loose-region  — the ordered loose region the renderer draws BARE above
;;                     the panel grid: each item is a loose node (a loose atom,
;;                     or a folded top-level `open` → a drill row) or a loose
;;                     block-spec (a diagram / live-list → a bare block).
;;                     Declaration order is preserved so blocks and rows
;;                     interleave as authored. No "General" panel is created.
;;   • blocks        — the live-list blocks (loose + panel-embedded) whose
;;                     on-enter-fn/on-leave-fn compose onto the screen/open
;;                     group; blocks under a nested `open` are excluded — they
;;                     compose onto that open's group.
;; Real panels (categories) pass through to the grid; an `open` declared INSIDE
;; a panel rides that panel's children (an accent group-row), untouched. Only
;; loose top-level atoms, top-level opens, and loose top-level blocks land in
;; the loose region.
(define (lower-panel-grid-body body)
  (let loop ((rest (expand-splices body)) (panels '()) (loose '()))
    (cond
      ((null? rest)
       (let* ((panels       (reverse panels))
              (loose-region (reverse loose))
              (loose-nodes  (loose-region-nodes loose-region))
              (loose-blocks (loose-region-blocks loose-region))
              (lifted       (lift-loose-block-children loose-blocks))
              (children     (append loose-nodes lifted panels))
              (blocks       (append loose-blocks (collect-panel-list-blocks panels))))
         (list children loose-region blocks)))
      ((category? (car rest))
       (loop (cdr rest) (cons (car rest) panels) loose))
      (else
       ;; A loose atom, a top-level `open` (a panel-grid group), or a loose
       ;; block-spec — all collect into the ordered loose region.
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
;; renderer marker + optional cols / layout / loose) shared by screen and open.
;; BLOCKS are the embedded list blocks whose on-enter-fn/on-leave-fn compose
;; with the user thunks. LAYOUT ('masonry | 'grid | #f) rides as an opaque
;; marker the renderer reads back; #f (the masonry default) carries none. LOOSE
;; is the ordered loose region (nodes + block-specs); it rides as an opaque
;; 'loose marker the renderer reads back to draw the bare row block, and is
;; omitted when empty (every child is a real panel).
(define (panel-grid-head blocks on-enter on-leave sticky display-name exit-unk cols layout loose)
  (let* ((composed-on-enter (compose-hooks on-enter (filter-fns blocks 'on-enter-fn)))
         (composed-on-leave (compose-hooks on-leave (filter-fns blocks 'on-leave-fn))))
    (append
      (if composed-on-enter (list 'on-enter composed-on-enter) '())
      (if composed-on-leave (list 'on-leave composed-on-leave) '())
      (if sticky            (list 'sticky sticky)              '())
      (if display-name      (list 'display-name display-name)  '())
      (if exit-unk          (list 'exit-on-unknown exit-unk)   '())
      (if cols              (list 'cols cols)                  '())
      (if layout            (list 'layout layout)              '())
      (if (null? loose)     '() (list 'loose loose))
      (list 'renderer 'panel-grid))))

;; (screen 'scope [keywords…] panel…) → registers a panel-grid tree under
;; 'scope. Body is an implicit grid of panels; loose top-level atoms, folded
;; top-level opens, and loose top-level blocks render BARE above the grid (the
;; loose region — no "General" panel). Keywords mirror register-tree! (on-enter /
;; on-leave / sticky / display-name / exit-on-unknown) plus 'cols N — the
;; authored column count (default CSS-intrinsic auto-fit, resolved in the
;; renderer leaf) — and 'layout ('masonry | 'grid) — the panel-packing mode
;; (default 'masonry: shortest-lane packing; 'grid: aligned deterministic
;; placement). The registered root carries 'renderer 'panel-grid (+ 'cols /
;; 'layout) for the panel-grid renderer.
(define (screen scope . args)
  (let loop ((rest args)
             (on-enter #f) (on-leave #f) (sticky #f)
             (display-name #f) (exit-unk #f) (cols #f) (layout #f))
    (cond
      ((and (pair? rest) (symbol? (car rest)) (pair? (cdr rest))
            (memq (car rest) '(on-enter on-leave sticky display-name exit-on-unknown cols layout)))
       (case (car rest)
         ((on-enter)        (loop (cddr rest) (cadr rest) on-leave sticky display-name exit-unk cols layout))
         ((on-leave)        (loop (cddr rest) on-enter (cadr rest) sticky display-name exit-unk cols layout))
         ((sticky)          (loop (cddr rest) on-enter on-leave (cadr rest) display-name exit-unk cols layout))
         ((display-name)    (loop (cddr rest) on-enter on-leave sticky (cadr rest) exit-unk cols layout))
         ((exit-on-unknown) (loop (cddr rest) on-enter on-leave sticky display-name (cadr rest) cols layout))
         ((cols)            (loop (cddr rest) on-enter on-leave sticky display-name exit-unk (cadr rest) layout))
         ((layout)
          (let ((v (cadr rest)))
            (unless (valid-layout? v)
              (error "screen: 'layout must be 'masonry or 'grid" v))
            (loop (cddr rest) on-enter on-leave sticky display-name exit-unk cols v)))))
      (else
       (let* ((lowered  (lower-panel-grid-body rest))
              (children (car lowered))
              (loose    (cadr lowered))
              (blocks   (caddr lowered))
              (head     (panel-grid-head blocks on-enter on-leave sticky
                                         display-name exit-unk cols layout loose)))
         (apply register-tree! scope (append head children)))))))

;; (open KEY LABEL [keywords…] panel…) → a navigable group drilling into a
;; sub-screen — the panel-native replacement for the old (key K L (overlay …))
;; idiom. Its children are the lowered sub-grid; it carries 'renderer
;; 'panel-grid (+ 'cols / 'layout). Keywords: on-enter / on-leave / sticky /
;; exit-on-unknown / cols / layout — not 'display-name, which is a
;; breadcrumb-root override that a child group (vs. a registered tree root) has
;; no use for.
(define (open key label . args)
  (let loop ((rest args)
             (on-enter #f) (on-leave #f) (sticky #f) (exit-unk #f) (cols #f) (layout #f))
    (cond
      ((and (pair? rest) (symbol? (car rest)) (pair? (cdr rest))
            (memq (car rest) '(on-enter on-leave sticky exit-on-unknown cols layout)))
       (case (car rest)
         ((on-enter)        (loop (cddr rest) (cadr rest) on-leave sticky exit-unk cols layout))
         ((on-leave)        (loop (cddr rest) on-enter (cadr rest) sticky exit-unk cols layout))
         ((sticky)          (loop (cddr rest) on-enter on-leave (cadr rest) exit-unk cols layout))
         ((exit-on-unknown) (loop (cddr rest) on-enter on-leave sticky (cadr rest) cols layout))
         ((cols)            (loop (cddr rest) on-enter on-leave sticky exit-unk (cadr rest) layout))
         ((layout)
          (let ((v (cadr rest)))
            (unless (valid-layout? v)
              (error "open: 'layout must be 'masonry or 'grid" v))
            (loop (cddr rest) on-enter on-leave sticky exit-unk cols v)))))
      (else
       (let* ((lowered  (lower-panel-grid-body rest))
              (children (car lowered))
              (loose    (cadr lowered))
              (blocks   (caddr lowered))
              (head     (panel-grid-head blocks on-enter on-leave sticky
                                         #f exit-unk cols layout loose)))
         (apply group key label (append head children)))))))

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
