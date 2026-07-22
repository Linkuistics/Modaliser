;; (modaliser util) — Shared utility functions used across other
;; (modaliser …) libraries. Pure Scheme except for the centralised
;; SRFI 69 hashtable re-exports below. After Phase D this library
;; imports only (scheme …) and (srfi …); no host-specific libraries.

(define-library (modaliser util)
  (export alist-ref
          props->alist
          string-join
          read-file-text
          log
          round-div
          ;; SRFI 69 hashtable surface (re-exported for callers that
          ;; import (modaliser util) and don't want to depend on
          ;; (srfi 69) by name).
          make-hash-table hash-table-set! hash-table-ref/default
          string-hash
          ;; Local string helpers (no SRFI 13 in LispKit's bundle,
          ;; so we implement these on (scheme base) directly).
          string-split string-trim string-contains? escape-string
          ;; SRFI 1 list-searching/filtering surface (re-exported, same idea as
          ;; the SRFI 69 re-exports above): (scheme base) omits filter / remove /
          ;; partition / filter-map / find, so (modaliser …) libraries that want
          ;; them would each have to reach for (srfi 1). We re-export the standard
          ;; bindings from this one base library instead. Because they are the
          ;; very same (srfi 1) bindings, a library importing both this and
          ;; (srfi 1) sees no inconsistent-import conflict.
          filter remove partition filter-map find
          ;; The R7RS (scheme cxr) accessor family — the 3- and 4-deep car/cdr
          ;; compositions (caddr / cadddr / …). LispKit's (scheme base) provides
          ;; only the 2-deep accessors (caar/cadr/cdar/cddr), so a (modaliser …)
          ;; library that wants caddr must reach for (scheme cxr). We RE-EXPORT
          ;; the standard bindings here so callers can get them from this one
          ;; base library — and, because they are the very same (scheme cxr)
          ;; bindings, a library that imports both this and (scheme cxr)
          ;; directly sees no inconsistent-import conflict.
          caaar caadr cadar caddr cdaar cdadr cddar cdddr
          caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
          cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr)
  (import (scheme base)
          (scheme cxr)
          (scheme file)
          (scheme write)
          (scheme char)
          (srfi 69)
          ;; Only the five list procedures — `only` keeps SRFI 1's
          ;; redefinitions of map / assoc / member / fold-right out of this
          ;; library's own body.
          (only (srfi 1) filter remove partition filter-map find))
  (begin

    ;; alist-ref returns the default (or #f) on a MISSING key. That makes it
    ;; the right tool for the (let ((e (assoc k a))) (if e (cdr e) DEFAULT))
    ;; accessors (e.g. state-machine's node-*). It is deliberately NOT used to
    ;; mechanically rewrite the many bare (cdr (assoc 'k a)) sites (window-actions
    ;; js-cell, the app/mux libraries, …): those omit a default ON PURPOSE — the
    ;; key is guaranteed present by construction, so the bare cdr is a presence
    ;; assertion that errors loudly on a structural bug. Swapping in alist-ref
    ;; would silently turn that crash into a propagating #f. Audited under
    ;; util-extraction-audit-k26 (finding E): considered, intentionally not done.
    (define (alist-ref alist key . default)
      (let ((pair (assoc key alist)))
        (if pair
          (cdr pair)
          (if (null? default) #f (car default)))))

    (define (props->alist . args)
      (let loop ((rest args) (result '()))
        (if (or (null? rest) (null? (cdr rest)))
          (reverse result)
          (loop (cdr (cdr rest))
                (cons (cons (car rest) (car (cdr rest))) result)))))

    (define (string-join strs sep)
      (if (null? strs)
        ""
        (let loop ((rest (cdr strs)) (result (car strs)))
          (if (null? rest)
            result
            (loop (cdr rest)
                  (string-append result sep (car rest)))))))

    (define (read-file-text path)
      (if (file-exists? path)
        (let ((port (open-input-file path)))
          (let loop ((lines '()))
            (let ((line (read-line port)))
              (if (eof-object? line)
                (begin
                  (close-input-port port)
                  (string-join (reverse lines) "\n"))
                (loop (cons line lines))))))
        ""))

    (define (log . args)
      (for-each display args)
      (newline))

    ;; Rounds A/B to the nearest integer (round-half-up), using only exact
    ;; integer arithmetic — no floats, no rational-number dependence. A and
    ;; B must both be non-negative (every current caller scales a pixel/
    ;; cell coordinate, never a signed delta). Plain `quotient` truncates
    ;; toward zero, which is a systematic floor bias: scaling a long list
    ;; of coordinates by an independent `(quotient (* n scale) total)` per
    ;; entry (rather than a running cumulative sum) lets that bias show up
    ;; as visible position/size drift growing across the list once the
    ;; true per-unit size isn't a whole number of pixels — found via
    ;; mini-chip-size-and-label-anchor-k38's live dogfooding, scaling herdr
    ;; ui.layout's cell-grid coordinates to real screen pixels.
    (define (round-div a b)
      (quotient (+ a (quotient b 2)) b))

    ;; ─── Local string ops ───────────────────────────────────────
    ;; Implemented on (scheme base) only; no SRFI 13 needed.

    (define (string-index-of haystack needle start)
      ;; Returns the index of the first match of needle in haystack at
      ;; or after start, or #f if not found. Naive O(n*m) scan — fine
      ;; for the short strings we split on (paths, command output).
      (let ((hlen (string-length haystack))
            (nlen (string-length needle)))
        (if (zero? nlen)
          start
          (let outer ((i start))
            (cond
              ((> (+ i nlen) hlen) #f)
              ((let inner ((j 0))
                 (cond
                   ((= j nlen) #t)
                   ((char=? (string-ref haystack (+ i j))
                            (string-ref needle j))
                    (inner (+ j 1)))
                   (else #f)))
               i)
              (else (outer (+ i 1))))))))

    (define (string-contains? haystack needle)
      (if (string-index-of haystack needle 0) #t #f))

    (define (string-split str sep)
      ;; Split str on every occurrence of the literal string sep.
      ;; Matches the input/output shape the existing callers rely on:
      ;;   (string-split "a/b/c" "/") => ("a" "b" "c")
      ;;   (string-split "abc" "/")   => ("abc")
      ;;   (string-split "" "/")      => ("")
      (let ((slen (string-length str))
            (seplen (string-length sep)))
        (if (zero? seplen)
          (list str)
          (let loop ((start 0) (acc '()))
            (let ((hit (string-index-of str sep start)))
              (if hit
                (loop (+ hit seplen)
                      (cons (substring str start hit) acc))
                (reverse (cons (substring str start slen) acc))))))))

    (define (string-trim str)
      ;; Strip leading/trailing whitespace (per char-whitespace?).
      (let ((len (string-length str)))
        (let scan-left ((i 0))
          (cond
            ((= i len) "")
            ((char-whitespace? (string-ref str i)) (scan-left (+ i 1)))
            (else
              (let scan-right ((j (- len 1)))
                (if (char-whitespace? (string-ref str j))
                  (scan-right (- j 1))
                  (substring str i (+ j 1)))))))))

    (define (escape-string str table)
      ;; Walk str char by char, replacing every char that is a key in `table`
      ;; (an alist of char -> replacement-string) with its replacement; all
      ;; other chars pass through unchanged. This is the single char-walk
      ;; skeleton shared by the host UI's JS-literal / JSON / HTML-attribute
      ;; escapers: what differs between them is ONLY the table, since the set of
      ;; chars unsafe to emit depends on the target (a JS string literal vs a
      ;; JSON string vs a single-quoted HTML attribute). Keeping the mechanism
      ;; here and the tables at the call sites means there is one place that can
      ;; be wrong about the walk and a self-documenting table per target.
      (let loop ((chars (string->list str)) (result '()))
        (if (null? chars)
          (list->string (reverse result))
          (let* ((c (car chars))
                 (hit (assv c table)))
            (loop (cdr chars)
                  (if hit
                    ;; Prepend the replacement's chars (reversed, because
                    ;; `result` accumulates in reverse and is reversed at the end).
                    (append (reverse (string->list (cdr hit))) result)
                    (cons c result)))))))
    ;; The (scheme cxr) accessors are re-exported, not redefined — see the
    ;; export list above; nothing to define here.
    ))
