;; (modaliser dsl) — User-facing DSL.
;;
;; This is the surface user configs import:
;;
;;   (import (modaliser dsl))
;;
;; Then write (key …), (group …), (selector …), (action …),
;; (screen …) etc. directly in their config.scm
;; or in their own .sld libraries. Every form is PURE (ADR-0018): it
;; builds and returns data — nodes, tree contributions — and the single
;; effectful moment is the config's own (modaliser:start! …) handoff.
;; The library is portable: imports
;; only (scheme …) and other (modaliser …) — no host-specific libraries.

(define-library (modaliser dsl)
  (export key key-range keys group selector action
          walk splice step-in
          screen panel open
          ;; The pure tree-root builder — what a library uses for a mode
          ;; tree that is not a panel-grid screen (a walk's latch target,
          ;; a digit-jump mode).
          tree-root
          λ
          modifier-symbols->mask)
  (import (scheme base)
          (scheme bitwise)
          (modaliser util)
          ;; Only the tree-contribution constructor: `screen` returns a
          ;; (tree scope node) contribution for the configuration merge
          ;; (ADR-0018).
          (only (modaliser configuration) tree)
          ;; The bare authoring surface the sugar compiles onto
          ;; (ADR-0011/0012; display-dsl-surface-k23): screen/panel/open
          ;; build their display values through the d: clause
          ;; constructors and attach via d:with-display — prefixed
          ;; because `panel` deliberately exists on both surfaces.
          (prefix (modaliser display-dsl) d:)
          (modaliser fsm)
          (modaliser keyboard))
  (begin

;; Pure Scheme node constructors for the command tree. These produce
;; alist nodes consumed by the modal state machine.

;; (key k label action [keyword value]...) → command alist
;;
;; Optional trailing keyword/value pairs:
;;   'next TARGET — the leaf's post-action transition (ADR-0015). TARGET
;;                  is a registered tree's id (a symbol — a cross edge:
;;                  push the caller, switch into it), the literal 'self
;;                  (a cyclic edge — re-arm in place, no push; use inside
;;                  a `walk`'s own registered members), or a 0-arg
;;                  procedure resolved at fire time (a dynamic edge,
;;                  e.g. "whichever backend is frontmost"). Declaring
;;                  'next also makes the leaf non-Terminal, so dispatch
;;                  keeps modal capture through the action instead of
;;                  releasing it first — and the overlay renders a ↻
;;                  marker on the cell. Omitting 'next makes the leaf
;;                  Terminal: capture is released BEFORE the action
;;                  runs, so the action may freely hand the keyboard
;;                  elsewhere (a dialog, an external prompt).
;;   'hidden VALUE — presentation only: keep the row out of the overlay
;;                  while VALUE holds. #t hides it always; a 0-arg
;;                  predicate is resolved at render time, so the row can
;;                  come and go without a relaunch. Dispatch is
;;                  unaffected — a hidden key still fires. This is how a
;;                  configuration authors a one-shot setup row that
;;                  retires itself, e.g.
;;                  `(key "C-I" "Configure iTerm" iterm:configure!
;;                        'hidden iterm:configured?)`.
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
;; syntactic. `opts` is the optional trailing 'next tail.
(define (key-cmd k label action . opts)
  (let loop ((rest opts) (acc (list (cons 'kind 'command)
                                    (cons 'key k)
                                    (cons 'label label)
                                    (cons 'action action))))
    (cond
      ((null? rest) acc)
      ((or (null? (cdr rest)) (not (symbol? (car rest))))
       (error "key: expected trailing keyword/value pairs" rest))
      ((eq? (car rest) 'next)
       (loop (cddr rest) (cons (cons 'next (cadr rest)) acc)))
      ;; Presentation, not dispatch: the renderer's node-hidden? resolves
      ;; #t or a 0-arg predicate. Accepted here so a CONFIGURATION can
      ;; author a self-retiring row (ADR-0021) — whether to hide a
      ;; provisioning key once its gate is satisfied is preference, while
      ;; the gate itself is the library's facility.
      ((eq? (car rest) 'hidden)
       (loop (cddr rest) (cons (cons 'hidden (cadr rest)) acc)))
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
          (string-join keylist "/"))
         ((and (digit-key? first) (string=? last "9"))
          (string-append first ".."))
         (else
          (string-append first ".." last)))))
    (else (string-join keylist "/"))))

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

;; (group k label [keyword value]... . children) → group alist
;;
;; Optional leading keyword/value pairs. Recognized keywords:
;;   'on-enter THUNK        — called when modal navigates into this group
;;   'on-leave THUNK        — called when modal navigates out of this group
;;   'exit-on-unknown BOOL  — unrecognised keys at or below this group
;;                            dismiss the modal instead of being swallowed.
;;                            Useful for cyclic focus-movement modes (a
;;                            Walk) where typing a non-binding key should
;;                            hand control back to the underlying app.
;;   'provider PROC         — an FSM edge provider (CONTEXT.md "Edge
;;                            provider"): a 1-arg procedure run each time
;;                            the group comes to rest, returning an alist
;;                            of extra 'edges / 'states for that Visit
;;                            only (docs/specs/fsm-graph.md). Lowers
;;                            straight onto the state's 'provider slot —
;;                            unlike on-enter/on-leave, it is not
;;                            presentation-gated. Its argument is the id of
;;                            the state it was lowered onto: a provider
;;                            minting a provided RESTING state (a narrowing
;;                            prefix state) must id it `<owner-id>/<key>`
;;                            and point its 'up edge at `<owner-id>`, which
;;                            is not derivable any other way.
;;   'entry THUNK / 'exit THUNK — the unconditional action-slot pair
;;                            (CONTEXT.md "Action slots"): 'entry fires at
;;                            come-to-rest of a Visit (including
;;                            fsm-activate! at leader press), 'exit at the
;;                            Visit's end (navigate-away or modal-exit) —
;;                            BOTH regardless of whether the overlay ever
;;                            displays, unlike on-enter/on-leave (gated
;;                            onto show/hide, fired only if/when the
;;                            delayed overlay show elapses). Lower straight
;;                            onto the state's 'entry/'exit slots.
;;                            Author-only: a block child's hook fns
;;                            (on-enter-fn/on-leave-fn) never fire from
;;                            these — they are presentation, fired
;;                            structurally with the gated pair by
;;                            run-on-enter/run-on-leave (fsm.sld).
;;
;; A group has no latching flag of its own (ADR-0015) — a command leaf
;; at or below it cycles only if it individually declares 'next 'self
;; (see `key`); stickiness is derived from the leaves' edges, never
;; declared on the group.
;;
;; Args after the keyword pairs are children. Disambiguation: a child node
;; is always a pair whose first element is a pair (alist starting with
;; (kind . ...)); a keyword is a bare symbol. So leading bare symbols start
;; the keyword tail and the first non-symbol begins the children.
(define (group k label . rest)
  (let loop ((args rest)
             (on-enter #f) (on-leave #f)
             (exit-unk #f)
             (provider #f)
             (entry #f) (exit #f)
             (order #f)
             (extras '())            ; reverse-accumulated alist of unknown kw/val pairs
             (children '()))
    (cond
      ((null? args)
        ;; 'order is display data (row ordering — ADR-0011): fold it into
        ;; the group's display value — merged into a 'display extra when
        ;; one was passed as a raw keyword, else a fresh single-entry
        ;; value. (The sugar no longer routes 'display through here — it
        ;; attaches via d:with-display; the fold keeps the keyword
        ;; convenience coherent for direct group authors.) An empty
        ;; display value is dropped (absent ≡ empty — fsm.sld
        ;; node-display).
        (let* ((extras (reverse extras))
               (dext   (assq 'display extras))
               (extras (remove (lambda (e) (eq? (car e) 'display)) extras))
               (dv     (let ((base (if dext (cdr dext) '())))
                         (if order (cons (cons 'order order) base) base)))
               (acc (list (cons 'kind 'group)
                          (cons 'key k)
                          (cons 'label label)
                          ;; Splice children survive construction
                          ;; (dsl-purification-k9): dispatch-children
                          ;; expands them at dispatch/lowering read time,
                          ;; and the configuration merge hoists any tree
                          ;; they carry.
                          (cons 'children (reverse children))))
               (acc (if exit-unk    (cons (cons 'exit-on-unknown exit-unk) acc) acc))
               (acc (if provider    (cons (cons 'provider provider)        acc) acc))
               (acc (if entry       (cons (cons 'entry entry)              acc) acc))
               (acc (if exit        (cons (cons 'exit exit)                acc) acc))
               (acc (if on-leave    (cons (cons 'on-leave on-leave)        acc) acc))
               (acc (if on-enter    (cons (cons 'on-enter on-enter)        acc) acc))
               (acc (if (pair? dv)  (cons (cons 'display dv)               acc) acc))
               (acc (append extras acc)))   ; remaining extras carried through as-is
          acc))
      ((and (symbol? (car args)) (not (null? (cdr args))))
       (case (car args)
         ((on-enter)        (loop (cddr args) (cadr args) on-leave exit-unk provider entry exit order extras children))
         ((on-leave)        (loop (cddr args) on-enter (cadr args) exit-unk provider entry exit order extras children))
         ((exit-on-unknown) (loop (cddr args) on-enter on-leave (cadr args) provider entry exit order extras children))
         ((provider)        (loop (cddr args) on-enter on-leave exit-unk (cadr args) entry exit order extras children))
         ((entry)           (loop (cddr args) on-enter on-leave exit-unk provider (cadr args) exit order extras children))
         ((exit)            (loop (cddr args) on-enter on-leave exit-unk provider entry (cadr args) order extras children))
         ((order)           (loop (cddr args) on-enter on-leave exit-unk provider entry exit (cadr args) extras children))
         (else
           ;; Unknown keyword — accumulate as opaque alist entry.
           (loop (cddr args) on-enter on-leave exit-unk provider entry exit order
                 (cons (cons (car args) (cadr args)) extras)
                 children))))
      (else
       ;; Positional child node.
       (loop (cdr args) on-enter on-leave exit-unk provider entry exit order extras
             (cons (car args) children))))))

;; (tree-root SCOPE [keyword value]... child…) → root group node (pure)
;;
;; Build a tree's ROOT node: what a (tree SCOPE root) contribution
;; carries, what `screen` and `walk` build internally, and what a
;; library uses directly for a mode tree that is not a panel-grid screen
;; (a digit-jump mode, a focus walk). The root carries 'scope (the key
;; string) instead of a label; the breadcrumb is computed at activation
;; time from it (compute-tree-root-segments).
;;
;; Recognized keywords (mirror the (group ...) DSL):
;;   'on-enter THUNK / 'on-leave THUNK — the presentation-gated pair
;;                         (lowered onto show/hide).
;;   'entry THUNK / 'exit THUNK — the unconditional action-slot pair
;;                         (CONTEXT.md "Action slots"), fired at Visit
;;                         come-to-rest / end regardless of overlay
;;                         display.
;;   'provider PROC      — an FSM edge provider on the root state.
;;   'exit-on-unknown BOOL — unrecognised keys dismiss the modal instead
;;                         of being swallowed (inherited by descendants).
;;   'display-name STR   — overrides the breadcrumb scope segment;
;;                         stored in the root's display value (the
;;                         breadcrumb is presentation — ADR-0011),
;;                         merged into a 'display keyword's value when
;;                         both are given.
;; Unknown keywords pass through as opaque alist entries.
;;
;; Children are alist nodes produced by (key ...), (group ...),
;; (selector ...); authored splice nodes survive intact
;; (dsl-purification-k9) — expansion happens at lowering / read time, so
;; a walk's carried tree survives for the pure merge to hoist.
(define (tree-root scope . rest)
  (let ((scope-str (if (symbol? scope) (symbol->string scope) scope)))
    (let loop ((args rest)
               (on-enter #f) (on-leave #f)
               (display-name #f) (exit-unk #f)
               (provider #f)
               (entry #f) (exit #f)
               (order #f)
               (extras '()))     ; reverse-accumulated opaque kw/val pairs
      (cond
        ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
         (case (car args)
           ((on-enter)        (loop (cddr args) (cadr args) on-leave display-name exit-unk provider entry exit order extras))
           ((on-leave)        (loop (cddr args) on-enter (cadr args) display-name exit-unk provider entry exit order extras))
           ((display-name)    (loop (cddr args) on-enter on-leave (cadr args) exit-unk provider entry exit order extras))
           ((exit-on-unknown) (loop (cddr args) on-enter on-leave display-name (cadr args) provider entry exit order extras))
           ((provider)        (loop (cddr args) on-enter on-leave display-name exit-unk (cadr args) entry exit order extras))
           ((entry)           (loop (cddr args) on-enter on-leave display-name exit-unk provider (cadr args) exit order extras))
           ((exit)            (loop (cddr args) on-enter on-leave display-name exit-unk provider entry (cadr args) order extras))
           ((order)           (loop (cddr args) on-enter on-leave display-name exit-unk provider entry exit (cadr args) extras))
           (else
             (loop (cddr args) on-enter on-leave display-name exit-unk provider entry exit order
                   (cons (cons (car args) (cadr args)) extras)))))
        (else
          ;; 'display-name and 'order are display data (ADR-0011): fold
          ;; them into the root's display value — merged into a 'display
          ;; extra when one was passed as a raw keyword, else a fresh
          ;; value (walk passes the keywords; the sugar attaches via
          ;; d:with-display instead). An empty display value is dropped
          ;; (absent ≡ empty — fsm.sld node-display).
          (let* ((extras (reverse extras))
                 (dext   (assq 'display extras))
                 (extras (remove (lambda (e) (eq? (car e) 'display)) extras))
                 (dv     (let* ((base (if dext (cdr dext) '()))
                                (base (if order (cons (cons 'order order) base) base)))
                           (if display-name
                             (cons (cons 'display-name display-name) base)
                             base)))
                 (acc (list (cons 'kind 'group)
                            (cons 'key "")
                            (cons 'scope scope-str)
                            (cons 'children args)))
                 (acc (if on-leave (cons (cons 'on-leave on-leave)  acc) acc))
                 (acc (if on-enter (cons (cons 'on-enter on-enter)  acc) acc))
                 (acc (if provider (cons (cons 'provider provider)  acc) acc))
                 (acc (if entry    (cons (cons 'entry entry)        acc) acc))
                 (acc (if exit     (cons (cons 'exit exit)          acc) acc))
                 (acc (if exit-unk (cons (cons 'exit-on-unknown #t) acc) acc))
                 (acc (if (pair? dv) (cons (cons 'display dv)       acc) acc)))
            (append extras acc)))))))

;; (walk MODE-ID DISPLAY-NAME ['order 'keys|'declared] key …) → splice node
;;
;; Define a reusable "act + latch" navigation set ONCE, then splice it
;; into any number of parents (DRY). The returned splice node carries two
;; things built from the one key list:
;;
;;   1. Under 'tree: the mode tree (MODE-ID . root), the latch target —
;;      exit-on-unknown + DISPLAY-NAME breadcrumb, holding the keys each
;;      decorated 'next 'self, a cyclic edge, so firing one re-arms in
;;      place (CONTEXT.md "Walk"). The configuration merge hoists it into
;;      the tree set — the same walk spliced into two screens contributes
;;      its mode tree ONCE (identity dedup).
;;   2. Under 'children: the SAME keys again, each decorated 'next MODE-ID
;;      — a cross edge. Placing the splice in a parent (screen / panel /
;;      open / group) supplies those entry keys in place, so pressing one
;;      fires its action AND crosses into the mode.
;;
;; The key list is thus written once and supplies both the mode and every
;; entry point, each copy decorated for its own edge (cyclic for the mode
;; members, cross for the entry splice) — the two `map`s below build
;; non-destructive copies from the same `keys`, so neither decoration
;; leaks into the other. Use individual (key …) forms — not
;; (keys …)/(key-range …) — since 'next is a (key …)-only keyword.
;;
;; An optional leading 'order keyword ('keys | 'declared, mirroring panel /
;; screen) tunes the row ordering of the mode tree — the latched walk:
;; 'declared shows the keys in declaration order, 'keys (the default)
;; key-sorts them. It is forwarded only to the mode tree, never into the
;; splice — the spliced entry keys land in their parent's loose region,
;; which is already declaration-ordered (iterm-nav-declared-order-k38).
;;
;;   (define split-nav
;;     (walk 'iterm-split-walk "Splits" 'order 'declared
;;       (key "h" "Focus Left" focus-left)
;;       (key "H" "Move Left"  move-left) …))
;;   (open "s" "Splits" split-nav (group "n" "New Split" …))
(define (walk mode-id display-name . rest)
  ;; Parse the optional leading 'order <mode> off the front; the remaining
  ;; args are the (key …) forms. Keeping 'order out of `keys` is what stops
  ;; it leaking into either decorated copy the maps below build.
  (let* ((has-order (and (pair? rest) (eq? (car rest) 'order) (pair? (cdr rest))))
         (order     (and has-order (cadr rest)))
         (keys      (if has-order (cddr rest) rest))
         (mode-keys (map (lambda (k) (cons (cons 'next 'self) k)) keys))
         ;; tree-root folds 'order and 'display-name into the mode
         ;; root's display value (row ordering and the breadcrumb are
         ;; display data — ADR-0011).
         (mode-root (apply tree-root mode-id
                           'exit-on-unknown #t
                           'display-name display-name
                           (if order
                             (cons 'order (cons order mode-keys))
                             mode-keys))))
    (list (cons 'kind 'splice)
          (cons 'tree (cons mode-id mode-root))
          (cons 'children
                (map (lambda (k) (cons (cons 'next mode-id) k))
                     keys)))))

;; (splice child …) → splice node
;;
;; A reusable, NAMED chunk of layout — panels (for screen-level reuse) or
;; command rows (for panel-level reuse) — bound once to a Scheme variable
;; and spliced into any number of screens/panels for DRY (formerly
;; `fragment`; renamed when "Fragment" became the configuration term,
;; ADR-0018). It is `walk`'s second half on its own: a 'kind 'splice
;; node, with NO carried mode tree and NO 'next decoration — pure
;; structural reuse.
;;
;; The splice node survives construction as data (dsl-purification-k9);
;; expansion happens downstream — dispatch-children for dispatch and the
;; FSM lowering, expand-splices for the presentation views — so the
;; lowered tree is identical to writing the children inline. Nested
;; splices / walks compose for free, since both expansions recurse
;; through splice children.
;;
;;   (define window-ops
;;     (splice
;;       (key "c" "Center"   center-window)
;;       (key "m" "Maximise" maximise-window)))
;;   (screen 'global (panel "Windows" window-ops …))   ; spliced here …
;;   (screen 'finder (panel "Layout"  window-ops …))   ; … and here
(define (splice . children)
  (list (cons 'kind 'splice)
        (cons 'children children)))

;; (step-in key label target-scope gate) → step-in alist node
;;
;; A gated cross-tree key edge (CONTEXT.md "Edge gate" — "e.g. the `.`
;; step-in edge", ADR-0013): pressing KEY moves directly to another tree's
;; root in the same configuration value — an ordinary key edge, not a call
;; (no return-stack push, unlike a (key … 'next TARGET) cross edge), so
;; the target's OWN up edge is what
;; backspace follows back out, and the move lands and shows immediately
;; like any other group descent, with no intermediate command state.
;;
;; Live only while GATE (a 0-arg predicate) holds: gate-filtered out of
;; dispatch exactly like any other edge gate, and the row is hidden from
;; the overlay via a 'hidden thunk derived from the SAME gate, so "no
;; inner context detected" means both no edge and no overlay row.
;;
;;   (step-in "." "Herdr" "com.googlecode.iterm2/herdr" herdr-detected?)
(define (step-in key label target-scope gate)
  (let ((target (if (symbol? target-scope) (symbol->string target-scope) target-scope)))
    (list (cons 'kind 'step-in)
          (cons 'key key)
          (cons 'label label)
          (cons 'target target)
          (cons 'gate gate)
          (cons 'hidden (lambda () (not (gate)))))))

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
;; Three container forms that LOWER — at construction time — onto the
;; two-layer node model: flat dispatch children plus ONE disjoint
;; 'display entry holding the node's complete Display value
;; ((modaliser display-dsl); CONTEXT.md "Display value"):
;;
;;   (panel  "label" ['span S] child…)    → a construction-time panel-spec,
;;                                          consumed by screen/open: its
;;                                          atoms join the flat children,
;;                                          its shape becomes a display
;;                                          panel clause (never a node)
;;   (screen 'scope  [keywords…] panel…)  → (tree 'scope root) contribution
;;   (open   KEY LABEL [keywords…] panel…)→ navigable 'group + 'display
;;
;; The dispatch atoms (key / keys / key-range / selector / group /
;; walk) are kept verbatim — they ARE the operational IR. Nothing
;; panel-shaped lands among dispatch children; the renderer resolves the
;; display value against the children via the pure resolve-display seam.
;; See ADR-0012. (The legacy define-tree / category / overlay forms these
;; replaced were removed in the post-k9 flag-day deletion; the 'kind
;; 'category node and its flatten-categories tunneling retired at the
;; display-readers cutover.)

;; A live-list block-spec (window:list-block / iterm:pane-list-block /
;; iterm:tab-list-block) is an alist carrying a 'type entry — distinct from a
;; node-form, which carries 'kind. A panel may embed one as a child.
(define (block-spec? x)
  (and (pair? x) (pair? (car x)) (assoc 'type x) #t))

;; Build a PANEL-SPEC — a construction-time record, never an IR node:
;; screen / open consume it (lower-panel-grid-body), splicing its
;; authored children into the enclosing group's FLAT dispatch children
;; and deriving a display panel clause from its shape
;; (panel-clause). Splice nodes SURVIVE among its children
;; (dsl-purification-k9; dispatch-children expands them at read time,
;; and the configuration merge hoists any tree they carry). Partitioning
;; looks at the splice-EXPANDED view, so a block or atom inside a splice
;; counts: at most one embedded live-list block, which stays IN the
;; children as a dispatch atom (its hidden digit key-range expands at
;; dispatch read time — fsm.sld dispatch-children) and rides under
;; 'list for hook composition + the display's block reference. Nested
;; panels reject: a panel groups ROWS; there is no grid-in-grid. SPAN is
;; the explicit 'span value, or #f to default — 'narrow, auto-'wide when
;; a list block is present. ORDER is the explicit row-ordering mode
;; ('keys | 'declared), or #f when unauthored — stored only when given so
;; its ABSENCE means "inherit the screen/open default" (manual-panel-order-k24).
(define (make-panel-node label span order children)
  (let* ((expanded (expand-splices children))
         (blocks   (filter block-spec? expanded)))
    (when (and (pair? blocks) (pair? (cdr blocks)))
      (error "panel: at most one embedded live-list block per panel" label))
    (when (pair? (filter panel-spec? expanded))
      (error "panel: panels cannot nest — a panel groups rows" label))
    (let* ((block (and (pair? blocks) (car blocks)))
           (span* (or span (if block 'wide 'narrow)))
           (base (list (cons 'kind 'panel-spec)
                       (cons 'label label)
                       (cons 'span span*)
                       (cons 'children children)))
           (base (if order (append base (list (cons 'order order))) base)))
      (if block
        (append base (list (cons 'list block)))
        base))))

;; A construction-time (panel …) record — recognisable so screen / open
;; can consume it wherever it appears in a body, including inside a
;; splice's expanded view. Never survives into a node's children.
(define (panel-spec? x)
  (and (pair? x) (pair? (car x))
       (let ((kind (assoc 'kind x)))
         (and kind (eq? (cdr kind) 'panel-spec)))))

;; (panel "label" ['span 'narrow|'wide|'full] ['order 'keys|'declared] child…)
;; → panel-spec (consumed by the enclosing screen / open — see
;; make-panel-node). Default span 'narrow; auto-'wide when a live-list block is
;; embedded and no explicit 'span is given. 'order ('keys | 'declared) opts the
;; panel's rows out of (or back into) key-sorting; omitted, the panel inherits
;; the enclosing screen/open default (manual-panel-order-k24). Children are
;; dispatch atoms plus at most one live-list block; splices (walk / splice)
;; survive as data and expand at dispatch read time. A leading bare symbol is
;; a keyword ('span / 'order); the first non-symbol begins the children.
(define (panel label . rest)
  (let loop ((args rest) (span #f) (order #f))
    (cond
      ((and (pair? args) (eq? (car args) 'span) (pair? (cdr args)))
       ;; Validate through the bare clause constructor — one home for
       ;; the rule (display-dsl), immediate error at the (panel …) form.
       (loop (cddr args) (cdr (d:span (cadr args))) order))
      ((and (pair? args) (eq? (car args) 'order) (pair? (cdr args)))
       (loop (cddr args) span (cdr (d:order (cadr args)))))
      ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
       (error "panel: unknown keyword" (car args)))
      (else
       (make-panel-node label span order args)))))

;; Flatten every panel-spec in ITEMS into its authored children, in
;; place — the construction-time step that keeps a node's children FLAT
;; (ADR-0011): a panel contributes its rows and its block atom to the
;; enclosing group's dispatch children; only the display value remembers
;; the grouping. Splice nodes pass through UNTOUCHED unless their
;; subtree carries a panel (screen-level panel reuse): identity is
;; preserved for the common case so the configuration merge's
;; carried-tree dedup (eq? on a walk's hoisted tree) still sees the very
;; same splice value from every site; a panel-bearing splice is rebuilt
;; with the panels flattened inside it, its other entries — notably a
;; carried 'tree — kept by reference.
(define (flatten-panel-specs items)
  (let loop ((rest items) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((panel-spec? (car rest))
       (loop (cdr rest)
             (append (reverse (flatten-panel-specs (node-children (car rest)))) acc)))
      ((and (splice? (car rest)) (subtree-carries-panel? (car rest)))
       (let ((rebuilt (map (lambda (e)
                             (if (eq? (car e) 'children)
                               (cons 'children (flatten-panel-specs (cdr e)))
                               e))
                           (car rest))))
         (loop (cdr rest) (cons rebuilt acc))))
      (else (loop (cdr rest) (cons (car rest) acc))))))

(define (subtree-carries-panel? sp)
  (let loop ((rest (node-children sp)))
    (cond
      ((null? rest) #f)
      ((panel-spec? (car rest)) #t)
      ((and (splice? (car rest)) (subtree-carries-panel? (car rest))) #t)
      (else (loop (cdr rest))))))

;; Lower a panel-grid body — the shared core of screen / open. Returns a
;; (children loose-region panels) list:
;;   • children      — the FLAT dispatch children of the screen/open
;;                     group, in declaration order: the authored body
;;                     with every panel-spec flattened into its rows
;;                     (flatten-panel-specs) — splice nodes SURVIVE in
;;                     place (dsl-purification-k9), so the merge can
;;                     hoist their carried trees, and block-specs stay
;;                     as dispatch atoms (their hidden digit keys expand
;;                     at read time — fsm.sld dispatch-children, and
;;                     their hook fns fire structurally from the
;;                     children — fsm.sld run-on-enter/run-on-leave).
;;   • loose-region  — the ordered loose region the renderer draws BARE above
;;                     the panel grid, computed over the splice-EXPANDED view
;;                     (a spliced walk's entry keys land here exactly as if
;;                     authored inline): each item is a loose node (a loose
;;                     atom, or a folded top-level `open` → a drill row) or a
;;                     loose block-spec (a diagram / live-list → a bare
;;                     block). Declaration order is preserved so blocks and
;;                     rows interleave as authored. No "General" panel is
;;                     created.
;;   • panels        — the body's panel-specs, splice-expanded view, grid
;;                     order — what display-clauses derives the display
;;                     value's panel clauses from.
;; An `open` declared INSIDE a panel rides that panel's flattened
;; children (an accent group-row via the display's key ref), untouched.
;; Only loose atoms, top-level opens, and loose blocks land in the loose
;; region.
(define (lower-panel-grid-body body)
  (let* ((expanded     (expand-splices body))
         (panels       (filter panel-spec? expanded))
         (loose-region (remove panel-spec? expanded))
         (children     (flatten-panel-specs body)))
    (list children loose-region panels)))

;; ─── The sugar's compile-to-bare step (ADR-0011/0012) ────────────
;;
;; screen / open build their display values THROUGH the bare clause
;; constructors and attach via d:with-display — the whole of the
;; sugar's display story is this translation, pinned by the sugar≡bare
;; equivalence test (DisplayDslTests). The display value references
;; rows BY KEY and blocks BY ID, never holding node copies, so
;; substituting it cannot change the live key set.

;; One loose-region item as a bare ref argument: a node by its binding
;; key string, a block-spec by its (block ID) ref.
(define (loose-ref-argument item)
  (if (block-spec? item)
    (d:block (d:block-ref-id item))
    (node-key item)))

;; (panel-clause ps) → the display value's panel clause for one
;; construction-time panel-spec, built through the bare constructor:
;; label / resolved span / explicit 'order (absence inherits the grid
;; default) / rows as key-ref strings over the splice-expanded
;; children, with the embedded block's ref landing after the row refs —
;; matching the rendered structure (rows, then list).
(define (panel-clause ps)
  (let* ((block (let ((e (assoc 'list ps))) (and e (cdr e))))
         (kids  (expand-splices (node-children ps)))
         (args  (append
                  (list (d:span (cdr (assoc 'span ps))))
                  (let ((e (assoc 'order ps)))
                    (if e (list (d:order (cdr e))) '()))
                  (filter-map
                    (lambda (c) (and (not (block-spec? c)) (node-key c)))
                    kids)
                  (if block (list (d:block (d:block-ref-id block))) '()))))
    (apply d:panel (node-label-raw ps) args)))

;; A headerless panel stores (label . #f); node-label coerces absent to
;; "", so read the raw entry — the display value keeps #f (headerless)
;; distinct from "" for the renderer.
(define (node-label-raw node)
  (let ((e (assoc 'label node)))
    (and e (cdr e))))

;; (display-clauses display-name cols layout order embed loose-region
;;  panels) → the screen/open display value as a list of bare clauses,
;; ready for d:with-display: each authored keyword becomes its clause,
;; the loose region becomes refs preserving the authored interleaving,
;; the panel-specs become panel clauses. Reference-id uniqueness and
;; ref resolution are with-display's own validation — the sugar adds
;; nothing.
(define (display-clauses display-name cols layout order embed loose-region panels)
  (append
    (if display-name (list (d:display-name display-name)) '())
    (if cols         (list (d:cols cols))                 '())
    (if layout       (list (d:layout layout))             '())
    (if order        (list (d:order order))               '())
    (if embed        (list (apply d:embed embed))         '())
    (if (null? loose-region)
      '()
      (list (apply d:loose (map loose-ref-argument loose-region))))
    (map panel-clause panels)))

;; Assemble the leading keyword/value head of dispatch-side keywords
;; shared by screen and open. Hooks ride RAW: a block child's hook fns
;; are never composed here — run-on-enter/run-on-leave (fsm.sld) fire
;; them structurally from the children, so the bare surface behaves
;; identically (display-dsl-surface-k23).
;; PROVIDER (a procedure, or #f) is an FSM edge provider (see `group`'s
;; docstring) riding straight through to the registered root's/group's
;; 'provider slot. Both callers — `screen` and `open` — pass it
;; identically (provider-state-id-k9 wired `open`'s).
;; ENTRY / EXIT (procedures, or #f) are the unconditional action-slot
;; pair (CONTEXT.md "Action slots") — blocks are presentation, so their
;; hook fns fire only with the gated show/hide pair, never on
;; entry/exit (see `group`'s docstring).
(define (dispatch-head on-enter on-leave exit-unk provider entry exit)
  (append
    (if on-enter (list 'on-enter on-enter)         '())
    (if on-leave (list 'on-leave on-leave)         '())
    (if exit-unk (list 'exit-on-unknown exit-unk)  '())
    (if provider (list 'provider provider)         '())
    (if entry    (list 'entry entry)               '())
    (if exit     (list 'exit exit)                 '())))

;; (screen 'scope [keywords…] panel…) → a (tree 'scope node) contribution
;; (ADR-0018) for the configuration merge — pure: nothing installs until
;; the config's own handoff. Body is an implicit grid of panels; loose
;; top-level atoms,
;; folded top-level opens, and loose top-level blocks render BARE above the
;; grid (the loose region — no "General" panel). Keywords mirror
;; tree-root (on-enter / on-leave / display-name / exit-on-unknown)
;; plus 'cols N — the authored column count (default CSS-intrinsic
;; auto-fit, resolved in the renderer leaf) — 'layout ('masonry | 'grid) —
;; the panel-packing mode (default 'masonry: shortest-lane packing; 'grid:
;; aligned deterministic placement) — and 'embed (a list of key strings) —
;; the display layer's per-edge embed choice (ADR-0011, CONTEXT.md
;; "Embed": each listed key edge's target renders as an in-place SECTION
;; of this node's display root, replacing its drill row; each key must
;; lower to a group child, validated by lower-node!). All of these land
;; INSIDE the root's single 'display entry (display-clauses →
;; d:with-display) — the renderer derives everything from the display
;; value's shape.
;;
;; 'provider PROC — an FSM edge provider (see `group`'s docstring), lowered
;; onto the root's own state (tree-root's 'provider
;; keyword). The natural home for a per-visit dynamic edge source declared
;; at a tree's root — e.g. the herdr entry node's jump-space targets.
;;
;; 'entry THUNK / 'exit THUNK — the unconditional action-slot pair (CONTEXT.md
;; "Action slots"), lowered onto the root's own state alongside
;; 'on-enter/'on-leave's show/hide (see `group`'s docstring for the full
;; contract — same keywords, same semantics, just at the tree root).
(define (screen scope . args)
  (let loop ((rest args)
             (on-enter #f) (on-leave #f)
             (display-name #f) (exit-unk #f) (provider #f) (cols #f) (layout #f) (order #f)
             (entry #f) (exit #f) (embed #f))
    (cond
      ((and (pair? rest) (symbol? (car rest)) (pair? (cdr rest))
            (memq (car rest) '(on-enter on-leave display-name exit-on-unknown provider cols layout order entry exit embed)))
       (case (car rest)
         ((on-enter)        (loop (cddr rest) (cadr rest) on-leave display-name exit-unk provider cols layout order entry exit embed))
         ((on-leave)        (loop (cddr rest) on-enter (cadr rest) display-name exit-unk provider cols layout order entry exit embed))
         ((display-name)    (loop (cddr rest) on-enter on-leave (cadr rest) exit-unk provider cols layout order entry exit embed))
         ((exit-on-unknown) (loop (cddr rest) on-enter on-leave display-name (cadr rest) provider cols layout order entry exit embed))
         ((provider)        (loop (cddr rest) on-enter on-leave display-name exit-unk (cadr rest) cols layout order entry exit embed))
         ((cols)            (loop (cddr rest) on-enter on-leave display-name exit-unk provider (cadr rest) layout order entry exit embed))
         ((entry)           (loop (cddr rest) on-enter on-leave display-name exit-unk provider cols layout order (cadr rest) exit embed))
         ((exit)            (loop (cddr rest) on-enter on-leave display-name exit-unk provider cols layout order entry (cadr rest) embed))
         ((layout)          (loop (cddr rest) on-enter on-leave display-name exit-unk provider cols (cadr rest) order entry exit embed))
         ((order)           (loop (cddr rest) on-enter on-leave display-name exit-unk provider cols layout (cadr rest) entry exit embed))
         ((embed)           (loop (cddr rest) on-enter on-leave display-name exit-unk provider cols layout order entry exit (cadr rest)))))
      (else
       ;; Keyword values validate in the d: clause constructors
       ;; (display-clauses) — one home for each rule, still an error at
       ;; this (screen …) call.
       (let* ((lowered  (lower-panel-grid-body rest))
              (children (car lowered))
              (loose    (cadr lowered))
              (panels   (caddr lowered))
              (head     (dispatch-head on-enter on-leave exit-unk
                                       provider entry exit))
              (root     (apply tree-root scope (append head children)))
              (root     (apply d:with-display root
                               (display-clauses display-name cols layout
                                                order embed loose panels))))
         (tree scope root))))))

;; (open KEY LABEL [keywords…] panel…) → a navigable group drilling into a
;; sub-screen — the panel-native replacement for the old (key K L (overlay …))
;; idiom. Its children are the flat lowered sub-grid; its display value
;; carries the panel clauses (+ 'cols / 'layout / 'embed). Keywords:
;; on-enter / on-leave / exit-on-unknown / provider / cols / layout /
;; order / entry / exit / embed — not 'display-name, which is a
;; breadcrumb-root override that a child group (vs. a registered tree
;; root) has no use for. 'entry/'exit (the unconditional action-slot pair
;; — see `group`'s docstring) ride straight through to `group`, same as
;; on-enter/on-leave, and so does 'provider (an FSM edge provider — see
;; `group`'s docstring again), landing on the group's own 'provider slot
;; exactly as `screen` threads one onto a tree root. A sub-drill whose
;; content is per-Visit dynamic — paneru's Strip listing is the first —
;; declares it here rather than dropping to the bare `group` form
;; (provider-state-id-k9; before it, `open` dropped the slot).
(define (open key label . args)
  (let loop ((rest args)
             (on-enter #f) (on-leave #f) (exit-unk #f) (provider #f)
             (cols #f) (layout #f) (order #f)
             (entry #f) (exit #f) (embed #f))
    (cond
      ((and (pair? rest) (symbol? (car rest)) (pair? (cdr rest))
            (memq (car rest) '(on-enter on-leave exit-on-unknown provider cols layout order entry exit embed)))
       (case (car rest)
         ((on-enter)        (loop (cddr rest) (cadr rest) on-leave exit-unk provider cols layout order entry exit embed))
         ((on-leave)        (loop (cddr rest) on-enter (cadr rest) exit-unk provider cols layout order entry exit embed))
         ((exit-on-unknown) (loop (cddr rest) on-enter on-leave (cadr rest) provider cols layout order entry exit embed))
         ((provider)        (loop (cddr rest) on-enter on-leave exit-unk (cadr rest) cols layout order entry exit embed))
         ((cols)            (loop (cddr rest) on-enter on-leave exit-unk provider (cadr rest) layout order entry exit embed))
         ((entry)           (loop (cddr rest) on-enter on-leave exit-unk provider cols layout order (cadr rest) exit embed))
         ((exit)            (loop (cddr rest) on-enter on-leave exit-unk provider cols layout order entry (cadr rest) embed))
         ((layout)          (loop (cddr rest) on-enter on-leave exit-unk provider cols (cadr rest) order entry exit embed))
         ((order)           (loop (cddr rest) on-enter on-leave exit-unk provider cols layout (cadr rest) entry exit embed))
         ((embed)           (loop (cddr rest) on-enter on-leave exit-unk provider cols layout order entry exit (cadr rest)))))
      (else
       ;; Keyword values validate in the d: clause constructors, as in
       ;; `screen`.
       (let* ((lowered  (lower-panel-grid-body rest))
              (children (car lowered))
              (loose    (cadr lowered))
              (panels   (caddr lowered))
              (head     (dispatch-head on-enter on-leave exit-unk
                                       provider entry exit)))
         (apply d:with-display
                (apply group key label (append head children))
                (display-clauses #f cols layout order embed
                                 loose panels)))))))

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

)) ;; end begin / define-library
