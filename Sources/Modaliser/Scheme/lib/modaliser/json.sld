;; (modaliser json) — a small, portable JSON reader and writer.
;;
;; Why this exists. Socket-API muxes (herdr) speak compact single-line,
;; nested JSON. The multiline awk parsers the tmux/zellij/wezterm backends
;; use do NOT transfer to compact single-line output, and the tree had no
;; general JSON reader — each backend rolled its own ad-hoc extractor.
;; This library is the shared, testable answer, in both directions:
;; `herdr` output → Scheme data, and Scheme data → a herdr request line
;; (ADR-0020's socket transport builds `{"id","method","params"}` with
;; json-write rather than by string-appending, so escaping is decided in
;; exactly one place).
;;
;; Portability. Depends ONLY on (scheme base) + (scheme char) — no
;; hashtable library, no host JSON primitive — so it belongs in the
;; portable lib/modaliser tree and keeps check-portable-surface.sh green.
;;
;; Representation (chosen so objects and arrays are distinguishable at a
;; glance, and so extraction is plain assoc / vector-ref):
;;
;;   JSON object  → alist  ((string-key . value) …)   empty → '()
;;   JSON array   → vector  #(value …)                empty → #()
;;   JSON string  → string
;;   JSON number  → number
;;   true / false → #t / #f
;;   null         → the symbol  null
;;
;; Objects (proper lists of pairs) and arrays (vectors) never collide, so
;; `json-ref` walks objects while `vector-ref` / `vector-length` walk
;; arrays. Scalars are self-evident.
;;
;; Caveat (documented, not a bug): a key whose value is JSON `false`
;; reads back as #f, indistinguishable from "key absent" via json-ref.
;; Callers that must tell those apart should check membership first; the
;; herdr backend only extracts strings / arrays / numbers, so it is
;; unaffected.

(define-library (modaliser json)
  (export json-parse json-ref json-write)
  (import (scheme base)
          (scheme char))
  (begin

    ;; Look up string KEY in a parsed JSON object (an alist). Returns the
    ;; value, or #f when OBJ is not an object or lacks the key. A vector
    ;; (array) or scalar OBJ yields #f rather than an error, so chained
    ;; lookups down a path that doesn't exist degrade to #f.
    (define (json-ref obj key)
      (and (list? obj)
           (let ((p (assoc key obj)))
             (and (pair? p) (cdr p)))))

    ;; Parse JSON text into the representation above. Raises on malformed
    ;; input; callers shelling out to a CLI wrap this in `guard` so a
    ;; stray non-JSON line degrades to #f rather than breaking a leader
    ;; press. A single mutable cursor `i` walks the string; the internal
    ;; procedures form a letrec* so their mutual references resolve.
    (define (json-parse str)
      (let ((n (string-length str))
            (i 0))
        (define (peek) (if (< i n) (string-ref str i) #\x0))
        (define (advance!) (set! i (+ i 1)))
        (define (skip-ws)
          (let loop ()
            (when (and (< i n) (char-whitespace? (peek)))
              (advance!) (loop))))
        (define (expect ch)
          (if (char=? (peek) ch)
              (advance!)
              (error "json-parse: unexpected character" (peek) 'expected ch)))

        (define (parse-value)
          (skip-ws)
          (let ((c (peek)))
            (cond
              ((char=? c #\{) (parse-object))
              ((char=? c #\[) (parse-array))
              ((char=? c #\") (parse-string))
              ((char=? c #\t) (parse-lit "true" #t))
              ((char=? c #\f) (parse-lit "false" #f))
              ((char=? c #\n) (parse-lit "null" 'null))
              (else (parse-number)))))

        (define (parse-lit word val)
          (let loop ((k 0))
            (if (= k (string-length word))
                val
                (begin (expect (string-ref word k)) (loop (+ k 1))))))

        ;; { key : value , … } → alist, keys reversed back into source order.
        (define (parse-object)
          (expect #\{) (skip-ws)
          (if (char=? (peek) #\})
              (begin (advance!) '())
              (let loop ((acc '()))
                (skip-ws)
                (let ((key (parse-string)))
                  (skip-ws) (expect #\:)
                  (let ((val (parse-value)))
                    (skip-ws)
                    (let ((c (peek)))
                      (cond
                        ((char=? c #\,)
                         (advance!) (loop (cons (cons key val) acc)))
                        ((char=? c #\})
                         (advance!) (reverse (cons (cons key val) acc)))
                        (else (error "json-parse: malformed object" c)))))))))

        ;; [ value , … ] → vector, in source order.
        (define (parse-array)
          (expect #\[) (skip-ws)
          (if (char=? (peek) #\])
              (begin (advance!) #())
              (let loop ((acc '()))
                (let ((val (parse-value)))
                  (skip-ws)
                  (let ((c (peek)))
                    (cond
                      ((char=? c #\,)
                       (advance!) (loop (cons val acc)))
                      ((char=? c #\])
                       (advance!) (list->vector (reverse (cons val acc))))
                      (else (error "json-parse: malformed array" c))))))))

        (define (parse-string)
          (expect #\")
          (let loop ((acc '()))
            (let ((c (peek)))
              (cond
                ((char=? c #\") (advance!) (list->string (reverse acc)))
                ((char=? c #\\)
                 (advance!)
                 (let ((e (peek)))
                   (advance!)
                   (cond
                     ((char=? e #\") (loop (cons #\" acc)))
                     ((char=? e #\\) (loop (cons #\\ acc)))
                     ((char=? e #\/) (loop (cons #\/ acc)))
                     ((char=? e #\b) (loop (cons #\x8 acc)))
                     ((char=? e #\f) (loop (cons #\xc acc)))
                     ((char=? e #\n) (loop (cons #\newline acc)))
                     ((char=? e #\r) (loop (cons #\return acc)))
                     ((char=? e #\t) (loop (cons #\tab acc)))
                     ((char=? e #\u)
                      (let ((hex (substring str i (+ i 4))))
                        (set! i (+ i 4))
                        (loop (cons (integer->char (string->number hex 16)) acc))))
                     (else (error "json-parse: bad escape" e)))))
                (else (advance!) (loop (cons c acc)))))))

        (define (number-char? c)
          (or (char-numeric? c)
              (char=? c #\-) (char=? c #\+)
              (char=? c #\.) (char=? c #\e) (char=? c #\E)))

        (define (parse-number)
          (let ((start i))
            (let loop ()
              (when (and (< i n) (number-char? (peek))) (advance!) (loop)))
            (let ((tok (substring str start i)))
              (or (string->number tok)
                  (error "json-parse: malformed number" tok)))))

        (skip-ws)
        (parse-value)))

    ;; ─── Writer ─────────────────────────────────────────────────────
    ;;
    ;; json-parse's mirror over the same representation, so a socket-API
    ;; backend can build a request line without rolling its own encoder —
    ;; the ad-hoc-per-backend outcome this library exists to prevent.
    ;;
    ;; Objects are emitted in alist order rather than sorted, which makes a
    ;; request line deterministic and therefore assertable in a test.
    ;; Output is compact (no spaces): these lines go on a socket, not to a
    ;; human.
    ;;
    ;; The representation's one ambiguity is inherited, not introduced: #f
    ;; means JSON `false`, so an "absent" value must be omitted from the
    ;; alist rather than written as #f. Symbols other than `null` and any
    ;; other unsupported value raise — a caller building a request from
    ;; malformed data is a programming error, not a wire condition.
    (define (json-write value)
      (let ((out (open-output-string)))
        (write-json value out)
        (get-output-string out)))

    (define (write-json v out)
      (cond
        ((eq? v 'null)  (write-string "null" out))
        ((eq? v #t)     (write-string "true" out))
        ((eq? v #f)     (write-string "false" out))
        ((string? v)    (write-json-string v out))
        ((number? v)    (write-string (number->string v) out))
        ((vector? v)    (write-json-array v out))
        ;; '() is the empty OBJECT (parse-object's result), not an empty
        ;; array — #() is the empty array. Both directions agree.
        ((null? v)      (write-string "{}" out))
        ((pair? v)      (write-json-object v out))
        (else (error "json-write: unsupported value" v))))

    (define (write-json-array vec out)
      (write-char #\[ out)
      (let loop ((k 0))
        (when (< k (vector-length vec))
          (when (> k 0) (write-char #\, out))
          (write-json (vector-ref vec k) out)
          (loop (+ k 1))))
      (write-char #\] out))

    (define (write-json-object alist out)
      (write-char #\{ out)
      (let loop ((rest alist) (first? #t))
        (unless (null? rest)
          (let ((entry (car rest)))
            (unless (and (pair? entry) (string? (car entry)))
              (error "json-write: object entry is not a (string . value) pair" entry))
            (unless first? (write-char #\, out))
            (write-json-string (car entry) out)
            (write-char #\: out)
            (write-json (cdr entry) out)
            (loop (cdr rest) #f))))
      (write-char #\} out))

    ;; Escapes exactly what JSON requires: the two structural characters
    ;; (" and \) and every control character below U+0020. Everything else
    ;; — including `/` and non-ASCII — goes out verbatim, which parse-string
    ;; reads back unchanged. The five short forms are used where they exist
    ;; because they are what a human debugging a captured line expects.
    (define (write-json-string s out)
      (write-char #\" out)
      (let loop ((k 0))
        (when (< k (string-length s))
          (let* ((c (string-ref s k))
                 (n (char->integer c)))
            (cond
              ((char=? c #\")      (write-string "\\\"" out))
              ((char=? c #\\)      (write-string "\\\\" out))
              ((char=? c #\newline)(write-string "\\n" out))
              ((char=? c #\return) (write-string "\\r" out))
              ((char=? c #\tab)    (write-string "\\t" out))
              ((= n 8)             (write-string "\\b" out))
              ((= n 12)            (write-string "\\f" out))
              ((< n 32)            (write-string (unicode-escape n) out))
              (else                (write-char c out))))
          (loop (+ k 1))))
      (write-char #\" out))

    ;; \u00XX — control codes only, so two hex digits always suffice and
    ;; the leading "00" is a constant.
    (define (unicode-escape n)
      (let ((hex "0123456789abcdef"))
        (string-append "\\u00"
                       (string (string-ref hex (quotient n 16))
                               (string-ref hex (remainder n 16))))))))
