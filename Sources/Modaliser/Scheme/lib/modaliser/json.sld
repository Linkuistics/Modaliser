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
    ;; press. The internal procedures form a letrec* so their mutual
    ;; references resolve.
    ;;
    ;; ─── Why the cursor is passed, not mutated ───────────────────────
    ;;
    ;; Every scanner below takes the index to read from and answers a
    ;; `(value . next-index)` pair. The obvious alternative — one `set!`
    ;; cursor with `peek` / `advance!` helpers, which is what this reader
    ;; used to be — is shorter to read and measurably slower, because in
    ;; an interpreter the cost is *operations per character* and that
    ;; shape spends several more of them on every one:
    ;;
    ;;   - a `set!`-captured variable is boxed, so each `i` read is an
    ;;     indirection and each `advance!` a write through it (measured at
    ;;     2.35 µs vs 1.87 µs for a plain call);
    ;;   - `peek` and `advance!` are closure calls, paid per character;
    ;;   - a loop variable costs neither.
    ;;
    ;; `parse-string` gains the most and is the hot path — most characters
    ;; in a real payload sit inside string literals. Scanning ahead to the
    ;; closing quote and lifting the whole literal out with one native
    ;; `substring` replaces a per-character `cons` plus a final `reverse`
    ;; and `list->string`. Only a literal that actually carries a backslash
    ;; falls back to consing (`parse-escaped-string`).
    ;;
    ;; Measured on `(modaliser wms paneru)`'s 1689-byte payload, release
    ;; build: **6.9 ms → 3.9 ms**, producing an `equal?` tree. That matters
    ;; because paneru's parse runs at come-to-rest, on the main thread,
    ;; between one keypress and the next — see
    ;; `docs/specs/paneru-window-management.md` decision 4.
    ;;
    ;; What did NOT help, so nobody re-tries it: a native substring search
    ;; to find the closing quote. LispKit has one, but it lives in a host
    ;; library this tree may not import, and the SRFI that re-exports the
    ;; name backs it with a Scheme KMP loop — slower than the inline scan.
    (define (json-parse str)
      (let ((n (string-length str)))

        (define (skip-ws k)
          (if (and (< k n) (char-whitespace? (string-ref str k)))
              (skip-ws (+ k 1))
              k))

        ;; K must hold CH; answers the index after it. Called at grammar
        ;; points only, never per character, so the call is not on the hot
        ;; path — and each one is a validation the reader would otherwise
        ;; silently skip (`{"a" 1}` must not read as `{"a": 1}`).
        (define (expect k ch)
          (if (and (< k n) (char=? (string-ref str k) ch))
              (+ k 1)
              (error "json-parse: unexpected character"
                     (if (< k n) (string-ref str k) 'end-of-input)
                     'expected ch)))

        (define (parse-value k)
          (let ((k (skip-ws k)))
            ;; Empty and whitespace-only input lands here. It must raise the
            ;; guardable kind — see parse-number's note, which owns the
            ;; reasoning for every malformed-input path.
            (if (>= k n)
                (error "json-parse: expected a value" 'end-of-input)
                (let ((c (string-ref str k)))
                  (cond
                    ((char=? c #\{) (parse-object (+ k 1)))
                    ((char=? c #\[) (parse-array (+ k 1)))
                    ((char=? c #\") (parse-string (+ k 1)))
                    ((char=? c #\t) (parse-lit k "true" #t))
                    ((char=? c #\f) (parse-lit k "false" #f))
                    ((char=? c #\n) (parse-lit k "null" 'null))
                    (else (parse-number k)))))))

        (define (parse-lit k word val)
          (let ((len (string-length word)))
            (let loop ((j 0))
              (cond
                ((= j len) (cons val (+ k len)))
                ((and (< (+ k j) n)
                      (char=? (string-ref str (+ k j)) (string-ref word j)))
                 (loop (+ j 1)))
                (else (error "json-parse: unexpected character"
                             (if (< (+ k j) n) (string-ref str (+ k j)) 'end-of-input)
                             'expected (string-ref word j)))))))

        ;; { key : value , … } → alist, keys reversed back into source order.
        ;; K is the index just past the `{`.
        (define (parse-object k)
          (let ((k (skip-ws k)))
            (if (and (< k n) (char=? (string-ref str k) #\}))
                (cons '() (+ k 1))
                (let loop ((k k) (acc '()))
                  (let* ((kv  (parse-string (expect (skip-ws k) #\")))
                         (vv  (parse-value (expect (skip-ws (cdr kv)) #\:)))
                         (e   (skip-ws (cdr vv)))
                         (acc (cons (cons (car kv) (car vv)) acc)))
                    (cond
                      ((>= e n) (error "json-parse: malformed object" 'end-of-input))
                      ((char=? (string-ref str e) #\,) (loop (+ e 1) acc))
                      ((char=? (string-ref str e) #\}) (cons (reverse acc) (+ e 1)))
                      (else (error "json-parse: malformed object"
                                   (string-ref str e)))))))))

        ;; [ value , … ] → vector, in source order. K is just past the `[`.
        (define (parse-array k)
          (let ((k (skip-ws k)))
            (if (and (< k n) (char=? (string-ref str k) #\]))
                (cons #() (+ k 1))
                (let loop ((k k) (acc '()))
                  (let* ((vv  (parse-value k))
                         (e   (skip-ws (cdr vv)))
                         (acc (cons (car vv) acc)))
                    (cond
                      ((>= e n) (error "json-parse: malformed array" 'end-of-input))
                      ((char=? (string-ref str e) #\,) (loop (+ e 1) acc))
                      ((char=? (string-ref str e) #\])
                       (cons (list->vector (reverse acc)) (+ e 1)))
                      (else (error "json-parse: malformed array"
                                   (string-ref str e)))))))))

        ;; K is the index just past the opening quote. The scan touches each
        ;; character once and conses nothing: on reaching the closing quote
        ;; the literal is lifted out whole by `substring`.
        ;;
        ;; The end-of-input clause is load-bearing, not defensive: the `else`
        ;; branch advances on ANY character, so without it an unterminated
        ;; literal spins forever instead of raising. Every other scanner here
        ;; is already bounded (skip-ws and parse-number test `j < n`; the
        ;; object and array scanners test it explicitly), so this is the one
        ;; loop in the reader that could run away.
        ;;
        ;; A truncated payload is not hypothetical: json-parse's callers feed
        ;; it whatever a CLI printed, and (modaliser wms paneru)'s parse runs
        ;; at come-to-rest — on the main thread, between a keypress and the
        ;; next one. Raising degrades (callers already wrap this in `guard`);
        ;; spinning does not.
        (define (parse-string k)
          (let scan ((j k))
            (if (>= j n)
                (error "json-parse: unterminated string")
                (let ((c (string-ref str j)))
                  (cond
                    ((char=? c #\") (cons (substring str k j) (+ j 1)))
                    ;; One backslash anywhere in the literal and the whole
                    ;; thing is re-read character at a time — the escape
                    ;; decoding has to build a string that is not a substring
                    ;; of the source. Rare enough in practice (paneru and
                    ;; herdr payloads carry none) that the re-scan is cheaper
                    ;; than making the fast path carry the machinery.
                    ((char=? c #\\) (parse-escaped-string k))
                    (else (scan (+ j 1))))))))

        (define (parse-escaped-string k)
          (let loop ((j k) (acc '()))
            (if (>= j n)
                (error "json-parse: unterminated string")
                (let ((c (string-ref str j)))
                  (cond
                    ((char=? c #\") (cons (list->string (reverse acc)) (+ j 1)))
                    ((char=? c #\\)
                     ;; Bounds-check before reading the escape character.
                     ;; `string-ref` past the end raises a HOST range error,
                     ;; which is not the guardable kind — the one thing every
                     ;; malformed-input path here must avoid.
                     (if (>= (+ j 1) n)
                         (error "json-parse: unterminated string")
                         (let ((e (string-ref str (+ j 1))))
                           (cond
                             ((char=? e #\") (loop (+ j 2) (cons #\" acc)))
                             ((char=? e #\\) (loop (+ j 2) (cons #\\ acc)))
                             ((char=? e #\/) (loop (+ j 2) (cons #\/ acc)))
                             ((char=? e #\b) (loop (+ j 2) (cons #\x8 acc)))
                             ((char=? e #\f) (loop (+ j 2) (cons #\xc acc)))
                             ((char=? e #\n) (loop (+ j 2) (cons #\newline acc)))
                             ((char=? e #\r) (loop (+ j 2) (cons #\return acc)))
                             ((char=? e #\t) (loop (+ j 2) (cons #\tab acc)))
                             ((char=? e #\u)
                              (if (> (+ j 6) n)
                                  (error "json-parse: unterminated string")
                                  (let ((hex (string->number
                                               (substring str (+ j 2) (+ j 6)) 16)))
                                    (if (number? hex)
                                        (loop (+ j 6) (cons (integer->char hex) acc))
                                        (error "json-parse: bad escape" #\u)))))
                             (else (error "json-parse: bad escape" e))))))
                    (else (loop (+ j 1) (cons c acc))))))))

        (define (number-char? c)
          (or (char-numeric? c)
              (char=? c #\-) (char=? c #\+)
              (char=? c #\.) (char=? c #\e) (char=? c #\E)))

        ;; parse-value falls through to here for ANY character that does not
        ;; start an object, array, string or literal — so this is where every
        ;; piece of non-JSON input lands, not just a bad number. Shell noise
        ;; ("paneru: command not found") arrives with the cursor on a
        ;; character that consumes no number token at all; empty output never
        ;; reaches here, having already been caught by parse-value's own
        ;; end-of-input clause.
        ;;
        ;; The empty-token case is checked BEFORE `string->number` sees it,
        ;; deliberately: LispKit's `string->number` raises a type error on an
        ;; empty string rather than answering #f, and that error is not the
        ;; guardable kind — it escapes the `(guard (e (#t #f)) …)` every caller
        ;; wraps this in and reaches the host as a failed evaluation. Raising
        ;; our own `error` instead keeps ALL malformed input on one guardable
        ;; path, which is what lets a caller degrade to no data (ADR-0017's
        ;; empty-output shape) instead of breaking a leader press.
        (define (parse-number k)
          (let loop ((j k))
            (if (and (< j n) (number-char? (string-ref str j)))
                (loop (+ j 1))
                (if (= j k)
                    (error "json-parse: expected a value" (string-ref str k))
                    (let* ((tok (substring str k j))
                           (num (string->number tok)))
                      (if (number? num)
                          (cons num j)
                          (error "json-parse: malformed number" tok)))))))

        ;; Trailing text after the first complete value is ignored, exactly
        ;; as it always was — a CLI that prints a JSON line and then a
        ;; newline or a warning still reads.
        (car (parse-value 0))))

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
