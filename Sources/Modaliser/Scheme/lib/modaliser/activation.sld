;; (modaliser activation) — Terminal-context-map activation resolution
;; and the activation-aware lowering (context-map-activation-k8;
;; ADR-0013, ADR-0018, docs/specs/configuration-value.md "The Terminal
;; context map").
;;
;; Three pieces, all pure:
;;
;;   resolve-activation        — leader kind × frontmost bundle-id ×
;;                               detection chain × Configuration value →
;;                               landing (root state id + seeded return
;;                               stack): the spec's activation algorithm.
;;   resolve-direct-activation — the programmatic twin: entering a tree
;;                               by scope routes through the same
;;                               resolution, seeding outward frames when
;;                               the live chain contains that context.
;;   lower-with-activation     — context-reference validation + the
;;                               derived `.` step-in providers composed
;;                               onto terminal-like screen roots, then
;;                               the shared pure lower ((modaliser fsm)'s
;;                               lower-configuration) to a closed graph.
;;
;; THE live leader path (cutover-contract-k13): the handoff's armed
;; leader handlers resolve every press through resolve-activation
;; against the installed value and the live detection chain
;; ((modaliser handoff) make-configured-leader-handler); the entry-table
;; leader path is deleted.
;;
;; THE CHAIN IS AN ARGUMENT (docs/specs/configuration-value.md "Test
;; seams" — no mocking machinery): the resolvers take the
;; focused-terminal-path-shaped alist itself. lower-with-activation
;; instead takes a 0-arg CHAIN SOURCE, because the derived step-in edge
;; re-derives per come-to-rest snapshot. That split is the
;; chain-staleness doctrine: the chain is probed at activation and at
;; each snapshot; seeded frames are press-time values and outward steps
;; never re-probe.

(define-library (modaliser activation)
  (export resolve-activation
          resolve-direct-activation
          lower-with-activation)
  (import (scheme base)
          (modaliser util)
          (modaliser configuration)
          (modaliser terminal)
          (modaliser fsm))
  (begin

;; ─── Chain shape helpers ─────────────────────────────────────────────
;;
;; A chain is the focused-terminal-path alist: one (backend-sym . frame)
;; per hop, host first, innermost mux last; a frame is
;; #(pane <id> fg <cmd>) (CONTEXT.md "Focused-terminal path"). A frame's
;; fg is the foreground command in that backend's focused pane — i.e.
;; the context one step INWARD of that frame's backend.

(define (frame-fg frame)
  (let ((v (cdr frame)))
    (and (vector? v)
         (>= (vector-length v) 4)
         (let ((fg (vector-ref v 3)))
           (and (string? fg) fg)))))

(define (scope->string scope)
  (if (symbol? scope) (symbol->string scope) scope))

;; A frame's fg is the full foreground COMMAND LINE (`ps -o command=` —
;; "nvim README.md", "/opt/homebrew/bin/nvim"), but the Terminal context
;; map is keyed by EXE NAME (ADR-0013: "one entry per foreground
;; executable"). Normalize at the consult: first whitespace-separated
;; token, basename only. Deriving the exe here — not in the chain probe —
;; keeps frames carrying what the backend actually observed.
(define (fg->exe fg)
  (let* ((first-token
           (let loop ((i 0))
             (cond
               ((>= i (string-length fg)) fg)
               ((char=? (string-ref fg i) #\space) (substring fg 0 i))
               (else (loop (+ i 1))))))
         (parts (string-split first-token "/")))
    (if (null? parts) first-token (list-ref parts (- (length parts) 1)))))

;; The chain's MAPPED CONTEXTS, outermost first, as
;; (exe . tree-root-state-id): every frame's fg whose exe has a Terminal-
;; context-map entry. Walking every frame's fg in chain order enumerates
;; the step-in candidates from just-inside-the-host down to the
;; innermost foreground command; unmapped layers (a bare shell, a mux
;; with no entry) are simply skipped, so "innermost mapped" and "one
;; mapped context inward" both fall out of this one list.
(define (mapped-chain-contexts config chain)
  (filter-map
    (lambda (fr)
      (let* ((fg (frame-fg fr))
             (exe (and fg (fg->exe fg)))
             (entry (and exe (configuration-context-ref config exe))))
        (and entry
             (cons exe (scope->string (cdr (assq 'tree entry)))))))
    chain))

;; ─── Terminal-likeness ───────────────────────────────────────────────

;; (host-backend-anchor config scope-str) → the backend SYMBOL that makes
;; SCOPE-STR a terminal-like host screen, or #f. Terminal-likeness is
;; capability, not declaration (docs/specs/configuration-value.md): the
;; value must carry a 'host-kind backend record whose match-key is this
;; scope's bundle-id AND that implements the two chain probes
;; focused-terminal-path walks (focused-pane identity + foreground-
;; command detection). The symbol doubles as the screen's chain anchor
;; for the derived step-in edge below — read off the RECORD, not the
;; contribution's bucket key, because chain frames are keyed by
;; (terminal-backend-symbol record) (walk-path, terminal.sld).
(define (host-backend-anchor config scope-str)
  (let ((hit (find (lambda (kv)
                     (let ((r (cdr kv)))
                       (and (terminal-backend? r)
                            (eq? (terminal-backend-kind r) 'host)
                            (equal? (terminal-backend-match-key r) scope-str)
                            (terminal-backend-detect-fg r)
                            (terminal-backend-focused-pane-id r)
                            #t)))
                   (configuration-backends config))))
    (and hit (terminal-backend-symbol (cdr hit)))))

;; ─── Activation resolution ───────────────────────────────────────────

(define (landing root stack)
  (list (cons 'root root) (cons 'stack stack)))

(define (list-last lst)
  (if (null? (cdr lst)) (car lst) (list-last (cdr lst))))

(define (list-drop-last lst)
  (if (null? (cdr lst)) '() (cons (car lst) (list-drop-last (cdr lst)))))

;; (resolve-activation leader-kind bundle-id chain config)
;;   → ((root . <state-id>) (stack . (<state-id> …))) or #f
;;
;; The pure activation algorithm (docs/specs/configuration-value.md
;; "Activation"): map the leader kind to a screen ('global, or the
;; frontmost bundle-id, defaulting to the global screen); on a
;; terminal-like screen with a non-empty chain, land on the INNERMOST
;; mapped context's tree and seed one return frame per outer context.
;; The returned stack is in POP ORDER — the frame backspace pops first
;; at the head, the resolved screen always last — ready to hand to
;; (fsm-activate! root stack). #f when the value has no screen to land
;; on at all (the caller's no-op).
(define (resolve-activation leader-kind bundle-id chain config)
  (unless (memq leader-kind '(global local))
    (error "resolve-activation: leader-kind must be 'global or 'local"
           'invalid-leader-kind leader-kind))
  (let* ((scope (if (eq? leader-kind 'global) "global" bundle-id))
         (screen-key
           (cond
             ((and scope (configuration-tree-ref config scope))
              (scope->string scope))
             ((configuration-tree-ref config "global") "global")
             (else #f))))
    (and screen-key
         (let ((mapped (and (host-backend-anchor config screen-key)
                            (pair? chain)
                            (mapped-chain-contexts config chain))))
           (if (or (not mapped) (null? mapped))
             (landing screen-key '())
             (landing (cdr (list-last mapped))
                      (reverse (cons screen-key
                                     (map cdr (list-drop-last mapped))))))))))

;; (resolve-direct-activation scope chain config) → landing or #f
;;
;; Programmatic activation routes through the same resolution (ADR-0013):
;; entering a tree by scope lands on that tree; when it is a context-map
;; tree AND the live chain contains that context, the stack seeds the
;; same outward frames leader activation would have — the chain's host
;; screen (when the value carries one) plus every mapped context outward
;; of the entered one. Otherwise the stack is empty and backspace at the
;; root is honestly a no-op: there is no outer context. #f when SCOPE
;; names no tree in the value.
(define (resolve-direct-activation scope chain config)
  (and (configuration-tree-ref config scope)
       (let* ((scope-str (scope->string scope))
              (mapped (mapped-chain-contexts config chain))
              (tree-ids (map cdr mapped))
              (idx (last-index-of tree-ids scope-str)))
         (if (not idx)
           (landing scope-str '())
           (let ((outer (take-n tree-ids idx))
                 (host (chain-host-screen config chain)))
             (landing scope-str
                      (reverse (append (if host (list host) '()) outer))))))))

;; Innermost occurrence wins when a context somehow repeats in the chain
;; — consistent with activation's innermost-mapped rule.
(define (last-index-of lst x)
  (let loop ((rest lst) (i 0) (found #f))
    (cond
      ((null? rest) found)
      ((equal? (car rest) x) (loop (cdr rest) (+ i 1) i))
      (else (loop (cdr rest) (+ i 1) found)))))

(define (take-n lst n)
  (if (or (= n 0) (null? lst))
    '()
    (cons (car lst) (take-n (cdr lst) (- n 1)))))

;; The screen a direct entry's outermost seeded frame names: the chain's
;; HOST frame's backend record (matched by the record's own symbol —
;; that is what chain frames carry), when it is a host whose match-key
;; names a tree the value carries. #f otherwise — a chain whose host has
;; no screen simply seeds one frame fewer.
(define (chain-host-screen config chain)
  (and (pair? chain)
       (let ((hit (find (lambda (kv)
                          (let ((r (cdr kv)))
                            (and (terminal-backend? r)
                                 (eq? (terminal-backend-symbol r)
                                      (car (car chain))))))
                        (configuration-backends config))))
         (and hit
              (let ((r (cdr hit)))
                (and (eq? (terminal-backend-kind r) 'host)
                     (let ((mk (terminal-backend-match-key r)))
                       (and (string? mk)
                            (configuration-tree-ref config mk)
                            mk))))))))

;; ─── The derived `.` step-in edge ────────────────────────────────────
;;
;; Every terminal-like screen carries a derived, gated `.` call edge
;; stepping ONE MAPPED CONTEXT INWARD from that screen's own position in
;; the chain (docs/specs/configuration-value.md "Step-in" — authored by
;; nobody, symmetric with backspace). Implementation: a PROVIDER composed
;; onto the screen's root state at lowering. Providers run exactly at the
;; visit's snapshot instant, so the edge's target is computed then, and
;; its gate — "a mapped context exists inward of here" — is expressed by
;; the edge being present in (or absent from) the snapshot; no probe
;; happens between snapshots (chain-staleness doctrine).

;; (step-in-edge config chain anchor-sym) → edge spec or #f
;;
;; ANCHOR-SYM is the screen's own backend symbol (the host backend for a
;; host screen; the entry's mux backend for a mux-backed context tree).
;; The screen's chain position is the frame carrying that symbol; the
;; edge targets the FIRST mapped context at-or-inward of that frame's fg
;; — skipping unmapped layers, exactly as activation's innermost-mapped
;; walk does. No frame with the symbol (the chain is empty, or belongs
;; to a different host) → no edge.
(define (step-in-edge config chain anchor-sym)
  (let loop ((rest chain))
    (cond
      ((null? rest) #f)
      ((eq? (car (car rest)) anchor-sym)
       (let ((mapped (mapped-chain-contexts config rest)))
         (and (pair? mapped)
              (edge "." (cdr (car mapped)) 'call #t))))
      (else (loop (cdr rest))))))

;; (terminal-like-anchors config) → ((tree-root-state-id . backend-sym) …)
;;
;; The screens that derive a step-in edge: every terminal-like host
;; screen, and every MUX-BACKED context tree (herdr/tmux/zellij — an
;; entry carrying a 'backend reference; a tree-only entry like nvim
;; hosts no panes and derives nothing). First hit wins on a duplicate
;; scope.
(define (terminal-like-anchors config)
  (dedup-by-key
    (append
      (filter-map
        (lambda (kv)
          (let* ((scope-str (scope->string (car kv)))
                 (sym (host-backend-anchor config scope-str)))
            (and sym (cons scope-str sym))))
        (configuration-trees config))
      (filter-map
        (lambda (kv)
          (let* ((entry (cdr kv))
                 (t (assq 'tree entry))
                 (b (assq 'backend entry))
                 (r (and b (configuration-backend-ref config (cdr b)))))
            (and t r (terminal-backend? r)
                 (cons (scope->string (cdr t))
                       (terminal-backend-symbol r)))))
        (configuration-contexts config)))))

(define (dedup-by-key alist)
  (let loop ((rest alist) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((assoc (car (car rest)) acc) (loop (cdr rest) acc))
      (else (loop (cdr rest) (cons (car rest) acc))))))

;; Compose the derived step-in onto a root node's (possibly absent)
;; authored provider: the authored one runs first, then the step-in edge
;; is appended when the chain offers one. Provided states pass through
;; untouched, and an authored "." (static or provided) wins over the
;; derived edge — dispatch takes the first matching trigger.
(define (compose-step-in-provider authored config chain-source anchor-sym)
  (lambda ()
    (let* ((base (if authored ((fsm-behavior-proc authored)) '()))
           (e (step-in-edge config (chain-source) anchor-sym)))
      (if (not e)
        base
        (let ((base-edges  (let ((kv (assoc 'edges base)))  (if kv (cdr kv) '())))
              (base-states (let ((kv (assoc 'states base))) (if kv (cdr kv) '()))))
          (list (cons 'edges (append base-edges (list e)))
                (cons 'states base-states)))))))

;; Rebuild CONFIG with every terminal-like screen root carrying the
;; composed provider — a pure, value-level decoration: the root node
;; alist is SHADOWED with a fresh 'provider entry (assq finds the first),
;; nothing is mutated, and every other tree passes through untouched.
;; Decorating the VALUE rather than the graph is what keeps
;; lower-configuration itself activation-ignorant.
(define (decorate-step-in config chain-source)
  (let ((anchors (terminal-like-anchors config)))
    (if (null? anchors)
      config
      (list 'configuration
            (cons 'trees
                  (map (lambda (kv)
                         (let ((a (assoc (scope->string (car kv)) anchors)))
                           (if a
                             (cons (car kv)
                                   (cons (cons 'provider
                                               (compose-step-in-provider
                                                 (node-provider (cdr kv))
                                                 config chain-source (cdr a)))
                                         (cdr kv)))
                             kv)))
                       (configuration-trees config)))
            (cons 'backends (configuration-backends config))
            (cons 'contexts (configuration-contexts config))
            (cons 'settings (configuration-settings config))))))

;; ─── Context-reference closure + the activation-aware lower ──────────

;; A context entry references its tree — and, for a pane-op-capable exe,
;; its backend — BY KEY (the `context` constructor defers exactly this
;; check to lowering): both must resolve in the value, as decodable
;; load-time errors naming the offender.
(define (check-context-references config)
  (for-each
    (lambda (kv)
      (let* ((exe (car kv))
             (entry (cdr kv))
             (t (assq 'tree entry))
             (b (assq 'backend entry)))
        (unless (and t (configuration-tree-ref config (cdr t)))
          (error "lower-with-activation: context entry references a tree the value does not carry"
                 'dangling-context-tree exe (and t (cdr t))))
        (when (and b (not (configuration-backend-ref config (cdr b))))
          (error "lower-with-activation: context entry references a backend the value does not carry"
                 'dangling-context-backend exe (cdr b)))))
    (configuration-contexts config)))

;; (lower-with-activation config chain-source) → a closed FSM graph value.
;;
;; The activation-aware pure lower: validate the context map's reference
;; closure, decorate every terminal-like screen root with the derived
;; step-in provider (which probes CHAIN-SOURCE at each visit snapshot),
;; then run the shared pure lower (lower-configuration) to a graph
;; closed over its authored references. Still pure: CHAIN-SOURCE is
;; stored in the providers, never invoked here; the installed graph and
;; every other engine observable are untouched. Installing the result is
;; the Handoff's business (modaliser:start!, a later increment).
(define (lower-with-activation config chain-source)
  (unless (procedure? chain-source)
    (error "lower-with-activation: chain-source must be a procedure"
           'invalid-chain-source chain-source))
  (check-context-references config)
  (lower-configuration (decorate-step-in config chain-source)))

)) ;; end begin / define-library
