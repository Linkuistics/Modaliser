;; (modaliser configuration) — the Fragment model and the pure
;; `configuration` merge (ADR-0018, docs/specs/configuration-value.md).
;;
;; Libraries export pure constructors returning Fragments — printable
;; tagged contribution bags — and user config composes them with
;; ordinary Scheme (define/let/list/append), then assembles them with
;; `configuration`: a pure merge + validation returning the single
;; Configuration value the engine installs at the one-shot handoff
;; (modaliser:start!, a later increment). Nothing in this library
;; performs effects — no registry, no engine call; data in, data out.
;;
;; A CONTRIBUTION is a tagged three-element list (<tag> <key> <value>)
;; with the tag drawn from the closed vocabulary of what a
;; configuration can contain:
;;
;;   (tree    <scope>  <node>)   — a modal screen/tree body (an
;;                                 authored-altitude node alist), keyed
;;                                 by scope symbol or bundle-id string
;;   (backend <symbol> <record>) — a terminal-backend record (host or
;;                                 mux), keyed by its backend symbol
;;   (context <exe>    <entry>)  — a Terminal-context-map entry, keyed
;;                                 by the inner tool's exe name; the
;;                                 entry alist references its tree (and
;;                                 optional backend) BY KEY — reference
;;                                 closure is checked at lowering, not
;;                                 here
;;   (setting <name>   <value>)  — one named setting
;;
;; A FRAGMENT is a list of contributions and/or nested fragments;
;; `configuration` flattens arbitrary nesting, so constructors compose
;; with plain list-building and a caller never cares whether a value
;; is one contribution or a whole bag.
;;
;; MERGE RULE — one uniform rule across all four tags: contributions
;; are keyed (tree → scope, backend → backend symbol, context → exe
;; name, setting → setting name); two contributions with the same key
;; merge silently iff their values are identical in the sense of eq?
;; — the diamond case, one fragment reached via two composition paths
;; — and error otherwise. There is no override and no last-wins;
;; customization is composition, never patching. Tree scopes authored
;; as a symbol and as a string name the same scope (the engine keys
;; trees by string), so 'global and "global" collide.
;;
;; WALK HOISTING — a node inside a tree body MAY carry a 'tree entry
;; holding (<scope> . <node>): a tree-bearing value, the shape a
;; `walk`'s splice takes — splices survive construction to the merge
;; (dsl-purification-k9). The merge walks every tree body and
;; hoists each carried tree into the tree set under its scope,
;; identity-dedup'd by the same eq? rule — the same walk spliced into
;; two screens contributes its mode tree once; a DIFFERENT tree under
;; an occupied scope errors. Hoisted bodies are walked in turn, so
;; nesting hoists transitively. Splice EXPANSION stays downstream in
;; lowering; hoisting only closes the tree set.
;;
;; DECODABLE ERRORS — every error raised here carries, as its
;; irritants, a symbolic code followed by structured details, e.g.
;; (duplicate-key tree global) or (invalid-contribution <item>), so
;; the config-error surface can present failures without parsing
;; message text.

(define-library (modaliser configuration)
  (export ;; Contribution constructors — the closed tag vocabulary.
          tree backend context setting
          ;; The context map's named grouping fragment.
          terminal-contexts
          ;; Settings constructors (each returns a setting contribution).
          leader leaders overlay-delay
          ;; The pure merge + validation.
          configuration
          ;; Configuration-value accessors.
          configuration?
          configuration-trees configuration-backends
          configuration-contexts configuration-settings
          configuration-tree-ref configuration-backend-ref
          configuration-context-ref configuration-setting-ref)
  (import (scheme base)
          (scheme cxr))
  (begin

;; ─── Contribution constructors ───────────────────────────────────────

;; (tree scope node) → tree contribution. SCOPE is the symbol or
;; bundle-id string the screen registers under; NODE is the
;; authored-altitude node alist (as built by group / screen sugar).
(define (tree scope node)
  (unless (or (symbol? scope) (string? scope))
    (error "tree: scope must be a symbol or a string"
           'invalid-tree-scope scope))
  (unless (node-alist? node)
    (error "tree: body must be a node alist"
           'invalid-tree-node scope))
  (list 'tree scope node))

;; (backend sym record) → backend contribution. SYM is the backend
;; symbol (e.g. 'iterm, 'herdr); RECORD is the terminal-backend record
;; (opaque here — this library does not depend on the terminal façade).
(define (backend sym record)
  (unless (symbol? sym)
    (error "backend: key must be a symbol" 'invalid-backend-symbol sym))
  (list 'backend sym record))

;; (context exe 'tree scope ['backend sym]) → context contribution: one
;; Terminal-context-map entry mapping the focused pane's foreground exe
;; name to the tree activation lands in, plus — for pane-op-capable
;; exes (muxes) — the backend that drives its panes. Both are
;; references by key; the tree/backend contributions themselves travel
;; in the same fragment, and reference closure is validated at
;; lowering.
(define (context exe . opts)
  (unless (string? exe)
    (error "context: exe must be a string" 'invalid-context-exe exe))
  (let loop ((rest opts) (tree-key #f) (backend-key #f))
    (cond
      ((null? rest)
       (unless tree-key
         (error "context: missing required 'tree <scope>"
                'invalid-context-entry exe))
       (list 'context exe
             (append (list (cons 'tree tree-key))
                     (if backend-key
                       (list (cons 'backend backend-key))
                       '()))))
      ((or (null? (cdr rest)) (not (symbol? (car rest))))
       (error "context: expected keyword/value pairs"
              'invalid-context-entry exe))
      ((eq? (car rest) 'tree)    (loop (cddr rest) (cadr rest) backend-key))
      ((eq? (car rest) 'backend) (loop (cddr rest) tree-key (cadr rest)))
      (else
       (error "context: unknown keyword"
              'invalid-context-entry (car rest))))))

;; (setting name value) → setting contribution. The named settings
;; constructors below are sugar over this; unset settings fall to
;; engine defaults at the handoff.
(define (setting name value)
  (unless (symbol? name)
    (error "setting: name must be a symbol" 'invalid-setting-name name))
  (list 'setting name value))

;; (terminal-contexts item …) → a fragment: the named authoring surface
;; for the Terminal context map, assembled from the inner tools' wiring
;; constructors —
;;
;;   (terminal-contexts (herdr:wiring) (nvim:wiring))
;;
;; Pure grouping sugar: fragments already nest and concatenate, so this
;; returns exactly its arguments as one fragment and the merge flattens
;; and keys the entries as ever. It exists so a composition READS as
;; "the context map" rather than as an anonymous list.
(define (terminal-contexts . items) items)

;; ─── Settings constructors ───────────────────────────────────────────

;; (leader mode keycode ['modifiers syms] ['arm-when-frontmost ids])
;; → one leader spec (a plain alist), authored-altitude: modifiers stay
;; symbols; mask conversion is the engine's business at arming.
(define (leader mode keycode . opts)
  (unless (memq mode '(global local))
    (error "leader: mode must be 'global or 'local"
           'invalid-leader-mode mode))
  (unless (and (integer? keycode) (exact? keycode) (>= keycode 0))
    (error "leader: keycode must be a non-negative exact integer"
           'invalid-leader-keycode keycode))
  (let loop ((rest opts) (modifiers '()) (arm '()))
    (cond
      ((null? rest)
       (list (cons 'mode mode)
             (cons 'keycode keycode)
             (cons 'modifiers modifiers)
             (cons 'arm-when-frontmost arm)))
      ((or (null? (cdr rest)) (not (symbol? (car rest))))
       (error "leader: expected keyword/value pairs"
              'invalid-leader-spec rest))
      ((eq? (car rest) 'modifiers)
       (loop (cddr rest) (cadr rest) arm))
      ((eq? (car rest) 'arm-when-frontmost)
       (loop (cddr rest) modifiers (cadr rest)))
      (else
       (error "leader: unknown keyword" 'invalid-leader-spec (car rest))))))

;; (leaders spec …) → the 'leaders setting: the full leader
;; configuration as one contribution, so a second (leaders …) anywhere
;; in the composition is a same-key conflict — arming happens once,
;; from one value.
(define (leaders . specs)
  (for-each
    (lambda (s)
      (unless (and (pair? s) (pair? (car s)) (assq 'mode s) (assq 'keycode s))
        (error "leaders: each argument must be a (leader …) spec"
               'invalid-leader-spec s)))
    specs)
  (setting 'leaders specs))

;; (overlay-delay seconds) → the 'overlay-delay setting. 0 shows the
;; overlay immediately; typical values are 0.3–1.0 seconds.
(define (overlay-delay seconds)
  (unless (and (real? seconds) (>= seconds 0))
    (error "overlay-delay: seconds must be a non-negative number"
           'invalid-overlay-delay seconds))
  (setting 'overlay-delay seconds))

;; There is deliberately no `theme` constructor: theming is CSS, not a
;; setting. All visuals come from the cascade, and user overrides live in
;; ~/.config/modaliser/theme.css (docs/reference/theming.md) — so a theme
;; setting would put one preference in two homes with nothing reading
;; either. A named settings constructor earns its name by validating its
;; argument or by being read at the handoff; `theme` did neither, which
;; is why it went. `(setting 'theme …)` remains available as the general
;; escape hatch for carrying an opaque value.

;; ─── The merge ───────────────────────────────────────────────────────

;; A node alist: a non-empty list of pairs. The loosest shape check
;; that still rejects obvious misuse (a procedure, a bare symbol).
(define (node-alist? x)
  (and (pair? x) (pair? (car x))))

(define contribution-tags '(tree backend context setting))

(define (contribution? x)
  (and (pair? x)
       (symbol? (car x))
       (memq (car x) contribution-tags)
       (pair? (cdr x))
       (pair? (cddr x))
       (null? (cdddr x))))

;; Flatten a mix of contributions and arbitrarily nested fragments
;; into one ordered contribution list. A contribution's head is a tag
;; symbol; a fragment's head is itself a pair (or the fragment is
;; empty) — that structural difference is the whole discrimination.
(define (flatten-fragments items)
  (let loop ((rest items) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      (else
       (let ((item (car rest)))
         (cond
           ((contribution? item)
            (loop (cdr rest) (cons item acc)))
           ((null? item)                       ; empty fragment
            (loop (cdr rest) acc))
           ((and (pair? item)
                 (or (pair? (car item)) (null? (car item))))
            ;; A nested fragment: splice its items in place.
            (loop (append item (cdr rest)) acc))
           (else
            (error "configuration: not a contribution or fragment"
                   'invalid-contribution item))))))))

;; Key normalization: a tree scope authored as a symbol names the same
;; scope as its string spelling (the engine keys trees by string).
;; Other tags' keys compare as written.
(define (normalize-key tag key)
  (if (and (eq? tag 'tree) (symbol? key))
    (symbol->string key)
    key))

(define (bucket-find tag bucket key)
  (let ((norm (normalize-key tag key)))
    (let loop ((rest bucket))
      (cond
        ((null? rest) #f)
        ((equal? norm (normalize-key tag (car (car rest)))) (car rest))
        (else (loop (cdr rest)))))))

;; Add (key . value) to a bucket under the uniform merge rule: absent
;; key adds; same key with an eq?-identical value merges silently (the
;; diamond); same key with a different value errors. Buckets are
;; reverse-accumulated.
(define (bucket-add tag bucket key value)
  (let ((existing (bucket-find tag bucket key)))
    (cond
      ((not existing) (cons (cons key value) bucket))
      ((eq? (cdr existing) value) bucket)
      (else
       (error "configuration: conflicting contributions share a key"
              'duplicate-key tag key)))))

;; Per-tag key-type validation, applied to every flattened
;; contribution — hand-built contributions get the same checks the
;; constructors enforce.
(define (validate-contribution c)
  (let ((tag (car c)) (key (cadr c)) (value (caddr c)))
    (case tag
      ((tree)
       (unless (or (symbol? key) (string? key))
         (error "configuration: tree scope must be a symbol or a string"
                'invalid-tree-scope key))
       (unless (node-alist? value)
         (error "configuration: tree body must be a node alist"
                'invalid-tree-node key)))
      ((backend)
       (unless (symbol? key)
         (error "configuration: backend key must be a symbol"
                'invalid-backend-symbol key)))
      ((context)
       (unless (string? key)
         (error "configuration: context exe must be a string"
                'invalid-context-exe key)))
      ((setting)
       (unless (symbol? key)
         (error "configuration: setting name must be a symbol"
                'invalid-setting-name key))))))

;; Collect the tree-bearing values carried by NODE's body: every
;; (tree . (<scope> . <node>)) entry reachable through 'children,
;; depth-first, authored order. Carried trees are collected, not
;; descended into — hoisting queues each one, so nesting hoists
;; transitively without double-walking.
(define (collect-carried-trees node)
  (letrec
    ((walk (lambda (n acc)
             (if (not (node-alist? n))
               acc
               (let* ((t   (assq 'tree n))
                      (acc (if (and t (pair? (cdr t)))
                             (cons (cdr t) acc)
                             acc))
                      (kids (assq 'children n)))
                 (if (and kids (list? (cdr kids)))
                   (let kid-loop ((rest (cdr kids)) (acc acc))
                     (if (null? rest)
                       acc
                       (kid-loop (cdr rest) (walk (car rest) acc))))
                   acc))))))
    (reverse (walk node '()))))

;; Close the tree set over carried trees: walk every tree body (the
;; contributed ones, then each newly hoisted one), merging carried
;; trees under the same key rule. BUCKET arrives and returns in
;; authored order, hoisted entries appended.
(define (hoist-embedded-trees bucket)
  (let loop ((queue (map cdr bucket)) (bucket bucket))
    (if (null? queue)
      bucket
      (let add ((found (collect-carried-trees (car queue)))
                (bucket bucket)
                (extra '()))
        (cond
          ((null? found)
           (loop (append (cdr queue) (reverse extra)) bucket))
          (else
           (let* ((pair     (car found))
                  (scope    (car pair))
                  (body     (cdr pair))
                  (existing (bucket-find 'tree bucket scope)))
             (cond
               ((not existing)
                (add (cdr found)
                     (append bucket (list (cons scope body)))
                     (cons body extra)))
               ((eq? (cdr existing) body)
                (add (cdr found) bucket extra))
               (else
                (error "configuration: conflicting contributions share a key"
                       'duplicate-key 'tree scope))))))))))

;; (configuration item …) → the Configuration value, or a decodable
;; error. Items are contributions and/or fragments, nested freely.
;; Pure: flatten → validate → keyed merge per tag → hoist carried
;; trees → the assembled value. No keyword parameters — settings are
;; contributions like everything else.
(define (configuration . items)
  (let ((contribs (flatten-fragments items)))
    (for-each validate-contribution contribs)
    (let loop ((rest contribs)
               (trees '()) (backends '()) (contexts '()) (settings '()))
      (if (null? rest)
        (list 'configuration
              (cons 'trees    (hoist-embedded-trees (reverse trees)))
              (cons 'backends (reverse backends))
              (cons 'contexts (reverse contexts))
              (cons 'settings (reverse settings)))
        (let* ((c (car rest)) (tag (car c)) (key (cadr c)) (value (caddr c)))
          (case tag
            ((tree)
             (loop (cdr rest)
                   (bucket-add 'tree trees key value)
                   backends contexts settings))
            ((backend)
             (loop (cdr rest) trees
                   (bucket-add 'backend backends key value)
                   contexts settings))
            ((context)
             (loop (cdr rest) trees backends
                   (bucket-add 'context contexts key value)
                   settings))
            ((setting)
             (loop (cdr rest) trees backends contexts
                   (bucket-add 'setting settings key value)))))))))

;; ─── Configuration-value accessors ───────────────────────────────────

(define (configuration? x)
  (and (pair? x)
       (eq? (car x) 'configuration)
       (pair? (cdr x))
       (assq 'trees    (cdr x))
       (assq 'backends (cdr x))
       (assq 'contexts (cdr x))
       (assq 'settings (cdr x))
       #t))

(define (configuration-section config name)
  (unless (configuration? config)
    (error "configuration accessor: not a configuration value"
           'invalid-configuration config))
  (cdr (assq name (cdr config))))

(define (configuration-trees c)    (configuration-section c 'trees))
(define (configuration-backends c) (configuration-section c 'backends))
(define (configuration-contexts c) (configuration-section c 'contexts))
(define (configuration-settings c) (configuration-section c 'settings))

;; Keyed lookups. Tree scopes accept either spelling (symbol or
;; string); settings take an optional default for the unset case.
(define (configuration-tree-ref c scope)
  (let ((e (bucket-find 'tree (configuration-trees c) scope)))
    (and e (cdr e))))

(define (configuration-backend-ref c sym)
  (let ((e (bucket-find 'backend (configuration-backends c) sym)))
    (and e (cdr e))))

(define (configuration-context-ref c exe)
  (let ((e (bucket-find 'context (configuration-contexts c) exe)))
    (and e (cdr e))))

(define (configuration-setting-ref c name . default)
  (let ((e (bucket-find 'setting (configuration-settings c) name)))
    (cond
      (e (cdr e))
      ((pair? default) (car default))
      (else #f))))

)) ;; end begin / define-library
