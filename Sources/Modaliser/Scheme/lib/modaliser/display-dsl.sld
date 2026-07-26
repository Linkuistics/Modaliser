;; (modaliser display-dsl) — the Display value model (ADR-0011).
;;
;; A node's DISPLAY VALUE is one pure alist attached under the node's
;; single 'display entry (CONTEXT.md "Display value"), saying how the
;; node renders. It references the node's own rows BY KEY and its
;; live-list blocks BY ID — never holding node copies — so dispatch
;; structure and display stay disjoint: substituting a display value
;; structurally cannot change the live key set.
;;
;; The display value's shape (every entry optional; canonical order):
;;
;;   ((display-name . STR)          breadcrumb override (tree roots)
;;    (cols . N)                    authored column count
;;    (layout . masonry|grid)       panel-packing mode
;;    (order . keys|declared)       grid-wide row-order default
;;    (embed . (KEY …))             per-edge embed choice, key strings
;;    (loose . (REF …))             the loose region, ordered refs
;;    (panels . (PANEL …)))         the panel grid, grid order
;;
;;   PANEL = ((label . STR|#f)      #f = headerless
;;            (span . narrow|wide|full)
;;            (order . keys|declared)   only when explicitly authored —
;;                                      absence inherits the grid default
;;            (rows . (REF …)))     ordered refs; at most one block ref
;;   REF   = (key . "c")           a dispatch row, by its binding key
;;         | (block . ID)          a block, by reference id (block-ref-id)
;;
;; An EMPTY display value ('()) and an absent one render identically —
;; every child loose, in declaration order — so "no display" needs no
;; separate representation (fsm.sld node-display returns '() for both).
;;
;; This library owns BOTH halves of the display layer:
;;
;;   • the pure resolution seam (docs/specs/configuration-value.md
;;     "Test seams"): resolve-display turns (children, display value)
;;     into a RENDER PLAN the overlay only serializes;
;;   • the BARE AUTHORING SURFACE (ADR-0011): the clause constructors
;;     (panel / block / span / order / cols / layout / embed /
;;     display-name / loose) build printable clause data, and
;;     with-display assembles them into the canonical display value and
;;     attaches it to a dispatch node. The sugar (dsl.sld
;;     screen/panel/open) compiles onto these same constructors — the
;;     sugar≡bare equivalence test (DisplayDslTests) pins it as a
;;     veneer.
;;
;; `panel` deliberately shares its name with the sugar's panel form:
;; configs author through ONE surface at a time, so the bare surface is
;; imported prefixed — (import (prefix (modaliser display-dsl) d:)) —
;; alongside an unprefixed (modaliser dsl).
;;
;; Portable: imports only (scheme …) and (modaliser …).

(define-library (modaliser display-dsl)
  (export block-ref-id
          resolve-display
          ;; The canonical row-key sort ("a A b B …"), shared with the
          ;; overlay's list-renderer path so the two can never disagree.
          sort-rows
          ;; The bare authoring surface (display-dsl-surface-k23).
          with-display
          panel block loose
          span order cols layout embed display-name)
  (import (scheme base)
          (scheme char)
          (modaliser util)
          ;; Node-model helpers only — the display layer reads dispatch
          ;; structure (children, the display entry) but never the
          ;; engine.
          (only (modaliser fsm)
                node-key group? expand-splices
                node-children node-display node-with-display))
  (begin

;; A live-list / diagram block-spec carries 'type; a node-form carries
;; 'kind. Mirrors dsl.sld's private block-spec? — the shape is the
;; contract (ui/overlay.scm loose-block? re-tests it the same way).
(define (block-spec? x)
  (and (pair? x) (pair? (car x)) (assoc 'type x) #t))

;; (block-ref-id block-spec) → symbol
;;
;; The id a display value references a block by: the block's explicit
;; 'id entry when present, else its 'type. Blocks have no binding key,
;; so this is their whole reference identity; a screen embedding two
;; same-type blocks must give at least one an explicit 'id — duplicate
;; ids are a construction-time error (dsl.sld) and an ambiguity error
;; here at resolve time.
(define (block-ref-id block)
  (let ((id (assoc 'id block)))
    (if id (cdr id) (cdr (assoc 'type block)))))

(define (key-ref? r)   (and (pair? r) (eq? (car r) 'key)))
(define (block-ref? r) (and (pair? r) (eq? (car r) 'block)))

;; Sparse-alist read: #f when the entry is absent.
(define (display-entry display k)
  (let ((e (assoc k display)))
    (and e (cdr e))))

;; ─── Row ordering ────────────────────────────────────────────────
;;
;; The canonical row-key sort: case-insensitive on the primary,
;; lowercase before its own uppercase on the tiebreak, so mixed-case
;; rows read "a A b B …". Exported — the overlay's list-renderer path
;; sorts through this same procedure (its former private copy retired
;; at the readers cutover).
(define (row-key-lt? a b)
  (let* ((a (or a ""))
         (b (or b ""))
         (la (string-downcase a))
         (lb (string-downcase b)))
    (cond
      ((string<? la lb) #t)
      ((string<? lb la) #f)
      (else (string>? a b)))))

(define (sort-rows rows)
  (define (insert item sorted)
    (cond
      ((null? sorted) (list item))
      ((row-key-lt? (node-key item) (node-key (car sorted)))
       (cons item sorted))
      (else (cons (car sorted) (insert item (cdr sorted))))))
  (let loop ((rest rows) (sorted '()))
    (if (null? rest)
      sorted
      (loop (cdr rest) (insert (car rest) sorted)))))

;; ─── Reference resolution ────────────────────────────────────────
;;
;; Refs resolve one level deep, against the node's own (splice-expanded)
;; children. Dangling refs error: display references are validated at
;; lowering like every authored reference (docs/specs/
;; configuration-value.md "Lowering and validation"), so an unresolved
;; ref reaching this pure function is a structural bug, never runtime
;; weather — children are static data (gates remove edges, not rows).

(define (resolve-key-ref k rows)
  (or (find (lambda (n) (equal? (node-key n) k)) rows)
      (error "resolve-display: (key . …) ref names no child row" k)))

(define (resolve-block-ref id blocks)
  (let ((hits (filter (lambda (b) (eq? (block-ref-id b) id)) blocks)))
    (cond
      ((null? hits)
       (error "resolve-display: (block . …) ref names no child block" id))
      ((pair? (cdr hits))
       (error "resolve-display: ambiguous block id — give one block an explicit 'id entry" id))
      (else (car hits)))))

(define (resolve-ref r rows blocks)
  (cond
    ((key-ref? r)   (resolve-key-ref (cdr r) rows))
    ((block-ref? r) (resolve-block-ref (cdr r) blocks))
    (else (error "resolve-display: unknown display ref shape" r))))

;; ─── resolve-display ─────────────────────────────────────────────
;;
;; (resolve-display children display) → render plan (pure)
;;
;; CHILDREN is a node's flat children list — dispatch rows and
;; block-spec atoms, splices expanded transparently (they survive
;; construction as data). DISPLAY is the node's display value as above.
;; The RENDER PLAN is what the overlay serializes, resolution logic
;; exhausted — a total alist (every entry present, #f/() when empty):
;;
;;   ((loose    . (ITEM …))        resolved rows / block-specs, in order
;;    (panels   . (PLAN-PANEL …))  PLAN-PANEL below
;;    (sections . ((KEY . NODE) …)) one per embed key, targets resolved
;;    (cols . N|#f) (layout . SYM|#f) (display-name . STR|#f))
;;
;;   PLAN-PANEL = ((label . STR|#f) (span . SYM)
;;                 (rows . (NODE …))    resolved row order applied:
;;                                      panel 'order > display 'order >
;;                                      'keys (key-sorted); 'declared
;;                                      preserves ref order
;;                 (list . BLOCK|#f))   the panel's one block, if any
;;
;; Semantics mirrored from the legacy render path (ui/overlay.scm),
;; which this function replaces at the readers cutover:
;;   • a row whose key is in 'embed is dropped from loose and panel
;;     rows — its target renders as a section of this display root.
;;   • the loose region is always declaration-ordered.
;;   • 'hidden filtering stays renderer-side: hidden may be a runtime
;;     thunk, and this function is pure.
;; With NO 'loose entry, the loose region defaults to every child not
;; referenced by any panel, in declaration order — so an empty display
;; renders all rows loose (ADR-0011's no-display rendering), and a
;; panels-only display cannot silently drop an unreferenced live key.
;; An explicit 'loose entry states the loose region exactly.
(define (resolve-display children display)
  (let* ((expanded   (expand-splices children))
         (rows       (remove block-spec? expanded))
         (blocks     (filter block-spec? expanded))
         (embed-keys (or (display-entry display 'embed) '()))
         (panels     (or (display-entry display 'panels) '()))
         (grid-order (display-entry display 'order))
         (loose-e    (assoc 'loose display))
         (loose      (if loose-e
                       (resolve-loose (cdr loose-e) rows blocks embed-keys)
                       (fallback-loose expanded panels embed-keys))))
    (list
      (cons 'loose loose)
      (cons 'panels
            (map (lambda (p) (resolve-panel p rows blocks grid-order embed-keys))
                 panels))
      (cons 'sections (resolve-sections embed-keys rows))
      (cons 'cols (display-entry display 'cols))
      (cons 'layout (display-entry display 'layout))
      (cons 'display-name (display-entry display 'display-name)))))

;; An explicit loose ref list: resolve each ref, dropping rows whose key
;; the display embeds (the section replaces the drill row). Order is the
;; ref order — the loose region is always declaration-ordered.
(define (resolve-loose refs rows blocks embed-keys)
  (filter-map
    (lambda (r)
      (let ((item (resolve-ref r rows blocks)))
        (if (and (key-ref? r) (member (cdr r) embed-keys))
          #f
          item)))
    refs))

;; No 'loose entry: the loose region is every child no panel references,
;; in declaration order (blocks included — an unplaced block renders
;; bare, exactly as a display-less tree renders everything).
(define (fallback-loose expanded panels embed-keys)
  (let* ((refs (apply append (map (lambda (p) (cdr (assoc 'rows p))) panels)))
         (pkeys (filter-map (lambda (r) (and (key-ref? r) (cdr r))) refs))
         (pblks (filter-map (lambda (r) (and (block-ref? r) (cdr r))) refs)))
    (filter
      (lambda (item)
        (if (block-spec? item)
          (not (memq (block-ref-id item) pblks))
          (let ((k (node-key item)))
            (and (not (member k pkeys))
                 (not (member k embed-keys))))))
      expanded)))

;; One display panel: resolve its refs, partition the (at most one)
;; block out of the rows, apply the resolved row order. The partition
;; reproduces the rendered structure (rows, then the block) whatever
;; the authored interleaving.
(define (resolve-panel p rows blocks grid-order embed-keys)
  (let* ((label   (cdr (assoc 'label p)))
         (span    (cdr (assoc 'span p)))
         (order   (or (let ((e (assoc 'order p))) (and e (cdr e)))
                      grid-order
                      'keys))
         (items   (map (lambda (r) (resolve-ref r rows blocks))
                       (cdr (assoc 'rows p))))
         (prows   (remove (lambda (i)
                            (or (block-spec? i)
                                (member (node-key i) embed-keys)))
                          items))
         (pblocks (filter block-spec? items)))
    (when (and (pair? pblocks) (pair? (cdr pblocks)))
      (error "resolve-display: at most one block ref per panel" label))
    (list
      (cons 'label label)
      (cons 'span span)
      (cons 'rows (if (eq? order 'declared) prows (sort-rows prows)))
      (cons 'list (if (pair? pblocks) (car pblocks) #f)))))

;; One (KEY . TARGET) pair per embed key, in embed-list order. An embed
;; key must name a group child — the same load-time contract lower-node!
;; enforces (a section is an intra-tree drill target rendered in place).
(define (resolve-sections embed-keys rows)
  (map
    (lambda (k)
      (let ((target (find (lambda (n) (equal? (node-key n) k)) rows)))
        (unless (and target (group? target))
          (error "resolve-display: 'embed key does not name a group child" k))
        (cons k target)))
    embed-keys))

;; ─── The bare clause constructors (display-dsl-surface-k23) ──────
;;
;; The canonical authoring surface: each constructor validates its value
;; and returns one CLAUSE — plain printable data, exactly the alist
;; entry (or panel alist) that lands in the display value — and
;; with-display assembles clauses into the canonical value and attaches
;; it. Where a clause takes row references, a STRING names a dispatch
;; row by its binding key and a (block ID) clause names a block child by
;; its reference id (block-ref-id above).

(define (display-name s)
  (unless (string? s)
    (error "display-name: expected a string" s))
  (cons 'display-name s))

(define (cols n)
  (unless (and (exact-integer? n) (positive? n))
    (error "cols: expected a positive exact integer" n))
  (cons 'cols n))

(define (layout l)
  (unless (memq l '(masonry grid))
    (error "layout: expected 'masonry or 'grid" l))
  (cons 'layout l))

(define (order o)
  (unless (memq o '(keys declared))
    (error "order: expected 'keys or 'declared" o))
  (cons 'order o))

(define (span s)
  (unless (memq s '(narrow wide full))
    (error "span: expected 'narrow, 'wide or 'full" s))
  (cons 'span s))

(define (embed . keys)
  (for-each
    (lambda (k)
      (unless (string? k)
        (error "embed: expected key strings" k)))
    keys)
  (cons 'embed keys))

(define (block id)
  (unless (symbol? id)
    (error "block: expected a reference id symbol (the block's 'id entry, defaulting to its 'type)" id))
  (cons 'block id))

;; One row-reference argument: a key string or a (block ID) clause.
(define (ref-argument->ref x who)
  (cond
    ((string? x) (cons 'key x))
    ((block-ref? x) x)
    (else (error (string-append who ": expected a key string or (block ID) ref") x))))

(define (loose . args)
  (cons 'loose (map (lambda (x) (ref-argument->ref x "loose")) args)))

(define (span-clause? x)  (and (pair? x) (eq? (car x) 'span)))
(define (order-clause? x) (and (pair? x) (eq? (car x) 'order)))

;; (panel LABEL [CLAUSE|REF]…) → one panel clause of the 'panels list:
;; ((label . STR|#f) (span . SYM) [(order . SYM)] (rows . (REF …))).
;; LABEL #f is headerless. Args mix (span …)/(order …) clauses (at most
;; one each, position-free) with row refs in row order. Span defaults
;; 'narrow, auto-'wide when a block ref is present (the sugar resolves
;; its span at panel-spec construction and passes it explicitly, so the
;; two defaulting sites cannot disagree on sugar output); an explicit
;; 'order is stored only when authored — absence inherits the grid
;; default at resolve time. At most one block ref per panel (the
;; rendered structure is rows, then the one list).
(define (panel label . args)
  (unless (or (string? label) (eq? label #f))
    (error "panel: label must be a string, or #f for headerless" label))
  (let loop ((rest args) (span* #f) (order* #f) (refs '()))
    (cond
      ((null? rest)
       (let* ((refs (reverse refs))
              (block-refs (filter block-ref? refs)))
         (when (and (pair? block-refs) (pair? (cdr block-refs)))
           (error "panel: at most one block ref per panel" label))
         (append
           (list (cons 'label label)
                 (cons 'span (or span* (if (pair? block-refs) 'wide 'narrow))))
           (if order* (list (cons 'order order*)) '())
           (list (cons 'rows refs)))))
      ((span-clause? (car rest))
       (when span* (error "panel: duplicate span clause" label))
       (loop (cdr rest) (cdar rest) order* refs))
      ((order-clause? (car rest))
       (when order* (error "panel: duplicate order clause" label))
       (loop (cdr rest) span* (cdar rest) refs))
      (else
       (loop (cdr rest) span* order*
             (cons (ref-argument->ref (car rest) "panel") refs))))))

;; ─── with-display ────────────────────────────────────────────────

;; A panel clause is the one clause shape whose car is itself a pair —
;; the constructor-built alist always leads with its 'label entry.
(define (panel-clause? x)
  (and (pair? x) (pair? (car x)) (eq? (caar x) 'label)))

(define top-level-clause-keys
  '(display-name cols layout order embed loose))

;; (with-display NODE CLAUSE…) → NODE with the assembled display value
;; attached as its single 'display entry (ADR-0011; pure). Clause order
;; is free — assembly is always canonical (display-name, cols, layout,
;; order, embed, loose, panels) — and panel clauses accumulate in given
;; order. Zero clauses attach nothing ('() ≡ absent — node-display).
;; Attaching is ONE explicit step: a node already carrying a display
;; value rejects (state 'order via the clause here, not tree-root's
;; keyword; node-with-display (modaliser fsm) is the raw wholesale
;; replace when tooling needs one).
;;
;; Display references are load-time errors (docs/specs/
;; configuration-value.md "Lowering and validation") and the node is in
;; hand, so the attach validates: every ref resolves against the node's
;; own (splice-expanded) children via resolve-display; block reference
;; ids are unique across the value; and an explicit 'loose must leave no
;; child unplaced — a display may never silently drop a live row
;; (active rows ≡ live keys).
(define (with-display node . clauses)
  (let loop ((rest clauses) (entries '()) (panels '()))
    (cond
      ((null? rest)
       (let ((dv (append
                   (filter-map (lambda (k) (assq k entries))
                               top-level-clause-keys)
                   (if (null? panels)
                     '()
                     (list (cons 'panels (reverse panels)))))))
         (if (null? dv)
           node
           (begin
             (when (pair? (node-display node))
               (error "with-display: node already carries a display value — attach once (or replace via node-with-display)"
                      (node-display node)))
             (validate-display (node-children node) dv)
             (node-with-display node dv)))))
      ((panel-clause? (car rest))
       (loop (cdr rest) entries (cons (car rest) panels)))
      ((and (pair? (car rest)) (memq (caar rest) top-level-clause-keys))
       (when (assq (caar rest) entries)
         (error "with-display: duplicate clause" (caar rest)))
       (loop (cdr rest) (cons (car rest) entries) panels))
      ((span-clause? (car rest))
       (error "with-display: 'span is a panel clause — give it inside (panel …)" (car rest)))
      (else
       (error "with-display: unrecognised clause" (car rest))))))

(define (validate-display children dv)
  (resolve-display children dv)
  (check-unique-block-ids dv)
  (check-loose-coverage children dv))

;; Every (block . ID) ref across the value, loose + panel rows.
(define (display-block-ref-ids dv)
  (let ((refs (append (or (display-entry dv 'loose) '())
                      (apply append
                             (map (lambda (p) (cdr (assoc 'rows p)))
                                  (or (display-entry dv 'panels) '()))))))
    (filter-map (lambda (r) (and (block-ref? r) (cdr r))) refs)))

(define (check-unique-block-ids dv)
  (let loop ((rest (display-block-ref-ids dv)) (seen '()))
    (cond
      ((null? rest) #t)
      ((memq (car rest) seen)
       (error "with-display: two refs share one block reference id — give one block an explicit 'id entry"
              (car rest)))
      (else (loop (cdr rest) (cons (car rest) seen))))))

;; With an explicit 'loose entry the display states the whole render —
;; so every child must appear somewhere: loose, a panel's rows, or the
;; embed list. (Without one, fallback-loose collects the unreferenced
;; children, so nothing can be dropped.) Blocks count too: an unplaced
;; block's hidden digit keys would stay live with no rows shown.
(define (check-loose-coverage children dv)
  (when (assoc 'loose dv)
    (let* ((refs (append (cdr (assoc 'loose dv))
                         (apply append
                                (map (lambda (p) (cdr (assoc 'rows p)))
                                     (or (display-entry dv 'panels) '())))))
           (keys (filter-map (lambda (r) (and (key-ref? r) (cdr r))) refs))
           (ids  (filter-map (lambda (r) (and (block-ref? r) (cdr r))) refs))
           (embed-keys (or (display-entry dv 'embed) '())))
      (for-each
        (lambda (item)
          (if (block-spec? item)
            (unless (memq (block-ref-id item) ids)
              (error "with-display: explicit 'loose leaves a block unplaced — every child must be placed (loose, a panel, or embed)"
                     (block-ref-id item)))
            (let ((k (node-key item)))
              (unless (or (member k keys) (member k embed-keys))
                (error "with-display: explicit 'loose leaves a row unplaced — every child must be placed (loose, a panel, or embed)"
                       k)))))
        (expand-splices children)))))

)) ;; end begin / define-library
